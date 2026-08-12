//
//  BibleStore.swift
//  CatholicBible
//
//  번들된 판본별 본문 파일(Resources/BibleText_<판본id>.json)을 로드해
//  절 단위로 제공한다. 아직 수집되지 않은 판본/책은 빈 상태로 노출되어
//  서재·리더가 안내 문구를 대신 보여 준다 (scripts/fetch_cbck_bible.py 참고).
//

import Foundation
import Observation

/// BibleText_<판본>.json 파일 구조
private nonisolated struct BibleTextFile: Decodable, Sendable {
    let translation: String
    let source: String
    /// 판본 고유의 책 표시 이름 (예: 공동번역 "출애굽기", NAB "Genesis")
    let bookNames: [String: String]?
    /// 책 id → 장 번호(문자열) → 절 번호(문자열) → 본문
    let books: [String: [String: [String: String]]]
}

nonisolated struct Verse: Identifiable, Hashable, Sendable {
    let number: Int
    let text: String

    var id: Int { number }
}

nonisolated struct SearchHit: Identifiable, Hashable, Sendable {
    let editionID: String
    let bookID: String
    let chapter: Int
    let verse: Int
    let text: String

    var id: String { "\(editionID)-\(bookID)-\(chapter)-\(verse)" }
}

/// 로드된 한 판본의 본문
nonisolated struct EditionText: Sendable {
    var translation: String
    var source: String
    var bookNames: [String: String]
    /// 책 id → 장 → 절 목록 (절 번호 순 정렬 완료)
    var books: [String: [Int: [Verse]]]
    /// 검색용 원본
    var rawBooks: [String: [String: [String: String]]]
}

@Observable
final class BibleStore {
    private(set) var isLoaded = false
    /// 판본 id → 본문 (파일이 없는 판본은 항목 자체가 없음)
    private(set) var editions: [String: EditionText] = [:]

    func load() async {
        guard !isLoaded else { return }

        // 각 판본 파일을 백그라운드에서 한꺼번에 디코딩한다.
        let candidates: [(String, URL)] = Editions.all.compactMap { edition in
            Bundle.main.url(forResource: "BibleText_\(edition.id)", withExtension: "json")
                .map { (edition.id, $0) }
        }

        let loaded: [String: EditionText] = await Task.detached(priority: .userInitiated) {
            var result: [String: EditionText] = [:]
            for (editionID, url) in candidates {
                guard let data = try? Data(contentsOf: url),
                      let file = try? JSONDecoder().decode(BibleTextFile.self, from: data)
                else { continue }

                var indexed: [String: [Int: [Verse]]] = [:]
                for (bookID, chapters) in file.books {
                    var chapterMap: [Int: [Verse]] = [:]
                    for (chapterKey, verses) in chapters {
                        guard let chapterNumber = Int(chapterKey) else { continue }
                        chapterMap[chapterNumber] = verses
                            .compactMap { key, text in Int(key).map { Verse(number: $0, text: text) } }
                            .sorted { $0.number < $1.number }
                    }
                    if !chapterMap.isEmpty { indexed[bookID] = chapterMap }
                }
                result[editionID] = EditionText(translation: file.translation,
                                                source: file.source,
                                                bookNames: file.bookNames ?? [:],
                                                books: indexed,
                                                rawBooks: file.books)
            }
            return result
        }.value

        editions = loaded
        isLoaded = true
    }

    // MARK: - 조회

    func hasText(edition: Edition) -> Bool {
        !(editions[edition.id]?.books.isEmpty ?? true)
    }

    func hasText(edition: Edition, book: BibleBook) -> Bool {
        !(editions[edition.id]?.books[book.id]?.isEmpty ?? true)
    }

    /// 판본에 실제 담긴 책 수 / 목차상 책 수
    func availability(edition: Edition) -> (loaded: Int, total: Int) {
        let scoped = edition.scope.books
        let loaded = scoped.filter { hasText(edition: edition, book: $0) }.count
        return (loaded, scoped.count)
    }

    func verses(edition: Edition, book: BibleBook, chapter: Int) -> [Verse] {
        editions[edition.id]?.books[book.id]?[chapter] ?? []
    }

    /// 판본 고유의 책 표시 이름 (없으면 기본 한국어 이름)
    func bookName(edition: Edition, book: BibleBook) -> String {
        editions[edition.id]?.bookNames[book.id] ?? book.name
    }

    func bookShortName(edition: Edition, book: BibleBook) -> String {
        editions[edition.id]?.bookNames[book.id] ?? book.shortName
    }

    // MARK: - 검색 (현재 판본 안에서)

    func search(_ query: String, edition: Edition, mode: SearchMode = .text, limit: Int = 200) async -> [SearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, let text = editions[edition.id] else { return [] }
        let snapshot = text.rawBooks
        let order = edition.scope.books.map(\.id)
        let editionID = edition.id

        return await Task.detached(priority: .userInitiated) {
            var hits: [SearchHit] = []

            switch mode {
            case .text:
                hits = self.searchByText(trimmed, snapshot: snapshot, order: order, editionID: editionID, limit: limit)
            case .reference:
                hits = self.searchByReference(trimmed, snapshot: snapshot, order: order, editionID: editionID, limit: limit)
            }

            return hits
        }.value
    }

    nonisolated(unsafe) private func searchByText(_ query: String, snapshot: [String: [String: [String: String]]],
                             order: [String], editionID: String, limit: Int) -> [SearchHit] {
        var hits: [SearchHit] = []
        let terms = query.split(separator: " ").filter { !$0.isEmpty }
        let orTerms = terms.count > 1 && query.contains("OR") ? terms.map(String.init) : []
        let andTerms = orTerms.isEmpty ? terms.map(String.init) : []

        outer: for bookID in order {
            guard let chapters = snapshot[bookID] else { continue }
            let chapterNumbers = chapters.keys.compactMap { Int($0) }.sorted()
            for chapterNumber in chapterNumbers {
                guard let verses = chapters[String(chapterNumber)] else { continue }
                let verseNumbers = verses.keys.compactMap { Int($0) }.sorted()
                for verseNumber in verseNumbers {
                    guard let verseText = verses[String(verseNumber)] else { continue }
                    var matches = false

                    if !orTerms.isEmpty {
                        matches = orTerms.contains { verseText.localizedStandardContains($0) }
                    } else if !andTerms.isEmpty {
                        matches = andTerms.allSatisfy { verseText.localizedStandardContains($0) }
                    }

                    if matches {
                        hits.append(SearchHit(editionID: editionID, bookID: bookID,
                                            chapter: chapterNumber, verse: verseNumber,
                                            text: verseText))
                        if hits.count >= limit { break outer }
                    }
                }
            }
        }
        return hits
    }

    nonisolated(unsafe) private func searchByReference(_ query: String, snapshot: [String: [String: [String: String]]],
                                   order: [String], editionID: String, limit: Int) -> [SearchHit] {
        var hits: [SearchHit] = []
        let pattern = "^(\\d+):(\\d+)(?:-(\\d+))?$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return hits }

        let queryNS = query as NSString
        let range = NSRange(location: 0, length: queryNS.length)

        if let match = regex.firstMatch(in: query, range: range) {
            let chapter = Int(queryNS.substring(with: match.range(at: 1))) ?? 0
            let verse = Int(queryNS.substring(with: match.range(at: 2))) ?? 0
            let endVerse = match.range(at: 3).location != NSNotFound ? Int(queryNS.substring(with: match.range(at: 3))) ?? verse : verse

            guard chapter > 0, verse > 0 else { return hits }

            for bookID in order {
                guard let chapters = snapshot[bookID] else { continue }
                guard let verses = chapters[String(chapter)] else { continue }

                for v in verse...min(endVerse, verse + 10) {
                    guard let verseText = verses[String(v)] else { continue }
                    hits.append(SearchHit(editionID: editionID, bookID: bookID,
                                        chapter: chapter, verse: v,
                                        text: verseText))
                    if hits.count >= limit { break }
                }
                if !hits.isEmpty { break }
            }
        }
        return hits
    }

    /// 여러 판본에서 한꺼번에 검색한다(판본 순서대로, 판본별 상한 적용).
    func searchAll(_ query: String, editions searchEditions: [Edition],
                   mode: SearchMode = .text, limit: Int = 400) async -> [SearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        let perEdition = max(40, limit / max(1, searchEditions.count))
        var all: [SearchHit] = []
        for edition in searchEditions {
            guard editions[edition.id] != nil else { continue }
            let hits = await search(trimmed, edition: edition, mode: mode, limit: perEdition)
            all.append(contentsOf: hits)
            if all.count >= limit { break }
        }
        return Array(all.prefix(limit))
    }

    /// 본문이 로드된 판본만
    var loadedEditions: [Edition] {
        Editions.all.filter { editions[$0.id] != nil }
    }
}
