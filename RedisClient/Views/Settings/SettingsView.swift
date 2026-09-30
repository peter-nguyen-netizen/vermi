import SwiftUI

/// App preferences, shown in the standard macOS Settings window (⌘,).
/// Values persist via @AppStorage and are read wherever the setting applies.
struct SettingsView: View {
    @AppStorage("appearanceMode") private var appearanceRaw = AppearanceMode.system.rawValue
    @AppStorage("compactKeyList") private var compactKeyList = false
    @AppStorage("keyTreeMode") private var keyTreeMode = false
    @AppStorage("confirmDeletes") private var confirmDeletes = true
    @AppStorage("analysisSampleSize") private var analysisSampleSize = 1000
    @AppStorage("keyPageSize") private var keyPageSize = 100
    @AppStorage("textScale") private var textScale = 1.0
    @AppStorage("accentTheme") private var accentRaw = AccentTheme.vermilion.rawValue

    private var appearance: Binding<AppearanceMode> {
        Binding(
            get: { AppearanceMode(rawValue: appearanceRaw) ?? .system },
            set: { appearanceRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Mode", selection: appearance) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                // Accent theme — swatch row.
                HStack(spacing: 10) {
                    Text("Accent")
                    Spacer()
                    ForEach(AccentTheme.allCases) { theme in
                        Button {
                            accentRaw = theme.rawValue
                        } label: {
                            Circle()
                                .fill(theme.swatch)
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Circle().strokeBorder(Color.primary.opacity(accentRaw == theme.rawValue ? 0.9 : 0), lineWidth: 2)
                                        .padding(-3)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(theme.label)
                    }
                }

                Picker("Value text size", selection: $textScale) {
                    Text("Small").tag(0.9)
                    Text("Default").tag(1.0)
                    Text("Large").tag(1.15)
                    Text("Larger").tag(1.3)
                }
                Text("Scales the value viewer and console output text.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Key Browser") {
                Toggle("Compact list density", isOn: $compactKeyList)
                Toggle("Group keys as a namespace tree by default", isOn: $keyTreeMode)
                Picker("Keys per page", selection: $keyPageSize) {
                    Text("100").tag(100)
                    Text("200").tag(200)
                    Text("500").tag(500)
                    Text("1,000").tag(1000)
                }
            }

            Section("Safety") {
                Toggle("Confirm before deleting keys", isOn: $confirmDeletes)
                Text("When off, deletes happen immediately without a prompt.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Memory Analysis") {
                Picker("Default sample size", selection: $analysisSampleSize) {
                    Text("500").tag(500)
                    Text("1,000").tag(1000)
                    Text("5,000").tag(5000)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 420)
    }
}
