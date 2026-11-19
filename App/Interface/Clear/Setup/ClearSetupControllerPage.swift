import SwiftUI
import Core

/// Checklist › 水控: the first-run guide's controller check (same statuses, buttons and call).
/// Found, it goes back to the checklist; 「以后再核对」 goes back without it.
struct ClearSetupControllerPage: View {
    let done: () -> Void
    @EnvironmentObject private var water: ShowerModel
    /// 开始核对 was tapped on this page (an earlier check from Settings is not shown here).
    @State private var checked: Bool

    #if DEBUG
    /// DEBUG demo values (`OnboardingDemo`): nothing connects, the buttons only go back.
    let preview: OnboardingView.Preview?
    init(preview: OnboardingView.Preview? = nil, done: @escaping () -> Void) {
        self.preview = preview; self.done = done
        _checked = State(initialValue:preview?.waterOutcome != nil)
    }
    private var previewing: Bool { preview != nil }
    private var checking: Bool { preview?.waterChecking ?? water.inspecting }
    private var blocked: String? { previewing ? preview?.waterBlocked : water.inspectionBlockedText }
    private var lastOutcome: ShowerModel.InspectionOutcome? { previewing ? preview?.waterOutcome : water.inspectionOutcome }
    #else
    init(done: @escaping () -> Void) {
        self.done = done
        _checked = State(initialValue:false)
    }
    private var previewing: Bool { false }
    private var checking: Bool { water.inspecting }
    private var blocked: String? { water.inspectionBlockedText }
    private var lastOutcome: ShowerModel.InspectionOutcome? { water.inspectionOutcome }
    #endif

    private var outcome: ShowerModel.InspectionOutcome? {
        guard checked, !checking, blocked == nil else { return nil }
        return lastOutcome
    }

    var body: some View {
        ClearSetupStep(navTitle:SetupChecklist.title(.controller), heading:"核对宿舍的水控",
                       message:"站在水控旁边，打开蓝牙。只读编号，不会开水。") {
            ControllerCheckStatus(blocked:blocked, checking:checking, outcome:outcome)
        } buttons: {
            ClearSetupButton(title:primaryTitle, symbol:outcome == .verified ? "checkmark" : "arrow.right", busy:checking, action:primary)
                .disabled(checking && blocked == nil)
                .sensoryFeedback(.success, trigger:outcome == .verified) { _, found in found }
                .accessibilityIdentifier("onboardingPrimary")
            if outcome != .verified && blocked == nil {
                ClearSetupTextButton(title:"以后再核对", action:done)
                    .accessibilityIdentifier("waterLater")
            }
        }
        // Found: a moment to read it, then back to the checklist.
        .task(id:outcome == .verified) {
            guard outcome == .verified, !previewing else { return }
            try? await Task.sleep(for:.seconds(1))
            if !Task.isCancelled { done() }
        }
    }

    private var primaryTitle: String {
        if checking { return "正在核对…" }
        if blocked != nil { return "先跳过" }
        switch outcome {
        case nil, .bluetoothOff?: return "开始核对"
        case .verified?: return "好"
        default: return "再试一次"
        }
    }

    private func primary() {
        if outcome == .verified || blocked != nil || previewing { done(); return }
        checked = true
        Task { await water.inspectBluetooth() }
    }
}
