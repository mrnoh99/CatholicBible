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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(settings)
                .environment(readingState)
                .environment(annotations)
                .environment(knbNotes)
                .environment(liturgy)
                .task {
                    await store.load()
                    await knbNotes.load()
                    await liturgy.load()
                }
        }
    }
}
