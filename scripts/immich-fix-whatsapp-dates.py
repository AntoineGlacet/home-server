#!/usr/bin/env python3
"""Re-date WhatsApp media whose Google date is wrong, using the date in the filename.

WhatsApp strips EXIF, so Google Photos dated these by upload time; the Takeout JSON
carried that wrong date into Immich. Filenames like IMG-20170101-WA0000.jpg encode the
day the media arrived in WhatsApp, which is the best date available.

Usage:  IMMICH_KEY=... scripts/immich-fix-whatsapp-dates.py plan            # write plan + backup CSV, change nothing
        scripts/immich-fix-whatsapp-dates.py apply --limit 1 # apply to the first N assets
        scripts/immich-fix-whatsapp-dates.py apply           # apply to all remaining
        scripts/immich-fix-whatsapp-dates.py refresh         # re-read metadata for applied ids (needed!)
        scripts/immich-fix-whatsapp-dates.py rollback        # restore original dates from backup CSV
"""
import csv, datetime as dt, json, os, re, subprocess, sys, urllib.request

KEY = os.environ['IMMICH_KEY']
BASE = 'https://immich.antoineglacet.com/api'
WORK = os.path.expanduser('~/immich-migration')
PLAN = os.path.join(WORK, 'wa-date-fix-plan.csv')      # also the rollback backup
DONE = os.path.join(WORK, 'wa-date-fix-done.txt')
PAT = re.compile(r'^(?:IMG|VID|AUD|PTT|STK|DOC)-(\d{8})-WA\d+', re.I)
TOLERANCE_DAYS = 2   # absorb timezone shifts; only fix real mismatches

def psql(sql):
    out = subprocess.run(['docker', 'exec', 'immich-postgres', 'psql', '-U', 'immich', '-d', 'immich',
                          '-tA', '-F', '\t', '-c', sql], check=True, capture_output=True, text=True).stdout
    return [l.split('\t') for l in out.splitlines() if l]

def api(method, path, body):
    req = urllib.request.Request(BASE + path, method=method, data=json.dumps(body).encode(),
                                 headers={'x-api-key': KEY, 'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.status

def plan():
    os.makedirs(WORK, exist_ok=True)
    rows = psql('''select a.id, a."originalFileName", a."localDateTime", e."dateTimeOriginal", e."timeZone"
                   from asset a left join asset_exif e on e."assetId" = a.id
                   where a."deletedAt" is null''')
    out = []
    for aid, name, local, orig, tz in rows:
        m = PAT.match(name)
        if not m:
            continue
        try:
            fdate = dt.datetime.strptime(m.group(1), '%Y%m%d').date()
        except ValueError:
            continue
        cur = dt.date.fromisoformat(local[:10])
        if abs((cur - fdate).days) > TOLERANCE_DAYS:
            out.append([aid, name, local, orig or '', tz or '', fdate.isoformat()])
    with open(PLAN, 'w', newline='') as f:
        w = csv.writer(f)
        w.writerow(['id', 'file', 'old_localDateTime', 'old_dateTimeOriginal', 'old_timeZone', 'new_date'])
        w.writerows(out)
    years = {}
    for r in out:
        k = (r[2][:4], r[5][:4]); years[k] = years.get(k, 0) + 1
    print(f'{len(out)} assets to re-date. Plan/backup: {PLAN}')
    for (a, b), n in sorted(years.items()):
        print(f'  {a} -> {b}: {n}')

def load_plan():
    with open(PLAN) as f:
        return list(csv.DictReader(f))

def apply(limit=None):
    done = set(open(DONE).read().split()) if os.path.exists(DONE) else set()
    todo = [r for r in load_plan() if r['id'] not in done][:limit]
    by_date = {}
    for r in todo:
        by_date.setdefault(r['new_date'], []).append(r['id'])
    n = 0
    with open(DONE, 'a') as log:
        for d, ids in sorted(by_date.items()):
            # Noon UTC keeps the calendar day stable in any timezone from UTC-11 to UTC+11.
            api('PUT', '/assets', {'ids': ids, 'dateTimeOriginal': f'{d}T12:00:00.000Z'})
            log.write('\n'.join(ids) + '\n'); log.flush()
            n += len(ids)
    print(f'applied to {n} assets in {len(by_date)} date groups')

def rollback():
    rows = load_plan()
    groups = {}
    for r in rows:
        val = r['old_dateTimeOriginal'] or r['old_localDateTime']
        groups.setdefault(val, []).append(r['id'])
    for val, ids in groups.items():
        iso = dt.datetime.fromisoformat(val.replace(' ', 'T')).isoformat()
        api('PUT', '/assets', {'ids': ids, 'dateTimeOriginal': iso})
    if os.path.exists(DONE):
        os.remove(DONE)
    print(f'restored {len(rows)} assets')

if __name__ == '__main__':
    cmd = sys.argv[1]
    if cmd == 'plan':
        plan()
    elif cmd == 'apply':
        lim = int(sys.argv[3]) if len(sys.argv) > 3 and sys.argv[2] == '--limit' else None
        apply(lim)
    elif cmd == 'rollback':
        rollback()
    elif cmd == 'refresh':
        # A PUT alone is not enough: the auto-queued metadata pass can race the sidecar
        # write and leave localDateTime stale. An explicit refresh-metadata re-reads it.
        ids = open(DONE).read().split()
        for i in range(0, len(ids), 500):
            api('POST', '/assets/jobs', {'assetIds': ids[i:i+500], 'name': 'refresh-metadata'})
        print(f'queued refresh-metadata for {len(ids)} assets')
