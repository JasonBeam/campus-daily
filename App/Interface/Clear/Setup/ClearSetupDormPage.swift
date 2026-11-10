import SwiftUI
import Core

/// Checklist › 宿舍: the first-run guide's dorm step (the dorm read from the school account,
/// the meter under it, 「就是这间」 binding the dorm's controller, 「换一间」) on a pushed page.
/// Confirmed, it saves the dorm as the checklist's and goes back there.
struct ClearSetupDormPage: View {
    let done: () -> Void
    @EnvironmentObject private var campus: CampusModel
    @EnvironmentObject private var water: ShowerModel
    @AppStorage(SetupChecklist.dormKey) private var confirmedDorm = ""
    /// Binds the dorm's hot-water controller when 「就是这间」 confirms the dorm.
    @StateObject private var dormFlow = DormSetupFlow()
    @State private var bindingWater = false
    /// Automatic binding already needed the dorm screen once; the next 「就是这间」 just confirms
    /// (hot water can be finished later from 设置 › 热水).
    @State private var bindTried = false
    @State private var dormPicker = false
    /// Same-name apartment picked (candidate id); confirmed by 「就是这间」.
    @State private var apartment: String?
    @State private var meterAsked: DormStepMeterStatus.Asked
    @State private var meterHalted: MeterWalkStop?
    @State private var meterPage = false

    #if DEBUG
    /// DEBUG demo values (`OnboardingDemo`): nothing is bound, the buttons only go back.
    let preview: OnboardingView.Preview?
    init(preview: OnboardingView.Preview? = nil, done: @escaping () -> Void) {
        self.preview = preview; self.done = done
        _apartment = State(initialValue:preview?.picked)
        _meterAsked = State(initialValue:DormStepMeterStatus.Asked(pick:preview?.meterPicked))
    }
    private var previewing: Bool { preview != nil }
    private var dorm: String? { previewing ? preview?.dorm : Theme.dorm(campus.room) }
    private var dormLocation: String? { previewing ? preview?.dormLocation : campus.profile?.directoryDormLocation }
    private var previewMeter: DormStepMeter? { preview.map { $0.meter ?? .hidden } }
    private var choices: [LocationChoice] { preview?.powerChoices ?? campus.powerChoices.map(\.choice) }
    #else
    init(done: @escaping () -> Void) {
        self.done = done
        _apartment = State(initialValue:nil)
        _meterAsked = State(initialValue:DormStepMeterStatus.Asked())
    }
    private var previewing: Bool { false }
    private var dorm: String? { Theme.dorm(campus.room) }
    private var dormLocation: String? { campus.profile?.directoryDormLocation }
    private var previewMeter: DormStepMeter? { nil }
    private var choices: [LocationChoice] { campus.powerChoices.map(\.choice) }
    #endif

    /// The school lists apartments with the dorm's name: 「就是这间」 waits for a choice.
    private var choosingApartment: Bool { !choices.isEmpty }

    var body: some View {
        ClearSetupStep(navTitle:SetupChecklist.title(.dorm), heading:heading, message:message) {
            if !choosingApartment, let dorm { dormCard(dorm) }
            if choosingApartment { apartmentList }
            if let issue = dormFlow.issue {
                Label { ClearNoticeText(issue).fixedSize(horizontal:false, vertical:true) } icon: { Image(systemName:"exclamationmark.circle") }
                    .font(.footnote).foregroundStyle(Theme.notice)
            }
        } buttons: {
            ClearSetupButton(title:primaryTitle, symbol:"checkmark", busy:bindingWater, action:primary)
                .disabled(bindingWater || choosingApartment && (apartment == nil || campus.matchingPower))
                .accessibilityIdentifier("onboardingPrimary")
            if dorm != nil {
                ClearSetupTextButton(title:choosingApartment ? "都不是，换一间" : "换一间") { openDormPicker() }
            }
        }
        .navigationDestination(isPresented:$dormPicker) { CampusOnboardingView() }
        .navigationDestination(isPresented:$meterPage) { CampusPowerSetupView(start:meterHalted) }
        // The dorm screen saved a controller: the dorm is set.
        .onChange(of:water.configured) { _, bound in if bound, !previewing { confirm() } }
    }

    private var heading: String {
        if choosingApartment { return SameNameText.titleLead + SameNameText.titleAccent + SameNameText.titleTail }
        return "你住哪间？"
    }

    private var message: String {
        if choosingApartment { return SameNameText.hint(choices) }
        return dorm != nil ? "电量和热水都按这间宿舍来。" : "没读到你的宿舍，手动选一下。"
    }

    private var primaryTitle: String {
        bindingWater ? "正在找宿舍的水控…" : dorm != nil ? "就是这间" : "选宿舍"
    }

    /// The dorm, its full location when the electricity directory gave one (what tells
    /// same-name dorms apart), where it came from, and the meter lookup under it.
    private func dormCard(_ dorm: String) -> some View {
        VStack(alignment:.leading, spacing:0) {
            VStack(alignment:.leading, spacing:6) {
                Text(dorm).font(.system(size:34, weight:.semibold)).monospacedDigit().foregroundStyle(Theme.ink)
                    .minimumScaleFactor(0.6).lineLimit(1)
                if let dormLocation {
                    Text(dormLocation).font(.subheadline).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal:false, vertical:true)
                }
                Text(OnboardingView.dormSource).font(.caption).foregroundStyle(Theme.ink2)
            }
            .padding(16)
            .frame(maxWidth:.infinity, alignment:.leading)
            .background(Theme.group, in:RoundedRectangle(cornerRadius:16, style:.continuous))
            DormStepMeterStatus(asked:$meterAsked, preview:previewMeter, previewing:previewing) { halted in
                meterHalted = halted; meterPage = true
            }
            .padding(.horizontal,4)
        }
    }

    /// Upstream 0.8.0-beta.2: the school directory can list two buildings with the same name.
    /// Automatic meter matching then needs the student to pick the right one once, by its full
    /// location (shared single-select list; 「就是这间」 confirms).
    private var apartmentList: some View {
        VStack(alignment:.leading, spacing:0) {
            LocationChoiceList(choices:choices, selection:$apartment)
                .disabled(campus.matchingPower)
                // A new list: an earlier pick may no longer be in it.
                .onChange(of:campus.powerChoices) { _, _ in if !previewing { apartment = nil } }
            if !previewing, let issue = campus.powerMatchIssue {
                Text(issue).font(.subheadline).foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal:false, vertical:true).padding(.top,8)
                Button("再找一次电表") { campus.matchPowerAutomatically() }
                    .font(.body.weight(.medium)).foregroundStyle(Theme.accentText)
                    .frame(minHeight:44).disabled(campus.matchingPower)
            }
        }
    }

    private func primary() {
        if choosingApartment {
            guard let apartment else { return }
            if previewing { done(); return }
            // On only once the meter is saved: a pick that is gone from the list, or a save that
            // failed (said on this page), stays here.
            guard let candidate = campus.powerChoices.first(where:{ $0.id == apartment }) else { self.apartment = nil; return }
            Task { if await campus.choosePower(candidate) { bindWaterThenConfirm() } }
        } else if dorm != nil { bindWaterThenConfirm() } else { openDormPicker() }
    }

    /// The dorm is confirmed: bind its hot-water controller too (one room, one controller), or
    /// open the dorm screen once when that needs a choice. Never blocks the checklist.
    private func bindWaterThenConfirm() {
        guard !previewing else { done(); return }
        guard !bindTried, !water.configured else { confirm(); return }
        guard !bindingWater else { return }
        bindingWater = true
        Task {
            let result = await dormFlow.autoBind(campus:campus, water:water)
            bindingWater = false
            switch result {
            case .bound, .unavailable: confirm()
            case .needsChoice: bindTried = true; openDormPicker()
            }
        }
    }

    private func confirm() {
        if let dorm { confirmedDorm = dorm }
        done()
    }

    private func openDormPicker() {
        guard !previewing else { return }
        dormPicker = true
    }
}
