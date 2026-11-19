import Foundation
import CoreLocation

/// Toronto's underground PATH as a walkable graph, bundled so directions work with no signal and no GPS.
/// Data: OpenStreetMap contributors (ODbL), built by Tools/build_path.py.
final class PathNetwork: @unchecked Sendable {
    static let shared = PathNetwork()
    static let center = CLLocationCoordinate2D(latitude: 43.6487, longitude: -79.3815)

    struct Node { let lat: Double; let lon: Double; let level: Double
        var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
    }
    enum EdgeKind: Int { case walk = 0, stairs = 1, elevator = 2, escalator = 3 }
    struct Edge { let to: Int; let metres: Double; let kind: EdgeKind; let name: String }

    struct Landmark: Identifiable, Hashable {
        enum Category: String { case station, entrance, food, shop, place }
        let id: Int
        let name: String
        let category: Category
        let node: Int
        let coordinate: CLLocationCoordinate2D
        static func == (a: Landmark, b: Landmark) -> Bool { a.id == b.id }
        func hash(into h: inout Hasher) { h.combine(id) }

        var symbol: String {
            switch category {
            case .station: return "tram.fill.tunnel"
            case .entrance: return "door.left.hand.open"
            case .food: return "fork.knife"
            case .shop: return "bag.fill"
            case .place: return "mappin"
            }
        }
    }

    struct Step: Identifiable, Hashable {
        let id: Int
        let instruction: String
        let detail: String?
        let metres: Double
        let bearing: Double          // degrees from north, for the compass arrow
        let symbol: String
        let path: [CLLocationCoordinate2D]
        static func == (a: Step, b: Step) -> Bool { a.id == b.id && a.instruction == b.instruction }
        func hash(into h: inout Hasher) { h.combine(id); h.combine(instruction) }
    }

    struct Route {
        let steps: [Step]
        let metres: Double
        let coordinates: [CLLocationCoordinate2D]
        var minutes: Int { max(1, Int((metres / 75).rounded())) } // indoor pace ~75 m/min
    }

    private(set) var nodes: [Node] = []
    private(set) var adjacency: [[Edge]] = []
    private(set) var landmarks: [Landmark] = []
    private(set) var lines: [[CLLocationCoordinate2D]] = []
    private var landmarksByNode: [Int: [Landmark]] = [:]
    let attribution = "PATH map © OpenStreetMap contributors"

    private init() {
        guard let url = Bundle.appMain.url(forResource: "path_toronto", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        nodes = (json["nodes"] as? [[Double]] ?? []).map { Node(lat: $0[0], lon: $0[1], level: $0.count > 2 ? $0[2] : -1) }
        let names = json["names"] as? [String] ?? []
        adjacency = Array(repeating: [], count: nodes.count)
        for e in json["edges"] as? [[Int]] ?? [] where e.count >= 5 && e[0] < nodes.count && e[1] < nodes.count {
            let m = Double(e[2]) / 10, kind = EdgeKind(rawValue: e[3]) ?? .walk, name = e[4] < names.count ? names[e[4]] : ""
            adjacency[e[0]].append(Edge(to: e[1], metres: m, kind: kind, name: name))
            adjacency[e[1]].append(Edge(to: e[0], metres: m, kind: kind, name: name))
        }
        lines = Self.chains(nodes: nodes, adjacency: adjacency)
        landmarks = (json["pois"] as? [[Any]] ?? []).enumerated().compactMap { i, p in
            guard p.count >= 5, let name = p[0] as? String, let node = p[2] as? Int, node < nodes.count,
                  let lat = p[3] as? Double, let lon = p[4] as? Double else { return nil }
            return Landmark(id: i, name: name, category: Landmark.Category(rawValue: p[1] as? String ?? "") ?? .place,
                            node: node, coordinate: .init(latitude: lat, longitude: lon))
        }
        landmarksByNode = Dictionary(grouping: landmarks, by: \.node)
    }

    var isAvailable: Bool { !nodes.isEmpty }

    /// Joins edges into long polylines (one per corridor run) so the map draws a few hundred overlays, not thousands.
    private static func chains(nodes: [Node], adjacency: [[Edge]]) -> [[CLLocationCoordinate2D]] {
        var used = Set<Int64>()
        func key(_ a: Int, _ b: Int) -> Int64 { Int64(min(a, b)) << 32 | Int64(max(a, b)) }
        var out: [[CLLocationCoordinate2D]] = []
        let starts = adjacency.indices.sorted { (adjacency[$0].count == 2 ? 1 : 0) < (adjacency[$1].count == 2 ? 1 : 0) }
        for s in starts {
            for e in adjacency[s] where !used.contains(key(s, e.to)) {
                var line = [nodes[s].coordinate], prev = s, cur = e.to
                used.insert(key(s, cur))
                line.append(nodes[cur].coordinate)
                while adjacency[cur].count == 2, let next = adjacency[cur].first(where: { $0.to != prev })?.to, !used.contains(key(cur, next)) {
                    used.insert(key(cur, next)); prev = cur; cur = next
                    line.append(nodes[cur].coordinate)
                }
                out.append(line)
            }
        }
        return out
    }

    static func covers(_ c: CLLocationCoordinate2D) -> Bool {
        CLLocation(latitude: c.latitude, longitude: c.longitude)
            .distance(from: CLLocation(latitude: center.latitude, longitude: center.longitude)) < 2500
    }

    /// Landmarks to start or end at — stations and entrances first, nearest to `near`.
    func places(near: CLLocationCoordinate2D?, matching query: String = "") -> [Landmark] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        let here = near.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        let rank: (Landmark) -> Int = { [.station: 0, .entrance: 1, .place: 2, .food: 3, .shop: 4][$0.category] ?? 5 }
        var seenNames = Set<String>()
        return landmarks
            .filter { q.isEmpty || $0.name.lowercased().contains(q) }
            .sorted { a, b in
                if let here {
                    let da = here.distance(from: CLLocation(latitude: a.coordinate.latitude, longitude: a.coordinate.longitude))
                    let db = here.distance(from: CLLocation(latitude: b.coordinate.latitude, longitude: b.coordinate.longitude))
                    if q.isEmpty && abs(da - db) > 40 { return da < db }
                }
                return rank(a) != rank(b) ? rank(a) < rank(b) : a.name < b.name
            }
            // Several entrances often share a name ("Union Station"); list each name once (the nearest).
            .filter { seenNames.insert($0.name.lowercased()).inserted }
    }

    // MARK: Routing

    /// Shortest walk between two landmarks. `stepFree` avoids stairs.
    func route(from: Landmark, to: Landmark, stepFree: Bool) -> Route? {
        guard let path = shortestPath(from: from.node, to: to.node, stepFree: stepFree) else { return nil }
        return describe(path, from: from, to: to)
    }

    private func shortestPath(from s: Int, to t: Int, stepFree: Bool) -> [(node: Int, edge: Edge?)]? {
        guard s < nodes.count, t < nodes.count else { return nil }
        var dist = [Double](repeating: .infinity, count: nodes.count)
        var prev = [(Int, Edge)?](repeating: nil, count: nodes.count)
        var heap = MinHeap()
        dist[s] = 0; heap.push(0, s)
        while let (d, u) = heap.pop() {
            if u == t { break }
            if d > dist[u] { continue }
            for e in adjacency[u] {
                if stepFree && e.kind == .stairs { continue }
                // Small penalties keep routes on main corridors and off needless level changes.
                let cost = e.metres + (e.kind == .stairs ? 8 : e.kind == .elevator ? 25 : 0) + (e.name.isEmpty ? e.metres * 0.05 : 0)
                let nd = d + cost
                if nd < dist[e.to] { dist[e.to] = nd; prev[e.to] = (u, e); heap.push(nd, e.to) }
            }
        }
        guard dist[t].isFinite else { return nil }
        var out: [(Int, Edge?)] = [(t, nil)]
        var cur = t
        while let (p, e) = prev[cur] { out[out.count - 1].1 = e; out.append((p, nil)); cur = p }
        // out is target→source with each entry's edge = edge used to arrive at it; flip to source→target.
        return out.reversed().map { (node: $0.0, edge: $0.1) }
    }

    private func bearing(_ a: Node, _ b: Node) -> Double {
        let φ1 = a.lat * .pi / 180, φ2 = b.lat * .pi / 180, Δλ = (b.lon - a.lon) * .pi / 180
        let y = sin(Δλ) * cos(φ2), x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(Δλ)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    private func describe(_ path: [(node: Int, edge: Edge?)], from: Landmark, to: Landmark) -> Route {
        // Group consecutive edges into steps by corridor name, mode (stairs/elevator) and sharp turns.
        struct Seg { var nodes: [Int]; var metres: Double; var kind: EdgeKind; var name: String; var startBearing: Double; var endBearing: Double }
        var segs: [Seg] = []
        for i in 1..<path.count {
            guard let e = path[i].edge else { continue }
            let a = nodes[path[i - 1].node], b = nodes[path[i].node]
            let br = bearing(a, b)
            if var last = segs.last {
                let turn = abs(((br - last.endBearing + 540).truncatingRemainder(dividingBy: 360)) - 180)
                let sameName = e.name == last.name || e.name.isEmpty || last.name.isEmpty
                if e.kind == last.kind && sameName && (turn < 40 || e.metres < 6 || e.kind != .walk) {
                    last.nodes.append(path[i].node); last.metres += e.metres; last.endBearing = br
                    if last.name.isEmpty { last.name = e.name }
                    segs[segs.count - 1] = last
                    continue
                }
            }
            segs.append(Seg(nodes: [path[i - 1].node, path[i].node], metres: e.metres, kind: e.kind, name: e.name, startBearing: br, endBearing: br))
        }
        // Fold tiny walk segments into their neighbours.
        var merged: [Seg] = []
        for s in segs {
            if let last = merged.last, s.kind == .walk, last.kind == .walk, s.metres < 12 {
                merged[merged.count - 1].nodes += s.nodes.dropFirst(); merged[merged.count - 1].metres += s.metres
                merged[merged.count - 1].endBearing = s.endBearing
            } else { merged.append(s) }
        }

        var steps: [Step] = []
        var used = Set<Int>([from.id, to.id])
        for (i, s) in merged.enumerated() {
            let startLevel = nodes[s.nodes.first!].level, endLevel = nodes[s.nodes.last!].level
            let up = endLevel > startLevel
            let corridor = s.name.isEmpty || s.name.lowercased() == "path" ? "the PATH" : s.name
            var instruction: String, symbol: String
            switch s.kind {
            case .stairs: instruction = up ? "Take the stairs up" : "Take the stairs down"; symbol = up ? "figure.stairs" : "figure.stairs"
            case .escalator: instruction = up ? "Take the escalator up" : "Take the escalator down"; symbol = "escalator"
            case .elevator: instruction = "Take the elevator \(up ? "up" : "down")"; symbol = "arrow.up.arrow.down.square.fill"
            case .walk:
                if i == 0 {
                    instruction = "Head \(compass(s.startBearing)) along \(corridor)"; symbol = "location.north.line.fill"
                } else {
                    let prevEnd = merged[i - 1].endBearing
                    let delta = ((s.startBearing - prevEnd + 540).truncatingRemainder(dividingBy: 360)) - 180
                    let dir = delta > 30 ? "right" : delta < -30 ? "left" : nil
                    instruction = dir.map { "Turn \($0) onto \(corridor)" } ?? "Continue along \(corridor)"
                    symbol = dir == "right" ? "arrow.turn.up.right" : dir == "left" ? "arrow.turn.up.left" : "arrow.up"
                }
            }
            // Landmarks passed on this step make directions usable without a blue dot.
            let passed = s.nodes.flatMap { landmarksByNode[$0] ?? [] }.filter { used.insert($0.id).inserted }
            let named = passed.sorted { ($0.category == .entrance ? 1 : 0) < ($1.category == .entrance ? 1 : 0) }.prefix(2).map(\.name)
            let detail = named.isEmpty ? nil : "Pass \(named.joined(separator: " and "))"
            steps.append(Step(id: i, instruction: instruction, detail: detail, metres: s.metres, bearing: s.startBearing, symbol: symbol,
                              path: s.nodes.map { nodes[$0].coordinate }))
        }
        steps.append(Step(id: steps.count, instruction: "Arrive at \(to.name)", detail: nil, metres: 0,
                          bearing: merged.last?.endBearing ?? 0, symbol: "flag.checkered", path: []))
        let total = merged.reduce(0) { $0 + $1.metres }
        return Route(steps: steps, metres: total, coordinates: path.map { nodes[$0.node].coordinate })
    }

    private func compass(_ b: Double) -> String {
        ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"][Int(((b + 22.5) / 45).rounded(.down)) % 8]
    }
}

/// Binary min-heap for Dijkstra.
private struct MinHeap {
    private var items: [(Double, Int)] = []
    mutating func push(_ p: Double, _ v: Int) {
        items.append((p, v)); var i = items.count - 1
        while i > 0 { let parent = (i - 1) / 2; if items[parent].0 <= items[i].0 { break }; items.swapAt(i, parent); i = parent }
    }
    mutating func pop() -> (Double, Int)? {
        guard !items.isEmpty else { return nil }
        let top = items[0]; let last = items.removeLast()
        if !items.isEmpty {
            items[0] = last; var i = 0
            while true {
                let l = 2 * i + 1, r = l + 1; var m = i
                if l < items.count && items[l].0 < items[m].0 { m = l }
                if r < items.count && items[r].0 < items[m].0 { m = r }
                if m == i { break }; items.swapAt(i, m); i = m
            }
        }
        return top
    }
}
