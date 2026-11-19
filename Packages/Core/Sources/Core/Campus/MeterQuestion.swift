import Foundation

/// The lookup stopped with rooms of the dorm's name in several apartments (or campuses): the
/// question asked in onboarding's 「你住哪间」 step and on the meter page, one row per room.
public struct MeterQuestion: Sendable, Equatable {
    public struct Row: Sendable, Equatable, Identifiable {
        /// A room to bind as it is.
        public var candidate: MeterCandidate?
        /// A branch halted before its rooms: the picker opens here.
        public var picker: MeterWalkStop?
        /// The apartment (or campus) the room or branch lies under, 「半山公寓」.
        public var title: String
        public var id: String
        /// 「星湖校区 · 半山公寓 · 3 栋 · 108」, or 「这边没对上，点进去自己选」.
        public var location: String { candidate?.location ?? MeterPageText.haltedRow }
        /// VoiceOver: 「半山公寓，星湖校区 半山公寓 3 栋 108」.
        public var spoken: String { title + "，" + location.replacingOccurrences(of: " · ", with: " ") }
    }

    /// 「2 个公寓都有 3 栋 108，你住哪个？」, or 「3 栋 108 在哪个公寓？」 with a halted branch.
    public var text: String
    /// In the order of the level's rows.
    public var rows: [Row]

    /// nil for a stop without rooms or halted branches to choose from, or without the dorm.
    public init?(_ stop: MeterWalkStop, address: DormAddress?) {
        guard let text = MeterPageText.question(stop, address: address) else { return nil }
        self.text = text
        var rows: [(Int, Row)] = []
        let order = Dictionary(stop.options.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        func rank(_ node: PowerNode?) -> Int { node.flatMap { order[$0.id] } ?? Int.max }
        for c in stop.candidates {
            rows.append((rank(stop.branch(of: c)), Row(candidate: c, picker: nil, title: stop.branchName(c), id: c.id)))
        }
        for h in stop.halted {
            let branch = stop.branch(of: h)
            rows.append((rank(branch), Row(candidate: nil, picker: h, title: branch?.name ?? MeterPageText.matchedLine(h.path),
                                           id: "halted|" + (h.path.last?.id ?? ""))))
        }
        self.rows = rows.enumerated().sorted { ($0.element.0, $0.offset) < ($1.element.0, $1.offset) }.map(\.element.1)
    }
}

/// What onboarding's 「你住哪间」 step says about the meter under the dorm.
public enum DormStepMeter: Sendable, Equatable {
    /// Nothing: bound, a plain stop (home says 「还没找到电表」), or no lookup.
    case hidden
    /// 「正在找电表…」 with a spinner.
    case finding
    /// The apartments to choose from; a tap binds.
    case ask(MeterQuestion)
    /// The lookup failed (the page's words), with 「再找一次电表」 and `skipNote`.
    case failed(String)

    public static let retry = "再找一次电表"
    public static let skipNote = "电表先跳过，之后在设置 › 电表里选。"

    public var text: String? {
        switch self {
        case .hidden: return nil
        case .finding: return MeterPageText.finding
        case .ask(let q): return q.text
        case .failed(let text): return text
        }
    }

    /// `running`: the lookup runs (again); `bound`: a meter is bound; `stop` and `issue`: what
    /// the last lookup left.
    public init(running: Bool, bound: Bool, stop: MeterWalkStop?, issue: String?, address: DormAddress?) {
        if running { self = .finding; return }
        guard !bound else { self = .hidden; return }
        if let stop, let q = MeterQuestion(stop, address: address) { self = .ask(q); return }
        if let issue, issue != MeterPageText.stoppedIssue { self = .failed(MeterPageText.issue(issue)); return }
        self = .hidden
    }
}
