import Foundation
import Core

/// campusdaily://demo/records/<state> — 校园卡记录 over the home demo, on synthetic pages (nothing
/// is read from the school). `list` is also the sample mode's (「先看看示例」), in Release too:
/// - `list`: four weeks of meals, showers, laundry and top-ups (the last three days the home
///   demo's, with its lunch paid with WeChat), then the end;
/// - `loading`: the first read never answers;
/// - `more`: two days, then the older read never answers (the footer spinner);
/// - `end`: today, then nothing older;
/// - `failed`: the first read fails; the app's own shower and laundry order show alone;
/// - `more-failed`: two days, then the older read fails;
/// - `empty`: the school has nothing and the app has nothing;
/// - `open` (清爽): `list` under a shower that is running and a laundry order that is washing;
/// - `signed-out` (清爽): nobody signed in.
enum RecordsDemo: String {
    case list, loading, more, end, failed
    case moreFailed = "more-failed"
    case empty, open
    case signedOut = "signed-out"

    #if DEBUG
    static func handle(_ url: URL) -> RecordsDemo? {
        guard url.scheme == "campusdaily", url.host == "demo" else { return nil }
        let parts = Array(url.pathComponents.dropFirst())
        guard parts.first == "records" else { return nil }
        return RecordsDemo(rawValue:parts.count > 1 ? parts[1] : "list")
    }
    #endif

    /// The app's own records: those of the home demo, none for `empty`.
    func app(now: Date = Date()) -> [AppActivity] {
        self == .empty ? [] : HomeData.sample(now:now).appActivities
    }

    var source: CardRecordsSource {
        let demo = self
        let rows = SampleData.cardRecords(days:demo.days, now:Date())
        return CardRecordsSource(stamp:{ 0 }, page:{ query, _ in
            try await Task.sleep(for:.milliseconds(500))
            let firstRange = query.end == SchoolCalendar.dayString(Date())
            switch demo {
            case .loading: try await Task.sleep(for:.seconds(3600))
            case .failed: throw ServiceError.offline
            case .more where !firstRange: try await Task.sleep(for:.seconds(3600))
            case .moreFailed where !firstRange: throw ServiceError.offline
            default: break
            }
            return SampleData.recordPage(rows, query)
        })
    }

    /// Days back from today that have records.
    private var days: [Int] {
        switch self {
        case .list, .open: return SampleData.recordDays
        case .loading, .failed, .empty, .signedOut: return []
        case .more, .moreFailed: return [0, 1, 16, 17]
        case .end: return [0]
        }
    }
}
