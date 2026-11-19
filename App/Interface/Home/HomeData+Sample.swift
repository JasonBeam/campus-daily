import Foundation
import Core

extension HomeData {
    /// Home on the synthetic data (`SampleData`): what 「先看看示例」 shows, and the DEBUG demos'
    /// starting point. Signed in to a made-up account, everything bound and idle.
    static func sample(now: Date = Date()) -> HomeData {
        var data = HomeData()
        data.dorm = SampleData.dorm
        data.dormLocation = SampleData.dormLocation
        data.meterLocation = SampleData.dormLocation
        data.schoolAccount = SchoolAccount(account:SampleData.account)
        data.snapshot = SampleData.homeSnapshot(now:now)
        data.lastShowerMinutes = SampleData.lastShowerMinutes
        data.lastShowerCost = SampleData.lastShowerCost.yuan
        data.lastShowerEnded = now.addingTimeInterval(-SampleData.showerAgo)
        data.laundryBound = true
        data.laundryMachine = SampleData.laundryMachine
        data.laundry = .idle
        data.appActivities = SampleData.appActivities(now:now)
        return data
    }
}
