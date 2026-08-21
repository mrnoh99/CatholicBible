import SwiftUI

struct SettingsView: View {
    @Environment(ReaderSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section("보기") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("글자 크기").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Text("가").font(.footnote)
                            Slider(value: $settings.fontSize, in: ReaderSettings.fontSizeRange, step: 1)
                            Text("가").font(.title2)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("줄 간격").font(.caption).foregroundStyle(.secondary)
                        Slider(value: $settings.lineSpacingFactor, in: 0.35...1.1)
                    }
                    Picker("테마", selection: $settings.theme) {
                        ForEach(ReaderTheme.allCases) { theme in
                            Text(theme.label).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                    Picker("한글 서체", selection: $settings.fontChoice) {
                        ForEach(FontChoice.allCases) { choice in Text(choice.label).tag(choice) }
                    }
                    .pickerStyle(.segmented)
                    Picker("영문 서체", selection: $settings.englishFontChoice) {
                        ForEach(EnglishFontChoice.allCases) { choice in Text(choice.label).tag(choice) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("정보") {
                    HStack {
                        Text("앱 버전")
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("설정")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }

    private var appVersion: String {
        let bundle = Bundle.main
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        return "\(version) (\(build))"
    }
}

#Preview {
    SettingsView()
}
