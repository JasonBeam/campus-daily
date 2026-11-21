//
//  DebtShowerSection.swift
//  XiaoRiChang
//
//  Created by @Zach677 on 2026/11/20.
//

import SwiftUI
import Core

/// The debt start setting's own group: the switch with its icon and the footer (copy v2 §3),
/// while `visit` shows it (never in the sample). A turn-off the phone didn't store says so in
/// the footer, in the notice colour, with a retry under it (§5).
struct DebtShowerSection<Below: View>: View {
    @Binding var visit: DebtShowerVisit
    let clear: Bool
    /// Under the footer (清爽: the version, which the group comes right above).
    @ViewBuilder var below: () -> Below
    @EnvironmentObject private var shower: ShowerModel
    @Environment(SampleMode.self) private var sample
    var pending = DebtShowerPending.shared

    var body: some View {
        if visit.shows(pending:pending.unstored) && !sample.isActive {
            Section {
                Toggle(isOn:Binding(get:{ shower.allowsDebt }, set:set)) {
                    SettingsRow(symbol:DebtShowerText.symbol, title:DebtShowerText.title(clear:clear))
                }
                .tint(clear ? NativeTheme.tint : Theme.accent)
                .accessibilityIdentifier("debtShowerToggle")
            } footer: {
                VStack(spacing:0) {
                    footer.frame(maxWidth:.infinity, alignment:.leading)
                    below()
                }
            }
            .listRowBackground(Theme.group)
        }
    }

    @ViewBuilder private var footer: some View {
        if pending.unstored {
            VStack(alignment:.leading, spacing:0) {
                Label(DebtShowerText.unstored(clear:clear), systemImage:"exclamationmark.circle")
                    .foregroundStyle(clear ? NativeTheme.notice : Theme.notice)
                    .fixedSize(horizontal:false, vertical:true)
                    .accessibilityIdentifier("debtShowerUnstored")
                // Styled as 去充值 / 前往校园充值 under a greyed-out 开始洗澡: 15pt accent with the
                // chevron, at least 44pt tall.
                Button { turnOff() } label: {
                    ShowerStartReasonLinkLabel(text:DebtShowerText.retry(clear:clear), clear:clear)
                }
                .buttonStyle(RowPressStyle())
                .padding(.top, 6)
                .accessibilityIdentifier("debtShowerRetry")
            }
        } else {
            Text(DebtShowerText.footer(clear:clear))
        }
    }

    private func set(_ on: Bool) {
        if on {
            // Again in the same visit: no phrase. Not stored, it stays off.
            visit.changed(on:shower.setAllowsDebt(true))
        } else {
            turnOff()
        }
    }

    private func turnOff() { pending.turnOff(shower) }
}

extension View {
    /// The page side of the debt start setting: the visit follows the page and the setting, the
    /// system alert for the phrase (no message; a wrong one closes it without a word), and a
    /// success haptic for the right one.
    func debtShowerUnlock(_ visit: Binding<DebtShowerVisit>, shower: ShowerModel) -> some View {
        modifier(DebtShowerUnlock(visit:visit, shower:shower))
    }
}

private struct DebtShowerUnlock: ViewModifier {
    @Binding var visit: DebtShowerVisit
    @ObservedObject var shower: ShowerModel

    func body(content: Content) -> some View {
        content
            .onAppear { visit.appeared(on:shower.allowsDebt, pending:DebtShowerPending.shared.unstored) }
            .onChange(of:shower.allowsDebt) { _, on in
                visit.changed(on:on)
                if on { DebtShowerPending.shared.turnedOn() }
            }
            .sensoryFeedback(.success, trigger:visit.unlocked)
            .background {
                // The system tint, as 学校账号's alerts: on iOS 27 an alert fills its main button
                // with the default blue.
                Color.clear
                    .alert(DebtShowerText.alertTitle, isPresented:$visit.asking) {
                        TextField(DebtShowerText.placeholder, text:$visit.typed)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .keyboardType(.asciiCapable)
                        Button(DebtShowerText.cancel, role:.cancel) { visit.typed = "" }
                        Button(DebtShowerText.confirm) {
                            shower.tryUnlock(visit.typed)
                            visit.confirmed(on:shower.allowsDebt)
                        }
                    }
                    .tint(nil)
            }
    }
}

#if DEBUG
extension DebtShowerVisit {
    /// campusdaily://demo/seed/debt-off-unstored: every turn-off reads as not stored.
    @MainActor static var demoTurnOffUnstored = false
}
#endif
