//
//  ReadingState.swift
//  CatholicBible
//
//  이어 읽기 위치와 책갈피. UserDefaults에 JSON으로 저장한다.
//

import Foundation
import Observation

struct Bookmark: Codable, Identifiable, Hashable {
    var id = UUID()
    let bookID: String
    let chapter: Int
    /// nil이면 장 전체 책갈피
    let verse: Int?
    var created = Date()

    /// "마태 5,3" 식의 성구 표기
    var reference: String {
        guard let book = Bible.book(bookID) else { return "" }
        if let verse { return "\(book.abbrev) \(chapter),\(verse)" }
        return "\(book.shortName) \(book.chapterLabel(chapter))"
    }
}

@Observable
final class ReadingState {
    private static let defaults = UserDefaults.standard
    private static let bookmarksKey = "reading.bookmarks"
    private static let lastBookKey = "reading.lastBookID"
    private static let chapterPrefix = "reading.chapter."

    /// 마지막으로 읽던 책 (앱 시작 시 이어 읽기)
    var lastBookID: String? {
        didSet { Self.defaults.set(lastBookID, forKey: Self.lastBookKey) }
    }

    private(set) var bookmarks: [Bookmark]

    init() {
        lastBookID = Self.defaults.string(forKey: Self.lastBookKey)
        if let data = Self.defaults.data(forKey: Self.bookmarksKey),
           let saved = try? JSONDecoder().decode([Bookmark].self, from: data) {
            bookmarks = saved
        } else {
            bookmarks = []
        }
    }

    // MARK: - 이어 읽기 (책별 마지막 장)

    func lastChapter(for book: BibleBook) -> Int {
        let saved = Self.defaults.integer(forKey: Self.chapterPrefix + book.id)
        return (1...book.chapterCount).contains(saved) ? saved : 1
    }

    func savePosition(book: BibleBook, chapter: Int) {
        Self.defaults.set(chapter, forKey: Self.chapterPrefix + book.id)
        lastBookID = book.id
    }

    // MARK: - 책갈피

    private func persistBookmarks() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            Self.defaults.set(data, forKey: Self.bookmarksKey)
        }
    }

    func isBookmarked(bookID: String, chapter: Int, verse: Int? = nil) -> Bool {
        bookmarks.contains { $0.bookID == bookID && $0.chapter == chapter && $0.verse == verse }
    }

    func toggleBookmark(bookID: String, chapter: Int, verse: Int? = nil) {
        if let index = bookmarks.firstIndex(where: {
            $0.bookID == bookID && $0.chapter == chapter && $0.verse == verse
        }) {
            bookmarks.remove(at: index)
        } else {
            bookmarks.insert(Bookmark(bookID: bookID, chapter: chapter, verse: verse), at: 0)
        }
        persistBookmarks()
    }

    func removeBookmarks(at offsets: IndexSet) {
        bookmarks.remove(atOffsets: offsets)
        persistBookmarks()
    }
}
