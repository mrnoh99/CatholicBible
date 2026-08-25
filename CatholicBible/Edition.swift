//
//  Edition.swift
//  CatholicBible
//
//  천주교회의 판본들. 각 판본이 서재의 ebook 한 권이다.
//
//    1. 성경(새 번역)      /Knb             73권
//    2. 영어 NAB 성경      /Nab             73권 (미국 가톨릭)
//    3. 주석 성경          /Knbnotes/Bible  73권 (TOB 기반 주석)
//    4. 공동번역 성서       /Ncb             73권
//    5. 200주년 신약성서    /200             신약 27권
//    6. NABRE(본문+주석)   /                73권 (영어)
//    7. 최민순 역 시편      /Pscms           시편 150편
//    8. Nova Vulgata      /Vulgata         73권 (라틴어)
//    9. 전례 시편          /Pslitur         시편 150편
//

import Foundation

/// 판본이 담는 책의 범위
enum EditionScope: String, Sendable {
    case full          // 구약+신약 73권
    case newTestament  // 신약 27권
    case psalter       // 시편 150편

    /// 이 범위에 포함되는 책들 (성경 목차 순서)
    var books: [BibleBook] {
        switch self {
        case .full:         return Bible.books
        case .newTestament: return Bible.books.filter { $0.testament == .new }
        case .psalter:      return Bible.books.filter { $0.id == "ps" }
        }
    }

    func contains(_ book: BibleBook) -> Bool {
        switch self {
        case .full:         return true
        case .newTestament: return book.testament == .new
        case .psalter:      return book.id == "ps"
        }
    }
}

struct Edition: Identifiable, Hashable, Sendable {
    /// 저장/파일명에 쓰는 식별자 (Resources/BibleText_<id>.json)
    let id: String
    /// bible.cbck.or.kr URL 경로 (수집 스크립트와 일치)
    let urlPath: String
    let name: String
    let shortName: String
    /// 저작권 표시 (각 장 하단)
    let copyright: String
    /// 서재 카드에 보여 줄 한 줄 설명
    let summary: String
    let scope: EditionScope
    /// 본문 언어 코드 ("ko", "en", "la")
    let language: String

    /// 본문 + 주석을 2단으로 보는 '주석 판본'인지 (주석성경·NABRE).
    /// 주석 데이터는 KnbNotesStore 가 판본 id 별로 로드한다
    /// (knbnotes→KnbNotes.json, nabre→NabreNotes.json).
    var isAnnotated: Bool { id == "knbnotes" || id == "nabre" }
}

enum Editions {
    static let all: [Edition] = [
        Edition(id: "knb", urlPath: "Knb",
                name: "성경", shortName: "성경",
                copyright: "「성경」 ⓒ 한국천주교주교회의",
                summary: "한국 천주교 공용 새 번역 성경 (2005)",
                scope: .full, language: "ko"),
        Edition(id: "nab", urlPath: "Nab",
                name: "영어 NAB 성경", shortName: "NAB",
                copyright: "New American Bible ⓒ Confraternity of Christian Doctrine (USCCB)",
                summary: "미국 가톨릭 공용 영어 성경",
                scope: .full, language: "en"),
        Edition(id: "knbnotes", urlPath: "Knbnotes/Bible",
                name: "주석 성경", shortName: "주석성경",
                copyright: "「주석 성경」 ⓒ 한국천주교주교회의",
                summary: "「성경」 본문 + TOB 기반 주석",
                scope: .full, language: "ko"),
        Edition(id: "ncb", urlPath: "Ncb",
                name: "공동번역 성서", shortName: "공동번역",
                copyright: "「공동번역 성서」 ⓒ 대한성서공회",
                summary: "가톨릭·개신교 공동 번역 (1977/개정 1999)",
                scope: .full, language: "ko"),
        Edition(id: "b200", urlPath: "200",
                name: "200주년 신약성서", shortName: "200주년 신약성서",
                copyright: "「200주년 신약성서」 ⓒ 분도출판사",
                summary: "한국 천주교 200주년 기념 신약 번역",
                scope: .newTestament, language: "ko"),
        Edition(id: "nabre", urlPath: "",
                name: "NABRE (본문+주석)", shortName: "NABRE 주석",
                copyright: "New American Bible, revised edition ⓒ Confraternity of Christian Doctrine (USCCB)",
                summary: "미국 가톨릭 공용 영어 성경(개정판) + 주석·소제목",
                scope: .full, language: "en"),
        Edition(id: "pscms", urlPath: "Pscms",
                name: "최민순 역 시편", shortName: "최민순시편",
                copyright: "「시편」 최민순 옮김 ⓒ 한국천주교주교회의 게재본",
                summary: "최민순 신부의 운문 시편 번역",
                scope: .psalter, language: "ko"),
        Edition(id: "vulgata", urlPath: "Vulgata",
                name: "Nova Vulgata", shortName: "Vulgata",
                copyright: "Nova Vulgata ⓒ Libreria Editrice Vaticana",
                summary: "교회 공식 라틴어 성경",
                scope: .full, language: "la"),
        Edition(id: "pslitur", urlPath: "Pslitur",
                name: "전례 시편", shortName: "전례시편",
                copyright: "「전례 시편」 ⓒ 한국천주교주교회의",
                summary: "미사·성무일도에 쓰는 전례용 시편",
                scope: .psalter, language: "ko"),
    ]

    static let byID: [String: Edition] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func edition(_ id: String) -> Edition? { byID[id] }

    static let defaultEditionID = "knb"
}
