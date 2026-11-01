import Foundation
import Core

extension CardRecordsSource {
    /// The school session: pages for the person signed in when the list was read from today.
    @MainActor static var live: CardRecordsSource {
        let session = AppEnvironment.school
        return CardRecordsSource(stamp:{ await session.personStamp() },
                                 page:{ query, stamp in try await session.cardHistoryPage(query, since:stamp) },
                                 samePerson:{ await session.isSamePerson(since:$0) },
                                 renew:{ await CampusModel.shared.renewCardSession() })
    }
}

/// 校园卡记录's state for SwiftUI, over Core's `CardRecordsLoader`. Nothing is stored: every
/// visit (and every pull) starts from today.
@MainActor final class CardRecordsModel: ObservableObject {
    @Published private(set) var state = CardRecordsState()
    private let loader: CardRecordsLoader

    init(source: CardRecordsSource) {
        loader = CardRecordsLoader(source:source)
        loader.changed = { [weak self] in self?.state = $0 }
    }

    var phase: CardRecordsState.Phase { state.phase }
    var history: CardHistory? { state.history }
    var loadingMore: Bool { state.loadingMore }
    var moreFailed: Bool { state.moreFailed }
    var reloads: Int { state.reloads }

    /// From today again (first visit, pull).
    func reload() async { await loader.reload() }
    /// Older records: when the list's end appears, or 「点这里再试」.
    func loadMore() async { await loader.loadMore() }
}
