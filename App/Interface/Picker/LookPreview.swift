import SwiftUI
import Core

/// One theme's real home inside 「选一个样子」: the app's own root (`CampusScene`) on a sample of its
/// own (new sample services and models, `SampleMode.enter`), drawn with `theme`. Nothing in it
/// reaches the live graph; it takes no touches, has no sample bar and is not read by VoiceOver.
struct LookPreview: View {
    let theme: AppTheme
    /// Room left at the top for the picker's title card and name labels.
    static let topInset: CGFloat = 118

    @State private var sample: SampleMode = {
        let sample = SampleMode(gate:LiveShowerGate(record:{ .known(.idle) }))
        sample.enter()
        return sample
    }()
    @State private var alerts = SampleAlertStack()

    var body: some View {
        if let services = sample.services {
            SampleScene(services:services, theme:theme)
                .environment(sample).environment(alerts)
                .environment(\.lookPreview, true)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
