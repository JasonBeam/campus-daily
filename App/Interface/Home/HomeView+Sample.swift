import SwiftUI
import Core

extension HomeView {
    /// On the sample's root (its own graph, `SampleScene`): home and its pages on the sample's
    /// data (`HomeData.sample`), the washer idle, 校园卡记录 on its four weeks. The live root is
    /// not shown while the sample is on; leaving (去登录) shows it again.
    func followSample(_ active: Bool) {
        if active {
            onboarding = nil; settings = false; path = []; pathAfterSettings = nil; panel = nil
            demo = HomeData.sample()
            laundryDemo = LaundryDemo.make(.idle)
            recordsDemo = .list
            return
        }
        // Launched outside the sample: nothing to undo.
        guard demo != nil || laundryDemo != nil || recordsDemo != nil else { return }
        settings = false; path = []; pathAfterSettings = nil; panel = nil
        demo = nil; laundryDemo = nil; recordsDemo = nil
    }

    /// 去登录: the login step, on this root or on the one shown after the sample's theme went.
    func openLoginAfterSample(_ due: Bool) {
        guard due, sample.takeLogin() else { return }
        // As after a reset: let a sheet go first, or the cover is not presented. A newer link
        // in the meantime wins (`destination`).
        destination.after(600) { openOnboarding(from:.sample) }
    }
}
