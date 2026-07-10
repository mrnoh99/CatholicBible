//
//  ReadingState.swift
//  CatholicBible
//
//  선택된 판본, 이어 읽기 위치, 책갈피. UserDefaults에 저장한다.
//

import Foundation
import Observation

struct Bookmark: Codable, Identifiable, Hashable {
    var id = UUID()
    var editionID: String = Editions.defaultEditionID
    let bookID: String
    let chapter: Int
    /// nil이면 장 전체 책갈피
    let verse: Int?
    var created = Date()

    enum CodingKeys: String, CodingKey {
        case id, editionID, bookID, chapter, verse, created
    }

    init(editionID: String, bookID: String, chapter: Int, verse: Int?) {
        self.editionID = editionID
        self.bookID = bookID
        self.chapter = chapter
        self.verse = verse
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        // 판본 도입 전에 저장된 책갈피는 「성경」으로 간주
        editionID = try c.decodeIfPresent(String.self, forKey: .editionID) ?? Editions.defaultEditionID
        bookID = try c.decode(String.self, forKey: .bookID)
        chapter = try c.decode(Int.self, forKey: .chapter)
        verse = try c.decodeIfPresent(Int.self, forKey: .verse)
        created = try c.decodeIfPresent(Date.self, forKey: .created) ?? Date()
    }

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
    private static let editionKey = "reading.editionID"
    private static let lastBookKey = "reading.lastBookID"
    private static let chapterPrefix = "reading.chapter."

    /// 서재에서 선택된 판본
    var selectedEditionID: String {
        didSet { Self.defaults.set(selectedEditionID, forKey: Self.editionKey) }
    }

    /// 마지막으로 읽던 책 (판본별)
    private var lastBookIDs: [String: String] {
        didSet { Self.defaults.set(lastBookIDs, forKey: Self.lastBookKey) }
    }

    private(set) var bookmarks: [Bookmark]

    init() {
        selectedEditionID = Self.defaults.string(forKey: Self.editionKey) ?? Editions.defaultEditionID
        lastBookIDs = Self.defaults.dictionary(forKey: Self.lastBookKey) as? [String: String] ?? [:]
        if let data = Self.defaults.data(forKey: Self.bookmarksKey),
           let saved = try? JSONDecoder().decode([Bookmark].self, from: data) {
            bookmarks = saved
        } else {
            bookmarks = []
        }
    }

    var selectedEdition: Edition {
        Editions.edition(selectedEditionID) ?? Editions.all[0]
    }

    // MARK: - 이어 읽기 (판본×책별 마지막 장)

    func lastBookID(edition: Edition) -> String? {
        lastBookIDs[edition.id]
    }

    func lastChapter(edition: Edition, book: BibleBook) -> Int {
        let saved = Self.defaults.integer(forKey: Self.chapterPrefix + edition.id + "." + book.id)
        return (1...book.chapterCount).contains(saved) ? saved : 1
    }

    func savePosition(edition: Edition, book: BibleBook, chapter: Int) {
        Self.defaults.set(chapter, forKey: Self.chapterPrefix + edition.id + "." + book.id)
        lastBookIDs[edition.id] = book.id
    }

    // MARK: - 책갈피

    private func persistBookmarks() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            Self.defaults.set(data, forKey: Self.bookmarksKey)
        }
    }

    func isBookmarked(editionID: String, bookID: String, chapter: Int, verse: Int? = nil) -> Bool {
        bookmarks.contains {
            $0.editionID == editionID && $0.bookID == bookID
                && $0.chapter == chapter && $0.verse == verse
        }
    }

    func toggleBookmark(editionID: String, bookID: String, chapter: Int, verse: Int? = nil) {
        if let index = bookmarks.firstIndex(where: {
            $0.editionID == editionID && $0.bookID == bookID
                && $0.chapter == chapter && $0.verse == verse
        }) {
            bookmarks.remove(at: index)
        } else {
            bookmarks.insert(Bookmark(editionID: editionID, bookID: bookID,
                                      chapter: chapter, verse: verse), at: 0)
        }
        persistBookmarks()
    }

    func removeBookmarks(at offsets: IndexSet) {
        bookmarks.remove(atOffsets: offsets)
        persistBookmarks()
    }
}
