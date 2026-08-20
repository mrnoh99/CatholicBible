import SwiftUI

struct SettingsView: View {
    @StateObject private var downloadManager = DataDownloadManager.shared
    @State private var showUpdateAlert = false

    var body: some View {
        NavigationStack {
            List {
                Section("데이터") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("헤딩 데이터 업데이트")
                                    .font(.headline)
                                if let lastUpdate = downloadManager.lastUpdateTime {
                                    Text("마지막 업데이트: \(lastUpdate.formatted())")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("아직 업데이트되지 않음")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if downloadManager.isDownloading {
                                ProgressView(value: downloadManager.downloadProgress)
                                    .frame(width: 100)
                            } else {
                                Button(action: { downloadManager.downloadHeadings() }) {
                                    Label("업데이트", systemImage: "arrow.clockwise")
                                        .font(.subheadline)
                                }
                                .disabled(downloadManager.isDownloading)
                            }
                        }

                        if let error = downloadManager.lastError {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(.red)
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(6)
                        }
                    }
                    .padding(.vertical, 8)
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
