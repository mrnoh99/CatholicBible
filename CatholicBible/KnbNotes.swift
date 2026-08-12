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

private struct KnbNotesFile: Decodable {
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
