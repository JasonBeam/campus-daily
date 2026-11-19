import Core

extension HomeRoute {
    /// 暖橙's stack taking `new` over `old`: while a shower is on (`ShowerPageFlow.opensPageOnRoute`)
    /// a push of 热水 (home's 最近, 校园卡记录) brings up the timer page instead of the 热水洗澡
    /// screen, the pages under it staying. Anything else goes through as it is.
    static func opened(_ new: [HomeRoute], over old: [HomeRoute], page: ShowerPageFlow) -> (routes: [HomeRoute], showsPage: Bool) {
        guard page.opensPageOnRoute, new.count > old.count, new.last == .shower,
              Array(new.prefix(old.count)) == old else { return (new, false) }
        return (Array(new.dropLast()), true)
    }
}
