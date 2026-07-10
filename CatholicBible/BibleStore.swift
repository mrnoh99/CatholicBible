//
//  BibleStore.swift
//  CatholicBible
//
//  번들된 BibleText.json(주교회의 「성경」 본문)을 로드해 절 단위로 제공한다.
//  본문이 아직 수집되지 않은 책은 빈 상태로 노출되어, 리더 화면이
//  안내 문구를 대신 보여 준다 (scripts/fetch_cbck_bible.py 참고).
//

import Foundation
import Observation

/// BibleText.json 파일 구조 (백그라운드에서 디코딩하므로 nonisolated)
private nonisolated struct BibleTextFile: Decodable, Sendable {
    let translation: String
    let source: String
    /// 책 id → 장 번호(문자열) → 절 번호(문자열) → 본문
    let books: [String: [String: [String: String]]]
}

nonisolated struct Verse: Identifiable, Hashable, Sendable {
    let number: Int
    let text: String

    var id: Int { number }
}

nonisolated struct SearchHit: Identifiable, Hashable, Sendable {
    let bookID: String
    let chapter: Int
    let verse: Int
    let text: String

    var id: String { "\(bookID)-\(chapter)-\(verse)" }
}

@Observable
final class BibleStore {
    private(set) var translation = "한국 천주교 주교회의 「성경」"
    private(set) var source = "https://bible.cbck.or.kr"
    private(set) var isLoaded = false
    private(set) var loadError: String?

    /// 책 id → 장 → 절 목록 (절 번호 순 정렬 완료)
    private(set) var books: [String: [Int: [Verse]]] = [:]

    /// 검색용 원본 (immutable snapshot)
    private var rawBooks: [String: [String: [String: String]]] = [:]

    func load() async {
        guard !isLoaded else { return }
        guard let url = Bundle.main.url(forResource: "BibleText", withExtension: "json") else {
            loadError = "BibleText.json이 앱 번들에 없습니다."
            isLoaded = true
            return
        }
        do {
            let file = try await Task.detached(priority: .userInitiated) {
                let data = try Data(contentsOf: url)
                return try JSONDecoder().decode(BibleTextFile.self, from: data)
            }.value

            var indexed: [String: [Int: [Verse]]] = [:]
            for (bookID, chapters) in file.books {
                var chapterMap: [Int: [Verse]] = [:]
                for (chapterKey, verses) in chapters {
                    guard let chapterNumber = Int(chapterKey) else { continue }
                    chapterMap[chapterNumber] = verses
                        .compactMap { key, text in Int(key).map { Verse(number: $0, text: text) } }
                        .sorted { $0.number < $1.number }
                }
                indexed[bookID] = chapterMap
            }
            translation = file.translation
            source = file.source
            rawBooks = file.books
            books = indexed
        } catch {
            loadError = "본문을 읽지 못했습니다: \(error.localizedDescription)"
        }
        isLoaded = true
    }

    // MARK: - 조회

    func hasText(_ book: BibleBook) -> Bool {
        !(books[book.id]?.isEmpty ?? true)
    }

    /// 본문이 있는 장 수 (미수집 책은 0)
    func availableChapterCount(_ book: BibleBook) -> Int {
        books[book.id]?.count ?? 0
    }

    func verses(book: BibleBook, chapter: Int) -> [Verse] {
        books[book.id]?[chapter] ?? []
    }

    var availableBookCount: Int {
        Bible.books.filter { hasText($0) }.count
    }

    // MARK: - 검색

    /// 로드된 모든 책에서 구절을 검색한다. 결과는 성경 목차 순서.
    func search(_ query: String, limit: Int = 200) async -> [SearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        let snapshot = rawBooks
        let order = Bible.books.map(\.id)

        return await Task.detached(priority: .userInitiated) {
            var hits: [SearchHit] = []
            outer: for bookID in order {
                guard let chapters = snapshot[bookID] else { continue }
                let chapterNumbers = chapters.keys.compactMap { Int($0) }.sorted()
                for chapterNumber in chapterNumbers {
                    guard let verses = chapters[String(chapterNumber)] else { continue }
                    let verseNumbers = verses.keys.compactMap { Int($0) }.sorted()
                    for verseNumber in verseNumbers {
                        guard let text = verses[String(verseNumber)] else { continue }
                        if text.localizedStandardContains(trimmed) {
                            hits.append(SearchHit(bookID: bookID, chapter: chapterNumber,
                                                  verse: verseNumber, text: text))
                            if hits.count >= limit { break outer }
                        }
                    }
                }
            }
            return hits
        }.value
    }
}
