import SwiftUI
import Core

/// Checklist › 学校洗衣机: the first-run guide's question. 「用，接着设置」 opens the U净 login or
/// 常用洗衣机 as there; a machine saved, or 「不用」, goes back to the checklist.
struct ClearSetupLaundryPage: View {
    let done: () -> Void
    /// DEBUG demo (`OnboardingDemo`): nothing is changed, the buttons only go back.
    var previewing = false
    @EnvironmentObject private var laundry: LaundryModel
    @State private var ujing = false
    @State private var washer = false

    var body: some View {
        ClearSetupStep(navTitle:SetupChecklist.title(.laundry), heading:SchoolLaundryPreference.Onboarding.title,
                       message:SchoolLaundryPreference.Onboarding.subtitle) {
            EmptyView()
        } buttons: {
            ClearSetupButton(title:SchoolLaundryPreference.Onboarding.yes, action:use)
                .accessibilityIdentifier("onboardingPrimary")
            ClearSetupTextButton(title:SchoolLaundryPreference.Onboarding.no, action:skip)
            Text(SchoolLaundryPreference.Onboarding.note)
                .font(.footnote).foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center).fixedSize(horizontal:false, vertical:true)
        }
        .navigationDestination(isPresented:$washer) { WasherSetupView() }
        .sheet(isPresented:$ujing) { UjingLoginView() }
        .onChange(of:laundry.savedMachines.count) { old, new in
            if !previewing, new > old { done() }
        }
    }

    /// 用，接着设置: the U净 login / scan flow, as in the guide.
    private func use() {
        if previewing { done(); return }
        laundry.setSchoolEnabled(true)
        if laundry.accountConnected { washer = true } else { ujing = true }
    }

    /// 不用: laundry hidden everywhere (changeable in 设置).
    private func skip() {
        if !previewing { laundry.setSchoolEnabled(false) }
        done()
    }
}
