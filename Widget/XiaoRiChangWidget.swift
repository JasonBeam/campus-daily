//
//  XiaoRiChangWidget.swift
//  XiaoRiChang
//
//  Created by @JasonBeam on 2026/10/28.
//

import SwiftUI
import WidgetKit
import Core

struct CampusEntry: TimelineEntry {
    let date: Date
    let model: CampusWidgetModel
    /// The app's theme when the entry was made (the app reloads the timelines when it changes).
    var theme = ThemePreference.shared()
}
struct CampusTimeline: TimelineProvider {
    /// The widget's own school read: the same stack as the app (card session → portal token →
    /// saved password once → needs login), writing the same shared snapshot, one process at a
    /// time through the lease. Built once per widget process. Its steps go to the TestFlight
    /// debug log's widget part (`WidgetDebugLog`: only once the app found it is TestFlight).
    static let school = SchoolRefreshStack(store:SharedKeychain.store, http:SchoolRefreshStack.schoolHTTP(), role:"widget",
                                           leaseWait:SchoolRefreshStack.widgetLeaseWait, leaseFile:RefreshLease.sharedFile(),
                                           debugLog:WidgetDebugLog.shared())
    /// The read gives up after this; the stored numbers are drawn and the next timeline tries again.
    static let readDeadline: TimeInterval = 20
    static let interval: TimeInterval = 30 * 60

    func placeholder(in context: Context) -> CampusEntry { CampusEntry(date:Date(), model:.placeholderFace) }
    /// Transient (gallery, first add): the stored snapshot, no network. Constructs the candidate
    /// face first (including reminder lines and theme), then acquires the shared commit lock
    /// right before invoking `completion` to verify `shared.sessionEpoch`.
    func getSnapshot(in context: Context, completion: @escaping (CampusEntry) -> Void) {
        let now = Date()
        let snapshots = SharedSnapshotStore(store:SharedKeychain.store)
        let vault = StoredSchoolVault(store:SharedKeychain.store)
        let theme = ThemePreference.shared()
        CampusWidgetDelivery.deliverSnapshot(
            now:now,
            preview:context.isPreview,
            snapshots:snapshots,
            vault:vault,
            commitLock:Self.school.refresher.commitLock,
            lines:{ ReminderLines.shared() }
        ) { model in
            completion(CampusEntry(date:now, model:model, theme:theme))
        }
    }
    /// Finishes a pending clear of the previous person's snapshot (offline), reads the school
    /// data (unless the app just did), constructs the candidate timeline first (including
    /// reminder lines and theme), then acquires the shared commit lock right before invoking
    /// `completion` to verify `shared.sessionEpoch`; again in 30 minutes.
    func getTimeline(in context: Context, completion: @escaping (Timeline<CampusEntry>) -> Void) {
        let done = Completion(call:completion)
        Task {
            let now = Date()
            let snapshots = SharedSnapshotStore(store:SharedKeychain.store)
            let vault = StoredSchoolVault(store:SharedKeychain.store)
            let theme = ThemePreference.shared()
            await CampusWidgetDelivery.deliverTimeline(
                now:now,
                interval:Self.interval,
                snapshots:snapshots,
                vault:vault,
                commitLock:Self.school.refresher.commitLock,
                lines:{ ReminderLines.shared() },
                finishPendingClear:{
                    await Self.school.refresher.finishPendingClear(lockWait:SchoolRefreshStack.widgetPendingClearWait)
                },
                refresh:{ expectedEpochID in
                    await WidgetRefresh.run(Self.school.refresher, now:now, deadline:Self.readDeadline,
                                            expectedEpochID:expectedEpochID)
                }
            ) { plan in
                done.call(Timeline(entries:plan.faces.map { CampusEntry(date:$0.date, model:$0.model, theme:theme) },
                                   policy:.after(plan.next)))
            }
        }
    }

    /// WidgetKit's completion handler, called once from the read's task.
    private struct Completion: @unchecked Sendable {
        // @unchecked: WidgetKit accepts the call from any thread.
        let call: (Timeline<CampusEntry>) -> Void
    }
}

@main struct XiaoRiChangWidgetBundle: WidgetBundle {
    var body: some Widget {
        XiaoRiChangWidget()
        ShowerLiveActivity()
        LaundryLiveActivity()
    }
}
struct XiaoRiChangWidget: Widget {
    let kind = SharedSnapshotStore.widgetKind
    var body: some WidgetConfiguration {
        StaticConfiguration(kind:kind, provider:CampusTimeline()) { entry in
            CampusWidgetEntryView(entry:entry)
        }
        .configurationDisplayName("校日常")
        .description("宿舍电量和校园卡余额，一眼就看到。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
struct CampusWidgetEntryView: View {
    let entry: CampusEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        CampusWidgetFace(model:entry.model, medium:family == .systemMedium, theme:entry.theme)
            .redacted(reason:entry.model.placeholder ? .placeholder : [])
            .privacySensitive()
            .containerBackground(ClearScriptsFace.draws(entry.model, medium:family == .systemMedium, theme:entry.theme)
                                 ? ClearScriptsFace.paper : CampusWidgetPalette.of(entry.theme).group, for:.widget)
            .widgetURL(entry.model.url)
    }
}
