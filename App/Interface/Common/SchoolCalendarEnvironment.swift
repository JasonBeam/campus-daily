import SwiftUI
import Core

private struct SchoolCalendarKey: EnvironmentKey {
    static let defaultValue = SchoolCalendar.shanghai
}

extension EnvironmentValues {
    /// The calendar the card's records on screen are read in: the school's, or the sample's
    /// (`SampleData.calendar`, the phone's time zone). Each root sets it from its `HomeData`.
    var schoolCalendar: Calendar {
        get { self[SchoolCalendarKey.self] }
        set { self[SchoolCalendarKey.self] = newValue }
    }
}
