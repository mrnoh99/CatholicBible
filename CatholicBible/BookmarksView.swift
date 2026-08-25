//
//  BookmarksView.swift
//  CatholicBible
//
//  판본 공통 절 책갈피 목록. 누르면 현재 판본에서 그 절로 이동한다.
//  책갈피는 판본과 무관하므로 어느 판본에서 달았든 여기 함께 모인다.
//

import SwiftUI

struct BookmarksView: View {
    @Environment(AnnotationStore.self) private var annotations
    @Environment(BibleStore.self) private var store
    @Environment(ReadingState.self) private var readingState
    @Environment(ReaderNavigation.self) private var navigation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if annotations.bookmarks.isEmpty {
                    ContentUnavailableView(
                        "책갈피 없음",
                        systemImage: "bookmark",
                        description: Text("리더에서 절을 길게 눌러 ‘책갈피’를 선택하세요. 책갈피는 판본과 상관없이 같은 절에 표시됩니다.")
                    )
                } else {
                    List {
                        ForEach(annotations.sortedBookmarks) { ref in
                            Button { open(ref) } label: { row(ref) }
                                .buttonStyle(.plain)
                        }
                        .onDelete(perform: delete)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("책갈피")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } }
                if !annotations.bookmarks.isEmpty {
                    ToolbarItem(placement: .primaryAction) { EditButton() }
                }
            }
        }
    }

    private func row(_ ref: VerseRef) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "bookmark.fill")
                    .font(.caption).foregroundStyle(Color.accentColor)
                Text(ref.reference)
                    .font(.subheadline.weight(.semibold))
                if annotations.hasNote(ref) {
                    Image(systemName: "note.text").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if let preview = previewText(ref) {
                Text(preview).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private func previewText(_ ref: VerseRef) -> String? {
        guard let book = Bible.book(ref.bookID) else { return nil }
        let edition = readingState.selectedEdition
        if let v = store.verses(edition: edition, book: book, chapter: ref.chapter)
            .first(where: { $0.number == ref.verse }) { return v.text }
        if let knb = Editions.edition("knb") {
            return store.verses(edition: knb, book: book, chapter: ref.chapter)
                .first { $0.number == ref.verse }?.text
        }
        return nil
    }

    private func open(_ ref: VerseRef) {
        navigation.open(bookID: ref.bookID, chapter: ref.chapter, verse: Int(ref.verse))
        dismiss()
    }

    private func delete(at offsets: IndexSet) {
        let list = annotations.sortedBookmarks
        for i in offsets { annotations.removeBookmark(list[i]) }
    }
}
