//
//  AppSettings.swift
//  CatholicBible
//
//  시스템 설정을 따르는 앱 설정
//

import SwiftUI
import Observation

@Observable
final class AppSettings {
    static let shared = AppSettings()

    private(set) var themePreference: String = UserDefaults.standard.string(forKey: "theme.preference") ?? "system" {
        didSet { UserDefaults.standard.set(themePreference, forKey: "theme.preference") }
    }

    private(set) var fontSize: Double = UserDefaults.standard.double(forKey: "fontSize") > 0 ? UserDefaults.standard.double(forKey: "fontSize") : 16 {
        didSet { UserDefaults.standard.set(fontSize, forKey: "fontSize") }
    }

    private(set) var lineHeight: Double = UserDefaults.standard.double(forKey: "lineHeight") > 0 ? UserDefaults.standard.double(forKey: "lineHeight") : 1.5 {
        didSet { UserDefaults.standard.set(lineHeight, forKey: "lineHeight") }
    }

    // MARK: - 백업 설정
    var backupManager = BackupManager.shared

    var isAutoBackupEnabled: Bool {
        get { backupManager.isAutoBackupEnabled }
        set { backupManager.isAutoBackupEnabled = newValue }
    }

    var backupFrequency: BackupFrequency {
        get { backupManager.backupFrequency }
        set { backupManager.backupFrequency = newValue }
    }

    var lastBackupDate: Date? {
        backupManager.lastBackupDate
    }
}
