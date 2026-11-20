import SwiftUI
import Core

/// 「先看看示例」's bar over every page while the sample is on: 「示例，不是你的账号」,
/// 换个样子 (「选一个样子」 over the sample, `LookPicker`) and 去登录, back to the login step.
/// VoiceOver reads it as one element whose actions are 去登录 and 换个样子.
struct SampleBar: View {
    @Environment(SampleMode.self) private var sample
    @Environment(LookPicker.self) private var picker: LookPicker?
    /// The sample's theme, shown at once when a look is picked.
    @Environment(ThemeStore.self) private var themeStore
    @State private var picking = false
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Picked in the cover: applied once it has gone (the theme switch replaces this page).
    @State private var picked: AppTheme?

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                // Too wide for one row at these sizes: the words over the buttons, and the buttons
                // under each other when side by side would still run off the screen.
                VStack(alignment:.leading, spacing:6) {
                    HStack(alignment:.firstTextBaseline, spacing:12) { eye; words }
                    ViewThatFits(in:.horizontal) {
                        HStack(spacing:12) { buttons }
                        VStack(alignment:.leading, spacing:0) { buttons }
                    }
                }
                .frame(maxWidth:.infinity, alignment:.leading)
            } else {
                HStack(spacing:12) {
                    eye
                    words
                    Spacer(minLength:8)
                    buttons
                }
            }
        }
        // 20 pt in from the screen edges, as the pages under it.
        .padding(.horizontal,20).padding(.vertical,4)
        .frame(maxWidth:.infinity)
        .background {
            ZStack { Rectangle().fill(.ultraThinMaterial); Theme.group.opacity(0.9) }.ignoresSafeArea(edges:.top)
        }
        .overlay(alignment:.bottom) { Rectangle().fill(Theme.separator).frame(height:0.5) }
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(SampleCopy.barSpoken)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { sample.leave() }
        .accessibilityAction(named:SampleCopy.barLook) { openPicker() }
        .accessibilityIdentifier("sampleBar")
        .fullScreenCover(isPresented:$picking, onDismiss:{
            picker?.dismiss()
            if let theme = picked { picked = nil; picker?.choose(theme, shownOn:themeStore) }
        }) {
            LookPickerView(mode:.sample, choose:{ theme in picked = theme; picking = false },
                           close:{ picking = false })
        }
    }

    private var eye: some View {
        Image(systemName:"eye").font(.system(size:15, weight:.semibold)).foregroundStyle(Theme.ink2)
            .accessibilityHidden(true)
    }

    private var words: some View {
        Text(SampleCopy.barText).scaledFont(15, .medium, relativeTo:.subheadline).foregroundStyle(Theme.ink)
            // One line; at accessibility sizes, where the buttons are below, as many as it takes.
            .lineLimit(typeSize.isAccessibilitySize ? nil : 1).minimumScaleFactor(typeSize.isAccessibilitySize ? 1 : 0.8)
            .fixedSize(horizontal:false, vertical:typeSize.isAccessibilitySize)
    }

    @ViewBuilder private var buttons: some View {
        if picker != nil {
            Button { openPicker() } label: {
                Text(SampleCopy.barLook).scaledFont(15, .semibold, relativeTo:.subheadline).foregroundStyle(Theme.ink)
                    .padding(.horizontal,14).frame(minHeight:34)
                    .background(Theme.bg, in:Capsule())
                    .overlay { Capsule().strokeBorder(Theme.separator, lineWidth:0.5) }
                    .contentShape(Capsule())
                    .fixedSize()
            }
            .buttonStyle(PressScaleStyle())
            .frame(minHeight:44)
            .accessibilityIdentifier("sampleLook")
        }
        Button { sample.leave() } label: {
            Text(SampleCopy.barAction).scaledFont(15, .semibold, relativeTo:.subheadline).foregroundStyle(Theme.pillInk)
                .padding(.horizontal,14).frame(minHeight:34)
                .background(Theme.pill, in:Capsule())
                .contentShape(Capsule())
                .fixedSize()
        }
        .buttonStyle(PressScaleStyle())
        .frame(minHeight:44)
    }

    private func openPicker() {
        picker?.present(.sample)
        picking = true
    }
}

/// The pages wearing `SampleChrome` now on screen, the root first and the sheet or cover on
/// top last. Only the top one shows the blocked message: two alerts on one state would have the
/// root's close the sheet over it.
@MainActor @Observable final class SampleAlertStack {
    private(set) var shown: [UUID] = []
    func appeared(_ id: UUID) { shown.removeAll { $0 == id }; shown.append(id) }
    func disappeared(_ id: UUID) { shown.removeAll { $0 == id } }
}

/// The bar on top and the blocked-action message, on a root and on every sheet or cover over
/// it (an alert from the root does not show above a sheet).
struct SampleChrome: ViewModifier {
    @Environment(SampleMode.self) private var sample
    @Environment(SampleAlertStack.self) private var stack
    @State private var id = UUID()
    /// Inside 「选一个样子」's previews: no bar.
    @Environment(\.lookPreview) private var lookPreview
    /// False where the root's bar already shows (a sheet that leaves it visible).
    var bar = true

    func body(content: Content) -> some View {
        // Above the page, not a safe-area inset: a navigation bar would stay under an inset.
        VStack(spacing:0) {
            if bar && sample.isActive && !lookPreview { SampleBar() }
            content
        }
            .alert(SampleCopy.blocked, isPresented:Binding(get:{ sample.blocked != nil && stack.shown.last == id },
                                                           set:{ if !$0 { sample.blocked = nil } })) {
                Button("好", role:.cancel) {}
            }
            .onAppear { stack.appeared(id) }
            .onDisappear { stack.disappeared(id) }
    }
}

extension View {
    func sampleChrome(bar: Bool = true) -> some View { modifier(SampleChrome(bar:bar)) }
}

/// A row whose page needs a real account or device: in the sample it says `SampleCopy.blocked`
/// instead of opening; outside it is the row as given (a link, usually).
struct SampleGatedRow<Row: View, Label: View>: View {
    @Environment(SampleMode.self) private var sample
    let action: SampleAction
    @ViewBuilder let row: Row
    @ViewBuilder let label: Label

    var body: some View {
        if sample.isActive {
            Button { sample.perform(action) {} } label: { label }
        } else {
            row
        }
    }
}

/// A settings row as a button: the row and the system disclosure chevron, as a link draws it.
struct SampleRowLabel<Row: View>: View {
    let row: Row
    var body: some View {
        HStack(spacing:10) {
            row
            Image(systemName:"chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.ink3)
                .padding(.trailing,2)
                .accessibilityHidden(true)
        }
    }
}

/// 余额 in the sample: the balance over 校园卡记录 on the sample's records; 充值 opens 校园充值,
/// which only leaves for the school's WeChat service or web page (nothing is read after).
/// (The live 余额 is 校园充值 itself.)
struct SampleCardPage: View {
    let data: HomeData

    var body: some View {
        CardRecordsView(app:RecordsDemo.list.app(), source:RecordsDemo.list.source)
            .safeAreaInset(edge:.bottom) {
                DockBar {
                    NavigationLink { CampusTopUpView() } label: { DockPillLabel(title:"充值") }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityIdentifier("sampleCardRecharge")
                }
            }
    }
}

/// 电量 in the sample: the room, what is left and the daily use from the sample's meter;
/// 充值 opens 校园充值 and 电表 is blocked. (The live 电量 is 校园充值 itself.)
struct SamplePowerPage: View {
    let data: HomeData
    /// 「4.6 度」: the daily average behind the meter's days left, 「—」 without one.
    static func dailyUse(_ meter: Meter?) -> String {
        meter?.averageDailyKWh.map { Theme.kwh($0) + " 度" } ?? "—"
    }
    @Environment(SampleMode.self) private var sample

    var body: some View {
        let meter = data.snapshot.power.value
        let figure = data.powerFigure()
        List {
            Section {
                row("宿舍", data.meterLocation ?? data.dorm ?? "")
                row("剩余电量", meter?.remainingKWh.map { Theme.kwh($0) + " 度" } ?? "—")
                row(CampusFormat.dailyAverageLabel, Self.dailyUse(meter))
                if let subline = figure.subline { row("预计", subline.text) }
            } footer: {
                if let read = data.snapshot.power.fetchedAt {
                    Text("读取于 " + ClearBalanceText.dateTime(read))
                }
            }
            .listRowBackground(Theme.group)
            Section {
                Button { sample.perform(.bindMeter) {} } label: { ChevronRow(title:"电表") }
                    .accessibilityIdentifier("sampleBindMeter")
            }
            .listRowBackground(Theme.group)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("电量").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge:.bottom) {
            DockBar {
                NavigationLink { CampusTopUpView() } label: { DockPillLabel(title:"充值") }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityIdentifier("samplePowerRecharge")
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Theme.ink2)
            Spacer()
            Text(value).foregroundStyle(Theme.ink).monospacedDigit().multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children:.combine)
    }
}
