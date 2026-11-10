import SwiftUI
import Core

/// Settings › 外观 › 主题: 暖橙 or 清爽, switched on tap. While a shower is under way (from
/// 开始洗澡 until the settlement) or a laundry order is unfinished both options are greyed out
/// (`ThemeLock`), and grey out as soon as one starts with the page open.
struct ThemeSettingsView: View {
    /// DEBUG demo data from the settings sheet; nil = live models.
    var preview: HomeData? = nil
    @EnvironmentObject private var shower: ShowerModel
    @EnvironmentObject private var laundry: LaundryModel
    @Environment(ThemeStore.self) private var store

    private var lock: ThemeLock? {
        preview != nil ? preview?.themeLock : ThemeLock.lock(shower:shower.state, laundry:laundry.checkout?.phase)
    }

    var body: some View {
        let lock = lock
        let selected = store.theme
        List {
            Section {
                ForEach(AppTheme.allCases, id:\.self) { theme in
                    ThemeOptionRow(theme:theme, selected:theme == selected, locked:lock != nil) {
                        withAnimation(.easeInOut(duration:0.25)) { store.select(theme) }
                    }
                }
            } footer: {
                VStack(alignment:.leading, spacing:2) {
                    if let lock { Text(lock.reason).foregroundStyle(Theme.ink) }
                    Text(AppTheme.footer).foregroundStyle(Theme.ink2)
                }
                .scaledFont(13, relativeTo:.footnote)
                .accessibilityElement(children:.combine)
            }
            .listRowBackground(Theme.group)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("主题").navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger:selected)
        .animation(.easeInOut(duration:0.25), value:lock)
    }
}

/// One option: the theme's accent as a swatch, its name and line, a tick when chosen.
private struct ThemeOptionRow: View {
    let theme: AppTheme
    let selected: Bool
    let locked: Bool
    let choose: () -> Void

    var body: some View {
        Button(action:choose) {
            HStack(spacing:14) {
                Circle().fill(Self.swatch(theme)).frame(width:24, height:24).accessibilityHidden(true)
                VStack(alignment:.leading, spacing:2) {
                    Text(theme.name).scaledFont(17).foregroundStyle(Theme.ink)
                    Text(theme.summary).scaledFont(13, relativeTo:.footnote).foregroundStyle(Theme.ink2)
                        .fixedSize(horizontal:false, vertical:true)
                }
                // The separator starts under the name, past the swatch.
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                Spacer(minLength:8)
                if selected {
                    Image(systemName:"checkmark").font(.system(size:17, weight:.semibold)).foregroundStyle(Theme.accentText)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical,12)
            .frame(minHeight:60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .opacity(locked ? 0.4 : 1)
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(locked ? theme.unavailableLabel : theme.name)
        .accessibilityValue(locked ? "" : theme.summary)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("theme." + theme.rawValue)
    }

    /// Each theme's accent, the same in light and dark.
    private static func swatch(_ theme: AppTheme) -> Color {
        switch theme {
        case .warm: return Color(red:0xF2 / 255, green:0x60 / 255, blue:0x0C / 255)
        case .clear: return Color(red:0x17 / 255, green:0x5E / 255, blue:0xC9 / 255)
        }
    }
}
