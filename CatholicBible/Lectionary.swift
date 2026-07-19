//
//  Lectionary.swift
//  CatholicBible
//
//  날짜 → 그 날 미사 '복음' 독서(책·장·절)를 계산한다. 형제 앱 GospelForIpad의
//  Lectionary(가톨릭 주교회의 2026 전례력 대조 완료)를 이식하되, 반환값을
//  이 앱의 책 id(mt·mk·lk·jn)를 쓰는 ScriptureCitation으로 바꿨다.
//
//  이 표는 네트워크 없이 '오늘의 복음'을 항상 제공한다. 제1독서·화답송·제2독서
//  까지 갖춘 전체 독서는 매일 미사 자료(DailyReadings_<연도>.json)로 보완한다.
//

import Foundation

enum Lectionary {

    static func todayGospelCitation(_ date: Date = LDate.today()) -> ScriptureCitation? {
        let pos = LiturgicalCalendar.liturgicalPosition(date)

        // 대축일·축일의 고유 복음이 절기 배당보다 우선한다.
        if let proper = properReading(date, cycle: pos.sundayCycle) {
            return citation(from: proper)
        }

        let triple: (String, Int, Int, Int)?
        switch pos.season {
        case .advent:                 triple = adventGospel(pos)
        case .christmas:              triple = christmasGospel(pos)
        case .ordinaryBeforeLent:     triple = ordinaryGospel(pos)
        case .lent:                   triple = lentGospel(pos)
        case .easter:                 triple = easterGospel(pos)
        case .ordinaryAfterPentecost: triple = ordinaryGospel(pos)
        }
        guard let triple else { return nil }
        return citation(from: triple)
    }

    // MARK: - Helpers

    private static let M = "mt"
    private static let Mk = "mk"
    private static let L = "lk"
    private static let J = "jn"

    private static func gc(_ g: String, _ c: Int, _ v: Int = 1, _ end: Int = 0) -> (String, Int, Int, Int) {
        (g, c, v, max(end, v))
    }

    private static func citation(from triple: (String, Int, Int, Int)) -> ScriptureCitation? {
        let (bookID, chapter, verse, endVerse) = triple
        guard let book = Bible.book(bookID), chapter >= 1, chapter <= book.chapterCount else { return nil }
        return ScriptureCitation(bookID: bookID, chapter: chapter,
                                 verseStart: verse, verseEnd: max(endVerse, verse))
    }

    private static let sunday = 7

    // MARK: - Proper gospels (solemnities & feasts)

    /// 주일과 겹치면 주일에 양보하는 성인(사도·복음사가) 축일.
    private static let saintFeastMDs: Set<Int> = [125, 222, 425, 503, 514, 703, 824, 921, 1018, 1028, 1130, 1226, 1227, 1228]

    private static func properReading(_ date: Date, cycle: SundayCycle) -> (String, Int, Int, Int)? {
        let year = LDate.year(date)
        let md = LDate.month(date) * 100 + LDate.day(date)
        let isSunday = LDate.dayOfWeek(date) == sunday

        if !(saintFeastMDs.contains(md) && isSunday) {
            switch md {
            case 101:  return gc(L, 2, 16, 21)
            case 125:  return gc(Mk, 16, 15, 18)
            case 202:  return gc(L, 2, 22, 40)
            case 222:  return gc(M, 16, 13, 19)
            case 319:  return gc(M, 1, 16, 24)
            case 325:  return gc(L, 1, 26, 38)
            case 425:  return gc(Mk, 16, 15, 20)
            case 503:  return gc(J, 14, 6, 14)
            case 514:  return gc(J, 15, 9, 17)
            case 624:  return gc(L, 1, 57, 66)
            case 629:  return gc(M, 16, 13, 19)
            case 703:  return gc(J, 20, 24, 29)
            case 806:
                switch cycle { case .a: return gc(M, 17, 1, 9); case .b: return gc(Mk, 9, 2, 10); case .c: return gc(L, 9, 28, 36) }
            case 815:  return gc(L, 1, 39, 56)
            case 824:  return gc(J, 1, 45, 51)
            case 914:  return gc(J, 3, 13, 17)
            case 921:  return gc(M, 9, 9, 13)
            case 1018: return gc(L, 10, 1, 9)
            case 1028: return gc(L, 6, 12, 16)
            case 1101: return gc(M, 5, 1, 12)
            case 1102: return gc(J, 6, 37, 40)
            case 1109: return gc(J, 2, 13, 22)
            case 1130: return gc(M, 4, 18, 22)
            case 1208: return gc(L, 1, 26, 38)
            case 1225: return gc(J, 1, 1, 18)
            case 1226: return gc(M, 10, 17, 22)
            case 1227: return gc(J, 20, 2, 8)
            case 1228: return gc(M, 2, 13, 18)
            default: break
            }
        }

        let easter = LiturgicalCalendar.easterDate(year)
        let ashWednesday = LDate.addDays(easter, -46)
        let ascension = LDate.addDays(easter, 42)
        let pentecost = LDate.addDays(easter, 49)
        let trinity = LDate.addDays(easter, 56)
        let corpusChristi = LDate.addDays(easter, 63)
        let sacredHeart = LDate.addDays(easter, 68)

        if date == ashWednesday { return gc(M, 6, 1, 18) }
        if date == ascension {
            switch cycle { case .a: return gc(M, 28, 16, 20); case .b: return gc(Mk, 16, 15, 20); case .c: return gc(L, 24, 46, 53) }
        }
        if date == pentecost { return gc(J, 20, 19, 23) }
        if date == trinity {
            switch cycle { case .a: return gc(J, 3, 16, 18); case .b: return gc(M, 28, 16, 20); case .c: return gc(J, 16, 12, 15) }
        }
        if date == corpusChristi {
            switch cycle { case .a: return gc(J, 6, 51, 58); case .b: return gc(Mk, 14, 12, 26); case .c: return gc(L, 9, 11, 17) }
        }
        if date == sacredHeart {
            switch cycle { case .a: return gc(M, 11, 25, 30); case .b: return gc(J, 19, 31, 37); case .c: return gc(L, 15, 3, 7) }
        }

        if LDate.month(date) == 1, (2...8).contains(LDate.day(date)), isSunday {
            return gc(M, 2, 1, 12)
        }
        // 주님 세례 축일: 공현(1월 2–8일 주일) 다음 주일. 공현이 1월 7·8일이면 다음 월요일.
        let epiphany = LDate.next(LDate.make(year, 1, 1), weekday: sunday)
        let baptism = LDate.day(epiphany) >= 7 ? LDate.addDays(epiphany, 1) : LDate.addWeeks(epiphany, 1)
        if date == baptism {
            switch cycle { case .a: return gc(M, 3, 13, 17); case .b: return gc(Mk, 1, 7, 11); case .c: return gc(L, 3, 15, 22) }
        }
        let dec25 = LDate.make(year, 12, 25)
        let holyFamily = LDate.dayOfWeek(dec25) == sunday ? LDate.make(year, 12, 30) : LDate.next(dec25, weekday: sunday)
        if date == holyFamily {
            switch cycle { case .a: return gc(M, 2, 13, 23); case .b: return gc(L, 2, 22, 40); case .c: return gc(L, 2, 41, 52) }
        }

        return nil
    }

    // MARK: - Advent

    private static func adventGospel(_ pos: LiturgicalPosition) -> (String, Int, Int, Int)? {
        if pos.dayOfWeek != sunday {
            if pos.week == 4 {
                switch pos.dayOfWeek {
                case 1, 2: return gc(M, 1, 18, 24)
                default:   return gc(L, 1, 26, 38)
                }
            }
        }
        return pos.dayOfWeek == sunday
            ? adventSundayGospel(pos.week, pos.sundayCycle)
            : adventWeekdayGospel(pos.week, pos.dayOfWeek)
    }

    private static func adventSundayGospel(_ week: Int, _ cycle: SundayCycle) -> (String, Int, Int, Int) {
        switch cycle {
        case .a:
            switch week { case 1: return gc(M, 24, 37, 44); case 2: return gc(M, 3, 1, 12); case 3: return gc(M, 11, 2, 11); default: return gc(M, 1, 18, 24) }
        case .b:
            switch week { case 1: return gc(Mk, 13, 33, 37); case 2: return gc(Mk, 1, 1, 8); case 3: return gc(J, 1, 6, 28); default: return gc(L, 1, 26, 38) }
        case .c:
            switch week { case 1: return gc(L, 21, 25, 36); case 2: return gc(L, 3, 1, 6); case 3: return gc(L, 3, 10, 18); default: return gc(L, 1, 39, 45) }
        }
    }

    private static func adventWeekdayGospel(_ week: Int, _ dow: Int) -> (String, Int, Int, Int) {
        let table = [
            [gc(L, 10, 25, 37), gc(M, 15, 29, 37), gc(L, 10, 21, 24), gc(M, 15, 21, 28), gc(M, 9, 27, 31), gc(L, 20, 27, 40)],
            [gc(L, 5, 17, 26), gc(M, 17, 10, 13), gc(M, 11, 28, 30), gc(M, 11, 11, 15), gc(L, 7, 24, 30), gc(M, 17, 10, 13)],
            [gc(M, 21, 28, 32), gc(J, 1, 6, 28), gc(M, 21, 28, 32), gc(L, 7, 24, 30), gc(L, 7, 31, 35), gc(J, 1, 19, 28)],
        ]
        let wIdx = min(max(week - 1, 0), 2)
        let dIdx = min(max(dow - 1, 0), 5)
        return table[wIdx][dIdx]
    }

    // MARK: - Christmas

    private static func christmasGospel(_ pos: LiturgicalPosition) -> (String, Int, Int, Int)? {
        pos.dayOfWeek == sunday
            ? christmasSundayGospel(pos.week, pos.sundayCycle)
            : christmasWeekdayGospel(pos.week, pos.dayOfWeek)
    }

    private static func christmasSundayGospel(_ week: Int, _ cycle: SundayCycle) -> (String, Int, Int, Int) {
        switch week {
        case 1: return gc(J, 1, 1, 18)
        case 2:
            switch cycle {
            case .a: return gc(M, 2, 13, 23)
            case .b: return gc(L, 2, 22, 40)
            case .c: return gc(L, 2, 41, 52)
            }
        default: return gc(J, 1, 1, 18)
        }
    }

    private static func christmasWeekdayGospel(_ week: Int, _ dow: Int) -> (String, Int, Int, Int) {
        let table = [
            [gc(J, 1, 1, 18), gc(J, 1, 1, 18), gc(J, 1, 1, 18), gc(J, 1, 1, 18), gc(J, 1, 1, 18), gc(J, 1, 1, 18)],
            [gc(J, 1, 19, 28), gc(J, 1, 29, 34), gc(J, 2, 1, 11), gc(J, 2, 1, 11), gc(M, 2, 13, 23), gc(J, 1, 43, 51)],
        ]
        let wIdx = min(max(week - 1, 0), 1)
        let dIdx = min(max(dow - 1, 0), 5)
        return table[wIdx][dIdx]
    }

    // MARK: - Ordinary Time

    private static func ordinaryGospel(_ pos: LiturgicalPosition) -> (String, Int, Int, Int)? {
        pos.dayOfWeek == sunday
            ? ordinarySundayGospel(pos.week, pos.sundayCycle)
            : ordinaryWeekdayGospel(pos.week, pos.dayOfWeek)
    }

    private static func ordinarySundayGospel(_ week: Int, _ cycle: SundayCycle) -> (String, Int, Int, Int)? {
        switch cycle {
        case .a: return ordinarySundayA(week)
        case .b: return ordinarySundayB(week)
        case .c: return ordinarySundayC(week)
        }
    }

    private static func ordinarySundayA(_ week: Int) -> (String, Int, Int, Int)? {
        switch week {
        case 2:  return gc(J, 1, 29, 34)
        case 3:  return gc(M, 4, 12, 23)
        case 4:  return gc(M, 5, 1, 12)
        case 5:  return gc(M, 5, 13, 16)
        case 6:  return gc(M, 5, 17, 37)
        case 7:  return gc(M, 5, 38, 48)
        case 8:  return gc(M, 6, 24, 34)
        case 9:  return gc(M, 7, 21, 27)
        case 10: return gc(M, 9, 9, 13)
        case 11: return gc(M, 9, 36, 38)
        case 12: return gc(M, 10, 26, 33)
        case 13: return gc(M, 10, 37, 42)
        case 14: return gc(M, 11, 25, 30)
        case 15: return gc(M, 13, 1, 23)
        case 16: return gc(M, 13, 24, 43)
        case 17: return gc(M, 13, 44, 52)
        case 18: return gc(M, 14, 13, 21)
        case 19: return gc(M, 14, 22, 33)
        case 20: return gc(M, 15, 21, 28)
        case 21: return gc(M, 16, 13, 20)
        case 22: return gc(M, 16, 21, 27)
        case 23: return gc(M, 18, 15, 20)
        case 24: return gc(M, 18, 21, 35)
        case 25: return gc(M, 20, 1, 16)
        case 26: return gc(M, 21, 28, 32)
        case 27: return gc(M, 21, 33, 43)
        case 28: return gc(M, 22, 1, 14)
        case 29: return gc(M, 22, 15, 21)
        case 30: return gc(M, 22, 34, 40)
        case 31: return gc(M, 23, 1, 12)
        case 32: return gc(M, 25, 1, 13)
        case 33: return gc(M, 25, 14, 30)
        case 34: return gc(M, 25, 31, 46)
        default: return nil
        }
    }

    private static func ordinarySundayB(_ week: Int) -> (String, Int, Int, Int)? {
        switch week {
        case 2:  return gc(J, 1, 35, 42)
        case 3:  return gc(Mk, 1, 14, 20)
        case 4:  return gc(Mk, 1, 21, 28)
        case 5:  return gc(Mk, 1, 29, 39)
        case 6:  return gc(Mk, 1, 40, 45)
        case 7:  return gc(Mk, 2, 1, 12)
        case 8:  return gc(Mk, 2, 18, 22)
        case 9:  return gc(Mk, 2, 23, 28)
        case 10: return gc(Mk, 3, 20, 35)
        case 11: return gc(Mk, 4, 26, 34)
        case 12: return gc(Mk, 4, 35, 41)
        case 13: return gc(Mk, 5, 21, 43)
        case 14: return gc(Mk, 6, 1, 6)
        case 15: return gc(Mk, 6, 7, 13)
        case 16: return gc(Mk, 6, 30, 34)
        case 17: return gc(J, 6, 1, 15)
        case 18: return gc(J, 6, 24, 35)
        case 19: return gc(J, 6, 41, 51)
        case 20: return gc(J, 6, 51, 58)
        case 21: return gc(J, 6, 60, 69)
        case 22: return gc(Mk, 7, 1, 23)
        case 23: return gc(Mk, 7, 31, 37)
        case 24: return gc(Mk, 8, 27, 35)
        case 25: return gc(Mk, 9, 30, 37)
        case 26: return gc(Mk, 9, 38, 48)
        case 27: return gc(Mk, 10, 2, 16)
        case 28: return gc(Mk, 10, 17, 30)
        case 29: return gc(Mk, 10, 35, 45)
        case 30: return gc(Mk, 10, 46, 52)
        case 31: return gc(Mk, 12, 28, 34)
        case 32: return gc(Mk, 12, 38, 44)
        case 33: return gc(Mk, 13, 24, 32)
        case 34: return gc(J, 18, 33, 37)
        default: return nil
        }
    }

    private static func ordinarySundayC(_ week: Int) -> (String, Int, Int, Int)? {
        switch week {
        case 2:  return gc(J, 2, 1, 11)
        case 3:  return gc(L, 4, 14, 21)
        case 4:  return gc(L, 4, 21, 30)
        case 5:  return gc(L, 5, 1, 11)
        case 6:  return gc(L, 6, 17, 26)
        case 7:  return gc(L, 6, 27, 38)
        case 8:  return gc(L, 6, 39, 45)
        case 9:  return gc(L, 7, 1, 10)
        case 10: return gc(L, 7, 11, 17)
        case 11: return gc(L, 7, 36, 50)
        case 12: return gc(L, 9, 18, 24)
        case 13: return gc(L, 9, 51, 62)
        case 14: return gc(L, 10, 1, 12)
        case 15: return gc(L, 10, 25, 37)
        case 16: return gc(L, 10, 38, 42)
        case 17: return gc(L, 11, 1, 13)
        case 18: return gc(L, 12, 13, 21)
        case 19: return gc(L, 12, 32, 48)
        case 20: return gc(L, 12, 49, 53)
        case 21: return gc(L, 13, 22, 30)
        case 22: return gc(L, 14, 1, 14)
        case 23: return gc(L, 14, 25, 33)
        case 24: return gc(L, 15, 1, 32)
        case 25: return gc(L, 16, 1, 13)
        case 26: return gc(L, 16, 19, 31)
        case 27: return gc(L, 17, 5, 10)
        case 28: return gc(L, 17, 11, 19)
        case 29: return gc(L, 18, 1, 8)
        case 30: return gc(L, 18, 9, 14)
        case 31: return gc(L, 19, 1, 10)
        case 32: return gc(L, 20, 27, 38)
        case 33: return gc(L, 21, 5, 19)
        case 34: return gc(L, 23, 35, 43)
        default: return nil
        }
    }

    private static func ordinaryWeekdayGospel(_ week: Int, _ dow: Int) -> (String, Int, Int, Int)? {
        let table: [[(String, Int, Int, Int)]] = [
            [gc(Mk, 1, 14, 20), gc(Mk, 1, 21, 28), gc(Mk, 1, 29, 39), gc(Mk, 1, 40, 45), gc(Mk, 2, 1, 12), gc(Mk, 2, 13, 17)],
            [gc(Mk, 2, 18, 22), gc(Mk, 2, 23, 28), gc(Mk, 3, 1, 6), gc(Mk, 3, 7, 12), gc(Mk, 3, 13, 19), gc(Mk, 3, 20, 21)],
            [gc(Mk, 3, 22, 30), gc(Mk, 3, 31, 35), gc(Mk, 4, 1, 20), gc(Mk, 4, 21, 25), gc(Mk, 4, 26, 34), gc(Mk, 4, 35, 41)],
            [gc(Mk, 4, 35, 41), gc(Mk, 5, 1, 20), gc(Mk, 5, 21, 43), gc(Mk, 5, 21, 43), gc(Mk, 5, 35, 43), gc(Mk, 5, 35, 43)],
            [gc(Mk, 6, 1, 6), gc(Mk, 6, 7, 13), gc(Mk, 6, 14, 29), gc(Mk, 6, 30, 34), gc(Mk, 6, 34, 44), gc(Mk, 7, 1, 13)],
            [gc(Mk, 7, 1, 13), gc(Mk, 7, 14, 23), gc(Mk, 7, 24, 30), gc(Mk, 7, 31, 37), gc(Mk, 8, 1, 10), gc(Mk, 8, 14, 21)],
            [gc(Mk, 8, 22, 26), gc(Mk, 8, 22, 26), gc(Mk, 9, 2, 10), gc(Mk, 9, 14, 29), gc(Mk, 9, 30, 37), gc(Mk, 9, 38, 40)],
            [gc(Mk, 9, 38, 40), gc(Mk, 9, 41, 50), gc(Mk, 10, 1, 12), gc(Mk, 10, 13, 16), gc(Mk, 10, 17, 27), gc(Mk, 10, 28, 31)],
            [gc(Mk, 10, 32, 45), gc(Mk, 10, 35, 45), gc(Mk, 10, 46, 52), gc(Mk, 12, 28, 34), gc(Mk, 12, 35, 37), gc(Mk, 12, 38, 44)],
            [gc(M, 5, 1, 12), gc(M, 5, 13, 16), gc(M, 5, 17, 19), gc(M, 5, 20, 26), gc(M, 5, 27, 32), gc(M, 5, 33, 37)],
            [gc(M, 5, 38, 42), gc(M, 5, 43, 48), gc(M, 6, 1, 18), gc(M, 6, 7, 15), gc(M, 6, 19, 23), gc(M, 6, 24, 34)],
            [gc(M, 7, 1, 5), gc(M, 7, 6, 14), gc(M, 7, 15, 20), gc(M, 7, 21, 29), gc(M, 8, 1, 4), gc(M, 8, 5, 17)],
            [gc(M, 8, 18, 22), gc(M, 8, 23, 27), gc(M, 8, 28, 34), gc(M, 9, 1, 8), gc(M, 9, 9, 13), gc(M, 9, 14, 17)],
            [gc(M, 9, 18, 26), gc(M, 9, 32, 38), gc(M, 10, 1, 7), gc(M, 10, 7, 15), gc(M, 10, 16, 23), gc(M, 10, 24, 33)],
            [gc(M, 10, 34, 42), gc(M, 11, 20, 24), gc(M, 11, 25, 27), gc(M, 11, 28, 30), gc(M, 12, 1, 8), gc(M, 12, 14, 21)],
            [gc(M, 12, 38, 42), gc(M, 12, 46, 50), gc(M, 13, 1, 9), gc(M, 13, 10, 17), gc(M, 13, 18, 23), gc(M, 13, 24, 30)],
            [gc(M, 13, 31, 35), gc(M, 13, 36, 43), gc(M, 13, 44, 46), gc(M, 13, 47, 53), gc(M, 13, 54, 58), gc(M, 14, 1, 12)],
            [gc(M, 14, 13, 21), gc(M, 14, 22, 36), gc(M, 15, 21, 28), gc(M, 16, 13, 19), gc(M, 17, 1, 9), gc(M, 17, 14, 20)],
            [gc(M, 17, 22, 27), gc(M, 18, 1, 14), gc(M, 18, 15, 20), gc(M, 18, 21, 35), gc(M, 18, 21, 35), gc(M, 18, 21, 35)],
            [gc(M, 19, 3, 12), gc(M, 19, 13, 15), gc(M, 19, 23, 30), gc(M, 20, 1, 16), gc(M, 20, 17, 28), gc(M, 20, 24, 28)],
            [gc(M, 23, 1, 12), gc(M, 23, 13, 22), gc(M, 23, 27, 32), gc(M, 24, 37, 44), gc(M, 25, 1, 13), gc(M, 25, 14, 30)],
            [gc(L, 4, 16, 30), gc(L, 4, 31, 37), gc(L, 4, 38, 44), gc(L, 5, 1, 11), gc(L, 5, 33, 39), gc(L, 6, 1, 5)],
            [gc(L, 6, 6, 11), gc(L, 6, 12, 19), gc(L, 6, 20, 26), gc(L, 6, 27, 38), gc(L, 6, 39, 42), gc(L, 6, 43, 49)],
            [gc(L, 7, 1, 10), gc(L, 7, 11, 17), gc(L, 7, 31, 35), gc(L, 7, 36, 50), gc(L, 8, 1, 3), gc(L, 8, 4, 15)],
            [gc(L, 8, 16, 18), gc(L, 8, 19, 21), gc(L, 9, 1, 6), gc(L, 9, 7, 9), gc(L, 9, 18, 22), gc(L, 9, 43, 45)],
            [gc(L, 9, 46, 50), gc(L, 9, 51, 56), gc(L, 9, 57, 62), gc(L, 10, 1, 12), gc(L, 10, 13, 16), gc(L, 10, 17, 24)],
            [gc(L, 10, 25, 37), gc(L, 10, 38, 42), gc(L, 11, 1, 4), gc(L, 11, 5, 13), gc(L, 11, 15, 26), gc(L, 11, 27, 28)],
            [gc(L, 11, 29, 32), gc(L, 11, 37, 41), gc(L, 11, 42, 46), gc(L, 11, 47, 54), gc(L, 12, 1, 7), gc(L, 12, 8, 12)],
            [gc(L, 12, 13, 21), gc(L, 12, 35, 38), gc(L, 12, 39, 48), gc(L, 12, 49, 53), gc(L, 12, 54, 59), gc(L, 13, 1, 9)],
            [gc(L, 13, 10, 17), gc(L, 13, 18, 21), gc(L, 13, 22, 30), gc(L, 13, 31, 35), gc(L, 14, 1, 6), gc(L, 14, 7, 11)],
            [gc(L, 14, 12, 14), gc(L, 14, 15, 24), gc(L, 14, 25, 33), gc(L, 15, 1, 10), gc(L, 16, 1, 8), gc(L, 16, 9, 15)],
            [gc(L, 17, 1, 6), gc(L, 17, 7, 10), gc(L, 17, 11, 19), gc(L, 17, 20, 25), gc(L, 17, 26, 37), gc(L, 18, 1, 8)],
            [gc(L, 18, 35, 43), gc(L, 19, 1, 10), gc(L, 19, 11, 28), gc(L, 19, 41, 44), gc(L, 19, 45, 48), gc(L, 20, 27, 40)],
            [gc(L, 21, 1, 4), gc(L, 21, 5, 11), gc(L, 21, 12, 19), gc(L, 21, 20, 28), gc(L, 21, 29, 33), gc(L, 21, 34, 36)],
        ]
        let wIdx = min(max(week - 1, 0), 33)
        let dIdx = min(max(dow - 1, 0), 5)
        return table[wIdx][dIdx]
    }

    // MARK: - Lent

    private static func lentGospel(_ pos: LiturgicalPosition) -> (String, Int, Int, Int)? {
        pos.dayOfWeek == sunday
            ? lentSundayGospel(pos.week, pos.sundayCycle)
            : lentWeekdayGospel(pos.week, pos.dayOfWeek)
    }

    private static func lentSundayGospel(_ week: Int, _ cycle: SundayCycle) -> (String, Int, Int, Int)? {
        switch cycle {
        case .a:
            switch week {
            case 1: return gc(M, 4, 1, 11); case 2: return gc(M, 17, 1, 9); case 3: return gc(J, 4, 5, 42)
            case 4: return gc(J, 9, 1, 41); case 5: return gc(J, 11, 1, 45); case 6: return gc(M, 26, 14, 25)
            default: return nil
            }
        case .b:
            switch week {
            case 1: return gc(Mk, 1, 12, 15); case 2: return gc(Mk, 9, 2, 10); case 3: return gc(J, 2, 13, 25)
            case 4: return gc(J, 3, 14, 21); case 5: return gc(J, 12, 20, 33); case 6: return gc(Mk, 14, 1, 72)
            default: return nil
            }
        case .c:
            switch week {
            case 1: return gc(L, 4, 1, 13); case 2: return gc(L, 9, 28, 36); case 3: return gc(J, 4, 5, 42)
            case 4: return gc(L, 15, 1, 32); case 5: return gc(J, 8, 1, 11); case 6: return gc(L, 22, 14, 71)
            default: return nil
            }
        }
    }

    private static func lentWeekdayGospel(_ week: Int, _ dow: Int) -> (String, Int, Int, Int)? {
        let table: [[(String, Int, Int, Int)]] = [
            [gc(M, 25, 31, 46), gc(M, 6, 1, 18), gc(M, 6, 7, 15), gc(L, 11, 1, 4), gc(M, 7, 7, 12), gc(M, 5, 43, 48)],
            [gc(L, 6, 36, 38), gc(M, 23, 1, 12), gc(L, 13, 22, 30), gc(M, 20, 17, 28), gc(L, 15, 1, 32), gc(L, 15, 11, 32)],
            [gc(L, 4, 24, 30), gc(M, 5, 17, 19), gc(L, 11, 29, 32), gc(J, 4, 43, 54), gc(Mk, 12, 28, 34), gc(L, 18, 9, 14)],
            [gc(J, 4, 43, 54), gc(J, 5, 1, 16), gc(J, 5, 17, 30), gc(J, 5, 31, 47), gc(J, 7, 1, 30), gc(J, 7, 40, 53)],
            [gc(J, 8, 1, 11), gc(J, 8, 21, 30), gc(J, 8, 31, 42), gc(J, 8, 51, 59), gc(J, 10, 31, 42), gc(J, 11, 45, 56)],
            [gc(J, 12, 1, 11), gc(J, 13, 21, 38), gc(M, 26, 14, 25), gc(J, 13, 1, 15), gc(J, 18, 1, 40), gc(L, 23, 50, 56)],
        ]
        let wIdx = min(max(week - 1, 0), 5)
        let dIdx = min(max(dow - 1, 0), 5)
        return table[wIdx][dIdx]
    }

    // MARK: - Easter

    private static func easterGospel(_ pos: LiturgicalPosition) -> (String, Int, Int, Int)? {
        pos.dayOfWeek == sunday
            ? easterSundayGospel(pos.week, pos.sundayCycle)
            : easterWeekdayGospel(pos.week, pos.dayOfWeek)
    }

    private static func easterSundayGospel(_ week: Int, _ cycle: SundayCycle) -> (String, Int, Int, Int)? {
        switch week {
        case 1: return gc(J, 20, 1, 9)
        case 2: return gc(J, 20, 19, 31)
        case 3:
            switch cycle {
            case .a: return gc(L, 24, 13, 35)
            case .b: return gc(L, 24, 35, 48)
            case .c: return gc(J, 21, 1, 19)
            }
        case 4:
            switch cycle {
            case .a: return gc(J, 10, 1, 10)
            case .b: return gc(J, 10, 11, 18)
            case .c: return gc(J, 10, 27, 30)
            }
        case 5:
            switch cycle {
            case .a: return gc(J, 14, 1, 12)
            case .b: return gc(J, 15, 1, 8)
            case .c: return gc(J, 13, 31, 35)
            }
        case 6:
            switch cycle {
            case .a: return gc(J, 14, 15, 21)
            case .b: return gc(J, 15, 9, 17)
            case .c: return gc(J, 14, 23, 29)
            }
        case 7:
            switch cycle {
            case .a: return gc(J, 17, 1, 11)
            case .b: return gc(J, 17, 11, 19)
            case .c: return gc(J, 17, 20, 26)
            }
        default: return nil
        }
    }

    private static func easterWeekdayGospel(_ week: Int, _ dow: Int) -> (String, Int, Int, Int)? {
        let table: [[(String, Int, Int, Int)]] = [
            [gc(M, 28, 8, 15), gc(J, 20, 11, 18), gc(L, 24, 13, 35), gc(L, 24, 35, 48), gc(J, 21, 1, 14), gc(J, 21, 1, 14)],
            [gc(J, 3, 1, 8), gc(J, 3, 7, 15), gc(J, 3, 16, 21), gc(J, 3, 31, 36), gc(J, 6, 1, 15), gc(J, 6, 16, 21)],
            [gc(J, 6, 22, 29), gc(J, 6, 30, 35), gc(J, 6, 35, 40), gc(J, 6, 44, 51), gc(J, 6, 52, 59), gc(J, 6, 60, 69)],
            [gc(J, 10, 1, 10), gc(J, 10, 22, 30), gc(J, 12, 44, 50), gc(J, 13, 16, 20), gc(J, 14, 1, 6), gc(J, 14, 7, 14)],
            [gc(J, 14, 21, 26), gc(J, 14, 27, 31), gc(J, 15, 1, 8), gc(J, 15, 9, 11), gc(J, 15, 12, 17), gc(J, 15, 18, 21)],
            [gc(J, 15, 26, 27), gc(J, 16, 5, 11), gc(J, 16, 12, 15), gc(J, 16, 16, 20), gc(J, 16, 20, 23), gc(J, 16, 23, 28)],
            [gc(J, 16, 29, 33), gc(J, 17, 1, 11), gc(J, 17, 11, 19), gc(J, 17, 20, 26), gc(J, 21, 15, 19), gc(J, 21, 20, 25)],
        ]
        let wIdx = min(max(week - 1, 0), 6)
        let dIdx = min(max(dow - 1, 0), 5)
        return table[wIdx][dIdx]
    }
}
