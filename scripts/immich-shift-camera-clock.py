#!/usr/bin/env python3
"""Re-date photos from a camera whose clock was wrong, keeping the gaps between shots.

A camera whose clock resets (a Casio EX-Z6 falls back to 2006-01-01 00:00 when its
battery dies) still records correct *intervals* between photos, so one known real
time per run of photos fixes the whole run. Each run is a range of filenames in one
Immich album, an anchor clock time as the camera recorded it, and the real time
(with UTC offset) that clock reading corresponds to.

Usage (on the server, IMMICH_KEY = an admin-scope API key):
  scripts/immich-shift-camera-clock.py plan  <segments.json>   # plan + backup CSV, changes nothing
  scripts/immich-shift-camera-clock.py apply <segments.json> [--limit N]
  scripts/immich-shift-camera-clock.py refresh <segments.json> # re-read metadata (needed after apply)
  scripts/immich-shift-camera-clock.py rollback <segments.json>

segments.json:
  {"name": "casio-2012", "segments": [
     {"album": "Hong Kong / Xi'an", "first": "CIMG2379.JPG", "last": "CIMG2545.JPG",
      "clock": "2006-01-15T08:10:58", "real": "2012-09-28T21:00:58+08:00"}, ...]}
Files are matched by originalFileName within the album, inclusive, compared as strings.
"""
import csv, datetime as dt, json, os, subprocess, sys, urllib.request

KEY = os.environ['IMMICH_KEY']
BASE = os.environ.get('IMMICH_URL', 'https://immich.antoineglacet.com') + '/api'
WORK = os.path.expanduser('~/immich-migration')


def psql(sql):
    out = subprocess.run(['docker', 'exec', 'immich-postgres', 'psql', '-U', 'immich', '-d', 'immich',
                          '-tA', '-F', '\t', '-c', sql], check=True, capture_output=True, text=True).stdout
    return [l.split('\t') for l in out.splitlines() if l]


def api(method, path, body):
    req = urllib.request.Request(BASE + path, method=method, data=json.dumps(body).encode(),
                                 headers={'x-api-key': KEY, 'Content-Type': 'application/json',
                                          # Cloudflare 403s the default Python-urllib UA off the LAN
                                          'User-Agent': 'home-server-immich-scripts/1.0'})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.status


def paths(cfg):
    n = cfg['name']
    return os.path.join(WORK, f'{n}-plan.csv'), os.path.join(WORK, f'{n}-done.txt')


def lit(s):
    return s.replace("'", "''")


def plan(cfg):
    plan_csv, _ = paths(cfg)
    if os.path.exists(plan_csv):
        sys.exit(f'{plan_csv} exists; it is the rollback backup. Move it away to re-plan.')
    out = []
    for seg in cfg['segments']:
        rows = psql(f'''select a.id, a."originalFileName", e."dateTimeOriginal", a."localDateTime", e."timeZone"
                        from asset a join album_asset aa on aa."assetId" = a.id
                        join album al on al.id = aa."albumId"
                        left join asset_exif e on e."assetId" = a.id
                        where al."albumName" = '{lit(seg['album'])}' and a."deletedAt" is null
                          and a."originalFileName" between '{lit(seg['first'])}' and '{lit(seg['last'])}'
                        order by a."originalFileName"''')
        clock0 = dt.datetime.fromisoformat(seg['clock'])
        real0 = dt.datetime.fromisoformat(seg['real'])
        for aid, name, dto, local, tz in rows:
            # The camera wrote a naive clock value; Immich stored it as-is (treated as UTC or local).
            # localDateTime holds that wall-clock reading, so shift from it.
            clock = dt.datetime.fromisoformat(local.replace(' ', 'T').split('+')[0])
            new = real0 + (clock - clock0)
            out.append([aid, name, seg['album'], dto or '', local, tz or '', new.isoformat()])
        print(f"{seg['album']:28} {seg['first']}..{seg['last']}: {len(rows)} assets, "
              f"{out[-len(rows)][6] if rows else '-'} .. {out[-1][6] if rows else '-'}")
    os.makedirs(WORK, exist_ok=True)
    with open(plan_csv, 'w', newline='') as f:
        w = csv.writer(f)
        w.writerow(['id', 'file', 'album', 'old_dateTimeOriginal', 'old_localDateTime', 'old_timeZone', 'new'])
        w.writerows(out)
    print(f'{len(out)} assets planned; backup of old dates: {plan_csv}')


def load(cfg):
    with open(paths(cfg)[0]) as f:
        return list(csv.DictReader(f))


def apply(cfg, limit=None):
    _, done_txt = paths(cfg)
    done = set(open(done_txt).read().split()) if os.path.exists(done_txt) else set()
    todo = [r for r in load(cfg) if r['id'] not in done][:limit]
    with open(done_txt, 'a') as log:
        for r in todo:
            api('PUT', f"/assets/{r['id']}", {'dateTimeOriginal': r['new']})
            log.write(r['id'] + '\n')
            log.flush()
    print(f'applied {len(todo)}')


def refresh(cfg):
    ids = open(paths(cfg)[1]).read().split()
    for i in range(0, len(ids), 500):
        api('POST', '/assets/jobs', {'assetIds': ids[i:i + 500], 'name': 'refresh-metadata'})
    print(f'queued refresh-metadata for {len(ids)} assets')


def rollback(cfg):
    rows = load(cfg)
    for r in rows:
        old = r['old_dateTimeOriginal'] or r['old_localDateTime']
        api('PUT', f"/assets/{r['id']}", {'dateTimeOriginal': dt.datetime.fromisoformat(old.replace(' ', 'T')).isoformat()})
    done_txt = paths(cfg)[1]
    if os.path.exists(done_txt):
        os.remove(done_txt)
    print(f'restored {len(rows)}; now run refresh')
    with open(done_txt, 'w') as f:
        f.write('\n'.join(r['id'] for r in rows) + '\n')


if __name__ == '__main__':
    cmd, cfg_path = sys.argv[1], sys.argv[2]
    cfg = json.load(open(cfg_path))
    lim = int(sys.argv[4]) if len(sys.argv) > 4 and sys.argv[3] == '--limit' else None
    {'plan': plan, 'apply': lambda c: apply(c, lim), 'refresh': refresh, 'rollback': rollback}[cmd](cfg)
