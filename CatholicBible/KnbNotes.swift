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

// MARK: - 모델

struct ChapterNote: Codable, Identifiable, Hashable, Sendable {
    /// 각주 번호(문자열)
    let n: String
    let text: String
    var id: String { n }
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
}

// MARK: - 저장소

@Observable
final class KnbNotesStore {
    private(set) var isLoaded = false
    private(set) var intros: [Introduction] = []
    /// 책 id → 장 → 주석
    private(set) var annotations: [String: [Int: [ChapterNote]]] = [:]

    var hasData: Bool { !intros.isEmpty || !annotations.isEmpty }

    func load() async {
        guard !isLoaded else { return }
        guard let url = Bundle.main.url(forResource: "KnbNotes", withExtension: "json") else {
            isLoaded = true
            return
        }
        let parsed: (intros: [Introduction], anno: [String: [Int: [ChapterNote]]])? =
            await Task.detached(priority: .userInitiated) {
                guard let data = try? Data(contentsOf: url),
                      let file = try? JSONDecoder().decode(KnbNotesFile.self, from: data)
                else { return nil }
                var anno: [String: [Int: [ChapterNote]]] = [:]
                for (bookID, chapters) in file.annotations ?? [:] {
                    var map: [Int: [ChapterNote]] = [:]
                    for (chKey, notes) in chapters {
                        if let ch = Int(chKey) { map[ch] = notes }
                    }
                    anno[bookID] = map
                }
                return (file.intros ?? [], anno)
            }.value
        if let parsed {
            intros = parsed.intros
            annotations = parsed.anno
        }
        isLoaded = true
    }

    // MARK: 조회

    func notes(bookID: String, chapter: Int) -> [ChapterNote] {
        annotations[bookID]?[chapter] ?? []
    }

    func intro(forBook bookID: String) -> Introduction? {
        intros.first { $0.level == .book && $0.bookID == bookID }
    }

    var bibleIntro: Introduction? { intros.first { $0.level == .bible } }

    func intros(of level: IntroLevel) -> [Introduction] {
        intros.filter { $0.level == level }
    }
}
