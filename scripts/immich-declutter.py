#!/usr/bin/env python3
"""Declutter an Immich library: resolve duplicate groups, and archive text-heavy clutter.

Nothing here is permanent. Duplicates go to Immich's trash (kept for the trash retention,
30 days by default); clutter is *archived* (hidden from the timeline, still searchable,
never expires) and tagged so it can be reviewed or bulk-deleted from the Archive view.
Every run writes a plan CSV under ~/immich-migration/ that `undo` replays.

Usage (on the server, IMMICH_KEY = an admin-scope API key):
  scripts/immich-declutter.py duplicates plan|apply|undo
  scripts/immich-declutter.py clutter    plan|apply|undo   [--min-chars 150]

duplicates: for each group Immich found (Utilities > Review duplicates), keep the copy
  with the most pixels (then the largest file), add it to every album any copy was in,
  carry over favourite status, and send the other copies to trash.
clutter: screenshots (by filename) plus anything whose OCR text is >= --min-chars
  characters (documents, receipts, chat and email screenshots, memes, textbook pages).
  They are tagged "Cleanup/Text-heavy" and archived.
"""
import csv, json, os, re, shutil, subprocess, sys, urllib.request
from concurrent.futures import ThreadPoolExecutor

KEY = os.environ['IMMICH_KEY']
BASE = os.environ.get('IMMICH_URL', 'https://immich.antoineglacet.com') + '/api'
WORK = os.path.expanduser('~/immich-migration')
TAG = 'Cleanup/Text-heavy'


def api(method, path, body=None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(BASE + path, method=method, data=data,
                                 headers={'x-api-key': KEY, 'Content-Type': 'application/json',
                                          # Cloudflare 403s the default Python-urllib UA off the LAN
                                          'User-Agent': 'home-server-immich-scripts/1.0'})
    with urllib.request.urlopen(req, timeout=120) as r:
        raw = r.read()
        return json.loads(raw) if raw else None


def psql(sql):
    out = subprocess.run(['docker', 'exec', 'immich-postgres', 'psql', '-U', 'immich', '-d', 'immich',
                          '-tA', '-F', '\t', '-c', sql], check=True, capture_output=True, text=True).stdout
    return [l.split('\t') for l in out.splitlines() if l]


def chunks(xs, n=500):
    for i in range(0, len(xs), n):
        yield xs[i:i + n]


# ---------------------------------------------------------------- duplicates
DUP_PLAN = os.path.join(WORK, 'duplicates-plan.csv')


def dup_plan():
    groups = api('GET', '/duplicates')
    # Album membership via the API (not the DB) so this step also runs off the LAN.
    albums = {}
    for g in groups:
        for a in g['assets']:
            albums[a['id']] = {al['id'] for al in api('GET', f"/albums?assetId={a['id']}")}
    rows = []
    for g in groups:
        def score(a):
            e = a.get('exifInfo') or {}
            return ((e.get('exifImageWidth') or 0) * (e.get('exifImageHeight') or 0), e.get('fileSizeInByte') or 0)
        assets = sorted(g['assets'], key=score, reverse=True)
        keep, drop = assets[0], assets[1:]
        union = set().union(*(albums.get(a['id'], set()) for a in assets))
        fav = any(a.get('isFavorite') for a in assets)
        for a in assets:
            rows.append([g['duplicateId'], a['id'], 'keep' if a is keep else 'trash', a['originalFileName'],
                         score(a)[0], score(a)[1],
                         ';'.join(sorted(union)) if a is keep else '', int(fav) if a is keep else ''])
    os.makedirs(WORK, exist_ok=True)
    with open(DUP_PLAN, 'w', newline='') as f:
        w = csv.writer(f)
        w.writerow(['duplicateId', 'assetId', 'action', 'file', 'pixels', 'bytes', 'albums_for_keeper', 'favorite'])
        w.writerows(rows)
    n_trash = sum(1 for r in rows if r[2] == 'trash')
    print(f'{len(groups)} groups: keep {len(groups)}, trash {n_trash}. Plan: {DUP_PLAN}')


def dup_apply():
    rows = list(csv.DictReader(open(DUP_PLAN)))
    by = {}
    for r in rows:
        by.setdefault(r['duplicateId'], []).append(r)
    groups = []
    for gid, rs in by.items():
        keep = [r for r in rs if r['action'] == 'keep'][0]
        for alb in filter(None, keep['albums_for_keeper'].split(';')):
            api('PUT', f'/albums/{alb}/assets', {'ids': [keep['assetId']]})
        if keep['favorite'] == '1':
            api('PUT', '/assets', {'ids': [keep['assetId']], 'isFavorite': True})
        groups.append({'duplicateId': gid, 'keepAssetIds': [keep['assetId']],
                       'trashAssetIds': [r['assetId'] for r in rs if r['action'] == 'trash']})
    for part in chunks(groups, 50):
        api('POST', '/duplicates/resolve', {'groups': part})
    print(f'resolved {len(groups)} groups; {sum(len(g["trashAssetIds"]) for g in groups)} copies moved to trash')


def dup_undo():
    ids = [r['assetId'] for r in csv.DictReader(open(DUP_PLAN)) if r['action'] == 'trash']
    for part in chunks(ids):
        api('POST', '/trash/restore/assets', {'ids': part})
    print(f'restored {len(ids)} from trash (album additions to keepers are left in place)')


# ---------------------------------------------------------------- clutter
CL_PLAN = os.path.join(WORK, 'clutter-plan.csv')


SHOT = re.compile(r'(^|[_ -])screen[_ -]?shot|^scr_', re.I)


def has_db():
    """True only where Immich's own Postgres container runs (i.e. on the server)."""
    if not shutil.which('docker'):
        return False
    r = subprocess.run(['docker', 'ps', '-q', '--filter', 'name=^immich-postgres$'], capture_output=True, text=True)
    return r.returncode == 0 and bool(r.stdout.strip())


def cl_rows_api(min_chars):
    """Same selection as the SQL below, via the API: page all timeline assets, fetch OCR per asset."""
    assets, page = [], 1
    while page:
        res = api('POST', '/search/metadata', {'visibility': 'timeline', 'size': 1000, 'page': page})['assets']
        assets += [(a['id'], a['originalFileName']) for a in res['items']]
        page = int(res['nextPage']) if res.get('nextPage') else None

    def chars(item):
        aid, name = item
        return aid, name, sum(len(o.get('text') or '') for o in api('GET', f'/assets/{aid}/ocr'))

    rows = []
    with ThreadPoolExecutor(max_workers=8) as ex:
        for aid, name, n in ex.map(chars, assets):
            shot = bool(SHOT.search(name))
            if shot or n >= min_chars:
                rows.append([aid, name, 'timeline', n, 'screenshot' if shot else 'text'])
    print(f'scanned {len(assets)} timeline assets via the API')
    return rows


def cl_plan(min_chars):
    if not has_db():
        return cl_write(cl_rows_api(min_chars))
    rows = psql(f'''with t as (select "assetId", sum(length(text)) as chars from asset_ocr group by 1)
                    select a.id, a."originalFileName", a.visibility, coalesce(t.chars, 0),
                           case when a."originalFileName" ~* '(^|[_ -])screen[_ -]?shot|^scr_' then 'screenshot'
                                else 'text' end
                    from asset a left join t on t."assetId" = a.id
                    where a."deletedAt" is null and a.visibility = 'timeline'
                      and (coalesce(t.chars, 0) >= {int(min_chars)}
                           or a."originalFileName" ~* '(^|[_ -])screen[_ -]?shot|^scr_')''')
    cl_write(rows)


def cl_write(rows):
    os.makedirs(WORK, exist_ok=True)
    with open(CL_PLAN, 'w', newline='') as f:
        w = csv.writer(f)
        w.writerow(['assetId', 'file', 'old_visibility', 'ocr_chars', 'reason'])
        w.writerows(rows)
    by = {}
    for r in rows:
        by[r[4]] = by.get(r[4], 0) + 1
    print(f'{len(rows)} assets to tag + archive {by}. Plan: {CL_PLAN}')


def tag_id():
    for t in api('GET', '/tags'):
        if t.get('value') == TAG:
            return t['id']
    return api('PUT', '/tags', {'tags': [TAG]})[0]['id']


def cl_apply():
    ids = [r['assetId'] for r in csv.DictReader(open(CL_PLAN))]
    tid = tag_id()
    for part in chunks(ids):
        api('PUT', f'/tags/{tid}/assets', {'ids': part})
        api('PUT', '/assets', {'ids': part, 'visibility': 'archive'})
    print(f'tagged "{TAG}" and archived {len(ids)}')


def cl_undo():
    rows = list(csv.DictReader(open(CL_PLAN)))
    by = {}
    for r in rows:
        by.setdefault(r['old_visibility'], []).append(r['assetId'])
    for vis, ids in by.items():
        for part in chunks(ids):
            api('PUT', '/assets', {'ids': part, 'visibility': vis})
    tid = tag_id()
    for part in chunks([r['assetId'] for r in rows]):
        api('DELETE', f'/tags/{tid}/assets', {'ids': part})
    print(f'restored visibility and removed tag on {len(rows)}')


if __name__ == '__main__':
    what, cmd = sys.argv[1], sys.argv[2]
    mc = int(sys.argv[4]) if len(sys.argv) > 4 and sys.argv[3] == '--min-chars' else 150
    {('duplicates', 'plan'): dup_plan, ('duplicates', 'apply'): dup_apply, ('duplicates', 'undo'): dup_undo,
     ('clutter', 'plan'): lambda: cl_plan(mc), ('clutter', 'apply'): cl_apply, ('clutter', 'undo'): cl_undo,
     }[(what, cmd)]()
