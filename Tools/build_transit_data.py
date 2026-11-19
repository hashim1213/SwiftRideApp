"""Builds SwiftRide/Resources/TransitData/<agency>.json from each agency's static GTFS zip.

Usage:
  1. Download the zips listed in gtfs_sources.txt into a folder, named <id>.zip
     (e.g.  while read id url; do curl -L -o zips/$id.zip "$url"; done < gtfs_sources.txt)
  2. python3 build_transit_data.py zips ../SwiftRide/Resources/TransitData
Re-run whenever an agency publishes a new schedule (stop IDs rarely change, Calgary/Windsor trip IDs do).
"""
import sys,zipfile,csv,io,json,os,collections
ZIPS=sys.argv[1]; OUT=sys.argv[2]; ONLY=set(sys.argv[3].split(',')) if len(sys.argv)>3 else None; os.makedirs(OUT,exist_ok=True)
AG={'ttc':0,'go':0,'up':0,'calgary':1,'edmonton':0,'halifax':0,'victoria':0,'kelowna':0,'bct46':0,'bct41':0,'bct13':0,
    'yrt':0,'miway':0,'ltc':0,'hsr':0,'durham':0,'barrie':0,'kingston':0,'windsor':1}
def norm(c):
    c=(c or '').strip().lstrip('#').upper()
    return c if len(c)==6 else ''
for a,needTrips in AG.items():
    if ONLY and a not in ONLY: continue
    z=zipfile.ZipFile(os.path.join(ZIPS, f'{a}.zip'))
    rd=lambda n: csv.DictReader(io.TextIOWrapper(z.open(n),'utf-8-sig'))
    routes=list(rd('routes.txt')); ridx={r['route_id']:i for i,r in enumerate(routes)}
    trips={}; heads=[]; hidx={}
    for t in rd('trips.txt'):
        h=(t.get('trip_headsign') or '').strip()
        if h not in hidx: hidx[h]=len(heads); heads.append(h)
        trips[t['trip_id']]=(ridx.get(t['route_id'],-1),hidx[h])
    s2r=collections.defaultdict(set)
    last={}  # trip_id -> (seq, stop_id) of its final stop
    for st in rd('stop_times.txt'):
        tr=trips.get(st['trip_id'])
        if tr and tr[0]>=0: s2r[st['stop_id']].add(tr[0])
        q=int(st.get('stop_sequence') or 0)
        if st['trip_id'] not in last or q>last[st['trip_id']][0]: last[st['trip_id']]=(q,st['stop_id'])
    # "routeIdx|terminalStop" -> headsign: lets realtime trips without a trip map still show "to Dufferin Gate".
    term=collections.defaultdict(collections.Counter)
    for tid,(q,sid) in last.items():
        r,h=trips[tid]
        if r>=0 and heads[h]: term[f"{r}|{sid}"][h]+=1
    stops=[]
    for s in rd('stops.txt'):
        if s.get('location_type') not in (None,'','0'): continue
        if not s.get('stop_lat'): continue
        rs=sorted(s2r.get(s['stop_id'],()))
        if not rs and a not in('go','up'): continue
        code=(s.get('stop_code') or '').strip()
        stops.append([s['stop_id'], code if code!=s['stop_id'] else '', s['stop_name'].strip(), round(float(s['stop_lat']),6), round(float(s['stop_lon']),6), rs])
    out={'routes':[[r['route_id'],(r.get('route_short_name') or '').strip(),(r.get('route_long_name') or '').strip(),norm(r.get('route_color')),norm(r.get('route_text_color')),int(r.get('route_type') or 3)] for r in routes],'stops':stops}
    out['terminals']={k:heads[c.most_common(1)[0][0]] for k,c in term.items()}
    if needTrips:
        used=[t for t in trips.items()]
        out['headsigns']=heads; out['trips']={k:[v[0],v[1]] for k,v in used}
    p=f'{OUT}/{a}.json'; json.dump(out,open(p,'w'),separators=(',',':'),ensure_ascii=False)
    print(f'{a:9} routes={len(routes):4} stops={len(stops):5} size={os.path.getsize(p)//1024}KB')
