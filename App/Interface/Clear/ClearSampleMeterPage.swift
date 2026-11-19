import SwiftUI
import Core

/// 绑定宿舍电表 in the sample: the meter page's layout on the sample's dorm. Choosing a place
/// says what the sample can't do; nothing is read.
struct ClearSampleMeterPage: View {
    let data: HomeData
    @Environment(SampleMode.self) private var sample
    @State private var search = ""

    var body: some View {
        List {
            if data.powerBound {
                Section(ClearMeterPageText.section) {
                    Label(ClearMeterPageText.saved, systemImage:"checkmark.circle").foregroundStyle(.green)
                }
                .listRowBackground(Theme.group)
            }
            Section {
                VStack(alignment:.leading, spacing:6) {
                    Text(ClearMeterPageText.path([])).font(.headline)
                    Text(ClearMeterPageText.note).font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.vertical,4)
            }
            .listRowBackground(Theme.group)
            Section(ClearMeterPageText.listHeader(meters:false)) {
                ForEach(places.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }, id:\.self) { place in
                    Button(place) { sample.perform(.bindMeter) {} }
                }
            }
            .listRowBackground(Theme.group)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .tint(NativeTheme.tint)
        .navigationTitle(ClearMeterPageText.title).navigationBarTitleDisplayMode(.inline)
        .searchable(text:$search, prompt:ClearMeterPageText.searchPrompt)
        .accessibilityIdentifier("sampleBindMeter")
    }

    /// The sample dorm's campus, the first level of the picker.
    private var places: [String] {
        let location = data.meterLocation ?? SampleData.dormLocation
        return location.components(separatedBy:" · ").prefix(1).map { $0 }
    }
}
