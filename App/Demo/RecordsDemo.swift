#if DEBUG
import Foundation
import Core

/// campusdaily://demo/records/<state> — 校园卡记录 over the home demo, on synthetic pages (nothing
/// is read from the school):
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

    static func handle(_ url: URL) -> RecordsDemo? {
        guard url.scheme == "campusdaily", url.host == "demo" else { return nil }
        let parts = Array(url.pathComponents.dropFirst())
        guard parts.first == "records" else { return nil }
        return RecordsDemo(rawValue:parts.count > 1 ? parts[1] : "list")
    }

    /// The app's own records: those of the home demo, none for `empty`.
    func app(now: Date = Date()) -> [AppActivity] {
        self == .empty ? [] : HomeDemo.normal.content(now:now).0.appActivities
    }

    var source: CardRecordsSource {
        let demo = self
        let rows = Self.records(days:demo.days, now:Date())
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
            let inRange = rows.filter { $0.date >= query.begin && $0.date <= query.end }
            let start = (query.page - 1) * query.pageSize
            let page = start < inRange.count ? Array(inRange[start..<min(inRange.count, start + query.pageSize)]) : []
            return CardRecordPage(total:inRange.count, rows:page)
        })
    }

    /// Days back from today that have records.
    private var days: [Int] {
        switch self {
        case .list, .open: return Array(0..<28)
        case .loading, .failed, .empty, .signedOut: return []
        case .more, .moreFailed: return [0, 1, 16, 17]
        case .end: return [0]
        }
    }

    /// The last three days are the home demo's records (its meals, shower, laundry order and
    /// top-up), so 昨天 here sums to home's 昨天花了 under the same names; older days have meals
    /// at meal times, a shower or laundry order every few days and a top-up. Newest first, never
    /// later than a quarter-hour ago.
    static func records(days: [Int], now: Date) -> [CardRecord] {
        let school = SchoolCalendar.shanghai
        let today = school.startOfDay(for:now)
        func record(_ moment: Date, _ title: String, _ yuan: String, flag: String? = "1") -> CardRecord {
            let t = school.dateComponents([.hour, .minute, .second], from:moment)
            return CardRecord(date:SchoolCalendar.dayString(moment, calendar:school),
                              time:String(format:"%02d%02d%02d", t.hour ?? 0, t.minute ?? 0, t.second ?? 0), title:title,
                              amount:Money(yuanString:yuan)!, balanceAfter:nil, direction:flag)
        }
        func day(_ back: Int) -> Date { school.date(byAdding:.day, value:-back, to:today) ?? today }
        func at(_ hour: Int, _ minute: Int, _ back: Int) -> Date {
            school.date(bySettingHour:hour, minute:minute, second:0, of:day(back)) ?? day(back)
        }
        let home = HomeDemo.snapshot(now:now, read:now, kwh:"0", dailyKWh:"0").activity.value?.records ?? []
        var rows: [CardRecord] = []
        for back in days {
            if back < 3 {
                rows += home.filter { $0.date == SchoolCalendar.dayString(day(back), calendar:school) }
                continue
            }
            rows.append(record(at(7, 42 - back % 5, back), "POS消费示例早餐铺", ["4.50", "3.00", "5.50"][back % 3]))
            rows.append(record(at(12, 16 + back % 7, back), "POS消费示例面馆", ["12.00", "15.50", "11.00", "13.00"][back % 4]))
            if back % 4 != 3 { rows.append(record(at(17, 58 - back % 9, back), "POS消费示例面馆", ["9.00", "8.50", "10.00"][back % 3])) }
            if back % 3 == 2 { rows.append(record(at(21, 30, back), "蓝牙热水", "1.10")) }
            if back % 5 == 4 { rows.append(record(at(19, 12, back), "洗衣", "4.00")) }
            if back == 15 { rows.append(record(at(13, 5, back), "校园卡充值", "50.00", flag:nil)) }
        }
        // Each with a voucher, as the school gives them (synthetic: 99 and a zero-padded counter).
        // A meal paid with WeChat comes as the school sends it: WeChat's money in, then the
        // canteen's payment, under one voucher.
        return rows.filter { ($0.moment(calendar:school) ?? now) <= now.addingTimeInterval(-15 * 60) }
            .sorted { ($0.moment(calendar:school) ?? now) > ($1.moment(calendar:school) ?? now) }
            .enumerated().flatMap { i, row -> [CardRecord] in
                var row = row
                row.voucher = String(format:"99%018d", i + 1)
                guard row.paidWithWeChat else { return [row] }
                row.paidWithWeChat = false
                var wechat = row
                wechat.title = "微信支付(手机)"
                wechat.direction = "2"
                return [wechat, row]
            }
    }
}
#endif
