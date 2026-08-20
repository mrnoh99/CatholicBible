//
//  Typography.swift
//  CatholicBible
//
//  iOS/iPadOS에는 한글 명조 시스템 폰트가 없어, ebook다운 본문을 위해
//  나눔명조를 번들한다(Info.plist UIAppFonts에 등록).
//
//  영문 폰트: 명조체 선택 시 Georgia(세리프), 고딕체 선택 시 San Francisco(산세리프)

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

    /// 본문용 폰트. Dynamic Type과 함께 확대·축소된다.
    func font(size: CGFloat, relativeTo style: Font.TextStyle = .body, bold: Bool = false) -> Font {
        switch self {
        case .myeongjo:
            return .custom(bold ? "NanumMyeongjoBold" : "NanumMyeongjo", size: size, relativeTo: style)
        case .gothic:
            return .system(size: size, weight: bold ? .semibold : .regular)
        }
    }

    /// 영문 폰트. 한글 폰트와 조화되는 영문 세리프/산세리프 폰트.
    func englishFont(size: CGFloat, relativeTo style: Font.TextStyle = .body, bold: Bool = false) -> Font {
        switch self {
        case .myeongjo:
            return .custom(bold ? "Georgia-Bold" : "Georgia", size: size, relativeTo: style)
        case .gothic:
            return .system(size: size, weight: bold ? .semibold : .regular)
        }
    }
}
