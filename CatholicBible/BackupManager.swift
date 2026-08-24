//
//  BackupManager.swift
//  CatholicBible
//
//  책갈피와 노트의 자동 백업을 관리한다.
//

import Foundation
import UIKit

enum BackupFrequency: String, CaseIterable {
    case daily = "매일"
    case weekly = "매주"
    case monthly = "매월"

    var id: String { self.rawValue }
}

enum SyncError: LocalizedError {
    case iCloudUnavailable
    case syncFailed(String)
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .iCloudUnavailable:
            return "iCloud를 사용할 수 없습니다"
        case .syncFailed(let msg):
            return "동기화 실패: \(msg)"
        case .downloadFailed:
            return "다운로드 실패"
        }
    }
}

@Observable
final class BackupManager {
    static let shared = BackupManager()

    private static let defaults = UserDefaults.standard
    private static let backupDirName = "Backups"
    private static let lastBackupKey = "backupManager.lastBackupDate"
    private static let autoBackupEnabledKey = "backupManager.autoBackupEnabled"
    private static let backupFrequencyKey = "backupManager.backupFrequency"
    private static let iCloudEnabledKey = "backupManager.iCloudEnabled"
    private static let lastICloudSyncKey = "backupManager.lastICloudSync"
    private static let iCloudBackupDirName = "CatholicBibleBackups"

    var isAutoBackupEnabled: Bool {
        get {
            Self.defaults.bool(forKey: Self.autoBackupEnabledKey)
        }
        set {
            Self.defaults.set(newValue, forKey: Self.autoBackupEnabledKey)
        }
    }

    var backupFrequency: BackupFrequency {
        get {
            let stored = Self.defaults.string(forKey: Self.backupFrequencyKey) ?? "매주"
            return BackupFrequency(rawValue: stored) ?? .weekly
        }
        set {
            Self.defaults.set(newValue.rawValue, forKey: Self.backupFrequencyKey)
        }
    }

    var lastBackupDate: Date? {
        get {
            Self.defaults.object(forKey: Self.lastBackupKey) as? Date
        }
        set {
            if let date = newValue {
                Self.defaults.set(date, forKey: Self.lastBackupKey)
            } else {
                Self.defaults.removeObject(forKey: Self.lastBackupKey)
            }
        }
    }

    var isICloudEnabled: Bool {
        get {
            Self.defaults.bool(forKey: Self.iCloudEnabledKey)
        }
        set {
            Self.defaults.set(newValue, forKey: Self.iCloudEnabledKey)
        }
    }

    var lastICloudSyncDate: Date? {
        get {
            Self.defaults.object(forKey: Self.lastICloudSyncKey) as? Date
        }
        set {
            if let date = newValue {
                Self.defaults.set(date, forKey: Self.lastICloudSyncKey)
            } else {
                Self.defaults.removeObject(forKey: Self.lastICloudSyncKey)
            }
        }
    }

    var isSyncing = false

    private let backupDir: URL
    private let iCloudBackupDir: URL?

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        backupDir = docs.appendingPathComponent(Self.backupDirName, isDirectory: true)
        try? FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)

        // iCloud Drive 설정
        if let iCloudContainerURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            let iCloudBackupDirURL = iCloudContainerURL.appendingPathComponent(Self.iCloudBackupDirName, isDirectory: true)
            try? FileManager.default.createDirectory(at: iCloudBackupDirURL, withIntermediateDirectories: true)
            self.iCloudBackupDir = iCloudBackupDirURL
        } else {
            self.iCloudBackupDir = nil
        }
    }

    // MARK: - iCloud 확인

    func isICloudAvailable() -> Bool {
        iCloudBackupDir != nil
    }

    // MARK: - iCloud 동기화

    func syncToICloud(backupPath: URL) async -> Result<Void, Error> {
        guard let iCloudDir = iCloudBackupDir else {
            return .failure(SyncError.iCloudUnavailable)
        }

        isSyncing = true
        defer { isSyncing = false }

        do {
            let backupName = backupPath.lastPathComponent
            let iCloudBackupPath = iCloudDir.appendingPathComponent(backupName, isDirectory: true)

            // 기존 백업이 있으면 제거
            if FileManager.default.fileExists(atPath: iCloudBackupPath.path) {
                try FileManager.default.removeItem(at: iCloudBackupPath)
            }

            // 백업 폴더 복사
            try FileManager.default.copyItem(at: backupPath, to: iCloudBackupPath)
            lastICloudSyncDate = Date()
            return .success(())
        } catch {
            return .failure(SyncError.syncFailed(error.localizedDescription))
        }
    }

    func listICloudBackups() -> [BackupInfo] {
        guard let iCloudDir = iCloudBackupDir else { return [] }

        guard let contents = try? FileManager.default.contentsOfDirectory(at: iCloudDir, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }

        return contents.compactMap { url in
            let metadataFile = url.appendingPathComponent("metadata.json")
            guard let metadataData = try? Data(contentsOf: metadataFile),
                  let metadata = try? JSONSerialization.jsonObject(with: metadataData) as? [String: Any] else {
                return nil
            }

            return BackupInfo(
                path: url,
                name: url.lastPathComponent,
                date: metadata["date"] as? String ?? "",
                bookmarksCount: metadata["bookmarksCount"] as? Int ?? 0,
                notesCount: metadata["notesCount"] as? Int ?? 0
            )
        }.sorted { ($0.date) > ($1.date) }
    }

    func downloadFromICloud(_ backup: BackupInfo, to localDir: URL) async -> Result<Void, Error> {
        isSyncing = true
        defer { isSyncing = false }

        do {
            let localBackupPath = localDir.appendingPathComponent(backup.name, isDirectory: true)

            // 기존 백업이 있으면 제거
            if FileManager.default.fileExists(atPath: localBackupPath.path) {
                try FileManager.default.removeItem(at: localBackupPath)
            }

            // iCloud에서 복사
            try FileManager.default.copyItem(at: backup.path, to: localBackupPath)
            return .success(())
        } catch {
            return .failure(SyncError.downloadFailed)
        }
    }

    // MARK: - 자동 백업 체크

    func shouldBackup() -> Bool {
        guard isAutoBackupEnabled else { return false }
        guard let lastDate = lastBackupDate else { return true }

        let calendar = Calendar.current
        let now = Date()

        switch backupFrequency {
        case .daily:
            return !calendar.isDateInToday(lastDate)
        case .weekly:
            let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            return lastDate < sevenDaysAgo
        case .monthly:
            let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) ?? now
            return lastDate < thirtyDaysAgo
        }
    }

    // MARK: - 백업 생성

    func backup(annotationStore: AnnotationStore) -> Result<URL, Error> {
        let timestamp = ISO8601DateFormatter().string(from: Date()).prefix(19).replacingOccurrences(of: ":", with: "-")
        let backupName = "backup_\(timestamp)"
        let backupPath = backupDir.appendingPathComponent(backupName, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: backupPath, withIntermediateDirectories: true)

            // 책갈피 백업
            let bookmarksData = try JSONEncoder().encode(annotationStore.sortedBookmarks)
            try bookmarksData.write(to: backupPath.appendingPathComponent("bookmarks.json"))

            // 노트 백업
            let notesData = try JSONEncoder().encode(annotationStore.notes)
            try notesData.write(to: backupPath.appendingPathComponent("notes.json"))

            // 미디어 파일 백업
            let mediaSourceDir = annotationStore.mediaDir
            if FileManager.default.fileExists(atPath: mediaSourceDir.path) {
                let mediaBackupDir = backupPath.appendingPathComponent("NoteMedia", isDirectory: true)
                try FileManager.default.createDirectory(at: mediaBackupDir, withIntermediateDirectories: true)

                let mediaFiles = try FileManager.default.contentsOfDirectory(at: mediaSourceDir, includingPropertiesForKeys: nil)
                for file in mediaFiles {
                    try FileManager.default.copyItem(at: file, to: mediaBackupDir.appendingPathComponent(file.lastPathComponent))
                }
            }

            // 메타데이터 저장
            let metadata: [String: Any] = [
                "date": ISO8601DateFormatter().string(from: Date()),
                "appVersion": Bundle.main.appVersion,
                "osVersion": UIDevice.current.systemVersion,
                "bookmarksCount": annotationStore.sortedBookmarks.count,
                "notesCount": annotationStore.notes.count
            ]
            let metadataData = try JSONSerialization.data(withJSONObject: metadata)
            try metadataData.write(to: backupPath.appendingPathComponent("metadata.json"))

            lastBackupDate = Date()

            // iCloud 동기화 활성화 시 비동기로 업로드
            if isICloudEnabled {
                Task {
                    _ = await self.syncToICloud(backupPath: backupPath)
                }
            }

            return .success(backupPath)
        } catch {
            return .failure(error)
        }
    }

    // MARK: - 백업 복원

    func restore(from backupPath: URL, to annotationStore: AnnotationStore) -> Result<Void, Error> {
        do {
            // 책갈피 복원
            let bookmarksFile = backupPath.appendingPathComponent("bookmarks.json")
            if FileManager.default.fileExists(atPath: bookmarksFile.path) {
                let data = try Data(contentsOf: bookmarksFile)
                let bookmarks = try JSONDecoder().decode([VerseRef].self, from: data)
                for bookmark in bookmarks {
                    annotationStore.addBookmark(bookmark)
                }
            }

            // 노트 복원
            let notesFile = backupPath.appendingPathComponent("notes.json")
            if FileManager.default.fileExists(atPath: notesFile.path) {
                let data = try Data(contentsOf: notesFile)
                let notes = try JSONDecoder().decode([Note].self, from: data)
                for note in notes {
                    annotationStore.save(note)
                }
            }

            // 미디어 파일 복원
            let mediaBackupDir = backupPath.appendingPathComponent("NoteMedia")
            if FileManager.default.fileExists(atPath: mediaBackupDir.path) {
                let mediaFiles = try FileManager.default.contentsOfDirectory(at: mediaBackupDir, includingPropertiesForKeys: nil)
                for file in mediaFiles {
                    try FileManager.default.copyItem(at: file, to: annotationStore.mediaDir.appendingPathComponent(file.lastPathComponent))
                }
            }

            return .success(())
        } catch {
            return .failure(error)
        }
    }

    // MARK: - 백업 관리

    func listBackups() -> [BackupInfo] {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: backupDir, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }

        return contents.compactMap { url in
            let metadataFile = url.appendingPathComponent("metadata.json")
            guard let metadataData = try? Data(contentsOf: metadataFile),
                  let metadata = try? JSONSerialization.jsonObject(with: metadataData) as? [String: Any] else {
                return nil
            }

            return BackupInfo(
                path: url,
                name: url.lastPathComponent,
                date: metadata["date"] as? String ?? "",
                bookmarksCount: metadata["bookmarksCount"] as? Int ?? 0,
                notesCount: metadata["notesCount"] as? Int ?? 0
            )
        }.sorted { ($0.date) > ($1.date) }
    }

    func deleteBackup(_ backup: BackupInfo) -> Result<Void, Error> {
        do {
            try FileManager.default.removeItem(at: backup.path)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    func exportBackup(_ backup: BackupInfo) -> URL? {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("backup.zip")

        do {
            try FileManager.default.copyItem(at: backup.path, to: temp)
            return temp
        } catch {
            return nil
        }
    }
}

struct BackupInfo: Identifiable {
    let id = UUID()
    let path: URL
    let name: String
    let date: String
    let bookmarksCount: Int
    let notesCount: Int
}

extension Bundle {
    var appVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "Unknown"
    }
}
