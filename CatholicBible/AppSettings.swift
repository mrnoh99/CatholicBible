//
//  AppSettings.swift
//  CatholicBible
//
//  시스템 설정을 따르는 앱 설정
//

import SwiftUI

@Observable
final class AppSettings {
    static let shared = AppSettings()

    @AppStorage("theme.preference") var themePreference: String = "system"
    @AppStorage("fontSize") var fontSize: Double = 16
    @AppStorage("lineHeight") var lineHeight: Double = 1.5

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
