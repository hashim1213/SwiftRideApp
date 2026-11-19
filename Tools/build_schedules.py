"""Builds SwiftRide/Resources/TransitData/<agency>.sched.json — compact timetables for planning ahead.

Each trip is stored as [route, service, headsign, pattern, profile, startMinute]:
  pattern = the ordered stops it serves (indices into <agency>.json "stops")
  profile = minute offsets from the first stop (shared between trips with identical timing)
Services hold the weekly calendar plus exception dates.

Usage: python3 build_schedules.py <zips dir> <TransitData dir> [agency,agency]
Run after build_transit_data.py (it needs the stop order from <agency>.json).
"""
import sys, zipfile, csv, io, json, os, datetime
ZIPS, OUT = sys.argv[1], sys.argv[2]
ONLY = set(sys.argv[3].split(',')) if len(sys.argv) > 3 else None
# GO uses the Metrolinx Journey API and Winnipeg its own planner, so they don't need bundled timetables.
AGENCIES = ['ttc','up','calgary','edmonton','halifax','victoria','kelowna','bct46','bct41','bct13',
            'yrt','miway','ltc','hsr','durham','barrie','kingston','windsor']
today = datetime.date.today(); horizon = today + datetime.timedelta(days=150)
def ymd(d): return int(d.strftime('%Y%m%d'))

def mins(t):
    h, m, s = (t.strip() or '0:0:0').split(':')
    return int(h) * 60 + int(m) + (1 if int(s) >= 30 else 0)

for a in AGENCIES:
    if ONLY and a not in ONLY: continue
    base = json.load(open(os.path.join(OUT, f'{a}.json')))
    sidx = {s[0]: i for i, s in enumerate(base['stops'])}
    ridx = {r[0]: i for i, r in enumerate(base['routes'])}
    z = zipfile.ZipFile(os.path.join(ZIPS, f'{a}.zip'))
    names = set(z.namelist())
    rd = lambda n: csv.DictReader(io.TextIOWrapper(z.open(n), 'utf-8-sig'))

    services, sid_index = [], {}
    def service(sid):
        if sid not in sid_index:
            sid_index[sid] = len(services); services.append([sid, 0, 0, 0, [], []])
        return services[sid_index[sid]]
    if 'calendar.txt' in names:
        for c in rd('calendar.txt'):
            s = service(c['service_id'])
            s[1] = sum((1 << i) for i, d in enumerate(['monday','tuesday','wednesday','thursday','friday','saturday','sunday']) if c[d] == '1')
            s[2], s[3] = int(c['start_date']), int(c['end_date'])
    if 'calendar_dates.txt' in names:
        for c in rd('calendar_dates.txt'):
            d = int(c['date'])
            if d < ymd(today - datetime.timedelta(days=1)) or d > ymd(horizon): continue
            s = service(c['service_id'])
            (s[4] if c['exception_type'] == '1' else s[5]).append(d)

    trips, heads, hidx = {}, [], {}
    for t in rd('trips.txt'):
        if t['route_id'] not in ridx: continue
        h = (t.get('trip_headsign') or '').strip()
        if h not in hidx: hidx[h] = len(heads); heads.append(h)
        trips[t['trip_id']] = (ridx[t['route_id']], sid_index.get(t['service_id'], service(t['service_id']) and sid_index[t['service_id']]), hidx[h])

    seqs = {}
    for st in rd('stop_times.txt'):
        tid = st['trip_id']
        if tid not in trips or st['stop_id'] not in sidx: continue
        if (st.get('pickup_type') == '1' and st.get('drop_off_type') == '1'): continue
        t = st.get('departure_time') or st.get('arrival_time')
        if not t: continue
        seqs.setdefault(tid, []).append((int(st['stop_sequence']), sidx[st['stop_id']], mins(t)))

    patterns, pidx, profiles, fidx, out_trips = [], {}, [], {}, []
    for tid, seq in seqs.items():
        if len(seq) < 2: continue
        seq.sort()
        p = tuple(x[1] for x in seq); start = seq[0][2]; f = tuple(x[2] - start for x in seq)
        if p not in pidx: pidx[p] = len(patterns); patterns.append(list(p))
        if f not in fidx: fidx[f] = len(profiles); profiles.append(list(f))
        r, s, h = trips[tid]
        out_trips.append([r, s, h, pidx[p], fidx[f], start])
    out_trips.sort(key=lambda x: x[5])
    used = {t[1] for t in out_trips}
    doc = {'services': services, 'headsigns': heads, 'patterns': patterns, 'profiles': profiles, 'trips': out_trips}
    path = os.path.join(OUT, f'{a}.sched.json')
    json.dump(doc, open(path, 'w'), separators=(',', ':'), ensure_ascii=False)
    print(f'{a:9} trips={len(out_trips):6} patterns={len(patterns):5} profiles={len(profiles):6} services={len(used):3} size={os.path.getsize(path)//1024}KB')
