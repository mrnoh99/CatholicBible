//
//  Liturgy.swift
//  CatholicBible
//
//  매일 미사 독서(제1독서·화답송·제2독서·복음) 모델과 저장소.
//  독서 참조(예: "창세 18,1-10ㄴ")를 이 앱의 책 id로 파싱해 리더로 연결한다.
//  자료는 Resources/DailyReadings_<연도>.json (scripts/fetch_liturgy.py 로 수집).
//  파일이 없으면 복음만 전례력으로 계산해 보여 준다.
//

import Foundation
import Observation

// MARK: - 성경 참조(성구)

/// 리더로 열 수 있는 성경 위치.
struct ScriptureCitation: Codable, Hashable, Sendable {
    let bookID: String
    let chapter: Int
    var verseStart: Int = 1
    var verseEnd: Int = 0
    /// 여러 장에 걸치는 독서의 끝 장 (기본은 chapter)
    var endChapter: Int?

    enum CodingKeys: String, CodingKey { case bookID, chapter, verseStart, verseEnd, endChapter }

    init(bookID: String, chapter: Int, verseStart: Int = 1, verseEnd: Int = 0, endChapter: Int? = nil) {
        self.bookID = bookID
        self.chapter = chapter
        self.verseStart = verseStart
        self.verseEnd = max(verseEnd, verseStart)
        self.endChapter = endChapter
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bookID = try c.decode(String.self, forKey: .bookID)
        chapter = try c.decode(Int.self, forKey: .chapter)
        verseStart = (try? c.decode(Int.self, forKey: .verseStart)) ?? 1
        verseEnd = (try? c.decode(Int.self, forKey: .verseEnd)) ?? 0
        endChapter = try? c.decodeIfPresent(Int.self, forKey: .endChapter)
    }

    var book: BibleBook? { Bible.book(bookID) }
}

/// 한국어 성구 약칭 → 책 id 파서 (예: "1코린 12,31-13,13").
enum ScriptureReference {
    /// 약칭/이름 → 책 id (긴 것부터 매칭). Bible 목차에서 자동 생성 + 소수 별칭.
    private static let aliasToID: [(alias: String, id: String)] = {
        var map: [String: String] = [:]
        for b in Bible.books {
            map[b.abbrev] = b.id
            map[b.shortName] = b.id
            map[b.name] = b.id
        }
        // 매일 미사에서 쓰는 별칭 보완
        let extra: [String: String] = [
            "시편": "ps", "시": "ps",
            "탈출": "ex", "레위": "lv", "민수": "nm", "신명": "dt",
            "1사무엘": "1sm", "2사무엘": "2sm", "1열왕": "1kgs", "2열왕": "2kgs",
            "1역대": "1chr", "2역대": "2chr", "느헤미야": "neh", "에즈라": "ezr",
            "집회": "sir", "지혜": "wis", "아가": "sg", "코헬렛": "eccl",
            "이사": "is", "예레": "jer", "에제": "ez", "다니": "dn",
            "사도": "acts", "로마": "rom", "히브": "heb", "야고": "jas",
            "묵시": "rv", "유다": "jude",
            "1코린": "1cor", "2코린": "2cor", "1테살": "1thes", "2테살": "2thes",
            "1티모": "1tm", "2티모": "2tm", "1베드": "1pt", "2베드": "2pt",
            "1요한": "1jn", "2요한": "2jn", "3요한": "3jn",
        ]
        for (k, v) in extra { map[k] = v }
        return map.sorted { $0.key.count > $1.key.count }.map { ($0.key, $0.value) }
    }()

    /// 참조 문자열의 첫 성구를 파싱한다(리더로 열 위치). 실패하면 nil.
    static func parse(_ reference: String) -> ScriptureCitation? {
        var s = reference.trimmingCharacters(in: .whitespaces)
        // 앞의 책 토큰 매칭
        guard let match = aliasToID.first(where: { s.hasPrefix($0.alias) }) else { return nil }
        s = String(s.dropFirst(match.alias.count)).trimmingCharacters(in: .whitespaces)
        // 시편 히브리어 병기 "15(14)" 등 괄호 번호 제거
        if let paren = try? NSRegularExpression(pattern: "\\([^)]*\\)") {
            s = paren.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: "")
        }

        // 장,절 파싱: "18,1-10" / "12,31-13,13" / "150" / "3,16.18"
        let ns = s as NSString
        guard let chapterVerse = try? NSRegularExpression(pattern: "^(\\d+)(?:\\s*,\\s*(\\d+))?(?:\\s*[-–]\\s*(\\d+)(?:\\s*,\\s*(\\d+))?)?") else {
            return nil
        }
        guard let m = chapterVerse.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        func grp(_ i: Int) -> Int? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : Int(ns.substring(with: r))
        }
        guard let chapter = grp(1) else { return nil }
        let vStart = grp(2) ?? 1
        // 끝 그룹: "-N,M" 이면 N=끝장, M=끝절 / "-M" 이면 끝절
        let g3 = grp(3), g4 = grp(4)
        var endChapter: Int? = nil
        var vEnd = vStart
        if let g4 { endChapter = g3; vEnd = g4 }
        else if let g3 { vEnd = g3 }

        return ScriptureCitation(bookID: match.id, chapter: chapter,
                                 verseStart: vStart, verseEnd: vEnd, endChapter: endChapter)
    }

    /// 참조 문자열을 강조용 구간(segment)까지 풀어 준다.
    /// 불연속 독서(예: "마태 4,12-17.23-25")의 빠진 절을 칠하지 않도록,
    /// 절 그룹을 각각 나눠 담는다. (칠하기 전용 — 리더 이동 위치는 parse가 담당)
    static func highlight(_ reference: String) -> (bookID: String, highlight: VerseHighlight)? {
        var s = reference.trimmingCharacters(in: .whitespaces)
        guard let match = aliasToID.first(where: { s.hasPrefix($0.alias) }) else { return nil }
        s = String(s.dropFirst(match.alias.count)).trimmingCharacters(in: .whitespaces)
        // 히브리어 병기 "(66)" 등 괄호 제거
        if let paren = try? NSRegularExpression(pattern: "\\([^)]*\\)") {
            s = paren.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: "")
        }
        // 앞머리 장 번호
        let ns = s as NSString
        guard let chMatch = try? NSRegularExpression(pattern: "^\\s*(\\d+)"),
              let m = chMatch.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
              let firstChapter = Int(ns.substring(with: m.range(at: 1))) else { return nil }

        var cur = firstChapter
        var rest = ns.substring(from: m.range.location + m.range.length)
        rest = rest.trimmingCharacters(in: .whitespaces)

        var segs: [VerseHighlight.Segment] = []
        let bigEnd = Int.max

        // ",절…"이 없으면 장 전체
        guard rest.hasPrefix(",") else {
            return (match.id, VerseHighlight(segments: [.init(chapter: cur, low: 1, high: bigEnd)],
                                             startChapter: cur, startVerse: 1))
        }
        rest.removeFirst()
        // '과'·'와'(그리고)와 '·'를 그룹 구분자 '.'로 통일, 공백 제거
        rest = rest.replacingOccurrences(of: "과", with: ".")
                   .replacingOccurrences(of: "와", with: ".")
                   .replacingOccurrences(of: "·", with: ".")
                   .replacingOccurrences(of: " ", with: "")
        func leadingInt(_ t: Substring) -> Int? {
            let digits = t.prefix { $0.isNumber }
            return digits.isEmpty ? nil : Int(digits)
        }
        var firstVerse: Int?
        for g in rest.split(separator: ".") where !g.isEmpty {
            if let dash = g.firstIndex(where: { $0 == "-" || $0 == "–" }) {
                let left = g[g.startIndex..<dash]
                let right = g[g.index(after: dash)...]
                guard let lo = leadingInt(left) else { continue }
                if let comma = right.firstIndex(of: ",") {
                    // 장을 넘는 범위 "31-13,13"
                    let c2s = right[right.startIndex..<comma]
                    let v2s = right[right.index(after: comma)...]
                    guard let c2 = leadingInt(c2s), let v2 = leadingInt(v2s) else { continue }
                    segs.append(.init(chapter: cur, low: lo, high: bigEnd))
                    if c2 > cur + 1 { for c in (cur + 1)..<c2 { segs.append(.init(chapter: c, low: 1, high: bigEnd)) } }
                    segs.append(.init(chapter: c2, low: 1, high: v2))
                    cur = c2
                    if firstVerse == nil { firstVerse = lo }
                } else if let hi = leadingInt(right) {
                    segs.append(.init(chapter: cur, low: lo, high: hi))
                    if firstVerse == nil { firstVerse = lo }
                }
            } else if let comma = g.firstIndex(of: ",") {
                // 새 장의 한 절 "13,13"
                let c2s = g[g.startIndex..<comma]
                let v2s = g[g.index(after: comma)...]
                guard let c2 = leadingInt(c2s), let v2 = leadingInt(v2s) else { continue }
                cur = c2
                segs.append(.init(chapter: cur, low: v2, high: v2))
                if firstVerse == nil { firstVerse = v2 }
            } else if let v = leadingInt(g) {
                segs.append(.init(chapter: cur, low: v, high: v))
                if firstVerse == nil { firstVerse = v }
            }
        }
        if segs.isEmpty {
            segs = [.init(chapter: firstChapter, low: 1, high: bigEnd)]
            firstVerse = 1
        }
        return (match.id, VerseHighlight(segments: segs,
                                         startChapter: firstChapter,
                                         startVerse: firstVerse ?? 1))
    }
}

// MARK: - 독서 한 편

struct MassReading: Codable, Hashable, Identifiable, Sendable {
    /// "제1독서" · "화답송" · "제2독서" · "복음 환호송" · "복음"
    let role: String
    /// 사람이 읽는 성구 표기 (예: "창세 18,1-10ㄴ")
    let reference: String
    /// 독서 소제목 (예: "하느님께서는 지은 죄에 대하여 회개할 기회를 주십니다.")
    var subtitle: String?
    /// 화답송 후렴 (있을 때)
    var refrain: String?
    /// 파싱된 성경 위치 (리더 연결용). 비어 있으면 reference를 즉석 파싱한다.
    var citations: [ScriptureCitation] = []

    var id: String { role + reference }

    enum CodingKeys: String, CodingKey { case role, reference, subtitle, refrain, citations }

    init(role: String, reference: String, subtitle: String? = nil,
         refrain: String? = nil, citations: [ScriptureCitation] = []) {
        self.role = role
        self.reference = reference
        self.subtitle = subtitle
        self.refrain = refrain
        self.citations = citations
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        role = try c.decode(String.self, forKey: .role)
        reference = (try? c.decode(String.self, forKey: .reference)) ?? ""
        subtitle = try? c.decodeIfPresent(String.self, forKey: .subtitle)
        refrain = try? c.decodeIfPresent(String.self, forKey: .refrain)
        citations = (try? c.decode([ScriptureCitation].self, forKey: .citations)) ?? []
    }

    /// 리더로 열 첫 성구 (citations 우선, 없으면 reference 파싱).
    var primaryCitation: ScriptureCitation? {
        citations.first ?? ScriptureReference.parse(reference)
    }
}

// MARK: - 하루치 독서

struct DailyReadings: Codable, Hashable, Sendable {
    /// 미사 명칭(축일/기념일). 없으면 전례력 계산 이름을 쓴다.
    var title: String?
    /// 전례색 재정의. 없으면 전례력 계산 색을 쓴다.
    var color: LiturgicalColor?
    var readings: [MassReading]

    enum CodingKeys: String, CodingKey { case title, color, readings }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        color = try? c.decodeIfPresent(LiturgicalColor.self, forKey: .color)
        readings = (try? c.decode([MassReading].self, forKey: .readings)) ?? []
    }
}

private struct DailyReadingsFile: Decodable {
    let year: Int?
    let source: String?
    let days: [String: DailyReadings]?
}

// MARK: - 저장소

@Observable
final class LiturgyStore {
    private(set) var isLoaded = false
    /// "yyyy-MM-dd" → 하루치 독서
    private(set) var days: [String: DailyReadings] = [:]
    /// 전례일 정체성+주기 → 독서. 파일이 없는 해(예: 2027·2028)를 다른 해 같은
    /// 전례일로 재구성하는 데 쓴다. 독서는 3년(A·B·C)·2년(Ⅰ·Ⅱ) 주기로 반복된다.
    private(set) var cycleIndex: [String: [MassReading]] = [:]

    var hasData: Bool { !days.isEmpty }

    func load() async {
        guard !isLoaded else { return }
        // DailyReadings_*.json 을 모두 읽어 합친다(연도별 파일).
        let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil)?
            .filter { $0.lastPathComponent.hasPrefix("DailyReadings_") } ?? []

        let merged: [String: DailyReadings] = await Task.detached(priority: .userInitiated) {
            var out: [String: DailyReadings] = [:]
            for url in urls {
                guard let data = try? Data(contentsOf: url),
                      let file = try? JSONDecoder().decode(DailyReadingsFile.self, from: data),
                      let days = file.days else { continue }
                for (k, v) in days { out[k] = v }
            }
            return out
        }.value

        days = merged
        // 주기 색인 구성: 각 날짜를 '전례일 정체성+주기' 키로 묶는다.
        var index: [String: [MassReading]] = [:]
        for (k, v) in merged where !v.readings.isEmpty {
            guard let date = Self.parseKey(k) else { continue }
            let pk = Self.cycleKey(date)
            if index[pk] == nil { index[pk] = v.readings }
        }
        cycleIndex = index
        isLoaded = true
    }

    // MARK: 주기 색인 키

    /// "yyyy-MM-dd" → Date
    static func parseKey(_ s: String) -> Date? {
        let p = s.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return LDate.make(p[0], p[1], p[2])
    }

    /// 전례일 정체성 + 관련 독서 주기.
    /// 평일 연중/사순/… '제N주간 요일'은 평일 주기(Ⅰ·Ⅱ), 그 밖(주일·대축일·축일)은
    /// 주일 주기(가·나·다)로 구분한다. 원본·대상 모두 같은 함수로 키를 만들어
    /// 서로 일치한다.
    static func cycleKey(_ date: Date) -> String {
        let name = LiturgicalCalendar.liturgicalDayName(date)
        let pos = LiturgicalCalendar.liturgicalPosition(date)
        if name.contains("주간") {
            return "\(name)|W:\(pos.weekdayCycle.rawValue)"
        }
        return "\(name)|S:\(pos.sundayCycle.rawValue)"
    }

    // MARK: 조회

    /// 그 날 저장된 독서(그 날짜 파일이 있을 때).
    func stored(_ date: Date) -> DailyReadings? {
        days[LDate.key(date)]
    }

    /// 다른 해 같은 전례일에서 가져온 독서 (그 날짜 파일이 없을 때).
    func cycleReadings(_ date: Date) -> [MassReading]? {
        cycleIndex[Self.cycleKey(date)]
    }

    /// 그 날 미사 명칭 (저장값 우선, 없으면 전례력 계산).
    func title(_ date: Date) -> String {
        if let t = stored(date)?.title, !t.isEmpty { return t }
        return LiturgicalCalendar.liturgicalDayName(date)
    }

    /// 그 날 전례색 (저장값 우선, 없으면 전례력 계산).
    func color(_ date: Date) -> LiturgicalColor {
        stored(date)?.color ?? LiturgicalCalendar.liturgicalColor(date)
    }

    /// 그 날 독서 목록. ① 그 날짜 저장값 → ② 주기로 재구성 → ③ 복음만 계산.
    func readings(_ date: Date) -> [MassReading] {
        if let stored = stored(date), !stored.readings.isEmpty { return stored.readings }
        if let byCycle = cycleReadings(date), !byCycle.isEmpty { return byCycle }
        if let gospel = Lectionary.todayGospelCitation(date) {
            let ref = Self.referenceLabel(gospel)
            return [MassReading(role: "복음", reference: ref, refrain: nil, citations: [gospel])]
        }
        return []
    }

    /// 전체 독서(제1독서·화답송·…)가 있는지 (그 날짜 또는 주기 재구성).
    func hasFullReadings(_ date: Date) -> Bool {
        if !(stored(date)?.readings.isEmpty ?? true) { return true }
        return cycleReadings(date) != nil
    }

    /// 다른 해 같은 전례일의 독서로 재구성한 경우 (그 날짜 파일이 없을 때).
    func isReconstructed(_ date: Date) -> Bool {
        (stored(date)?.readings.isEmpty ?? true) && cycleReadings(date) != nil
    }

    /// 성구 → "루카 10,38-42" 식 표기 (계산된 복음 표시용).
    static func referenceLabel(_ c: ScriptureCitation) -> String {
        let name = Bible.book(c.bookID)?.abbrev ?? c.bookID
        if let ec = c.endChapter, ec != c.chapter {
            return "\(name) \(c.chapter),\(c.verseStart)-\(ec),\(c.verseEnd)"
        }
        if c.verseEnd > c.verseStart {
            return "\(name) \(c.chapter),\(c.verseStart)-\(c.verseEnd)"
        }
        return "\(name) \(c.chapter),\(c.verseStart)"
    }
}
