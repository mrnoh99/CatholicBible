//
//  AppSettings.swift
//  CatholicBible
//
//  앱 전체의 보기 설정(라이트/다크 모드)
//

import SwiftUI

enum AppThemeMode: String, CaseIterable, Identifiable {
    case light
    case dark
    case auto

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: return "라이트 모드"
        case .dark: return "다크 모드"
        case .auto: return "시스템 설정"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .auto: return nil
        }
    }
}

@Observable
final class AppSettings {
    private static let defaults = UserDefaults.standard

    var themeMode: AppThemeMode {
        didSet { Self.defaults.set(themeMode.rawValue, forKey: "app.themeMode") }
    }

    static let shared = AppSettings()

    init() {
        let d = Self.defaults
        themeMode = AppThemeMode(rawValue: d.string(forKey: "app.themeMode") ?? "") ?? .auto
    }
}
