import SwiftUI
import Core

/// One row of 提醒. With system notifications off: switches off and disabled, plus a row to Settings.
/// Its handlers are `SettingsReminderHandlers`, applied to the list.
struct SettingsReminderRow: View {
    let item: SettingsItem
    /// 「学校洗衣机」 is on: 「洗衣洗好时」 is shown.
    let laundryOn: Bool
    @AppStorage(ReminderKey.powerLow) private var powerAlert = true
    @AppStorage(ReminderKey.cardLow) private var cardAlert = true
    @AppStorage(ReminderKey.unsettledMinutes) private var unsettledMinutes = 30
    @AppStorage(ReminderKey.laundryDone) private var laundryAlert = true
    @AppStorage(ReminderKey.powerLine) private var powerLine = 10
    @AppStorage(ReminderKey.cardLine) private var cardLine = 20
    @EnvironmentObject private var reminders: Reminders
    @Environment(\.openURL) private var openURL
    @Environment(SampleMode.self) private var sample

    var body: some View {
        row.tint(.green)
    }

    @ViewBuilder private var row: some View {
        let off = reminders.denied
        switch item {
        case .powerLow:
            Toggle(isOn:off ? .constant(false) : held($powerAlert)) {
                lineLabel("电量低于", value:held($powerLine), choices:[5, 10, 15, 20, 30], unit:" 度", off:off)
            }.disabled(off)
        case .cardLow:
            Toggle(isOn:off ? .constant(false) : held($cardAlert)) {
                lineLabel("校园卡低于", value:held($cardLine), choices:[10, 20, 30, 50], unit:" 元", off:off)
            }.disabled(off)
        case .unsettled:
            if off {
                // A disabled navigation-link Picker is dimmed by the system on top of ink2, so it read lighter
                // than the three switches. Off: a static row in the same ink2 as their labels.
                HStack {
                    Text("洗完澡没结算").foregroundStyle(Theme.ink2)
                    Spacer()
                    Text(unsettledMinutes > 0 ? "\(unsettledMinutes) 分钟后" : "不提醒").foregroundStyle(Theme.ink2)
                    Image(systemName:"chevron.right").font(.system(size:13, weight:.semibold)).foregroundStyle(Theme.ink3)
                        .accessibilityHidden(true)
                }
                .accessibilityElement(children:.combine)
            } else {
                Picker(selection:held($unsettledMinutes)) {
                    ForEach([15, 30, 60], id:\.self) { Text("\($0) 分钟后").tag($0) }
                    Text("不提醒").tag(0)
                } label: { Text("洗完澡没结算").foregroundStyle(Theme.ink) }
                .pickerStyle(.navigationLink)
            }
        case .laundryDone:
            if laundryOn {
                // Hidden with 学校洗衣机 off; its value is kept.
                Toggle(isOn:off ? .constant(false) : held($laundryAlert)) {
                    Text("洗衣洗好时").foregroundStyle(off ? Theme.ink2 : Theme.ink)
                }.disabled(off)
            }
        case .notifications:
            if off {
                actionRow("去系统设置打开通知") {
                    if let url = URL(string:UIApplication.openNotificationSettingsURLString) { openURL(url) }
                }
            } else if reminders.notAsked {
                // Not asked yet: the switches read on; this row explains and asks. Gone once the system has asked.
                actionRow("打开提醒") {
                    if sample.isActive { sample.perform(.reminders) {}; return }
                    reminders.showPrompt(from:.settings)
                }
            }
        default:
            EmptyView()
        }
    }

    /// The stored value; in the sample a change is not stored, it says `SampleCopy.blocked`.
    private func held<T>(_ binding: Binding<T>) -> Binding<T> {
        guard sample.isActive else { return binding }
        return Binding(get:{ binding.wrappedValue }, set:{ _ in sample.perform(.reminders) {} })
    }

    /// Accent title + chevron (「去系统设置打开通知」/「打开提醒」).
    private func actionRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action:action) {
            HStack {
                Text(title).foregroundStyle(Theme.accentText)
                Spacer()
                Image(systemName:"chevron.right").font(.system(size:13, weight:.semibold)).foregroundStyle(Theme.ink3)
                    .accessibilityHidden(true)
            }
        }
    }
    /// 「电量低于 10 度」: the number opens a menu of lines (shared with home and the widget).
    private func lineLabel(_ lead: String, value: Binding<Int>, choices: [Int], unit: String, off: Bool) -> some View {
        HStack(spacing:4) {
            Text(lead).foregroundStyle(off ? Theme.ink2 : Theme.ink)
            Menu {
                Picker(lead, selection:value) { ForEach(choices, id:\.self) { Text("\($0)" + unit).tag($0) } }
            } label: {
                HStack(spacing:2) {
                    Text("\(value.wrappedValue)" + unit)
                    Image(systemName:"chevron.up.chevron.down").font(.system(size:11, weight:.semibold)).accessibilityHidden(true)
                }
                .foregroundStyle(off ? Theme.ink2 : Theme.accentText)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(lead + " \(value.wrappedValue)" + unit)
        }
    }
}
