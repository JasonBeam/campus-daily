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
    /// time through the lease. Built once per widget process.
    static let school = SchoolRefreshStack(store:SharedKeychain.store, http:SchoolRefreshStack.schoolHTTP(), role:"widget",
                                           leaseWait:SchoolRefreshStack.widgetLeaseWait, leaseFile:RefreshLease.sharedFile())
    /// The read gives up after this; the stored numbers are drawn and the next timeline tries again.
    static let readDeadline: TimeInterval = 20
    static let interval: TimeInterval = 30 * 60

    /// The snapshot and account, or nil before the first unlock / on a Keychain error.
    private static func stored() -> WidgetStoredData? {
        WidgetStoredData.read(snapshots:SharedSnapshotStore(store:SharedKeychain.store),
                              vault:StoredSchoolVault(store:SharedKeychain.store))
    }

    func placeholder(in context: Context) -> CampusEntry { CampusEntry(date:Date(), model:.placeholderFace) }
    /// Transient (gallery, first add): the stored snapshot, no network. Unreadable: grey bars,
    /// never numbers this read did not check (`CampusWidgetPlan`).
    func getSnapshot(in context: Context, completion: @escaping (CampusEntry) -> Void) {
        let now = Date()
        let choice = WidgetDrawChoice.choose(Self.stored())
        completion(CampusEntry(date:now, model:CampusWidgetPlan.face(choice, now:now, preview:context.isPreview,
                                                                     lines:ReminderLines.shared())))
    }
    /// Finishes a pending clear of the previous person's snapshot (offline), reads the school
    /// data (unless the app just did), then draws; again in 30 minutes. When the numbers turn
    /// stale before then by time alone, a second entry switches at that moment. Locked since a
    /// restart, or the Keychain refused: not "signed out", and no numbers; asked again soon.
    func getTimeline(in context: Context, completion: @escaping (Timeline<CampusEntry>) -> Void) {
        let done = Completion(call:completion)
        Task {
            let now = Date()
            Self.school.refresher.finishPendingClear()
            let choice = WidgetDrawChoice.choose(Self.stored())
            var drawn: HomeSnapshot?
            if case .draw = choice {
                drawn = await WidgetRefresh.run(Self.school.refresher, now:now, deadline:Self.readDeadline)
            }
            // The account read above: a second read failing here would draw "no saved password".
            let plan = CampusWidgetPlan.timeline(choice, drawn:drawn, now:now, interval:Self.interval, lines:ReminderLines.shared())
            done.call(Timeline(entries:plan.faces.map { CampusEntry(date:$0.date, model:$0.model) }, policy:.after(plan.next)))
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
