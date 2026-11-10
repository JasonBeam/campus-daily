import SwiftUI
import Core

/// 清爽's 洗衣提醒: the 洗衣结束提醒 switch (the same setting as 洗衣洗好时), what is set for the open
/// order, and 测试提醒（10 秒）. Only local notifications; no order is read or changed here.
struct ClearLaundryReminderPage: View {
    /// 「学校洗衣机」 is on.
    let laundryOn: Bool
    @AppStorage(ReminderKey.laundryDone) private var laundryAlert = true
    @EnvironmentObject private var reminders: Reminders
    @Environment(SampleMode.self) private var sample
    @State private var testResult: LaundryReminderText.TestResult?
    @State private var testing = false

    var body: some View {
        let off = reminders.denied || !laundryOn
        List {
            Section {
                Toggle(LaundryReminderText.toggle, isOn:off ? .constant(false) : switchBinding)
                    .tint(.green)
                    .disabled(off)
                    .accessibilityIdentifier("laundryReminders")
                Text(testResult.map(LaundryReminderText.testResult) ?? status)
                    .font(.footnote).foregroundStyle(Theme.ink2)
                    .accessibilityIdentifier("laundryReminderStatus")
                Button(LaundryReminderText.test) { test() }
                    .foregroundStyle(Theme.accentText)
                    .disabled(testing)
                    .accessibilityIdentifier("testLaundryReminder")
            } footer: {
                Text(LaundryReminderText.footer).foregroundStyle(Theme.ink2)
            }.listRowBackground(Theme.group)
        }
        .listStyle(.insetGrouped)
        .modifier(SettingsReminderHandlers())
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .tint(Theme.accentText)
        .navigationTitle(LaundryReminderText.title).navigationBarTitleDisplayMode(.inline)
        .task { await reminders.refreshAuthorization() }
    }

    private var status: String {
        LaundryReminderText.status(on:laundryAlert, allowed:reminders.notificationsAllowed || reminders.notAsked,
                                   laundryOn:laundryOn, scheduledEnd:reminders.laundryReminderEnd)
    }

    /// The stored value; in the sample a change is not stored, it says so.
    private var switchBinding: Binding<Bool> {
        Binding(get:{ laundryAlert }, set:{ on in
            if sample.isActive { sample.perform(.reminders) {}; return }
            testResult = nil
            laundryAlert = on
        })
    }

    private func test() {
        if sample.isActive { sample.perform(.reminders) {}; return }
        testing = true
        Task {
            defer { testing = false }
            if let result = await reminders.testLaundryReminder() { testResult = result }
        }
    }
}
