#if DEBUG
import Foundation

extension RecordsDemo {
    /// What 清爽's 记录 shows for this demo, over the home demo's data: `open` adds the home
    /// demo's running shower and washing laundry order, `signed-out` signs out.
    func shown(_ data: HomeData, now: Date = Date()) -> HomeData {
        var data = data
        switch self {
        case .open:
            data.shower = .showering(now.addingTimeInterval(-(8 * 60 + 42)))
            data.laundry = .running(program:"标准洗", end:now.addingTimeInterval(18 * 60 - 30))
        case .signedOut:
            data.signedIn = false
        case .list, .loading, .more, .end, .failed, .moreFailed, .empty:
            break
        }
        return data
    }
}
#endif
