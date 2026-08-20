//
//  ReaderSettings.swift
//  CatholicBible
//
//  ebook 리더의 보기 설정(글자 크기·줄 간격·서체·테마).
//  UserDefaults에 저장되어 앱을 다시 열어도 유지된다.
//

import SwiftUI

// MARK: - 종이 테마

enum ReaderTheme: String, CaseIterable, Identifiable {
    case light
    case sepia
    case gray
    case black

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: return "흰색"
        case .sepia: return "세피아"
        case .gray:  return "회색"
        case .black: return "검정"
        }
    }

    var background: Color {
        switch self {
        case .light: return Color(red: 1.00, green: 1.00, blue: 1.00)
        case .sepia: return Color(red: 0.98, green: 0.955, blue: 0.90)
        case .gray:  return Color(red: 0.16, green: 0.16, blue: 0.17)
        case .black: return Color.black
        }
    }

    var text: Color {
        switch self {
        case .light: return Color(red: 0.13, green: 0.12, blue: 0.11)
        case .sepia: return Color(red: 0.32, green: 0.25, blue: 0.18)
        case .gray:  return Color(red: 0.88, green: 0.88, blue: 0.89)
        case .black: return Color(red: 0.80, green: 0.80, blue: 0.80)
        }
    }

    /// 제목·독서 헤더용 색 — 본문색보다 명도를 높여 특히 어두운 테마에서 또렷하게.
    var headingText: Color {
        switch self {
        case .light: return Color(red: 0.10, green: 0.09, blue: 0.08)
        case .sepia: return Color(red: 0.26, green: 0.20, blue: 0.14)
        case .gray:  return Color(red: 0.98, green: 0.98, blue: 0.99)
        case .black: return Color(red: 0.97, green: 0.97, blue: 0.98)
        }
    }

    /// 절 번호·머리글 등 보조 요소 색
    var secondary: Color { text.opacity(0.55) }

    /// 시스템 컨트롤(툴바 등)이 따라갈 밝음/어두움
    var colorScheme: ColorScheme {
        switch self {
        case .light, .sepia: return .light
        case .gray, .black:  return .dark
        }
    }
}

// MARK: - 설정 저장소

@Observable
final class ReaderSettings {
    private static let defaults = UserDefaults.standard

    var fontSize: Double {
        didSet { Self.defaults.set(fontSize, forKey: "reader.fontSize") }
    }
    /// 줄 간격 배율 (본문 폰트 크기 대비)
    var lineSpacingFactor: Double {
        didSet { Self.defaults.set(lineSpacingFactor, forKey: "reader.lineSpacing") }
    }
    var fontChoice: FontChoice {
        didSet { Self.defaults.set(fontChoice.rawValue, forKey: "reader.fontChoice") }
    }
    var englishFontChoice: EnglishFontChoice {
        didSet { Self.defaults.set(englishFontChoice.rawValue, forKey: "reader.englishFontChoice") }
    }
    var theme: ReaderTheme {
        didSet { Self.defaults.set(theme.rawValue, forKey: "reader.theme") }
    }
    var showVerseNumbers: Bool {
        didSet { Self.defaults.set(showVerseNumbers, forKey: "reader.showVerseNumbers") }
    }

    static let fontSizeRange: ClosedRange<Double> = 14...30

    init() {
        let d = Self.defaults
        let size = d.double(forKey: "reader.fontSize")
        fontSize = size == 0 ? 19 : size
        let spacing = d.double(forKey: "reader.lineSpacing")
        lineSpacingFactor = spacing == 0 ? 0.65 : spacing
        fontChoice = FontChoice(rawValue: d.string(forKey: "reader.fontChoice") ?? "") ?? .myeongjo
        englishFontChoice = EnglishFontChoice(rawValue: d.string(forKey: "reader.englishFontChoice") ?? "") ?? .georgia
        theme = ReaderTheme(rawValue: d.string(forKey: "reader.theme") ?? "") ?? .sepia
        showVerseNumbers = d.object(forKey: "reader.showVerseNumbers") as? Bool ?? true
    }

    var lineSpacing: CGFloat { fontSize * lineSpacingFactor }

    func bodyFont(bold: Bool = false) -> Font {
        fontChoice.font(size: fontSize, bold: bold)
    }

    /// 영문 폰트
    func bodyEnglishFont(bold: Bool = false) -> Font {
        englishFontChoice.font(size: fontSize, bold: bold)
    }
}
