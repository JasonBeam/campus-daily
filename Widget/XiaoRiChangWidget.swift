import SwiftUI
import WidgetKit
import Core

struct CampusEntry: TimelineEntry { let date: Date; let model: CampusWidgetModel }
struct CampusTimeline: TimelineProvider {
    /// The widget's own school read: the same stack as the app (card session → portal token →
    /// saved password once → needs login), writing the same shared snapshot, one process at a
    /// time through the lease. Built once per widget process.
    static let school = SchoolRefreshStack(store:SharedKeychain.store, http:SchoolRefreshStack.schoolHTTP(), role:"widget",
                                           leaseWait:SchoolRefreshStack.widgetLeaseWait, leaseFile:RefreshLease.sharedFile())
    /// The read gives up after this; the stored numbers are drawn and the next timeline tries again.
    static let readDeadline: TimeInterval = 20
    static let interval: TimeInterval = 30 * 60

    /// The last entry drawn by this process, kept for a moment the Keychain can't be read.
    private static let last = LastEntry()

    /// The snapshot and account, or nil before the first unlock / on a Keychain error.
    private static func stored() -> WidgetStoredData? {
        WidgetStoredData.read(snapshots:SharedSnapshotStore(store:SharedKeychain.store),
                              vault:StoredSchoolVault(store:SharedKeychain.store))
    }

    private static func model(_ snapshot: HomeSnapshot?, account: SchoolAccount?, at date: Date) -> CampusWidgetModel {
        var model = CampusWidgetModel(snapshot:snapshot, account:account, now:date)
        model.lines = ReminderLines.shared()
        return model
    }

    func placeholder(in context: Context) -> CampusEntry { CampusEntry(date:Date(), model:.placeholderFace) }
    /// Transient (gallery, first add): the stored snapshot, no network. Unreadable with nothing
    /// drawn before: grey bars, never sample numbers passed off as fresh.
    func getSnapshot(in context: Context, completion: @escaping (CampusEntry) -> Void) {
        let now = Date()
        guard let stored = Self.stored() else {
            completion(Self.last.redrawn(at:now) ?? CampusEntry(date:now, model:.placeholderFace))
            return
        }
        let model = Self.model(stored.snapshot, account:stored.account, at:now)
        completion(CampusEntry(date:now, model:context.isPreview && model.state == .never ? .placeholderFace : model))
    }
    /// Reads the school data (unless the app just did), then draws; again in 30 minutes. When the
    /// numbers turn stale before then by time alone, a second entry switches at that moment.
    func getTimeline(in context: Context, completion: @escaping (Timeline<CampusEntry>) -> Void) {
        let done = Completion(call:completion)
        Task {
            let now = Date()
            // Locked since a restart, or the Keychain refused: not "signed out". Keep what was
            // drawn (no entries = the face stays) and ask again soon.
            guard let stored = Self.stored() else {
                let retry = now.addingTimeInterval(WidgetStoredData.unreadableRetry)
                done.call(Timeline(entries:Self.last.redrawn(at:now).map { [$0] } ?? [], policy:.after(retry)))
                return
            }
            let snapshot = await WidgetRefresh.run(Self.school.refresher, now:now, deadline:Self.readDeadline)
            // The account read above: a second read failing here would draw "no saved password".
            let account = stored.account
            let next = now.addingTimeInterval(Self.interval)
            var entries = [CampusEntry(date:now, model:Self.model(snapshot, account:account, at:now))]
            if let staleAt = WidgetStatus.staleAt(snapshot:snapshot, account:account, now:now), staleAt < next {
                entries.append(CampusEntry(date:staleAt, model:Self.model(snapshot, account:account, at:staleAt)))
            }
            Self.last.entry = entries.first
            done.call(Timeline(entries:entries, policy:.after(next)))
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
        CampusWidgetFace(model:entry.model, medium:family == .systemMedium)
            .redacted(reason:entry.model.placeholder ? .placeholder : [])
            .privacySensitive()
            .containerBackground(CampusWidgetPalette.group, for:.widget)
            .widgetURL(entry.model.url)
    }
}
