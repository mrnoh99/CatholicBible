//
//  KnbNotes.swift
//  CatholicBible
//
//  주석 성경(knbnotes)의 '입문(Introduction)'과 장별 '주석(annotation)'.
//  데이터는 Resources/KnbNotes.json (scripts/fetch_knbnotes.py 로 수집).
//  파일이 없으면 빈 상태로, 리더가 '주석 자료 준비 중'을 안내한다.
//

import Foundation
import Observation
import SwiftUI

// MARK: - 모델

struct ChapterNote: Codable, Identifiable, Hashable, Sendable {
    /// 각주 번호(문자열)
    let n: String
    let text: String
    var id: String { n }
}

/// 장 소제목 (해당 절 앞에 놓인다)
struct TitleItem: Codable, Hashable, Sendable {
    let v: Int        // 이 소제목이 앞서는 절 번호
    let text: String
}

// MARK: - 성경 참조 정규화

enum ScriptureRefNormalizer {
    /// 주석 텍스트의 성경 참조들을 정규화한다.
    /// 문맥상 생략된 책 이름을 추론하여 모든 참조를 완전하게 만든다.
    /// 예: "창세 1,1; 2,4-23; 욥 1,1; 2,1" → "창세 1,1; 창세 2,4-23; 욥 1,1; 욥 2,1"
    ///
    /// - Parameters:
    ///   - text: 정규화할 주석 텍스트
    ///   - currentBookID: 현재 주석이 속한 책 ID (예: "1chr", "1mo")
    ///   - chapter: 현재 장 번호 (절만 있는 참조를 정규화하기 위해 사용)
    static func normalize(_ text: String, currentBookID: String = "", chapter: Int = 0) -> String {
        var result = text

        // 1단계: "책 장의 절과 절" 형태를 정규화
        result = normalizeChapterRanges(result)

        // 2단계: "절 참조" 패턴 정규화 (괄호나 "참조" 포함)
        let currentBook = currentBookID.isEmpty ? nil : Bible.book(currentBookID)?.name
        if let currentBook = currentBook {
            result = normalizeVerseOnlyReferences(result, currentBook: currentBook, chapter: chapter)
        }

        // 3단계: "장 참조" 패턴 정규화
        result = normalizeChapterOnlyReferences(result, currentBook: currentBook)

        // 3.5단계: "장 범위 참조" 패턴 정규화 (예: "(28─29장 참조)", "(13─14 참조)")
        result = normalizeChapterRangeReferences(result, currentBook: currentBook)

        // 3.6단계: "점 형식 절 참조" 패턴 정규화 (예: "(3.13.14절)" → "(책 3,13); (책 3,14)")
        if let currentBook = currentBook, chapter > 0 {
            result = normalizeDotFormatReferences(result, currentBook: currentBook, chapter: chapter)
        }

        // 3.75단계: "입문 참조" 패턴 정규화 (예: "('입문' 6 참조)", "('입문' 4의 2)")
        if let currentBook = currentBook {
            result = normalizeIntroductionReferences(result, currentBook: currentBook)
        }

        // 3.8단계: "쉼표-점 형식" 절 참조 정규화 (예: "(1,1.19; 4,5)" → "(현재책 1,1; 현재책 1,19; 현재책 4,5)")
        if let currentBook = currentBook {
            result = normalizeCommaDotFormatReferences(result, currentBook: currentBook)
        }

        // 4단계: 세미콜론 구분 참조 정규화 (기존 로직)
        let parts = result.split(separator: ";", omittingEmptySubsequences: false).map { String($0) }
        var normalized: [String] = []
        var contextBook: String? = currentBook

        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                normalized.append(part)
                continue
            }

            let (book, ref) = extractBookAndRef(from: trimmed)

            // 책 이름이나 약자가 명시되지 않은 경우, ref에 약자가 있는지 다시 확인
            var finalBook = book
            var finalRef = ref

            if book == nil && !ref.isEmpty {
                // ref의 앞에 있는 구두점 제거하고 첫 단어가 책 약자인지 확인
                var refToCheck = ref
                while !refToCheck.isEmpty && !refToCheck.first!.isLetter {
                    refToCheck.removeFirst()
                }

                let refWords = refToCheck.split(separator: " ", maxSplits: 1).map { String($0) }
                if !refWords.isEmpty {
                    let firstWord = refWords[0]
                    if let foundBook = Bible.books.first(where: { $0.abbrev == firstWord || $0.searchKeywords.contains(firstWord) }) {
                        // 약자를 찾았으므로 책 이름을 사용하되, 약자는 유지
                        finalBook = foundBook.name
                        finalRef = ref  // 약자를 포함한 원본 ref 유지
                    }
                }
            }

            if let book = finalBook {
                contextBook = book
                // 책 이름이 명시된 경우: 중복 방지
                // ref가 책 약자로 시작하는지 확인 (예: "마태 1,1", "마르 2,1" 등)
                var shouldIncludeBook = true
                let refWords = finalRef.split(separator: " ").map { String($0) }
                if !refWords.isEmpty {
                    let firstWord = refWords[0]
                    // 참조의 첫 단어가 어떤 책의 약자나 검색 키워드와 일치하면 중복으로 판단
                    if Bible.books.contains(where: { $0.abbrev == firstWord || $0.searchKeywords.contains(firstWord) }) {
                        shouldIncludeBook = false
                    }

                    // ref의 어느 부분이든 책 이름이나 약자가 있으면, 그 부분부터 시작하는 참조로 재처리
                    // 예: "복음서 사도 4,31" → "사도 4,31" 사용
                    if shouldIncludeBook && refWords.count > 1 {
                        for i in 1..<refWords.count {
                            let potentialBookRef = refWords[i...].joined(separator: " ")
                            let currentWord = refWords[i]

                            // 약자 또는 searchKeywords 확인
                            if let foundBook = Bible.books.first(where: {
                                $0.abbrev == currentWord || $0.searchKeywords.contains(currentWord)
                            }) {
                                finalRef = potentialBookRef
                                shouldIncludeBook = false
                                break
                            }
                            // 전체 책 이름 확인
                            if let foundBook = Bible.books.first(where: { potentialBookRef.hasPrefix($0.name) }) {
                                finalRef = potentialBookRef
                                shouldIncludeBook = false
                                break
                            }
                        }
                    }
                }

                if shouldIncludeBook {
                    normalized.append(part.replacingOccurrences(of: trimmed, with: "\(book) \(finalRef)"))
                } else {
                    normalized.append(part.replacingOccurrences(of: trimmed, with: finalRef))
                }
            } else {
                normalized.append(part)
            }
        }

        return normalized.joined(separator: ";")
    }

    /// 절만 있는 참조를 정규화한다.
    /// 예: "(29절)" → "(현재책 현재장,29절)" (chapter > 0 일 때)
    /// 예: "6절 각주 참조" → "현재책 현재장,6절 각주 참조" (chapter > 0 일 때)
    /// chapter == 0 일 때는 책 이름만 추가.
    private static func normalizeVerseOnlyReferences(_ text: String, currentBook: String, chapter: Int) -> String {
        var result = text
        let chapterStr = chapter > 0 ? "\(chapter)," : ""

        // 패턴 1: "(절 번호절)" 또는 "(절 범위절)"
        // 예: "(29절)", "(1-23절)", "(18ㄴ-21절)", "(29-31절)", "(11-47절)"
        // 명시적 절 범위 패턴: 숫자[한글?][-숫자[한글?]?]?
        let pattern1 = "\\((\\d+[ㄱ-ㅁ]?(?:[-─]\\d+[ㄱ-ㅁ]?)?)절\\)"
        if let regex = try? NSRegularExpression(pattern: pattern1) {
            let ns = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            for match in matches.reversed() {
                if match.numberOfRanges >= 2 {
                    let verse = ns.substring(with: match.range(at: 1))
                    let replacement = "(\(currentBook) \(chapterStr)\(verse)절)"
                    result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
                }
            }
        }

        // 패턴 2: "절 각주 참조" 또는 "절에/에서/의" 형태 (뒤에 문맥 단어가 올 수 있음)
        // 예: "6절 각주 참조", "11절에 나온다", "17-23절에서는", "24-27절의 명단", "18ㄴ-21절의"
        let pattern2 = "(\\d+[ㄱ-ㅁ]?(?:[-─]\\d+[ㄱ-ㅁ]?)?)절(?:\\s*(?:에(?:\\s+[가-힣]+)*|에서(?:\\s+[가-힣]+)*|의|각주\\s*참조))"
        if let regex = try? NSRegularExpression(pattern: pattern2) {
            let ns = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            for match in matches.reversed() {
                if match.numberOfRanges >= 2 {
                    let verse = ns.substring(with: match.range(at: 1))
                    let fullMatch = ns.substring(with: match.range)
                    // 앞에 "현재책"을 추가하되 중복 제거
                    if !fullMatch.hasPrefix(currentBook) {
                        // verse (예: "5절")만 사용해서 LinkableRef 형태로 변환
                        // fullMatch (예: "5절의")의 뒤 부분은 따로 보존
                        let suffix = String(fullMatch.dropFirst(verse.count))  // "의" 등
                        let replacement = "\(currentBook) \(chapterStr)\(verse)\(suffix)"
                        result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
                    }
                }
            }
        }

        return result
    }

    /// 점 형식 절 참조를 정규화한다.
    /// 예: "(3.13.14절)" → "(책 장,13; 장,14)"
    /// 같은 장 내의 여러 절을 하나의 괄호 안에서 세미콜론으로 분리
    private static func normalizeDotFormatReferences(_ text: String, currentBook: String, chapter: Int) -> String {
        var result = text

        // 패턴: "(숫자.숫자.숫자...절)" 또는 "(숫자.숫자절)"
        // 예: (3.13.14절), (17.20.24절), (21.23.24절)
        let pattern = "\\((\\d+)(?:\\.(\\d+))+절\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return result
        }

        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))

        for match in matches.reversed() {
            if match.numberOfRanges >= 2 {
                // 점 형식에서 모든 숫자 추출
                let fullMatch = ns.substring(with: match.range)
                let versesStr = fullMatch.replacingOccurrences(of: "(", with: "")
                    .replacingOccurrences(of: ")", with: "")
                    .replacingOccurrences(of: "절", with: "")
                    .trimmingCharacters(in: .whitespaces)

                let verses = versesStr.split(separator: ".").map { String($0) }

                // 세미콜론으로 분리된 참조로 변환 (첫 번째는 책과 장 포함, 나머지는 장과 절만)
                var verseReferences: [String] = []
                for (index, verse) in verses.enumerated() {
                    if index == 0 {
                        // 첫 번째: 전체 형식 "책 장,절"
                        verseReferences.append("\(currentBook) \(chapter),\(verse)")
                    } else {
                        // 나머지: "장,절" 형식만
                        verseReferences.append("\(chapter),\(verse)")
                    }
                }

                let replacement = "(\(verseReferences.joined(separator: "; ")))"
                result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
            }
        }

        return result
    }

    /// 입문 참조를 정규화한다.
    /// 예: "('입문' 6 참조)" → "(현재책 입문)" (현재 책의 입문 섹션으로 링크)
    /// 예: "('입문' 4의 2)" → "(현재책 입문)" (입문 섹션 번호는 제거, 입문으로만 통합)
    private static func normalizeIntroductionReferences(_ text: String, currentBook: String) -> String {
        var result = text

        // 패턴: "('입문' 숫자[의 숫자] [참조]?)"
        // 예: ('입문' 6 참조), ('입문' 4의 2), ('입문' 5)
        let pattern = "\\('입문'\\s+\\d+(?:의\\s*\\d+)?(?:\\s*참조)?\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return result
        }

        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))

        for match in matches.reversed() {
            // 모든 입문 참조를 현재 책의 입문으로 정규화
            let replacement = "(\(currentBook) 입문)"
            result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
        }

        return result
    }

    /// 쉼표-점 형식 절 참조를 정규화한다.
    /// 예: "(1,1.19; 4,5)" → "(현재책 1,1; 현재책 1,19; 현재책 4,5)"
    /// 같은 장 내의 여러 절을 쉼표-점으로 표현한 형식을 확장한다.
    private static func normalizeCommaDotFormatReferences(_ text: String, currentBook: String) -> String {
        var result = text

        // 패턴: "(장,절.절... 또는 장,절; 장,절.절...)"
        // 예: (1,1.19), (1,1.19; 4,5), (3,38; 6,10.28)
        // 점 형식이 있으면서 절 마커가 없는 쉼표-점 혼합 형식
        // 단, 책 이름이나 약자로 시작하는 것은 제외
        let pattern = "\\(([^)]*\\d+,\\d+(?:\\.\\d+)+[^)]*)\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return result
        }

        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))

        for match in matches.reversed() {
            let fullMatch = ns.substring(with: match.range(at: 0))
            let innerContent = (fullMatch as NSString).substring(with: NSRange(location: 1, length: fullMatch.count - 2))

            // 책 이름이나 약자로 시작하는지 확인 (이미 명시된 참조는 건너뛰기)
            var startsWithBook = false
            var bookPrefix = ""

            // 책 이름 확인
            for book in Bible.books {
                if innerContent.hasPrefix(book.name) {
                    startsWithBook = true
                    bookPrefix = book.name
                    break
                }
            }

            // 책 약자 확인
            if !startsWithBook {
                for book in Bible.books {
                    if innerContent.hasPrefix(book.abbrev) {
                        // 약자가 완전한 단어인지 확인 (예: "루" in "루카"가 아닌지)
                        let afterAbbrev = String(innerContent.dropFirst(book.abbrev.count))
                        if afterAbbrev.isEmpty || afterAbbrev.first?.isWhitespace ?? false {
                            startsWithBook = true
                            bookPrefix = book.abbrev
                            break
                        }
                    }
                }
            }

            // 이미 책이 명시된 경우 건너뛰기
            if startsWithBook {
                continue
            }

            // 세미콜론으로 분리된 참조들을 처리
            let refs = innerContent.split(separator: ";").map { String($0).trimmingCharacters(in: .whitespaces) }
            var expandedRefs: [String] = []

            for ref in refs {
                // 각 참조가 "N,V.V" 형식인지 확인
                let parts = ref.split(separator: ",")
                if parts.count == 2 {
                    let chapter = String(parts[0]).trimmingCharacters(in: .whitespaces)
                    let versePart = String(parts[1])

                    // 점으로 분리된 절들
                    let verses = versePart.split(separator: ".").map { String($0).trimmingCharacters(in: .whitespaces) }

                    if verses.count > 1 {
                        // 점 형식이 있음 - 각 절을 확장
                        for verse in verses {
                            expandedRefs.append("\(currentBook) \(chapter),\(verse)")
                        }
                    } else {
                        // 점 형식이 없으면 책 이름이 있는지 확인 후 추가
                        if ref.contains(currentBook) {
                            expandedRefs.append(ref)
                        } else {
                            expandedRefs.append("\(currentBook) \(ref)")
                        }
                    }
                } else if !ref.contains(currentBook) {
                    // 책 이름이 없으면 추가
                    expandedRefs.append("\(currentBook) \(ref)")
                } else {
                    expandedRefs.append(ref)
                }
            }

            let replacement = "(\(expandedRefs.joined(separator: "; ")))"
            result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
        }

        return result
    }

    /// 장 범위 참조를 정규화한다.
    /// 예: "(28─29장 참조)" → "(현재책 28─29장 참조)" 또는 유지 (이미 책 이름 있으면 유지)
    /// 예: "(28─29장)" → "(현재책 28─29장)"
    /// 예: "(13─14 참조)" → "(현재책 13─14 참조)"
    /// "참조" 유무는 상관없음 (동일하게 처리)
    private static func normalizeChapterRangeReferences(_ text: String, currentBook: String?) -> String {
        var result = text

        let bookNames = Bible.books.map { $0.name }

        // 패턴 1: 책 이름이 명시된 경우 - "(책이름 장─장[장?] [참조]?)"
        for book in bookNames {
            let pattern = "\\(\(NSRegularExpression.escapedPattern(for: book))\\s+(\\d+)[-─](\\d+)(?:장)?(?:\\s*참조)?\\)"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }

            let ns = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length))

            for match in matches.reversed() {
                if match.numberOfRanges >= 3 {
                    let startChapter = ns.substring(with: match.range(at: 1))
                    let endChapter = ns.substring(with: match.range(at: 2))
                    let replacement = "(\(book) \(startChapter)─\(endChapter) 참조)"
                    result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
                }
            }
        }

        // 패턴 2: 책 이름 없는 경우 - "(장─장[장?] [참조]?)"
        if let currentBook = currentBook {
            let pattern = "\\((\\d+)[-─](\\d+)(?:장)?(?:\\s*참조)?\\)"
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return result
            }

            let ns = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length))

            for match in matches.reversed() {
                if match.numberOfRanges >= 3 {
                    let startChapter = ns.substring(with: match.range(at: 1))
                    let endChapter = ns.substring(with: match.range(at: 2))
                    let replacement = "(\(currentBook) \(startChapter)─\(endChapter) 참조)"
                    result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
                }
            }
        }

        return result
    }

    /// 장만 있는 참조를 정규화한다.
    /// 예: "(창세 10 참조)" → "(창세 10 참조)" (이미 정규화됨 또는 유지)
    /// 예: "(24장 참조)" → "(현재책 24 참조)" (현재 책 이름 추가, 장 전체 보기)
    private static func normalizeChapterOnlyReferences(_ text: String, currentBook: String?) -> String {
        var result = text

        // 패턴 1: "(책이름 숫자 참조)" 또는 "(책이름 숫자장 참조)"
        // 이미 책 이름이 명시되어 있으므로 장 전체 보기 형식으로 유지
        let bookNames = Bible.books.map { $0.name }
        for book in bookNames {
            let pattern = "\\(\(NSRegularExpression.escapedPattern(for: book))\\s+(\\d+)(?:,\\d+)?(?:장)?\\s*참조\\)"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }

            let ns = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length))

            for match in matches.reversed() {
                if match.numberOfRanges >= 2 {
                    let chapterStr = ns.substring(with: match.range(at: 1))
                    // 장 전체를 보여주기 위해 절 번호 제거
                    let replacement = "(\(book) \(chapterStr) 참조)"
                    result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
                }
            }
        }

        // 패턴 2: "(숫자장 참조)" - 현재 책 컨텍스트 사용
        if let currentBook = currentBook {
            let pattern = "\\((\\d+)장\\s*참조\\)"
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return result
            }

            let ns = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length))

            for match in matches.reversed() {
                if match.numberOfRanges >= 2 {
                    let chapterStr = ns.substring(with: match.range(at: 1))
                    // 장 전체를 보여주기 위해 절 번호 없이 유지
                    let replacement = "(\(currentBook) \(chapterStr) 참조)"
                    result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
                }
            }
        }

        return result
    }

    /// 주어진 참조 부분에서 책 이름과 참조 부분을 분리한다.
    /// 반환: (책이름, 참조) 또는 (nil, 원본문자)
    private static func extractBookAndRef(from ref: String) -> (String?, String) {
        var searchStr = ref
        var prefix = ""

        // 앞의 괄호나 다른 구두점 제거하고 저장
        while !searchStr.isEmpty && !searchStr.first!.isLetter {
            prefix.append(searchStr.removeFirst())
        }

        // 먼저 전체 책 이름으로 확인
        for book in Bible.books {
            if searchStr.hasPrefix(book.name) {
                let afterBook = String(searchStr.dropFirst(book.name.count)).trimmingCharacters(in: .whitespaces)
                return (book.name, afterBook)
            }
        }

        // 그 다음 약자로 확인
        for book in Bible.books {
            if searchStr.hasPrefix(book.abbrev) {
                // 약자가 참조의 일부가 아닌지 확인 (예: "루" in "루카"가 아닌지)
                let afterAbbrev = String(searchStr.dropFirst(book.abbrev.count))
                if afterAbbrev.isEmpty || afterAbbrev.first?.isWhitespace ?? false || afterAbbrev.first?.isNumber ?? false {
                    let trimmed = afterAbbrev.trimmingCharacters(in: .whitespaces)
                    return (book.name, trimmed)
                }
            }
        }

        // searchKeywords로 확인 (예: "히브리서" → "히브리인들에게 보낸 서간")
        for book in Bible.books {
            for keyword in book.searchKeywords {
                if searchStr.hasPrefix(keyword) {
                    // 키워드가 참조의 일부가 아닌지 확인 (예: "히브" in "히브리"가 아닌지)
                    let afterKeyword = String(searchStr.dropFirst(keyword.count))
                    if afterKeyword.isEmpty || afterKeyword.first?.isWhitespace ?? false || afterKeyword.first?.isNumber ?? false {
                        let trimmed = afterKeyword.trimmingCharacters(in: .whitespaces)
                        return (book.name, trimmed)
                    }
                }
            }
        }

        // 책 이름이 없으면 참조는 숫자로 시작하거나 장만 있어야 함
        // (예: "2,4-23", "38─39", "74,14-17", "104")
        return (nil, ref)
    }

    /// "창세 10장의 9-12절과 18ㄴ-21절" → "창세 10,9-12; 창세 10,18ㄴ-21"
    /// 같은 장 내의 여러 절 범위를 정규화한다.
    static func normalizeChapterRanges(_ text: String) -> String {
        let bookNames = Bible.books.map { $0.name }
        var result = text

        for book in bookNames {
            // "책 장장의 절-절과 절-절" 패턴 찾기
            let pattern = "\(book)\\s+(\\d+)장의\\s+([\\d,ㄱ-ㄹ\\-─과 및,;]+)"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }

            let ns = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))

            for match in matches.reversed() {
                if match.numberOfRanges >= 3 {
                    let chapterStr = ns.substring(with: match.range(at: 1))
                    let verseStr = ns.substring(with: match.range(at: 2))

                    // "9-12절과 18ㄴ-21절" → ["9-12절", "18ㄴ-21절"]
                    let verseParts = verseStr.split(separator: "과", omittingEmptySubsequences: true)
                        .map { $0.trimmingCharacters(in: .whitespaces) }

                    var normalized: [String] = []
                    for part in verseParts {
                        let cleaned = part.replacingOccurrences(of: "절", with: "")
                            .trimmingCharacters(in: .whitespaces)
                        if !cleaned.isEmpty {
                            normalized.append("\(book) \(chapterStr),\(cleaned)")
                        }
                    }

                    let replacement = normalized.joined(separator: "; ")
                    let originalRange = match.range
                    result = (result as NSString).replacingCharacters(
                        in: originalRange,
                        with: replacement
                    )
                }
            }
        }

        return result
    }

    /// 성경 참조 텍스트를 AttributedString으로 변환하여 cross-link를 추가한다.
    static func attributed(_ text: String) -> AttributedString {
        let normalized = normalize(text)
        var result = AttributedString()

        // 참조별로 파싱
        let parts = normalized.split(separator: ";", omittingEmptySubsequences: false)

        for part in parts {
            let trimmed = String(part).trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                result += AttributedString(String(part))
                continue
            }

            if let (book, ref) = tryParseReference(trimmed) {
                // 책 이름
                var bookAttr = AttributedString(book)
                result += bookAttr
                result += AttributedString(" ")

                // 참조
                var refAttr = AttributedString(ref)
                refAttr.link = createLink(for: book, reference: ref)
                refAttr.foregroundColor = .accentColor
                result += refAttr

                // 세미콜론
                if let last = String(part).last, last == ";" {
                    result += AttributedString("; ")
                }
            } else {
                result += AttributedString(String(part))
            }
        }

        return result
    }

    /// 참조를 파싱하여 (책이름, 참조) 반환
    private static func tryParseReference(_ ref: String) -> (String, String)? {
        let bookNames = Bible.books.map { $0.name }

        for book in bookNames {
            if ref.hasPrefix(book) {
                let afterBook = String(ref.dropFirst(book.count)).trimmingCharacters(in: .whitespaces)
                if !afterBook.isEmpty {
                    return (book, afterBook)
                }
            }
        }
        return nil
    }

    /// 성경 참조를 위한 deep link 생성
    /// 입문 참조: "(책 입문)" → catholicbible://introduction?b=bookID
    /// 성경 참조: "(책 1,1)" → catholicbible://verse?b=bookID&c=1&v=1
    private static func createLink(for bookName: String, reference: String) -> URL? {
        guard let book = Bible.book(bookName) else { return nil }

        // 입문 참조 확인
        if reference.trimmingCharacters(in: .whitespaces) == "입문" {
            let url = "catholicbible://introduction?b=\(book.id)"
            return URL(string: url)
        }

        // 성경 참조 파싱: "1,1-10" → 장 1, 절 1-10
        let parts = reference.split(separator: ",")
        guard let chapter = Int(parts.first ?? "") else { return nil }

        let verse = parts.count > 1 ? String(parts[1]) : "1"
        let url = "catholicbible://verse?b=\(book.id)&c=\(chapter)&v=\(verse)"
        return URL(string: url)
    }
}

// MARK: - 각주 마커 링크 마크업

enum AnnotationMarkup {
    /// 본문의 각주 마커 'N)'(앞이 숫자·'('가 아닌 것)를 탭 가능한 링크로 바꾼다.
    /// 링크 URL: catholicbible://note?b=<책>&c=<장>&n=<번호>
    static func attributed(_ text: String, linkable: Bool,
                           bookID: String, chapter: Int) -> AttributedString {
        guard linkable, let regex = markerRegex else { return AttributedString(text) }
        let ns = text as NSString
        var result = AttributedString()
        var last = 0
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if m.range.location > last {
                result += AttributedString(ns.substring(with:
                    NSRange(location: last, length: m.range.location - last)))
            }
            var marker = AttributedString(ns.substring(with: m.range))
            let n = ns.substring(with: m.range(at: 1))
            marker.link = URL(string: "catholicbible://note?b=\(bookID)&c=\(chapter)&n=\(n)")
            marker.foregroundColor = .accentColor
            result += marker
            last = m.range.location + m.range.length
        }
        if last < ns.length {
            result += AttributedString(ns.substring(from: last))
        }
        return result
    }

    // 각주 마커 'N)' — 단, 인용 참조의 닫는 괄호(예: "요한 1,19-28)", "(마태 3,1-12)")는
    // 마커가 아니므로, 숫자 앞이 하이픈·쉼표·마침표·숫자·'('이면 마커로 보지 않는다.
    private static let markerRegex = try? NSRegularExpression(
        pattern: "(?<![-,.\\d(])(\\d{1,3})\\)")

    /// 각주 마커('N)')를 지운 깨끗한 문자열(주석 없는 「성경」 소제목 표시용).
    static func stripMarkers(_ text: String) -> String {
        guard let regex = markerRegex else { return text }
        let ns = text as NSString
        let out = regex.stringByReplacingMatches(
            in: text, range: NSRange(location: 0, length: ns.length), withTemplate: "")
        return out.replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}

/// 각주 마커를 눌렀을 때 보여 줄 대상
struct MarkerNoteTarget: Identifiable {
    let id = UUID()
    let n: String
    let text: String
    let bookID: String  // 소제목 링크의 각주 마커를 위해 필요
    let chapter: Int    // 소제목 링크의 각주 마커를 위해 필요
}

enum IntroLevel: String, Codable, Sendable {
    case bible       // 성경 전체
    case testament   // 구약/신약
    case category    // 오경/역사서/…
    case book        // 개별 책

    var label: String {
        switch self {
        case .bible: return "성경 전체"
        case .testament: return "구약·신약"
        case .category: return "분류"
        case .book: return "책"
        }
    }
}

struct Introduction: Codable, Identifiable, Hashable, Sendable {
    let id: String            // 사이트 입문 번호 (예: "2101")
    let title: String
    let level: IntroLevel
    let bookID: String?       // level == .book 일 때 연결된 책
    let body: String
    let notes: [ChapterNote]

    enum CodingKeys: String, CodingKey { case id, title, level, bookID, body, notes }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        level = (try? c.decode(IntroLevel.self, forKey: .level)) ?? .book
        bookID = try? c.decodeIfPresent(String.self, forKey: .bookID)
        body = (try? c.decode(String.self, forKey: .body)) ?? ""
        notes = (try? c.decode([ChapterNote].self, forKey: .notes)) ?? []
    }
}

// MARK: - 파일 구조

nonisolated private struct KnbNotesFile: Decodable {
    let intros: [Introduction]?
    /// 책 id → 장(문자열) → 주석 목록
    let annotations: [String: [String: [ChapterNote]]]?
    /// 책 id → 장(문자열) → 상호참조 목록 (NABRE 등)
    let crossrefs: [String: [String: [ChapterNote]]]?
    /// 책 id → 장(문자열) → 소제목 목록
    let titles: [String: [String: [TitleItem]]]?
}

// MARK: - 저장소

@Observable
final class KnbNotesStore {
    private(set) var isLoaded = false

    /// 판본 id → 데이터. 주석성경(knbnotes)·NABRE(nabre) 등 '주석 판본'별로 보관.
    private var introsByEd: [String: [Introduction]] = [:]
    private var annoByEd: [String: [String: [Int: [ChapterNote]]]] = [:]
    private var xrefByEd: [String: [String: [Int: [ChapterNote]]]] = [:]
    private var titlesByEd: [String: [String: [Int: [TitleItem]]]] = [:]

    /// 판본 id → 번들 리소스 파일명 (확장자 없이).
    private static let resourceMap: [(edition: String, file: String)] = [
        ("knbnotes", "KnbNotes"),
        ("nabre", "NabreNotes"),
    ]

    // 하위호환: 인자 없는 접근자는 주석성경(knbnotes) 기준.
    var intros: [Introduction] { introsByEd["knbnotes"] ?? [] }
    var bibleIntro: Introduction? { intros.first { $0.level == .bible } }
    var hasData: Bool { hasData(edition: "knbnotes") }

    func hasData(edition: String) -> Bool {
        !(introsByEd[edition]?.isEmpty ?? true) || !(annoByEd[edition]?.isEmpty ?? true)
    }

    func hasIntros(edition: String) -> Bool { !(introsByEd[edition]?.isEmpty ?? true) }

    func load() async {
        guard !isLoaded else { return }
        let resourceMap = Self.resourceMap
        let parsed = await Task.detached(priority: .userInitiated) {
            () -> (intros: [String: [Introduction]],
                   anno: [String: [String: [Int: [ChapterNote]]]],
                   xref: [String: [String: [Int: [ChapterNote]]]],
                   titles: [String: [String: [Int: [TitleItem]]]]) in
            // 책 id → 장(문자열) → 목록  을  장(Int) 키로 변환
            func byIntCh<T>(_ src: [String: [String: [T]]]?) -> [String: [Int: [T]]] {
                var out: [String: [Int: [T]]] = [:]
                for (bookID, chapters) in src ?? [:] {
                    var map: [Int: [T]] = [:]
                    for (chKey, items) in chapters where Int(chKey) != nil {
                        map[Int(chKey)!] = items
                    }
                    out[bookID] = map
                }
                return out
            }
            var introsByEd: [String: [Introduction]] = [:]
            var annoByEd: [String: [String: [Int: [ChapterNote]]]] = [:]
            var xrefByEd: [String: [String: [Int: [ChapterNote]]]] = [:]
            var titlesByEd: [String: [String: [Int: [TitleItem]]]] = [:]
            for (edition, file) in resourceMap {
                guard let url = Bundle.main.url(forResource: file, withExtension: "json"),
                      let data = try? Data(contentsOf: url),
                      let f = try? JSONDecoder().decode(KnbNotesFile.self, from: data)
                else { continue }
                introsByEd[edition] = f.intros ?? []
                annoByEd[edition] = byIntCh(f.annotations)
                xrefByEd[edition] = byIntCh(f.crossrefs)
                titlesByEd[edition] = byIntCh(f.titles)
            }
            return (introsByEd, annoByEd, xrefByEd, titlesByEd)
        }.value
        introsByEd = parsed.intros
        annoByEd = parsed.anno
        xrefByEd = parsed.xref
        titlesByEd = parsed.titles
        isLoaded = true
    }

    // MARK: 조회 (edition 기본값 = 주석성경)

    func notes(edition: String = "knbnotes", bookID: String, chapter: Int) -> [ChapterNote] {
        annoByEd[edition]?[bookID]?[chapter] ?? []
    }

    /// 상호참조(병행구/평행 구절). NABRE 등에서 제공.
    func crossrefs(edition: String, bookID: String, chapter: Int) -> [ChapterNote] {
        xrefByEd[edition]?[bookID]?[chapter] ?? []
    }

    /// 이 판본이 상호참조 데이터를 갖는가(탭 노출 여부).
    func hasCrossrefs(edition: String) -> Bool { !(xrefByEd[edition]?.isEmpty ?? true) }

    /// 절 번호 → 그 절 앞에 놓일 소제목
    func titlesByVerse(edition: String = "knbnotes", bookID: String, chapter: Int) -> [Int: String] {
        var map: [Int: String] = [:]
        for item in titlesByEd[edition]?[bookID]?[chapter] ?? [] { map[item.v] = item.text }
        return map
    }

    func intro(edition: String = "knbnotes", forBook bookID: String) -> Introduction? {
        introsByEd[edition]?.first { $0.level == .book && $0.bookID == bookID }
    }

    func intros(edition: String = "knbnotes", of level: IntroLevel) -> [Introduction] {
        (introsByEd[edition] ?? []).filter { $0.level == level }
    }
}
