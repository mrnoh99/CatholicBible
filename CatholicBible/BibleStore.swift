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
    /// 소제목 데이터 (책 id → 장 번호(문자열) → 절 번호(문자열) → 제목)
    let headings: [String: [String: [String: String]]]?
}

/// 주석 JSON 파일 구조
private nonisolated struct AnnotationFile: Decodable, Sendable {
    struct Annotation: Decodable, Sendable {
        let n: String  // 절 번호
        let text: String  // 주석 내용
    }

    struct Title: Decodable, Sendable {
        let v: Int  // 절 번호
        let text: String  // 제목 텍스트
    }

    let annotations: [String: [String: [Annotation]]]?  // 책 id → 장 → [주석]
    let titles: [String: [String: [Title]]]?  // 책 id → 장 → [제목]
}

nonisolated struct Verse: Identifiable, Hashable, Sendable {
    let number: Int
    let text: String

    var id: Int { number }
}

nonisolated struct SectionTitle: Identifiable, Hashable, Sendable {
    let verse: Int
    let text: String

    var id: Int { verse }
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
    /// 주석 데이터 (책 id → 장 → 절 → 주석 텍스트)
    var annotations: [String: [Int: [Int: String]]] = [:]
    /// 소제목 데이터 (책 id → 장 → 절 → 제목 텍스트)
    var titles: [String: [Int: [Int: String]]] = [:]
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

                // 주석 로드
                var annotations: [String: [Int: [Int: String]]] = [:]
                var titles: [String: [Int: [Int: String]]] = [:]
                if let annotationURL = Bundle.main.url(forResource: BibleStore.annotationFileName(for: editionID), withExtension: "json"),
                   let annotationData = try? Data(contentsOf: annotationURL),
                   let annotationFile = try? JSONDecoder().decode(AnnotationFile.self, from: annotationData) {

                    // 주석 로드
                    if let annots = annotationFile.annotations {
                        for (bookID, chapters) in annots {
                            var bookAnnotations: [Int: [Int: String]] = [:]
                            for (chapterKey, annots) in chapters {
                                if let chapterNumber = Int(chapterKey) {
                                    var verseAnnotations: [Int: String] = [:]
                                    for annot in annots {
                                        if let verseNumber = Int(annot.n) {
                                            verseAnnotations[verseNumber] = annot.text
                                        }
                                    }
                                    if !verseAnnotations.isEmpty {
                                        bookAnnotations[chapterNumber] = verseAnnotations
                                    }
                                }
                            }
                            if !bookAnnotations.isEmpty {
                                annotations[bookID] = bookAnnotations
                            }
                        }
                    }

                    // 소제목 로드
                    if let ttls = annotationFile.titles {
                        for (bookID, chapters) in ttls {
                            var bookTitles: [Int: [Int: String]] = [:]
                            for (chapterKey, titleList) in chapters {
                                if let chapterNumber = Int(chapterKey) {
                                    var verseTitles: [Int: String] = [:]
                                    for title in titleList {
                                        verseTitles[title.v] = title.text
                                    }
                                    if !verseTitles.isEmpty {
                                        bookTitles[chapterNumber] = verseTitles
                                    }
                                }
                            }
                            if !bookTitles.isEmpty {
                                titles[bookID] = bookTitles
                            }
                        }
                    }
                }

                // BibleTextFile의 headings 로드 (NABRE에서 사용)
                if editionID == "nabre" && file.headings != nil {
                    let headingsData = file.headings!
                    var nabreHeadingCount = 0
                    for (bookID, chapters) in headingsData {
                        if titles[bookID] == nil {
                            titles[bookID] = [:]
                        }
                        for (chapterKey, verseTitles) in chapters {
                            if let chapterNumber = Int(chapterKey) {
                                var titleMap: [Int: String] = [:]
                                for (verseKey, titleText) in verseTitles {
                                    if let verseNumber = Int(verseKey) {
                                        titleMap[verseNumber] = titleText
                                        nabreHeadingCount += 1
                                    }
                                }
                                if !titleMap.isEmpty {
                                    if titles[bookID]![chapterNumber] == nil {
                                        titles[bookID]![chapterNumber] = titleMap
                                    } else {
                                        // 기존 titles과 병합
                                        titles[bookID]![chapterNumber]?.merge(titleMap) { (_, new) in new }
                                    }
                                }
                            }
                        }
                    }
                }

                result[editionID] = EditionText(translation: file.translation,
                                                source: file.source,
                                                bookNames: file.bookNames ?? [:],
                                                books: indexed,
                                                rawBooks: file.books,
                                                annotations: annotations,
                                                titles: titles)
            }
            return result
        }.value

        editions = loaded
        isLoaded = true
    }

    private static nonisolated func annotationFileName(for editionID: String) -> String {
        switch editionID {
        case "knb", "knbnotes":
            return "KnbNotes"
        case "nabre":
            return "NabreNotes"
        default:
            return ""
        }
    }

    /// NAB 같이 titles 파일이 없는 판본에서 verse 데이터를 분석해 제목 추출
    private static nonisolated func extractTitlesFromVerses(
        _ books: [String: [String: [String: String]]]
    ) -> [String: [Int: [Int: String]]] {
        var result: [String: [Int: [Int: String]]] = [:]

        for (bookID, chapters) in books {
            var bookTitles: [Int: [Int: String]] = [:]

            for (chapterKey, verses) in chapters {
                guard let chapterNumber = Int(chapterKey) else { continue }
                var chapterTitles: [Int: String] = [:]

                for (verseKey, verseText) in verses {
                    guard let verseNumber = Int(verseKey) else { continue }

                    // 제목 판별 기준
                    if Self.isLikelyTitle(verseText) {
                        chapterTitles[verseNumber] = verseText
                    }
                }

                if !chapterTitles.isEmpty {
                    bookTitles[chapterNumber] = chapterTitles
                }
            }

            if !bookTitles.isEmpty {
                result[bookID] = bookTitles
            }
        }

        return result
    }

    /// Verse 텍스트가 제목인지 판별
    private static nonisolated func isLikelyTitle(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)

        // 기본 길이 체크 (제목은 보통 짧음)
        guard trimmed.count > 3 && trimmed.count < 150 else { return false }

        // 마침표로 끝나야 함
        guard trimmed.hasSuffix(".") else { return false }

        // 숫자가 많으면 제목이 아님
        let digitCount = trimmed.filter { $0.isNumber }.count
        guard digitCount < trimmed.count / 5 else { return false }

        let lowerText = trimmed.lowercased()

        // 제목처럼 보이는 시작 패턴
        let titlePatterns = [
            "the ", "teaching ", "parable ", "vision ", "prayer ", "psalm ",
            "blessed ", "produce ", "proclamation ", "song "
        ]
        let startsWithPattern = titlePatterns.contains { lowerText.hasPrefix($0) }

        // 일반 문장의 동사로 시작하면 제목이 아님
        let commonVerbStarts = [
            "when ", "then ", "said ", "behold ", "and ", "now ", "also ", "but ",
            "so ", "as ", "he ", "she ", "they ", "jesus ", "god ", "the lord "
        ]
        let startsWithVerb = commonVerbStarts.contains { lowerText.hasPrefix($0) }

        // 제목은 동사로 시작하지 않거나, 특정 제목 패턴을 가짐
        if startsWithPattern {
            return true
        }

        if startsWithVerb {
            return false
        }

        // 대문자로 시작하는 짧은 구문 중 쉼표가 없고 마침표로 끝남
        guard trimmed.first?.isUppercase == true else { return false }
        let hasComma = trimmed.filter { $0 == "," }.count > 0
        guard !hasComma || trimmed.filter({ $0 == "," }).count <= 1 else { return false }

        return true
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

    /// 장의 소제목 목록 (절 번호 순서로)
    func titles(edition: Edition, book: BibleBook, chapter: Int) -> [SectionTitle] {
        guard let bookTitles = editions[edition.id]?.titles[book.id],
              let chapterTitles = bookTitles[chapter] else { return [] }
        return chapterTitles
            .map { SectionTitle(verse: $0.key, text: $0.value) }
            .sorted { $0.verse < $1.verse }
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
                             order: [String], editionID: String, limit: Int, offset: Int = 0) -> [SearchHit] {
        var hits: [SearchHit] = []
        var matched = 0
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
                        matches = orTerms.contains { verseText.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
                    } else if !andTerms.isEmpty {
                        matches = andTerms.allSatisfy { verseText.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
                    }

                    if matches {
                        if matched >= offset && hits.count < limit {
                            hits.append(SearchHit(editionID: editionID, bookID: bookID,
                                                chapter: chapterNumber, verse: verseNumber,
                                                text: verseText))
                        }
                        matched += 1
                        if hits.count >= limit { break outer }
                    }
                }
            }
        }
        return hits
    }

    nonisolated(unsafe) private func searchByReference(_ query: String, snapshot: [String: [String: [String: String]]],
                                   order: [String], editionID: String, limit: Int, offset: Int = 0) -> [SearchHit] {
        var hits: [SearchHit] = []
        var matched = 0
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
                    if matched >= offset && hits.count < limit {
                        hits.append(SearchHit(editionID: editionID, bookID: bookID,
                                            chapter: chapter, verse: v,
                                            text: verseText))
                    }
                    matched += 1
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

    // MARK: - Lazy Loading 검색 (제한 없음)

    /// 검색 결과 총 개수만 파악 (첫 번째 판본)
    func searchCount(_ query: String, edition: Edition, mode: SearchMode = .text) async -> Int {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, let text = editions[edition.id] else { return 0 }
        let snapshot = text.rawBooks
        let order = edition.scope.books.map(\.id)

        return await Task.detached(priority: .userInitiated) {
            switch mode {
            case .text:
                return self.countSearchByText(trimmed, snapshot: snapshot, order: order)
            case .reference:
                return self.countSearchByReference(trimmed, snapshot: snapshot, order: order)
            }
        }.value
    }

    /// Offset과 limit으로 검색 결과 일부 가져오기
    func searchWithOffset(_ query: String, edition: Edition, mode: SearchMode = .text,
                        offset: Int = 0, limit: Int = 50) async -> [SearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, let text = editions[edition.id] else { return [] }
        let snapshot = text.rawBooks
        let order = edition.scope.books.map(\.id)
        let editionID = edition.id

        return await Task.detached(priority: .userInitiated) {
            switch mode {
            case .text:
                return self.searchByText(trimmed, snapshot: snapshot, order: order, editionID: editionID, limit: limit, offset: offset)
            case .reference:
                return self.searchByReference(trimmed, snapshot: snapshot, order: order, editionID: editionID, limit: limit, offset: offset)
            }
        }.value
    }

    /// 여러 판본에서 검색 결과 총 개수만 파악
    func searchAllCount(_ query: String, editions searchEditions: [Edition], mode: SearchMode = .text) async -> Int {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return 0 }
        var total = 0
        for edition in searchEditions {
            guard editions[edition.id] != nil else { continue }
            let count = await searchCount(trimmed, edition: edition, mode: mode)
            total += count
        }
        return total
    }

    /// 여러 판본에서 offset과 limit으로 검색 결과 일부 가져오기
    func searchAllWithOffset(_ query: String, editions searchEditions: [Edition],
                           mode: SearchMode = .text, offset: Int = 0, limit: Int = 50) async -> [SearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        var all: [SearchHit] = []
        var currentOffset = offset
        let perEdition = limit

        for edition in searchEditions {
            guard editions[edition.id] != nil else { continue }
            let hits = await searchWithOffset(trimmed, edition: edition, mode: mode, offset: currentOffset, limit: perEdition)
            all.append(contentsOf: hits)
            if hits.count < perEdition {
                currentOffset = 0
            } else {
                currentOffset -= hits.count
                if currentOffset < 0 {
                    currentOffset = 0
                }
            }
            if all.count >= limit { break }
        }
        return Array(all.prefix(limit))
    }

    // MARK: - 검색 결과 개수 카운팅

    nonisolated(unsafe) private func countSearchByText(_ query: String, snapshot: [String: [String: [String: String]]],
                                          order: [String]) -> Int {
        var count = 0
        let terms = query.split(separator: " ").filter { !$0.isEmpty }
        let orTerms = terms.count > 1 && query.contains("OR") ? terms.map(String.init) : []
        let andTerms = orTerms.isEmpty ? terms.map(String.init) : []

        for bookID in order {
            guard let chapters = snapshot[bookID] else { continue }
            let chapterNumbers = chapters.keys.compactMap { Int($0) }.sorted()
            for chapterNumber in chapterNumbers {
                guard let verses = chapters[String(chapterNumber)] else { continue }
                let verseNumbers = verses.keys.compactMap { Int($0) }.sorted()
                for verseNumber in verseNumbers {
                    guard let verseText = verses[String(verseNumber)] else { continue }
                    var matches = false

                    if !orTerms.isEmpty {
                        matches = orTerms.contains { verseText.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
                    } else if !andTerms.isEmpty {
                        matches = andTerms.allSatisfy { verseText.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
                    }

                    if matches {
                        count += 1
                    }
                }
            }
        }
        return count
    }

    nonisolated(unsafe) private func countSearchByReference(_ query: String, snapshot: [String: [String: [String: String]]],
                                              order: [String]) -> Int {
        let pattern = "^(\\d+):(\\d+)(?:-(\\d+))?$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }

        let queryNS = query as NSString
        let range = NSRange(location: 0, length: queryNS.length)

        guard let match = regex.firstMatch(in: query, range: range) else { return 0 }

        let chapter = Int(queryNS.substring(with: match.range(at: 1))) ?? 0
        let verse = Int(queryNS.substring(with: match.range(at: 2))) ?? 0
        let endVerse = match.range(at: 3).location != NSNotFound ? Int(queryNS.substring(with: match.range(at: 3))) ?? verse : verse

        guard chapter > 0, verse > 0 else { return 0 }

        var count = 0
        for bookID in order {
            guard let chapters = snapshot[bookID] else { continue }
            guard let verses = chapters[String(chapter)] else { continue }

            for v in verse...min(endVerse, verse + 10) {
                guard verses[String(v)] != nil else { continue }
                count += 1
            }
            if count > 0 { break }
        }
        return count
    }

    // MARK: - 주석 검색

    /// 주석에서 검색 결과 총 개수 파악
    func searchAnnotationsCount(_ query: String, edition: Edition) async -> Int {
        guard !query.isEmpty, let text = editions[edition.id] else { return 0 }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return 0 }

        return await Task.detached(priority: .userInitiated) {
            var count = 0
            let terms = trimmed.split(separator: " ").filter { !$0.isEmpty }
            let order = edition.scope.books.map(\.id)

            for bookID in order {
                guard let chapters = text.annotations[bookID] else { continue }
                for (_, verses) in chapters {
                    for (_, annotationText) in verses {
                        let matches = terms.allSatisfy { annotationText.localizedStandardContains(String($0)) }
                        if matches {
                            count += 1
                        }
                    }
                }
            }
            return count
        }.value
    }

    /// 주석에서 offset과 limit으로 검색 결과 일부 가져오기
    func searchAnnotationsWithOffset(_ query: String, edition: Edition, offset: Int = 0, limit: Int = 50) async -> [SearchHit] {
        guard !query.isEmpty, let text = editions[edition.id] else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        return await Task.detached(priority: .userInitiated) {
            var hits: [SearchHit] = []
            var matched = 0
            let terms = trimmed.split(separator: " ").filter { !$0.isEmpty }
            let order = edition.scope.books.map(\.id)

            outer: for bookID in order {
                guard let chapters = text.annotations[bookID] else { continue }
                let chapterNumbers = chapters.keys.sorted()
                for chapterNumber in chapterNumbers {
                    guard let verses = chapters[chapterNumber] else { continue }
                    let verseNumbers = verses.keys.sorted()
                    for verseNumber in verseNumbers {
                        guard let annotationText = verses[verseNumber] else { continue }

                        let matches = terms.allSatisfy { annotationText.localizedStandardContains(String($0)) }
                        if matches {
                            if matched >= offset && hits.count < limit {
                                hits.append(SearchHit(editionID: edition.id, bookID: bookID,
                                                    chapter: chapterNumber, verse: verseNumber,
                                                    text: annotationText))
                            }
                            matched += 1
                            if hits.count >= limit { break outer }
                        }
                    }
                }
            }
            return hits
        }.value
    }

    /// 여러 판본에서 주석 검색 결과 총 개수 파악
    func searchAllAnnotationsCount(_ query: String, editions searchEditions: [Edition]) async -> Int {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return 0 }
        var total = 0
        for edition in searchEditions {
            guard editions[edition.id] != nil else { continue }
            let count = await searchAnnotationsCount(trimmed, edition: edition)
            total += count
        }
        return total
    }

    /// 여러 판본에서 offset과 limit으로 주석 검색 결과 일부 가져오기
    func searchAllAnnotationsWithOffset(_ query: String, editions searchEditions: [Edition],
                                       offset: Int = 0, limit: Int = 50) async -> [SearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        var all: [SearchHit] = []
        var currentOffset = offset
        let perEdition = limit

        for edition in searchEditions {
            guard editions[edition.id] != nil else { continue }
            let hits = await searchAnnotationsWithOffset(trimmed, edition: edition, offset: currentOffset, limit: perEdition)
            all.append(contentsOf: hits)
            if hits.count < perEdition {
                currentOffset = 0
            } else {
                currentOffset -= hits.count
                if currentOffset < 0 {
                    currentOffset = 0
                }
            }
            if all.count >= limit { break }
        }
        return Array(all.prefix(limit))
    }

    /// 본문이 로드된 판본만
    var loadedEditions: [Edition] {
        Editions.all.filter { editions[$0.id] != nil }
    }
}
