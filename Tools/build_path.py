"""Builds SwiftRide/Resources/TransitData/path_toronto.json — Toronto's underground PATH as a walkable graph.

Source: OpenStreetMap via the Overpass API (© OpenStreetMap contributors, ODbL — credited in the app).
Usage: python3 build_path.py <out.json> [ways.json pois.json]   (downloads if the cached files aren't given)
"""
import sys, json, math, urllib.request, urllib.parse, collections
BBOX = "43.636,-79.395,43.662,-79.369"
Q_WAYS = f"""[out:json][timeout:120];(
 way["highway"~"footway|corridor|steps|pedestrian|elevator"]["level"~"^-"]({BBOX});
 way["highway"~"footway|corridor|steps"]["tunnel"="yes"]({BBOX});
 way["indoor"="corridor"]({BBOX});
 way["highway"="footway"]["layer"~"^-"]({BBOX});
);out body geom;"""
Q_POIS = f"""[out:json][timeout:120];(
 node["name"]["level"~"^-"]({BBOX}); node["name"]["entrance"]({BBOX});
 node["railway"~"subway_entrance|train_station_entrance"]({BBOX});
);out tags;"""

def fetch(q):
    req = urllib.request.Request("https://overpass-api.de/api/interpreter", data=urllib.parse.urlencode({'data': q}).encode(),
                                 headers={'User-Agent': 'SwiftRide/4.0 (build_path.py)'})
    return json.load(urllib.request.urlopen(req, timeout=180))

out = sys.argv[1]
ways = json.load(open(sys.argv[2])) if len(sys.argv) > 2 else fetch(Q_WAYS)
pois = json.load(open(sys.argv[3])) if len(sys.argv) > 3 else fetch(Q_POIS)

def dist(a, b):
    return math.hypot((a[0] - b[0]) * 111_195, (a[1] - b[1]) * 111_195 * math.cos(math.radians(a[0])))

def level_of(tags):
    lv = tags.get('level') or tags.get('layer') or '-1'
    try: return min(float(x) for x in lv.split(';'))
    except ValueError: return -1.0

nid, nodes = {}, []           # osm node id -> index ; [lat, lon, level]
names, name_idx = [''], {'': 0}
edges = {}
KIND = {'steps': 1, 'elevator': 2, 'escalator': 3}
for w in ways['elements']:
    if w['type'] != 'way': continue
    t = w.get('tags', {}); lv = level_of(t)
    kind = 3 if t.get('conveying') else KIND.get(t.get('highway'), 0)
    nm = t.get('name') or ''
    if nm not in name_idx: name_idx[nm] = len(names); names.append(nm)
    ids = w.get('nodes', []); geom = w.get('geometry', [])
    prev = None
    for osm, g in zip(ids, geom):
        if osm not in nid: nid[osm] = len(nodes); nodes.append([round(g['lat'], 6), round(g['lon'], 6), lv])
        i = nid[osm]
        if prev is not None and prev != i:
            key = (min(prev, i), max(prev, i))
            d = dist(nodes[prev], nodes[i])
            if key not in edges or edges[key][0] > d: edges[key] = (d, kind, name_idx[nm])
        prev = i

# Largest connected component only (drops orphan scraps).
adj = collections.defaultdict(list)
for (a, b) in edges: adj[a].append(b); adj[b].append(a)
seen, comps = set(), []
for s in adj:
    if s in seen: continue
    comp, stack = [], [s]; seen.add(s)
    while stack:
        x = stack.pop(); comp.append(x)
        for y in adj[x]:
            if y not in seen: seen.add(y); stack.append(y)
    comps.append(comp)
comps.sort(key=len, reverse=True)
keep = set(c for comp in comps if len(comp) >= max(25, len(comps[0]) * 0.02) for c in comp)
remap = {old: new for new, old in enumerate(sorted(keep))}
nodes_out = [nodes[o] for o in sorted(keep)]
edges_out = [[remap[a], remap[b], int(round(d * 10)), k, n] for (a, b), (d, k, n) in edges.items() if a in keep and b in keep]

# Landmarks snapped to the nearest walkway node (within 40 m).
CAT = [('railway', 'station'), ('entrance', 'entrance'), ('amenity', 'food'), ('shop', 'shop')]
pois_out, seen_names = [], set()
for p in pois['elements']:
    t = p.get('tags', {}); nm = t.get('name')
    if not nm or 'lat' not in p: continue
    cat = next((c for k, c in CAT if k in t), 'place')
    if cat == 'food' and t.get('amenity') not in ('fast_food', 'cafe', 'restaurant', 'food_court'): cat = 'place'
    best, bd = None, 41.0
    pt = (p['lat'], p['lon'])
    for i, n in enumerate(nodes_out):
        if abs(n[0] - pt[0]) > 0.0005 or abs(n[1] - pt[1]) > 0.0007: continue
        d = dist(n, pt)
        if d < bd: best, bd = i, d
    if best is None: continue
    key = (nm, best)
    if key in seen_names: continue
    seen_names.add(key)
    pois_out.append([nm, cat, best, round(p['lat'], 6), round(p['lon'], 6)])

doc = {'attribution': '© OpenStreetMap contributors (ODbL)', 'nodes': nodes_out, 'edges': edges_out, 'names': names, 'pois': pois_out}
json.dump(doc, open(out, 'w'), separators=(',', ':'), ensure_ascii=False)
total = sum(e[2] for e in edges_out) / 10_000
print(f"components={len(comps)} kept_nodes={len(nodes_out)} edges={len(edges_out)} km={total:.1f} pois={len(pois_out)} "
      f"by_cat={collections.Counter(p[1] for p in pois_out)}")
