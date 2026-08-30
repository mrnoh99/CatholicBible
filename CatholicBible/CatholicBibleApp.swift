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
            ContentView()
                .environment(store)
                .environment(settings)
                .environment(readingState)
                .environment(annotations)
                .environment(knbNotes)
                .environment(liturgy)
                .environment(appSettings)
                .task {
                    await store.load()
                    await knbNotes.load()
                    await liturgy.load()
                    checkAutoBackup()
                }
                .onOpenURL { url in
                    // Handle custom catholicbible:// URLs at the app level
                    // This allows the system to properly route URLs to the app
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
