//
//  LiturgicalCalendar.swift
//  CatholicBible
//
//  가톨릭 전례력: 날짜 → 전례 시기·주간·주일 주기(가/나/다해)·평일 주기(Ⅰ/Ⅱ)와
//  한국어 전례일 이름을 계산한다. 표시법은 형제 앱 GospelForIpad의
//  LiturgicalCalendar를 그대로 따르며(같은 계산·같은 이름 규칙), 여기에
//  전례색(LiturgicalColor)과 독서 주기 라벨을 덧붙였다.
//
//  네트워크가 필요 없다. 축일 이름·전례색은 절기 계산으로 얻고, 매일 미사
//  독서(제1독서·화답송·제2독서)는 별도 자료(DailyReadings_<연도>.json)로
//  보완한다(scripts/fetch_liturgy.py 참고).
//

import Foundation
import SwiftUI

enum SundayCycle: String, Sendable { case a, b, c
    var label: String {   // 주일 독서 주기
        switch self { case .a: return "가해"; case .b: return "나해"; case .c: return "다해" }
    }
}
enum WeekdayCycle: String, Sendable { case i, ii
    var label: String {   // 평일(짝·홀) 독서 주기
        switch self { case .i: return "홀수해"; case .ii: return "짝수해" }
    }
}

enum LiturgicalSeason: Sendable {
    case advent
    case christmas
    case ordinaryBeforeLent
    case lent
    case easter
    case ordinaryAfterPentecost

    /// 표시용 짧은 이름
    var shortName: String {
        switch self {
        case .advent: return "대림 시기"
        case .christmas: return "성탄 시기"
        case .ordinaryBeforeLent, .ordinaryAfterPentecost: return "연중 시기"
        case .lent: return "사순 시기"
        case .easter: return "부활 시기"
        }
    }
}

/// 전례색
enum LiturgicalColor: String, Codable, Sendable {
    case green    // 녹색 — 연중
    case white    // 백색 — 성탄·부활·주님·성모·비순교 성인
    case red      // 홍색 — 수난·성령 강림·순교자·사도
    case violet   // 자주색 — 대림·사순·위령
    case rose     // 장미색 — 대림 제3주일·사순 제4주일

    var label: String {
        switch self {
        case .green: return "녹색"
        case .white: return "백색"
        case .red: return "홍색"
        case .violet: return "자주색"
        case .rose: return "장미색"
        }
    }

    var color: Color {
        switch self {
        case .green: return Color(red: 0.16, green: 0.49, blue: 0.28)
        case .white: return Color(red: 0.83, green: 0.68, blue: 0.22)  // 금빛(백색 표시)
        case .red: return Color(red: 0.72, green: 0.14, blue: 0.15)
        case .violet: return Color(red: 0.42, green: 0.24, blue: 0.55)
        case .rose: return Color(red: 0.85, green: 0.44, blue: 0.56)
        }
    }
}

struct LiturgicalPosition: Sendable {
    let season: LiturgicalSeason
    let week: Int
    /// 요일: 월요일 = 1 … 일요일 = 7
    let dayOfWeek: Int
    let sundayCycle: SundayCycle
    let weekdayCycle: WeekdayCycle
}

/// UTC 자정 기준 날짜 도우미 (java.time.LocalDate 대응)
enum LDate {
    static let sunday = 7
    static let monday = 1

    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    static func make(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
    }

    /// 기기 지역 시간대 기준 '오늘'을 UTC 자정 날짜로.
    static func today() -> Date {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = .current
        let c = local.dateComponents([.year, .month, .day], from: Date())
        return make(c.year ?? 2000, c.month ?? 1, c.day ?? 1)
    }

    static func year(_ d: Date) -> Int { calendar.component(.year, from: d) }
    static func month(_ d: Date) -> Int { calendar.component(.month, from: d) }
    static func day(_ d: Date) -> Int { calendar.component(.day, from: d) }

    /// 월요일 = 1 … 일요일 = 7
    static func dayOfWeek(_ d: Date) -> Int {
        let w = calendar.component(.weekday, from: d) // 일 = 1 … 토 = 7
        return ((w + 5) % 7) + 1
    }

    static func addDays(_ d: Date, _ n: Int) -> Date {
        calendar.date(byAdding: .day, value: n, to: d) ?? d
    }

    static func addWeeks(_ d: Date, _ n: Int) -> Date { addDays(d, n * 7) }

    static func epochDay(_ d: Date) -> Int { Int((d.timeIntervalSince1970 / 86_400).rounded()) }

    static func previousOrSame(_ d: Date, weekday target: Int) -> Date {
        var x = d
        while dayOfWeek(x) != target { x = addDays(x, -1) }
        return x
    }

    static func next(_ d: Date, weekday target: Int) -> Date {
        var x = addDays(d, 1)
        while dayOfWeek(x) != target { x = addDays(x, 1) }
        return x
    }

    /// "yyyy-MM-dd" 키 (DailyReadings 조회용)
    static func key(_ d: Date) -> String {
        String(format: "%04d-%02d-%02d", year(d), month(d), day(d))
    }
}

enum LiturgicalCalendar {

    // Anonymous Gregorian algorithm (Meeus/Jones/Butcher)
    static func easterDate(_ year: Int) -> Date {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = (h + l - 7 * m + 114) % 31 + 1
        return LDate.make(year, month, day)
    }

    // 대림 제1주일 = 대림 제4주일(성탄 전 마지막 주일)의 3주 전.
    // 성탄 당일이 주일이면 대림 제4주일은 그 전 주일이다.
    static func firstSundayOfAdvent(_ year: Int) -> Date {
        let dec24 = LDate.make(year, 12, 24)
        let advent4 = LDate.previousOrSame(dec24, weekday: LDate.sunday)
        return LDate.addWeeks(advent4, -3)
    }

    // 주님 공현 대축일: 1월 2–8일 사이 주일 (한국 관습)
    static func epiphany(_ year: Int) -> Date {
        LDate.next(LDate.make(year, 1, 1), weekday: LDate.sunday)
    }

    // 주님 세례 축일 = 주님 공현 다음 주일. 다만 공현이 1월 7·8일이면 그다음
    // 월요일에 지내고 성탄 시기가 그 월요일로 끝난다(한국 전례 지침).
    private static func baptismOfLord(_ year: Int) -> Date {
        let epi = epiphany(year)
        return LDate.day(epi) >= 7 ? LDate.addDays(epi, 1) : LDate.addWeeks(epi, 1)
    }

    private static func liturgicalYear(_ date: Date) -> Int {
        let advent = firstSundayOfAdvent(LDate.year(date))
        return date >= advent ? LDate.year(date) + 1 : LDate.year(date)
    }

    // 주일 주기: 가해 = 마태오, 나해 = 마르코, 다해 = 루카 (전례력 2026 = 가해)
    static func sundayCycle(_ date: Date) -> SundayCycle {
        let ly = liturgicalYear(date)
        switch (((ly - 2026) % 3) + 3) % 3 {
        case 0:  return .a
        case 1:  return .b
        default: return .c
        }
    }

    static func weekdayCycle(_ date: Date) -> WeekdayCycle {
        let ly = liturgicalYear(date)
        return ly % 2 != 0 ? .i : .ii
    }

    static func liturgicalPosition(_ date: Date) -> LiturgicalPosition {
        let year = LDate.year(date)
        let sc = sundayCycle(date)
        let wc = weekdayCycle(date)
        let dow = LDate.dayOfWeek(date)

        let advent = firstSundayOfAdvent(year)
        let inCurrentAdvent = date >= advent

        let christmasYear = inCurrentAdvent ? year : year - 1
        let easter = easterDate(inCurrentAdvent ? year + 1 : year)
        let baptism = baptismOfLord(christmasYear + 1)
        let christmas = LDate.make(christmasYear, 12, 25)
        let lYearStart = inCurrentAdvent ? advent : firstSundayOfAdvent(year - 1)

        let ashWednesday = LDate.addDays(easter, -46)
        let pentecost = LDate.addDays(easter, 49)

        let nextAdvent = inCurrentAdvent ? firstSundayOfAdvent(year + 1) : advent
        let christTheKing = LDate.addWeeks(nextAdvent, -1)

        let season: LiturgicalSeason
        if date >= lYearStart && date < christmas {
            season = .advent
        } else if date >= christmas && date < baptism {
            season = .christmas
        } else if date >= baptism && date < ashWednesday {
            season = .ordinaryBeforeLent
        } else if date >= ashWednesday && date < easter {
            season = .lent
        } else if date >= easter && date < pentecost {
            season = .easter
        } else {
            season = .ordinaryAfterPentecost
        }

        let week: Int
        switch season {
        case .advent:
            let days = LDate.epochDay(date) - LDate.epochDay(lYearStart)
            week = min(max(days / 7 + 1, 1), 4)
        case .christmas:
            let days = LDate.epochDay(date) - LDate.epochDay(christmas)
            week = min(max(days / 7 + 1, 1), 3)
        case .ordinaryBeforeLent:
            // 주간 번호 = 세례 주간의 주일부터 지나온 주일 수. 세례가 월요일인 해도
            // 그 주의 주일을 기준으로 삼아 평일·주일 번호가 어긋나지 않는다.
            let anchor = LDate.previousOrSame(baptism, weekday: LDate.sunday)
            let sunday = LDate.previousOrSame(date, weekday: LDate.sunday)
            week = min(max((LDate.epochDay(sunday) - LDate.epochDay(anchor)) / 7 + 1, 1), 9)
        case .lent:
            // 사순 제1주일(재의 수요일 다음 주일)을 기준으로 센다.
            let lentFirstSunday = LDate.addDays(ashWednesday, 4)
            let sunday = LDate.previousOrSame(date, weekday: LDate.sunday)
            week = min(max((LDate.epochDay(sunday) - LDate.epochDay(lentFirstSunday)) / 7 + 1, 1), 6)
        case .easter:
            let days = LDate.epochDay(date) - LDate.epochDay(easter)
            week = min(max(days / 7 + 1, 1), 7)
        case .ordinaryAfterPentecost:
            // 그리스도 왕 대축일(연중 제34주일)에서 거슬러 센다. 부활이 이른 해는
            // 성령 강림 뒤 제8주간 등 낮은 번호로 재개될 수 있다.
            let sundayOfWeek = LDate.previousOrSame(date, weekday: LDate.sunday)
            let days = LDate.epochDay(christTheKing) - LDate.epochDay(sundayOfWeek)
            week = min(max(34 - days / 7, 7), 34)
        }

        return LiturgicalPosition(season: season, week: week, dayOfWeek: dow, sundayCycle: sc, weekdayCycle: wc)
    }

    /// 주일 주기·평일 주기 표시 라벨 (예: "가해 · 짝수해")
    static func cycleLabel(_ date: Date = LDate.today()) -> String {
        let pos = liturgicalPosition(date)
        // 주일·대축일은 주일 주기, 평일은 평일 주기를 우선 보여 준다.
        if pos.dayOfWeek == LDate.sunday {
            return "\(pos.sundayCycle.label) · \(pos.weekdayCycle.label)"
        }
        return "\(pos.weekdayCycle.label) · \(pos.sundayCycle.label)"
    }

    static func liturgicalDayName(_ date: Date = LDate.today()) -> String {
        let pos = liturgicalPosition(date)
        let isSunday = pos.dayOfWeek == LDate.sunday
        // 대림·사순·부활 주일은 모든 대축일·축일보다 앞선다(전례력 규범). 이 주일에
        // 오는 고정 축일은 월요일로 옮겨 지내므로 여기서는 고정 축일을 건너뛴다.
        let privilegedSunday = isSunday &&
            (pos.season == .advent || pos.season == .lent || pos.season == .easter)

        // 1) 이동 축일(파스카 삼일·부활·성령 강림 등 특전 주일 포함)이 가장 앞선다.
        for (d, name) in movableFeasts(LDate.year(date)) where d == date {
            return name
        }

        // 2) 고정 대축일·축일 — 특전 주일에는 밀리므로 건너뛴다.
        if !privilegedSunday {
            let md = LDate.month(date) * 100 + LDate.day(date)
            switch md {
            case 101:  return "천주의 성모 마리아 대축일"
            case 202:  return "주님 봉헌 축일"
            case 319:  return "복되신 동정 마리아의 배필 성 요셉 대축일"
            case 325:  return "주님 탄생 예고 대축일"
            case 624:  return "성 요한 세례자 탄생 대축일"
            case 629:  return "성 베드로와 성 바오로 사도 대축일"
            case 806:  return "주님의 거룩한 변모 축일"
            case 815:  return "성모 승천 대축일"
            case 1101: return "모든 성인 대축일"
            case 1102: return "죽은 모든 이를 기억하는 위령의 날"
            case 1208: return "한국 교회의 수호자 원죄 없이 잉태되신 복되신 동정 마리아 대축일"
            case 1225: return "주님 성탄 대축일"
            case 1226: return "성 스테파노 첫 순교자 축일"
            case 1228: return "죄 없는 아기 순교자들 축일"
            default: break
            }
            // 대림 후기 평일 (12월 17–24일, 주일 제외)
            if LDate.month(date) == 12 && (17...24).contains(LDate.day(date)) && !isSunday {
                return "12월 \(LDate.day(date))일 대림"
            }
            // 주님 공현 (1월 2–8일 주일)
            if LDate.month(date) == 1 && (2...8).contains(LDate.day(date)) && isSunday {
                return "주님 공현 대축일"
            }
        }

        // 3) 절기 평일·주일
        let s: String
        switch pos.season {
        case .advent:    s = "대림"
        case .christmas: s = "성탄"
        case .ordinaryBeforeLent, .ordinaryAfterPentecost: s = "연중"
        case .lent:      s = "사순"
        case .easter:    s = "부활"
        }
        switch pos.dayOfWeek {
        case 7: return "\(s) 제\(pos.week)주일"
        case 1: return "\(s) 제\(pos.week)주간 월요일"
        case 2: return "\(s) 제\(pos.week)주간 화요일"
        case 3: return "\(s) 제\(pos.week)주간 수요일"
        case 4: return "\(s) 제\(pos.week)주간 목요일"
        case 5: return "\(s) 제\(pos.week)주간 금요일"
        case 6: return "\(s) 제\(pos.week)주간 토요일"
        default: return s
        }
    }

    // 해마다 날짜가 바뀌는 주님·성모 대축일과 성주간·부활 팔일 축제.
    private static func movableFeasts(_ year: Int) -> [(Date, String)] {
        let easter = easterDate(year)
        let ashWed = LDate.addDays(easter, -46)
        let pentecost = LDate.addDays(easter, 49)
        let baptism = baptismOfLord(year)
        let dec25 = LDate.make(year, 12, 25)
        let holyFamily = LDate.dayOfWeek(dec25) == LDate.sunday
            ? LDate.make(year, 12, 30)
            : LDate.next(dec25, weekday: LDate.sunday)
        let christTheKing = LDate.addWeeks(firstSundayOfAdvent(year), -1)

        return [
            (baptism, "주님 세례 축일"),
            (ashWed, "재의 수요일"),
            (LDate.addDays(ashWed, 1), "재의 예식 다음 목요일"),
            (LDate.addDays(ashWed, 2), "재의 예식 다음 금요일"),
            (LDate.addDays(ashWed, 3), "재의 예식 다음 토요일"),
            (LDate.addDays(easter, -7), "주님 수난 성지 주일"),
            (LDate.addDays(easter, -3), "주님 만찬 성목요일"),
            (LDate.addDays(easter, -2), "주님 수난 성금요일"),
            (LDate.addDays(easter, -1), "성토요일"),
            (easter, "주님 부활 대축일"),
            (LDate.addDays(easter, 1), "부활 팔일 축제 월요일"),
            (LDate.addDays(easter, 2), "부활 팔일 축제 화요일"),
            (LDate.addDays(easter, 3), "부활 팔일 축제 수요일"),
            (LDate.addDays(easter, 4), "부활 팔일 축제 목요일"),
            (LDate.addDays(easter, 5), "부활 팔일 축제 금요일"),
            (LDate.addDays(easter, 6), "부활 팔일 축제 토요일"),
            (LDate.addDays(easter, 42), "주님 승천 대축일"),
            (pentecost, "성령 강림 대축일"),
            (LDate.addDays(pentecost, 1), "교회의 어머니 복되신 동정 마리아 기념일"),
            (LDate.addDays(pentecost, 7), "지극히 거룩하신 삼위일체 대축일"),
            (LDate.addDays(pentecost, 14), "지극히 거룩하신 그리스도의 성체 성혈 대축일"),
            (LDate.addDays(pentecost, 19), "지극히 거룩하신 예수 성심 대축일"),
            (holyFamily, "예수, 마리아, 요셉의 성가정 축일"),
            (christTheKing, "온 누리의 임금이신 우리 주 예수 그리스도 왕 대축일"),
        ]
    }

    // MARK: - 전례색

    /// 그 날의 전례색. 절기 기준 + 주요 대축일·축일 예외를 반영한다.
    /// (개별 순교자 기념일 등 정밀한 색은 매일 미사 자료가 있으면 그쪽을 우선한다.)
    static func liturgicalColor(_ date: Date = LDate.today()) -> LiturgicalColor {
        let year = LDate.year(date)
        let easter = easterDate(year)
        let pentecost = LDate.addDays(easter, 49)
        let md = LDate.month(date) * 100 + LDate.day(date)

        // 홍색(움직이는): 수난 성지 주일·성금요일·성령 강림
        if date == LDate.addDays(easter, -7) { return .red }   // 주님 수난 성지 주일
        if date == LDate.addDays(easter, -2) { return .red }   // 주님 수난 성금요일
        if date == pentecost { return .red }                    // 성령 강림 대축일

        // 백색(움직이는 주님 대축일): 승천·삼위일체·성체 성혈·예수 성심·그리스도 왕
        let christTheKing = LDate.addWeeks(firstSundayOfAdvent(year), -1)
        let movableWhite: Set<Int> = [
            LDate.epochDay(LDate.addDays(easter, 42)),   // 주님 승천
            LDate.epochDay(LDate.addDays(easter, 56)),   // 삼위일체
            LDate.epochDay(LDate.addDays(easter, 63)),   // 성체 성혈
            LDate.epochDay(LDate.addDays(easter, 68)),   // 예수 성심
            LDate.epochDay(christTheKing),               // 그리스도 왕
        ]
        if movableWhite.contains(LDate.epochDay(date)) { return .white }

        // 백색 고정 대축일·축일
        let whiteFixed: Set<Int> = [101, 202, 319, 325, 624, 806, 815, 1101, 1109, 1208, 1225]
        if whiteFixed.contains(md) { return .white }
        // 홍색 고정(순교자·사도·성 십자가)
        let redFixed: Set<Int> = [629, 914, 1130, 1226, 1228]
        if redFixed.contains(md) { return .red }
        // 위령의 날
        if md == 1102 { return .violet }

        let pos = liturgicalPosition(date)
        // 장미색: 대림 제3주일(Gaudete)·사순 제4주일(Laetare)
        if pos.dayOfWeek == LDate.sunday {
            if pos.season == .advent && pos.week == 3 { return .rose }
            if pos.season == .lent && pos.week == 4 { return .rose }
        }

        switch pos.season {
        case .advent, .lent:      return .violet
        case .christmas, .easter: return .white
        case .ordinaryBeforeLent, .ordinaryAfterPentecost: return .green
        }
    }
}
