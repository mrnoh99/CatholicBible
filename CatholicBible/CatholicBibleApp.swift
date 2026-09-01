//
//  CatholicBibleApp.swift
//  CatholicBible
//

import SwiftUI

@main
struct CatholicBibleApp: App {
    @State private var store = BibleStore()
    @State private var settings = ReaderSettings()
    @State private var readingState = ReadingState()
    @State private var annotations = AnnotationStore()
    @State private var knbNotes = KnbNotesStore()
    @State private var liturgy = LiturgyStore()
    @State private var appSettings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            ZStack {
                if store.isLoaded && knbNotes.isLoaded && liturgy.isLoaded {
                    // 모든 데이터 로드 완료 → 실제 앱 표시
                    ContentView()
                        .environment(store)
                        .environment(settings)
                        .environment(readingState)
                        .environment(annotations)
                        .environment(knbNotes)
                        .environment(liturgy)
                        .environment(appSettings)
                        .onOpenURL { url in
                            // Handle custom catholicbible:// URLs at the app level
                            // This allows the system to properly route URLs to the app
                        }
                } else {
                    // 로딩 중 → 로딩 화면 표시
                    LoadingScreen(store: store, knbNotes: knbNotes, liturgy: liturgy)
                }
            }
            .task {
                // 모든 데이터 로드 (완료 후 ZStack이 자동으로 ContentView로 전환)
                async let storeLoad = store.load()
                async let notesLoad = knbNotes.load()
                async let liturgyLoad = liturgy.load()

                _ = await (storeLoad, notesLoad, liturgyLoad)
                checkAutoBackup()
            }
        }
    }

    private func checkAutoBackup() {
        let backupManager = BackupManager.shared
        if backupManager.shouldBackup() {
            _ = backupManager.backup(annotationStore: annotations)
        }
    }
}
