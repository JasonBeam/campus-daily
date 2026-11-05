import SwiftUI
import Core

extension ClearRootView {
    /// On the sample's root (its own graph, `SampleScene`): every tab on the sample's data
    /// (`HomeData.sample`), the washer idle, 记录 on its four weeks. The live root is not shown
    /// while the sample is on; leaving (去登录) shows it again, as it was launched.
    func followSample(_ active: Bool) {
        if active {
            navigator.setup = nil; navigator.relogin = false; navigator.panel = nil
            navigator.demo = HomeData.sample()
            navigator.laundryDemo = LaundryDemo.make(.idle)
            navigator.recordsDemo = .list
            popAll(from:.sample)
            return
        }
        // Launched outside the sample: nothing to undo.
        guard navigator.demo != nil || navigator.laundryDemo != nil || navigator.recordsDemo != nil else { return }
        navigator.demo = nil; navigator.laundryDemo = nil; navigator.recordsDemo = nil
        navigator.panel = nil
        popAll(from:.sample)
    }

    /// 去登录: 学校账号 on the checklist, on this root or on the one shown after the sample's
    /// theme went.
    func openLoginAfterSample(_ due: Bool) {
        guard due, sample.takeLogin() else { return }
        // Let a closing sheet go first, otherwise the new one is not presented. A newer link in
        // the meantime wins (`destination`).
        destination.after(600) { navigator.openSetup(at:.account, from:.sample) }
    }
}
