//
//  BookmarksView.swift
//  CatholicBible
//
//  저장한 책갈피 목록. 누르면 해당 판본·장·절로 이동한다.
//

import SwiftUI

struct BookmarksView: View {
    @Environment(BibleStore.self) private var store
    @Environment(ReadingState.self) private var readingState
    @Environment(ReaderNavigation.self) private var navigation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if readingState.bookmarks.isEmpty {
                    ContentUnavailableView(
                        "책갈피 없음",
                        systemImage: "bookmark",
                        description: Text("리더 상단의 책갈피 단추로 장을, 절을 길게 눌러 절을 저장할 수 있습니다.")
                    )
                } else {
                    List {
                        ForEach(readingState.bookmarks) { bookmark in
                            Button {
                                open(bookmark)
                            } label: {
                                bookmarkRow(bookmark)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { readingState.removeBookmarks(at: $0) }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("책갈피")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                if !readingState.bookmarks.isEmpty {
                    ToolbarItem(placement: .primaryAction) { EditButton() }
                }
            }
        }
    }

    private func open(_ bookmark: Bookmark) {
        // 책갈피의 판본으로 전환한 뒤 이동
        if Editions.edition(bookmark.editionID) != nil {
            readingState.selectedEditionID = bookmark.editionID
        }
        navigation.open(bookID: bookmark.bookID,
                        chapter: bookmark.chapter,
                        verse: bookmark.verse)
        dismiss()
    }

    private func bookmarkRow(_ bookmark: Bookmark) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: bookmark.verse == nil ? "bookmark" : "bookmark.fill")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                Text(bookmark.reference)
                    .font(.subheadline.weight(.semibold))
                if let edition = Editions.edition(bookmark.editionID) {
                    Text(edition.shortName)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                        .foregroundStyle(Color.accentColor)
                }
                Spacer()
                Text(bookmark.created, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if let preview = previewText(bookmark) {
                Text(preview)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private func previewText(_ bookmark: Bookmark) -> String? {
        guard let book = Bible.book(bookmark.bookID),
              let edition = Editions.edition(bookmark.editionID) else { return nil }
        let verses = store.verses(edition: edition, book: book, chapter: bookmark.chapter)
        guard !verses.isEmpty else { return nil }
        if let verseNumber = bookmark.verse {
            return verses.first { $0.number == verseNumber }?.text
        }
        return verses.first?.text
    }
}
