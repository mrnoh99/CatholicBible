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

    private static let markerRegex = try? NSRegularExpression(
        pattern: "(?<![\\d(])(\\d{1,3})\\)")

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

private struct KnbNotesFile: Decodable {
    let intros: [Introduction]?
    /// 책 id → 장(문자열) → 주석 목록
    let annotations: [String: [String: [ChapterNote]]]?
    /// 책 id → 장(문자열) → 소제목 목록
    let titles: [String: [String: [TitleItem]]]?
}

// MARK: - 저장소

@Observable
final class KnbNotesStore {
    private(set) var isLoaded = false
    private(set) var intros: [Introduction] = []
    /// 책 id → 장 → 주석
    private(set) var annotations: [String: [Int: [ChapterNote]]] = [:]
    /// 책 id → 장 → 소제목
    private(set) var titles: [String: [Int: [TitleItem]]] = [:]

    var hasData: Bool { !intros.isEmpty || !annotations.isEmpty }

    func load() async {
        guard !isLoaded else { return }
        guard let url = Bundle.main.url(forResource: "KnbNotes", withExtension: "json") else {
            isLoaded = true
            return
        }
        let parsed: (intros: [Introduction],
                     anno: [String: [Int: [ChapterNote]]],
                     titles: [String: [Int: [TitleItem]]])? =
            await Task.detached(priority: .userInitiated) {
                guard let data = try? Data(contentsOf: url),
                      let file = try? JSONDecoder().decode(KnbNotesFile.self, from: data)
                else { return nil }
                var anno: [String: [Int: [ChapterNote]]] = [:]
                for (bookID, chapters) in file.annotations ?? [:] {
                    var map: [Int: [ChapterNote]] = [:]
                    for (chKey, notes) in chapters where Int(chKey) != nil {
                        map[Int(chKey)!] = notes
                    }
                    anno[bookID] = map
                }
                var titleMap: [String: [Int: [TitleItem]]] = [:]
                for (bookID, chapters) in file.titles ?? [:] {
                    var map: [Int: [TitleItem]] = [:]
                    for (chKey, items) in chapters where Int(chKey) != nil {
                        map[Int(chKey)!] = items
                    }
                    titleMap[bookID] = map
                }
                return (file.intros ?? [], anno, titleMap)
            }.value
        if let parsed {
            intros = parsed.intros
            annotations = parsed.anno
            titles = parsed.titles
        }
        isLoaded = true
    }

    // MARK: 조회

    func notes(bookID: String, chapter: Int) -> [ChapterNote] {
        annotations[bookID]?[chapter] ?? []
    }

    /// 절 번호 → 그 절 앞에 놓일 소제목
    func titlesByVerse(bookID: String, chapter: Int) -> [Int: String] {
        var map: [Int: String] = [:]
        for item in titles[bookID]?[chapter] ?? [] { map[item.v] = item.text }
        return map
    }

    func intro(forBook bookID: String) -> Introduction? {
        intros.first { $0.level == .book && $0.bookID == bookID }
    }

    var bibleIntro: Introduction? { intros.first { $0.level == .bible } }

    func intros(of level: IntroLevel) -> [Introduction] {
        intros.filter { $0.level == level }
    }
}
