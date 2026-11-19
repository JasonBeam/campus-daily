import SwiftUI
import WidgetKit
import ActivityKit

/// Laundry countdown. Views live in Shared/LaundryActivityViews.swift.
struct LaundryLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for:LaundryActivityAttributes.self) { context in
            LaundryActivityLockView(attributes:context.attributes, state:context.state, isStale:context.isStale)
                .activityBackgroundTint(LaundryActivityStyle.background)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { LaundryIslandLeading(attributes:context.attributes, state:context.state, isStale:context.isStale) }
                DynamicIslandExpandedRegion(.trailing) { LaundryIslandTrailing(attributes:context.attributes, state:context.state, isStale:context.isStale) }
                DynamicIslandExpandedRegion(.bottom) { LaundryIslandBottom(state:context.state, isStale:context.isStale) }
            } compactLeading: {
                Image(systemName:LaundryActivityStyle.glyph).foregroundStyle(LaundryActivityStyle.accent)
            } compactTrailing: {
                LaundryIslandCompactTrailing(state:context.state, isStale:context.isStale)
            } minimal: {
                Image(systemName:LaundryActivityStyle.glyph).foregroundStyle(LaundryActivityStyle.accent)
            }
            .keylineTint(LaundryActivityStyle.accent)
        }
    }
}
