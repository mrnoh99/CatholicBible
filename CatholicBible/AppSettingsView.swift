//
//  AppSettingsView.swift
//  CatholicBible
//
//  앱 전체 설정
//

import SwiftUI

struct AppSettingsView: View {
    @Environment(ReaderSettings.self) private var readerSettings
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                readerSettingsTab
                    .tag(0)
                    .tabItem {
                        Image(systemName: "textformat")
                        Text("보기")
                    }

                backupSettingsTab
                    .tag(1)
                    .tabItem {
                        Image(systemName: "arrow.up.doc")
                        Text("백업")
                    }

                helpTab
                    .tag(2)
                    .tabItem {
                        Image(systemName: "questionmark.circle.fill")
                        Text("도움말")
                    }
            }
            .navigationTitle("설정")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") { dismiss() }
                }
            }
        }
    }

    private var readerSettingsTab: some View {
        SettingsView()
    }

    private var backupSettingsTab: some View {
        BackupSettingsView()
    }

    private var helpTab: some View {
        HelpManualView()
    }
}

#Preview {
    AppSettingsView()
        .environment(ReaderSettings())
        .environment(AppSettings.shared)
}
