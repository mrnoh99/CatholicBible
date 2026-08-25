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
    let number: String
    let text: String

    var id: String { number }
}

nonisolated struct SectionTitle: Identifiable, Hashable, Sendable {
    let verse: String
    let text: String

    var id: String { verse }
}

nonisolated struct SearchHit: Identifiable, Hashable, Sendable {
    let editionID: String
    let bookID: String
    let chapter: Int
    let verse: Int
    let text: String
    let annotationNumber: String?  // 주석 검색 결과의 주석 번호

    var id: String { "\(editionID)-\(bookID)-\(chapter)-\(verse)-\(annotationNumber ?? "")" }
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
    /// 주석 데이터 (책 id → 장(String) → 절(String) → 주석 텍스트)
    var annotations: [String: [String: [String: String]]] = [:]
    /// 소제목 데이터 (책 id → 장(String) → 절(String) → 제목 텍스트)
    var titles: [String: [String: [String: String]]] = [:]
}

@Observable
final class BibleStore {
    private(set) var isLoaded = false
    /// 판본 id → 본문 (파일이 없는 판본은 항목 자체가 없음)
    private(set) var editions: [String: EditionText] = [:]

    private let referenceRegex = try! NSRegularExpression(pattern: "^(\\d+):(\\d+)(?:-(\\d+))?$")

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

                // 파일에 포함된 제목 로드 (BibleText_*.json의 headings 필드)
                var headingsFromFile: [String: [String: [String: String]]] = [:]
                if let fileHeadings = file.headings {
                    for (bookID, chapters) in fileHeadings {
                        var bookHeadings: [String: [String: String]] = [:]
                        for (chapterKey, verses) in chapters {
                            var verseHeadings: [String: String] = [:]
                            for (verseKey, headingText) in verses {
                                verseHeadings[verseKey] = headingText
                            }
                            if !verseHeadings.isEmpty {
                                bookHeadings[chapterKey] = verseHeadings
                            }
                        }
                        if !bookHeadings.isEmpty {
                            headingsFromFile[bookID] = bookHeadings
                        }
                    }
                }

                // 주석 로드
                var annotations: [String: [String: [String: String]]] = [:]
                var titles: [String: [String: [String: String]]] = [:]
                let annotationFileName = BibleStore.annotationFileName(for: editionID)
                print("📝 주석 로드 시도: \(editionID) → \(annotationFileName).json")
                if let annotationURL = Bundle.main.url(forResource: annotationFileName, withExtension: "json"),
                   let annotationData = try? Data(contentsOf: annotationURL),
                   let annotationFile = try? JSONDecoder().decode(AnnotationFile.self, from: annotationData) {
                    print("✅ \(editionID) 주석 로드 성공")

                    // 주석 로드
                    if let annots = annotationFile.annotations {
                        for (bookID, chapters) in annots {
                            var bookAnnotations: [String: [String: String]] = [:]
                            for (chapterKey, annots) in chapters {
                                var verseAnnotations: [String: String] = [:]
                                for annot in annots {
                                    verseAnnotations[annot.n] = annot.text
                                }
                                if !verseAnnotations.isEmpty {
                                    bookAnnotations[chapterKey] = verseAnnotations
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
                            var bookTitles: [String: [String: String]] = [:]
                            for (chapterKey, titleList) in chapters {
                                var verseTitles: [String: String] = [:]
                                for title in titleList {
                                    verseTitles[String(title.v)] = title.text
                                }
                                if !verseTitles.isEmpty {
                                    bookTitles[chapterKey] = verseTitles
                                }
                            }
                            if !bookTitles.isEmpty {
                                titles[bookID] = bookTitles
                            }
                        }
                    }
                }


                // 파일의 제목과 주석의 제목 합치기
                for (bookID, bookHeadings) in headingsFromFile {
                    if titles[bookID] == nil {
                        titles[bookID] = [:]
                    }
                    for (chapterKey, chapterHeadings) in bookHeadings {
                        if titles[bookID]![chapterKey] == nil {
                            titles[bookID]![chapterKey] = [:]
                        }
                        for (verseKey, headingText) in chapterHeadings {
                            var cleanHeading = headingText

                            // 제목이 너무 길면 parenthetical 절 마커 앞부분만 추출
                            // (예: 에스더의 경우 "모르도카이의 꿈 1(1)..." → "모르도카이의 꿈")
                            if headingText.count > 150 {
                                // "1(", "2(" 등의 parenthetical 절 마커로 시작하는 부분 찾기
                                if let regex = try? NSRegularExpression(pattern: "\\s+\\d+\\(", options: []) {
                                    if let match = regex.firstMatch(in: headingText, options: [], range: NSRange(headingText.startIndex..., in: headingText)) {
                                        if let range = Range(match.range, in: headingText) {
                                            cleanHeading = String(headingText[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                                        }
                                    }
                                }
                            }

                            // 정제된 제목이 유효한 제목 형식인지 확인 (너무 짧지 않고, 마침표로 끝남 또는 간단한 구문)
                            if cleanHeading.count > 3 && cleanHeading.count < 150 {
                                // 마침표로 끝나거나, 짧은 구문(5-30자 사이)이면 제목으로 인정
                                if cleanHeading.hasSuffix(".") || (cleanHeading.count < 30 && !cleanHeading.contains("\n")) {
                                    // 이미 있는 제목이 없을 때만 파일의 제목 사용
                                    if titles[bookID]![chapterKey]![verseKey] == nil {
                                        titles[bookID]![chapterKey]![verseKey] = cleanHeading
                                    }
                                }
                            }
                        }
                    }
                }

                let annotationCount = annotations.values.reduce(0) { $0 + $1.values.reduce(0) { $0 + $1.count } }
                let titleCount = titles.values.reduce(0) { $0 + $1.values.reduce(0) { $0 + $1.count } }
                if annotationCount > 0 {
                    print("✅ \(editionID) 주석 개수: \(annotationCount)개")
                } else {
                    print("⚠️ \(editionID) 주석: 없음")
                }
                if titleCount > 0 {
                    print("[BibleStore] Edition '\(editionID)' has \(titleCount) titles")
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
        case "ncb":
            return "NcbNotes"
        default:
            return ""
        }
    }

    /// NAB 같이 titles 파일이 없는 판본에서 verse 데이터를 분석해 제목 추출
    private static nonisolated func extractTitlesFromVerses(
        _ books: [String: [String: [String: String]]]
    ) -> [String: [String: [String: String]]] {
        var result: [String: [String: [String: String]]] = [:]

        for (bookID, chapters) in books {
            var bookTitles: [String: [String: String]] = [:]

            for (chapterKey, verses) in chapters {
                var chapterTitles: [String: String] = [:]

                for (verseKey, verseText) in verses {
                    // 제목 판별 기준
                    if Self.isLikelyTitle(verseText) {
                        chapterTitles[verseKey] = verseText
                    }
                }

                if !chapterTitles.isEmpty {
                    bookTitles[chapterKey] = chapterTitles
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
              let chapterTitles = bookTitles[String(chapter)] else { return [] }
        let result = chapterTitles
            .map { SectionTitle(verse: $0.key, text: $0.value) }
            .sorted { compareVerseKeys($0.verse, $1.verse) }
        if edition.id == "nabre" && book.id == "gn" && chapter == 1 {
            print("[NABRE] titles() for Genesis Ch1: \(result.count) titles, verses: \(result.map { $0.verse })")
        }
        return result
    }

    private func compareVerseKeys(_ a: String, _ b: String) -> Bool {
        // "1", "2", "10", "1(1)", "1(2)" 등을 올바르게 정렬
        if let aNum = Int(a), let bNum = Int(b) {
            return aNum < bNum
        }
        if let aBase = Int(a.split(separator: "(").first.map(String.init) ?? a),
           let bBase = Int(b.split(separator: "(").first.map(String.init) ?? b) {
            if aBase != bBase { return aBase < bBase }
        }
        return a < b
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

    nonisolated private func searchByText(_ query: String, snapshot: [String: [String: [String: String]]],
                             order: [String], editionID: String, limit: Int, offset: Int = 0) -> [SearchHit] {
        let (orTerms, andTerms) = parseSearchTerms(query)
        guard !orTerms.isEmpty || !andTerms.isEmpty else { return [] }

        var hits: [SearchHit] = []
        var matched = 0

        outer: for bookID in order {
            guard let chapters = snapshot[bookID] else { continue }
            let chapterNumbers = chapters.keys.compactMap { Int($0) }.sorted()
            for chapterNumber in chapterNumbers {
                guard let verses = chapters[String(chapterNumber)] else { continue }
                let verseNumbers = verses.keys.compactMap { Int($0) }.sorted()
                for verseNumber in verseNumbers {
                    guard let verseText = verses[String(verseNumber)] else { continue }
                    let matches = !orTerms.isEmpty
                        ? orTerms.contains { verseText.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
                        : andTerms.allSatisfy { verseText.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }

                    if matches {
                        if matched >= offset && hits.count < limit {
                            hits.append(SearchHit(editionID: editionID, bookID: bookID,
                                                chapter: chapterNumber, verse: verseNumber,
                                                text: verseText, annotationNumber: nil))
                        }
                        matched += 1
                        if hits.count >= limit { break outer }
                    }
                }
            }
        }
        return hits
    }

    nonisolated private func searchByReference(_ query: String, snapshot: [String: [String: [String: String]]],
                                   order: [String], editionID: String, limit: Int, offset: Int = 0) -> [SearchHit] {
        guard let (chapter, verse, endVerse) = parseReference(query) else { return [] }

        var hits: [SearchHit] = []
        var matched = 0

        for bookID in order {
            guard let chapters = snapshot[bookID] else { continue }
            guard let verses = chapters[String(chapter)] else { continue }

            for v in verse...min(endVerse, verse + 100) {
                guard let verseText = verses[String(v)] else { continue }
                if matched >= offset && hits.count < limit {
                    hits.append(SearchHit(editionID: editionID, bookID: bookID,
                                        chapter: chapter, verse: v,
                                        text: verseText, annotationNumber: nil))
                }
                matched += 1
                if hits.count >= limit { break }
            }
            if !hits.isEmpty { break }
        }
        return hits
    }

    nonisolated private func parseSearchTerms(_ query: String) -> (orTerms: [String], andTerms: [String]) {
        let terms = query.split(separator: " ").filter { !$0.isEmpty }
        let orTerms = terms.count > 1 && query.contains("OR") ? terms.map(String.init) : []
        let andTerms = orTerms.isEmpty ? terms.map(String.init) : []
        return (orTerms, andTerms)
    }

    nonisolated private func parseReference(_ query: String) -> (chapter: Int, verse: Int, endVerse: Int)? {
        let queryNS = query as NSString
        let range = NSRange(location: 0, length: queryNS.length)
        guard let match = referenceRegex.firstMatch(in: query, range: range) else { return nil }

        let chapter = Int(queryNS.substring(with: match.range(at: 1))) ?? 0
        let verse = Int(queryNS.substring(with: match.range(at: 2))) ?? 0
        let endVerse = match.range(at: 3).location != NSNotFound ? Int(queryNS.substring(with: match.range(at: 3))) ?? verse : verse

        guard chapter > 0, verse > 0 else { return nil }
        return (chapter, verse, endVerse)
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

    nonisolated private func countSearchByText(_ query: String, snapshot: [String: [String: [String: String]]],
                                          order: [String]) -> Int {
        let (orTerms, andTerms) = parseSearchTerms(query)
        guard !orTerms.isEmpty || !andTerms.isEmpty else { return 0 }

        var count = 0

        for bookID in order {
            guard let chapters = snapshot[bookID] else { continue }
            let chapterNumbers = chapters.keys.compactMap { Int($0) }.sorted()
            for chapterNumber in chapterNumbers {
                guard let verses = chapters[String(chapterNumber)] else { continue }
                let verseNumbers = verses.keys.compactMap { Int($0) }.sorted()
                for verseNumber in verseNumbers {
                    guard let verseText = verses[String(verseNumber)] else { continue }
                    let matches = !orTerms.isEmpty
                        ? orTerms.contains { verseText.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
                        : andTerms.allSatisfy { verseText.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }

                    if matches {
                        count += 1
                    }
                }
            }
        }
        return count
    }

    nonisolated private func countSearchByReference(_ query: String, snapshot: [String: [String: [String: String]]],
                                              order: [String]) -> Int {
        guard let (chapter, verse, endVerse) = parseReference(query) else { return 0 }

        var count = 0
        for bookID in order {
            guard let chapters = snapshot[bookID] else { continue }
            guard let verses = chapters[String(chapter)] else { continue }

            for v in verse...min(endVerse, verse + 100) {
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
        guard !query.isEmpty, let text = editions[edition.id] else {
            print("🔍 검색 실패: edition.id=\(edition.id), 가용한 판본: \(editions.keys)")
            return 0
        }
        print("🔍 검색 시도: '\(query)' in \(edition.id)")
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return 0 }
        let order = edition.scope.books.map(\.id)

        return await Task.detached(priority: .userInitiated) {
            // 정확한 구문 검색 (큰따옴표로 감싸진 경우)
            let isPhrase = trimmed.starts(with: "\"") && trimmed.hasSuffix("\"")
            let searchQuery = isPhrase ? String(trimmed.dropFirst().dropLast()) : trimmed

            guard !searchQuery.isEmpty else { return 0 }

            var count = 0
            print("  - 검색 범위: \(order.count)개 책, 주석 데이터 책: \(text.annotations.keys.count)개")

            for bookID in order {
                guard let chapters = text.annotations[bookID] else { continue }
                for (_, verses) in chapters {
                    for (_, annotationText) in verses {
                        let matches: Bool
                        if isPhrase {
                            // 정확한 문구 검색
                            matches = annotationText.range(of: searchQuery, options: [.caseInsensitive]) != nil
                        } else {
                            // AND 검색 (모든 단어 포함)
                            let terms = searchQuery.split(separator: " ").map(String.init).filter { !$0.isEmpty }
                            matches = terms.allSatisfy { annotationText.range(of: $0, options: [.caseInsensitive]) != nil }
                        }
                        if matches {
                            count += 1
                        }
                    }
                }
            }
            print("📊 검색 결과: '\(searchQuery)' in \(edition.id) = \(count)개")
            return count
        }.value
    }

    /// 주석에서 offset과 limit으로 검색 결과 일부 가져오기
    func searchAnnotationsWithOffset(_ query: String, edition: Edition, offset: Int = 0, limit: Int = 50) async -> [SearchHit] {
        guard !query.isEmpty, let text = editions[edition.id] else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        let order = edition.scope.books.map(\.id)

        return await Task.detached(priority: .userInitiated) {
            // 정확한 구문 검색 (큰따옴표로 감싸진 경우)
            let isPhrase = trimmed.starts(with: "\"") && trimmed.hasSuffix("\"")
            let searchQuery = isPhrase ? String(trimmed.dropFirst().dropLast()) : trimmed

            guard !searchQuery.isEmpty else { return [] }

            var hits: [SearchHit] = []
            var matched = 0

            outer: for bookID in order {
                guard let chapters = text.annotations[bookID] else { continue }
                let chapterNumbers = chapters.keys.sorted()
                for chapterKey in chapterNumbers {
                    guard let verses = chapters[chapterKey] else { continue }
                    guard let chapterNumber = Int(chapterKey) else { continue }
                    let verseNumbers = verses.keys.sorted()
                    for verseKey in verseNumbers {
                        guard let annotationText = verses[verseKey] else { continue }
                        guard let verseNumber = Int(verseKey) else { continue }

                        let matches: Bool
                        if isPhrase {
                            // 정확한 문구 검색
                            matches = annotationText.range(of: searchQuery, options: [.caseInsensitive]) != nil
                        } else {
                            // AND 검색 (모든 단어 포함)
                            let terms = searchQuery.split(separator: " ").map(String.init).filter { !$0.isEmpty }
                            matches = terms.allSatisfy { annotationText.range(of: $0, options: [.caseInsensitive]) != nil }
                        }
                        if matches {
                            if matched >= offset && hits.count < limit {
                                hits.append(SearchHit(editionID: edition.id, bookID: bookID,
                                                    chapter: chapterNumber, verse: verseNumber,
                                                    text: annotationText, annotationNumber: verseKey))
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
