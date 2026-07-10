//
//  Bible.swift
//  CatholicBible
//
//  한국 천주교 주교회의 「성경」 73권(구약 46권 + 신약 27권) 목차 메타데이터.
//  책 이름·약칭·장수는 주교회의 성경 표기를 따른다 (https://bible.cbck.or.kr).
//

import Foundation

// MARK: - Testament

enum Testament: String, CaseIterable, Identifiable, Hashable, Sendable {
    case old
    case new

    var id: String { rawValue }

    var title: String {
        switch self {
        case .old: return "구약 성경"
        case .new: return "신약 성경"
        }
    }
}

// MARK: - Category (서가 구분)

enum BookCategory: String, CaseIterable, Identifiable, Hashable, Sendable {
    case pentateuch      // 오경
    case historical      // 역사서
    case wisdom          // 시서와 지혜서
    case prophets        // 예언서
    case gospels         // 복음서
    case acts            // 사도행전
    case paulineLetters  // 바오로 서간
    case catholicLetters // 가톨릭 서간
    case revelation      // 묵시록

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pentateuch: return "오경"
        case .historical: return "역사서"
        case .wisdom: return "시서와 지혜서"
        case .prophets: return "예언서"
        case .gospels: return "복음서"
        case .acts: return "사도행전"
        case .paulineLetters: return "바오로 서간"
        case .catholicLetters: return "가톨릭 서간"
        case .revelation: return "묵시록"
        }
    }

    var testament: Testament {
        switch self {
        case .pentateuch, .historical, .wisdom, .prophets: return .old
        case .gospels, .acts, .paulineLetters, .catholicLetters, .revelation: return .new
        }
    }
}

// MARK: - Book

struct BibleBook: Identifiable, Hashable, Sendable {
    /// 저장/조회에 쓰는 안정적 식별자 (BibleText_<판본>.json의 키와 일치)
    let id: String
    /// 정식 명칭 (예: "코린토 신자들에게 보낸 첫째 서간")
    let name: String
    /// 짧은 이름 (예: "코린토 1서")
    let shortName: String
    /// 성구 표기 약칭 (예: "1코린")
    let abbrev: String
    let category: BookCategory
    let chapterCount: Int

    var testament: Testament { category.testament }

    /// "시편 23편" / "창세기 3장" 식의 장 표기
    func chapterLabel(_ chapter: Int) -> String {
        id == "ps" ? "\(chapter)편" : "\(chapter)장"
    }
}

// MARK: - Canon (73권)

enum Bible {
    static let books: [BibleBook] = [
        // ───── 구약 · 오경 ─────
        BibleBook(id: "gn",    name: "창세기",   shortName: "창세기",   abbrev: "창세",  category: .pentateuch, chapterCount: 50),
        BibleBook(id: "ex",    name: "탈출기",   shortName: "탈출기",   abbrev: "탈출",  category: .pentateuch, chapterCount: 40),
        BibleBook(id: "lv",    name: "레위기",   shortName: "레위기",   abbrev: "레위",  category: .pentateuch, chapterCount: 27),
        BibleBook(id: "nm",    name: "민수기",   shortName: "민수기",   abbrev: "민수",  category: .pentateuch, chapterCount: 36),
        BibleBook(id: "dt",    name: "신명기",   shortName: "신명기",   abbrev: "신명",  category: .pentateuch, chapterCount: 34),
        // ───── 구약 · 역사서 ─────
        BibleBook(id: "jos",   name: "여호수아기",     shortName: "여호수아기",   abbrev: "여호",   category: .historical, chapterCount: 24),
        BibleBook(id: "jgs",   name: "판관기",         shortName: "판관기",       abbrev: "판관",   category: .historical, chapterCount: 21),
        BibleBook(id: "ru",    name: "룻기",           shortName: "룻기",         abbrev: "룻",     category: .historical, chapterCount: 4),
        BibleBook(id: "1sm",   name: "사무엘기 상권",  shortName: "사무엘기 상",  abbrev: "1사무",  category: .historical, chapterCount: 31),
        BibleBook(id: "2sm",   name: "사무엘기 하권",  shortName: "사무엘기 하",  abbrev: "2사무",  category: .historical, chapterCount: 24),
        BibleBook(id: "1kgs",  name: "열왕기 상권",    shortName: "열왕기 상",    abbrev: "1열왕",  category: .historical, chapterCount: 22),
        BibleBook(id: "2kgs",  name: "열왕기 하권",    shortName: "열왕기 하",    abbrev: "2열왕",  category: .historical, chapterCount: 25),
        BibleBook(id: "1chr",  name: "역대기 상권",    shortName: "역대기 상",    abbrev: "1역대",  category: .historical, chapterCount: 29),
        BibleBook(id: "2chr",  name: "역대기 하권",    shortName: "역대기 하",    abbrev: "2역대",  category: .historical, chapterCount: 36),
        BibleBook(id: "ezr",   name: "에즈라기",       shortName: "에즈라기",     abbrev: "에즈",   category: .historical, chapterCount: 10),
        BibleBook(id: "neh",   name: "느헤미야기",     shortName: "느헤미야기",   abbrev: "느헤",   category: .historical, chapterCount: 13),
        BibleBook(id: "tb",    name: "토빗기",         shortName: "토빗기",       abbrev: "토빗",   category: .historical, chapterCount: 14),
        BibleBook(id: "jdt",   name: "유딧기",         shortName: "유딧기",       abbrev: "유딧",   category: .historical, chapterCount: 16),
        BibleBook(id: "est",   name: "에스테르기",     shortName: "에스테르기",   abbrev: "에스",   category: .historical, chapterCount: 10),
        BibleBook(id: "1mc",   name: "마카베오기 상권", shortName: "마카베오기 상", abbrev: "1마카", category: .historical, chapterCount: 16),
        BibleBook(id: "2mc",   name: "마카베오기 하권", shortName: "마카베오기 하", abbrev: "2마카", category: .historical, chapterCount: 15),
        // ───── 구약 · 시서와 지혜서 ─────
        BibleBook(id: "jb",    name: "욥기",     shortName: "욥기",     abbrev: "욥",    category: .wisdom, chapterCount: 42),
        BibleBook(id: "ps",    name: "시편",     shortName: "시편",     abbrev: "시편",  category: .wisdom, chapterCount: 150),
        BibleBook(id: "prv",   name: "잠언",     shortName: "잠언",     abbrev: "잠언",  category: .wisdom, chapterCount: 31),
        BibleBook(id: "eccl",  name: "코헬렛",   shortName: "코헬렛",   abbrev: "코헬",  category: .wisdom, chapterCount: 12),
        BibleBook(id: "sg",    name: "아가",     shortName: "아가",     abbrev: "아가",  category: .wisdom, chapterCount: 8),
        BibleBook(id: "wis",   name: "지혜서",   shortName: "지혜서",   abbrev: "지혜",  category: .wisdom, chapterCount: 19),
        BibleBook(id: "sir",   name: "집회서",   shortName: "집회서",   abbrev: "집회",  category: .wisdom, chapterCount: 51),
        // ───── 구약 · 예언서 ─────
        BibleBook(id: "is",    name: "이사야서",   shortName: "이사야서",   abbrev: "이사",  category: .prophets, chapterCount: 66),
        BibleBook(id: "jer",   name: "예레미야서", shortName: "예레미야서", abbrev: "예레",  category: .prophets, chapterCount: 52),
        BibleBook(id: "lam",   name: "애가",       shortName: "애가",       abbrev: "애가",  category: .prophets, chapterCount: 5),
        BibleBook(id: "bar",   name: "바룩서",     shortName: "바룩서",     abbrev: "바룩",  category: .prophets, chapterCount: 6),
        BibleBook(id: "ez",    name: "에제키엘서", shortName: "에제키엘서", abbrev: "에제",  category: .prophets, chapterCount: 48),
        BibleBook(id: "dn",    name: "다니엘서",   shortName: "다니엘서",   abbrev: "다니",  category: .prophets, chapterCount: 14),
        BibleBook(id: "hos",   name: "호세아서",   shortName: "호세아서",   abbrev: "호세",  category: .prophets, chapterCount: 14),
        BibleBook(id: "jl",    name: "요엘서",     shortName: "요엘서",     abbrev: "요엘",  category: .prophets, chapterCount: 4),
        BibleBook(id: "am",    name: "아모스서",   shortName: "아모스서",   abbrev: "아모",  category: .prophets, chapterCount: 9),
        BibleBook(id: "ob",    name: "오바드야서", shortName: "오바드야서", abbrev: "오바",  category: .prophets, chapterCount: 1),
        BibleBook(id: "jon",   name: "요나서",     shortName: "요나서",     abbrev: "요나",  category: .prophets, chapterCount: 4),
        BibleBook(id: "mi",    name: "미카서",     shortName: "미카서",     abbrev: "미카",  category: .prophets, chapterCount: 7),
        BibleBook(id: "na",    name: "나훔서",     shortName: "나훔서",     abbrev: "나훔",  category: .prophets, chapterCount: 3),
        BibleBook(id: "hb",    name: "하바쿡서",   shortName: "하바쿡서",   abbrev: "하바",  category: .prophets, chapterCount: 3),
        BibleBook(id: "zep",   name: "스바니야서", shortName: "스바니야서", abbrev: "스바",  category: .prophets, chapterCount: 3),
        BibleBook(id: "hg",    name: "하까이서",   shortName: "하까이서",   abbrev: "하까",  category: .prophets, chapterCount: 2),
        BibleBook(id: "zec",   name: "즈카르야서", shortName: "즈카르야서", abbrev: "즈카",  category: .prophets, chapterCount: 14),
        BibleBook(id: "mal",   name: "말라키서",   shortName: "말라키서",   abbrev: "말라",  category: .prophets, chapterCount: 3),
        // ───── 신약 · 복음서 ─────
        BibleBook(id: "mt",    name: "마태오 복음서", shortName: "마태오 복음", abbrev: "마태", category: .gospels, chapterCount: 28),
        BibleBook(id: "mk",    name: "마르코 복음서", shortName: "마르코 복음", abbrev: "마르", category: .gospels, chapterCount: 16),
        BibleBook(id: "lk",    name: "루카 복음서",   shortName: "루카 복음",   abbrev: "루카", category: .gospels, chapterCount: 24),
        BibleBook(id: "jn",    name: "요한 복음서",   shortName: "요한 복음",   abbrev: "요한", category: .gospels, chapterCount: 21),
        // ───── 신약 · 사도행전 ─────
        BibleBook(id: "acts",  name: "사도행전", shortName: "사도행전", abbrev: "사도", category: .acts, chapterCount: 28),
        // ───── 신약 · 바오로 서간 ─────
        BibleBook(id: "rom",   name: "로마 신자들에게 보낸 서간",          shortName: "로마서",       abbrev: "로마",   category: .paulineLetters, chapterCount: 16),
        BibleBook(id: "1cor",  name: "코린토 신자들에게 보낸 첫째 서간",   shortName: "코린토 1서",   abbrev: "1코린",  category: .paulineLetters, chapterCount: 16),
        BibleBook(id: "2cor",  name: "코린토 신자들에게 보낸 둘째 서간",   shortName: "코린토 2서",   abbrev: "2코린",  category: .paulineLetters, chapterCount: 13),
        BibleBook(id: "gal",   name: "갈라티아 신자들에게 보낸 서간",      shortName: "갈라티아서",   abbrev: "갈라",   category: .paulineLetters, chapterCount: 6),
        BibleBook(id: "eph",   name: "에페소 신자들에게 보낸 서간",        shortName: "에페소서",     abbrev: "에페",   category: .paulineLetters, chapterCount: 6),
        BibleBook(id: "phil",  name: "필리피 신자들에게 보낸 서간",        shortName: "필리피서",     abbrev: "필리",   category: .paulineLetters, chapterCount: 4),
        BibleBook(id: "col",   name: "콜로새 신자들에게 보낸 서간",        shortName: "콜로새서",     abbrev: "콜로",   category: .paulineLetters, chapterCount: 4),
        BibleBook(id: "1thes", name: "테살로니카 신자들에게 보낸 첫째 서간", shortName: "테살로니카 1서", abbrev: "1테살", category: .paulineLetters, chapterCount: 5),
        BibleBook(id: "2thes", name: "테살로니카 신자들에게 보낸 둘째 서간", shortName: "테살로니카 2서", abbrev: "2테살", category: .paulineLetters, chapterCount: 3),
        BibleBook(id: "1tm",   name: "티모테오에게 보낸 첫째 서간",        shortName: "티모테오 1서", abbrev: "1티모",  category: .paulineLetters, chapterCount: 6),
        BibleBook(id: "2tm",   name: "티모테오에게 보낸 둘째 서간",        shortName: "티모테오 2서", abbrev: "2티모",  category: .paulineLetters, chapterCount: 4),
        BibleBook(id: "ti",    name: "티토에게 보낸 서간",                 shortName: "티토서",       abbrev: "티토",   category: .paulineLetters, chapterCount: 3),
        BibleBook(id: "phlm",  name: "필레몬에게 보낸 서간",               shortName: "필레몬서",     abbrev: "필레",   category: .paulineLetters, chapterCount: 1),
        BibleBook(id: "heb",   name: "히브리인들에게 보낸 서간",           shortName: "히브리서",     abbrev: "히브",   category: .paulineLetters, chapterCount: 13),
        // ───── 신약 · 가톨릭 서간 ─────
        BibleBook(id: "jas",   name: "야고보 서간",      shortName: "야고보서",   abbrev: "야고",   category: .catholicLetters, chapterCount: 5),
        BibleBook(id: "1pt",   name: "베드로의 첫째 서간", shortName: "베드로 1서", abbrev: "1베드", category: .catholicLetters, chapterCount: 5),
        BibleBook(id: "2pt",   name: "베드로의 둘째 서간", shortName: "베드로 2서", abbrev: "2베드", category: .catholicLetters, chapterCount: 3),
        BibleBook(id: "1jn",   name: "요한의 첫째 서간",  shortName: "요한 1서",   abbrev: "1요한", category: .catholicLetters, chapterCount: 5),
        BibleBook(id: "2jn",   name: "요한의 둘째 서간",  shortName: "요한 2서",   abbrev: "2요한", category: .catholicLetters, chapterCount: 1),
        BibleBook(id: "3jn",   name: "요한의 셋째 서간",  shortName: "요한 3서",   abbrev: "3요한", category: .catholicLetters, chapterCount: 1),
        BibleBook(id: "jude",  name: "유다 서간",        shortName: "유다서",     abbrev: "유다",   category: .catholicLetters, chapterCount: 1),
        // ───── 신약 · 묵시록 ─────
        BibleBook(id: "rv",    name: "요한 묵시록", shortName: "요한 묵시록", abbrev: "묵시", category: .revelation, chapterCount: 22),
    ]

    static let booksByID: [String: BibleBook] = Dictionary(uniqueKeysWithValues: books.map { ($0.id, $0) })

    static func book(_ id: String) -> BibleBook? { booksByID[id] }

    static func books(in category: BookCategory) -> [BibleBook] {
        books.filter { $0.category == category }
    }

    static func books(in testament: Testament) -> [BibleBook] {
        books.filter { $0.testament == testament }
    }
}
