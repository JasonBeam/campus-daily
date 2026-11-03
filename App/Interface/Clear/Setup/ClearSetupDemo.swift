#if DEBUG
import Core

/// campusdaily://demo/onboard/... in 清爽: the checklist opens with the guide step's row pushed,
/// the rows before it done, and the step page on the demo's values (`OnboardingDemo`).
/// `onboard/done`: every row done.
struct ClearSetupDemo {
    let values: OnboardingView.Preview
    /// The row pushed; nil = all done.
    let start: ClearSetupRow?

    var list: SetupChecklist {
        let order = ClearSetupRow.allCases
        let reached = start.flatMap { order.firstIndex(of:$0) } ?? order.count
        func done(_ row: ClearSetupRow) -> Bool { order.firstIndex(of:row)! < reached }
        return SetupChecklist(signedIn:done(.account), dorm:done(.dorm) ? values.dorm ?? "3 栋 108" : nil,
                              laundry:done(.laundry) ? .machine("3 号机") : .open,
                              controllerBound:true, controllerChecked:done(.controller))
    }
}
#endif
