import Foundation

/// The synthetic data both the DEBUG demos (campusdaily://demo/…) and the Release sample mode
/// (「先看看示例」) show: one made-up dorm, card, meter, washer and shower. Nothing here is read
/// from a service or a store, and nothing is real.
public enum SampleData {
    public static let dorm = "3 栋 108"
    /// 「校区 · 公寓 · 楼栋 · 房间」 of the dorm and of its meter.
    public static let dormLocation = "北校区 · 东苑公寓 · 3 栋 · 108"
    public static let account = "99100991"
    /// The meter's and the snapshot's room label.
    public static let roomLabel = "3栋108"
    public static let laundryMachine = "3"
    public static let lastShowerMinutes = 11
    public static let lastShowerCost = Money(fen: 132)

    /// The sample shower ended this long before now; its card record follows a minute later, so
    /// 最近 shows the shower once.
    public static let showerAgo: TimeInterval = 20 * 3600
    /// The sample laundry order was paid this long before now; its card record follows a minute later.
    public static let laundryAgo: TimeInterval = 44 * 3600

    /// The app's own records: the last shower and the last laundry order.
    public static func appActivities(now: Date) -> [AppActivity] {
        [
            AppActivity(id: "demo-shower", kind: .shower(minutes: lastShowerMinutes), date: now.addingTimeInterval(-showerAgo),
                        amount: lastShowerCost),
            AppActivity(id: "demo-laundry", kind: .laundry(program: "标准洗"), date: now.addingTimeInterval(-laundryAgo),
                        amount: Money(fen: 400), detail: "3 号机"),
        ]
    }

    /// Home as the sample shows it: read 25 minutes ago, 42.6 kWh left at 4.6 a day.
    public static func homeSnapshot(now: Date) -> HomeSnapshot {
        homeSnapshot(now: now, read: now.addingTimeInterval(-25 * 60), kwh: "42.6", dailyKWh: "4.6")
    }

    /// Synthetic balance, meter and card records, never later than `now` (whatever the device's
    /// time zone), written in the school's calendar as the school does. Meals sit at meal times
    /// (07:42, 12:16, 17:58) of the last days, so 最近 reads like a real week.
    public static func homeSnapshot(now: Date, read: Date, kwh: String, dailyKWh: String, balance: String = "86.50") -> HomeSnapshot {
        let school = SchoolCalendar.shanghai
        let range = CardActivity.range(at: now)
        var s = HomeSnapshot()
        s.card.succeed(Money(yuanString: balance)!, at: read)
        s.power.succeed(Meter(comAddress: "demo-meter", name: roomLabel, remainingKWh: Decimal(string: kwh),
                              dailyUseKWh: Decimal(string: dailyKWh)), at: read)
        let today = school.startOfDay(for: now)
        func at(_ hour: Int, _ minute: Int, daysBack: Int) -> Date {
            let day = school.date(byAdding: .day, value: -daysBack, to: today) ?? today
            return school.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        let meals = [(7, 42, "POS消费示例早餐铺", "4.50"), (12, 16, "POS消费示例面馆", "12.00"), (17, 58, "POS消费示例面馆", "9.00")]
        var records = (0..<3).flatMap { back in meals.map { meal in record(at(meal.0, meal.1, daysBack: back), meal.2, meal.3) } }
            .filter { ($0.moment(calendar: school) ?? now) <= now.addingTimeInterval(-15 * 60) }
        records.append(record(now.addingTimeInterval(-showerAgo + 60), "蓝牙热水", "1.32"))
        // The sample laundry order, as the card has it a minute after it was paid.
        records.append(record(now.addingTimeInterval(-laundryAgo + 60), "洗衣", "4.00"))
        records.append(record(at(13, 5, daysBack: 1), "校园卡充值", "50.00", flag: nil))
        // A lunch paid with WeChat, as the home read keeps it once its two records are paired.
        var wechat = record(at(11, 48, daysBack: 1), "POS消费(示例饭堂POS)(示例饭堂POS)02档口示例盖饭", "16.00")
        wechat.paidWithWeChat = true
        records.append(wechat)
        records.sort { ($0.moment(calendar: school) ?? now) > ($1.moment(calendar: school) ?? now) }
        s.activity.succeed(CardActivity(records: records, begin: range.begin, end: range.end, complete: true), at: read)
        s.roomLabel = roomLabel
        return s
    }

    // MARK: 校园卡记录

    /// Days back from today that 校园卡记录 has records for in the full sample: four weeks.
    public static let recordDays = Array(0..<28)

    /// The last three days are home's records (its meals, shower, laundry order and top-up), so
    /// 昨天 here sums to home's 昨天花了 under the same names; older days have meals at meal
    /// times, a shower or laundry order every few days and a top-up. Newest first, never later
    /// than a quarter-hour ago.
    public static func cardRecords(days: [Int], now: Date) -> [CardRecord] {
        let school = SchoolCalendar.shanghai
        let today = school.startOfDay(for: now)
        func day(_ back: Int) -> Date { school.date(byAdding: .day, value: -back, to: today) ?? today }
        func at(_ hour: Int, _ minute: Int, _ back: Int) -> Date {
            school.date(bySettingHour: hour, minute: minute, second: 0, of: day(back)) ?? day(back)
        }
        let home = homeSnapshot(now: now, read: now, kwh: "0", dailyKWh: "0").activity.value?.records ?? []
        var rows: [CardRecord] = []
        for back in days {
            if back < 3 {
                rows += home.filter { $0.date == SchoolCalendar.dayString(day(back), calendar: school) }
                continue
            }
            rows.append(record(at(7, 42 - back % 5, back), "POS消费示例早餐铺", ["4.50", "3.00", "5.50"][back % 3]))
            rows.append(record(at(12, 16 + back % 7, back), "POS消费示例面馆", ["12.00", "15.50", "11.00", "13.00"][back % 4]))
            if back % 4 != 3 { rows.append(record(at(17, 58 - back % 9, back), "POS消费示例面馆", ["9.00", "8.50", "10.00"][back % 3])) }
            if back % 3 == 2 { rows.append(record(at(21, 30, back), "蓝牙热水", "1.10")) }
            if back % 5 == 4 { rows.append(record(at(19, 12, back), "洗衣", "4.00")) }
            if back == 15 { rows.append(record(at(13, 5, back), "校园卡充值", "50.00", flag: nil)) }
        }
        // Each with a voucher, as the school gives them (synthetic: 99 and a zero-padded counter).
        // A meal paid with WeChat comes as the school sends it: WeChat's money in, then the
        // canteen's payment, under one voucher.
        return rows.filter { ($0.moment(calendar: school) ?? now) <= now.addingTimeInterval(-15 * 60) }
            .sorted { ($0.moment(calendar: school) ?? now) > ($1.moment(calendar: school) ?? now) }
            .enumerated().flatMap { i, row -> [CardRecord] in
                var row = row
                row.voucher = String(format: "99%018d", i + 1)
                guard row.paidWithWeChat else { return [row] }
                row.paidWithWeChat = false
                var wechat = row
                wechat.title = "微信支付(手机)"
                wechat.direction = "2"
                return [wechat, row]
            }
    }

    /// One page of `rows` for a query, as the school pages them.
    public static func recordPage(_ rows: [CardRecord], _ query: CardHistoryQuery) -> CardRecordPage {
        let inRange = rows.filter { $0.date >= query.begin && $0.date <= query.end }
        let start = (query.page - 1) * query.pageSize
        let page = start < inRange.count ? Array(inRange[start..<min(inRange.count, start + query.pageSize)]) : []
        return CardRecordPage(total: inRange.count, rows: page)
    }

    /// 校园卡记录 on the full sample, paged after a short wait; nothing is read from the school.
    public static func recordsSource(now: Date = Date(), delay: Duration = .milliseconds(500)) -> CardRecordsSource {
        let rows = cardRecords(days: recordDays, now: now)
        return CardRecordsSource(stamp: { 0 }, page: { query, _ in
            try await Task.sleep(for: delay)
            return recordPage(rows, query)
        })
    }

    // MARK: Laundry

    public static let washerPrograms: [WasherProgram] = [(1, "标准洗", 45, 400), (2, "快洗", 30, 300), (3, "大物洗", 60, 500), (4, "单脱水", 6, 100)].map {
        WasherProgram(id: $0.0, name: $0.1, minutes: $0.2, price: Money(fen: $0.3))
    }

    /// The sample washer, 3 号机 in 4 栋洗衣房, with U净's `status` (0 free, 1 in use, 2 broken,
    /// 8 offline, 9 disabled, 11 reserved) and the order on it.
    public static func washerSnapshot(status: Int, active: String? = nil) -> WasherSnapshot {
        WasherSnapshot(qrCode: "demo",
                       scan: WasherScan(deviceID: "demo-washer", moduleType: 7, status: status, createOrderEnabled: status == 0, activeOrderID: active),
                       info: WasherInfo(deviceID: "demo-washer", deviceNo: laundryMachine, typeName: "波轮洗衣机", storeName: "4 栋洗衣房",
                                        storeID: "demo-store", deviceTypeID: 1, moduleType: 7, programs: washerPrograms),
                       fetchedAt: Date())
    }

    /// A 标准洗 order on the sample washer at `stage`, with U净's order `status` when it has one.
    public static func laundryCheckout(stage: LaundryPhase, status: String?, paid: Bool, remain: Int?, created: Date, now: Date) -> LaundryCheckout {
        let draft = LaundryDraft(deviceID: "demo-washer", qrCode: "demo", machineName: laundryMachine, program: washerPrograms[0],
                                 request: OrderRequest(deviceID: "demo-washer", deviceTypeID: 1, storeID: "demo-store", programID: 1))
        var record = LaundryCheckout(phase: stage, draft: draft, createdAt: created)
        if let status {
            record.orderID = "demo1"
            record.order = LaundryOrder(id: "demo1", deviceID: "demo-washer", status: LaundryOrderStatus(status), paid: paid,
                                        remainSeconds: remain, programID: 1, price: Money(fen: 400),
                                        countDown: status == "10" ? 600 : nil)
            record.orderReadAt = now
        }
        if stage == .none, let status {
            record = LaundryCheckout(lastOutcome: LaundryOutcome(orderID: "demo1", status: LaundryOrderStatus(status), at: now))
        }
        return record
    }

    // MARK: Shower

    /// A shower record on the sample controller, by the demo's name for it: sh-connect, sh-run,
    /// sh-endfail, sh-stopped, sh-stopped-busy(-rechecking), sh-detail-stopped, sh-settle, sh-done, sh-nocon, sh-denied,
    /// sh-busy, sh-unsure (a settlement without an answer: kept for the school, the stopped page).
    /// Nil for any other name.
    public static func showerRecord(_ name: String, now: Date = Date()) -> ShowerState? {
        let start = now.addingTimeInterval(-(8 * 60 + 42))
        func failed(_ reason: ShowerFailureReason, review: Bool) -> ShowerState {
            // Only a failure after the water carries the timer's start.
            ShowerState(phase: .failed, startedAt: reason.isBeforeWater ? nil : start,
                        failure: ShowerFailure(reason: reason, needsReview: review))
        }
        switch name {
        case "sh-connect": return ShowerState(phase: .authorizing)
        case "sh-run", "sh-endfail": return ShowerState(phase: .running, startedAt: start)
        case "sh-stopped", "sh-detail-stopped":
            return ShowerState(phase: .running, startedAt: start, stateReviewRequired: true, notice: .notActive)
        // 开始下一次洗澡 found the controller in use (再查一次 running for -rechecking).
        case "sh-stopped-busy", "sh-stopped-busy-rechecking":
            return ShowerState(phase: .running, startedAt: start, stateReviewRequired: true, notice: .device(.busy), waitingForRelease: true)
        case "sh-settle": return ShowerState(phase: .settling, startedAt: start)
        case "sh-done":
            return ShowerState(phase: .done, startedAt: now.addingTimeInterval(-TimeInterval(lastShowerMinutes) * 60),
                               receipt: ShowerReceipt(amount: lastShowerCost), endedAt: now)
        case "sh-nocon": return failed(.deviceUnavailable, review: false)
        case "sh-denied": return failed(.authorizeRefused, review: false)
        case "sh-busy": return failed(.deviceBusy, review: false)
        case "sh-unsure": return failed(.settleUncertain, review: true)
        default: return nil
        }
    }

    // MARK: -

    private static func record(_ moment: Date, _ title: String, _ yuan: String, flag: String? = "1") -> CardRecord {
        let school = SchoolCalendar.shanghai
        let t = school.dateComponents([.hour, .minute, .second], from: moment)
        return CardRecord(date: SchoolCalendar.dayString(moment, calendar: school),
                          time: String(format: "%02d%02d%02d", t.hour ?? 0, t.minute ?? 0, t.second ?? 0), title: title,
                          amount: Money(yuanString: yuan)!, balanceAfter: nil, direction: flag)
    }
}
