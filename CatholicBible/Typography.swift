//
//  Typography.swift
//  CatholicBible
//
//  iOS/iPadOS에는 한글 명조 시스템 폰트가 없어, ebook다운 본문을 위해
//  나눔명조를 번들한다(Info.plist UIAppFonts에 등록).
//

import SwiftUI

enum FontChoice: String, CaseIterable, Identifiable {
    case myeongjo
    case gothic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .myeongjo: return "명조체"
        case .gothic:   return "고딕체"
        }
    }

    var shortLabel: String {
        switch self {
        case .myeongjo: return "명조"
        case .gothic:   return "고딕"
        }
    }

    var opposite: FontChoice {
        switch self {
        case .myeongjo: return .gothic
        case .gothic:   return .myeongjo
        }
    }

    /// 본문용 폰트. Dynamic Type과 함께 확대·축소된다.
    func font(size: CGFloat, relativeTo style: Font.TextStyle = .body, bold: Bool = false) -> Font {
        switch self {
        case .myeongjo:
            return .custom(bold ? "NanumMyeongjoBold" : "NanumMyeongjo", size: size, relativeTo: style)
        case .gothic:
            return .system(size: size, weight: bold ? .semibold : .regular)
        }
    }
}

enum EnglishFontChoice: String, CaseIterable, Identifiable {
    case georgia
    case sanfrancisco

    var id: String { rawValue }

    var label: String {
        switch self {
        case .georgia: return "Georgia"
        case .sanfrancisco: return "San Francisco"
        }
    }

    func font(size: CGFloat, relativeTo style: Font.TextStyle = .body, bold: Bool = false) -> Font {
        switch self {
        case .georgia:
            return .custom(bold ? "Georgia-Bold" : "Georgia", size: size, relativeTo: style)
        case .sanfrancisco:
            return .system(size: size, weight: bold ? .semibold : .regular)
        }
    }
}
