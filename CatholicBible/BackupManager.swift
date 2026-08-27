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

@Observable
final class BackupManager {
    static let shared = BackupManager()

    private static let defaults = UserDefaults.standard
    private static let backupDirName = "Backups"
    private static let lastBackupKey = "backupManager.lastBackupDate"
    private static let autoBackupEnabledKey = "backupManager.autoBackupEnabled"
    private static let backupFrequencyKey = "backupManager.backupFrequency"
    private static let deviceIdKey = "backupManager.deviceId"
    private static let customBackupDirKey = "backupManager.customBackupDir"

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

    var customBackupDirBookmark: Data? {
        get {
            Self.defaults.data(forKey: Self.customBackupDirKey)
        }
        set {
            if let data = newValue {
                Self.defaults.set(data, forKey: Self.customBackupDirKey)
            } else {
                Self.defaults.removeObject(forKey: Self.customBackupDirKey)
            }
        }
    }

    private let backupDir: URL
    private let deviceId: String
    private var customBackupDir: URL?

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        backupDir = docs.appendingPathComponent(Self.backupDirName, isDirectory: true)
        try? FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)

        // 기기 ID 설정 (처음 한 번만 생성)
        if let saved = Self.defaults.string(forKey: Self.deviceIdKey) {
            self.deviceId = saved
        } else {
            let newId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
            Self.defaults.set(newId, forKey: Self.deviceIdKey)
            self.deviceId = newId
        }

        // 저장된 커스텀 폴더 복원 시도
        if let bookmark = self.customBackupDirBookmark {
            do {
                var isStale = false
                let url = try URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale)
                if isStale {
                    let newBookmark = try url.bookmarkData(options: .minimalBookmark)
                    Self.defaults.set(newBookmark, forKey: Self.customBackupDirKey)
                }
                self.customBackupDir = url
            } catch {
                print("❌ 저장된 백업 폴더 복원 실패: \(error)")
            }
        }
    }

    // MARK: - 백업 폴더 설정

    func setCustomBackupDirectory(_ url: URL) {
        do {
            // 선택된 폴더에 접근 권한 확인
            _ = try url.resourceValues(forKeys: [.isDirectoryKey])
            let bookmark = try url.bookmarkData(options: .minimalBookmark)
            self.customBackupDirBookmark = bookmark
            self.customBackupDir = url
            print("✅ 백업 폴더 설정 완료: \(url.lastPathComponent)")
        } catch {
            print("❌ 백업 폴더 설정 실패: \(error)")
        }
    }

    func getBackupDirectory() -> URL {
        if let custom = customBackupDir {
            return custom
        }
        return backupDir
    }

    func getBackupDirectoryName() -> String {
        if let custom = customBackupDir {
            return custom.lastPathComponent
        }
        return "로컬 백업"
    }

    func clearCustomBackupDirectory() {
        self.customBackupDirBookmark = nil
        self.customBackupDir = nil
        print("✅ 커스텀 백업 폴더 설정 해제")
    }

    func hasCustomBackupDirectory() -> Bool {
        customBackupDir != nil
    }

    // MARK: - 기기 정보

    func getDeviceIdentifier() -> String {
        deviceId
    }

    func getDeviceName() -> String {
        UIDevice.current.name
    }

    // MARK: - Private Helpers

    private func copyBackupItem(from source: URL, to destination: URL) throws {
        let tempPath = destination.deletingLastPathComponent().appendingPathComponent(destination.lastPathComponent + ".tmp")

        if FileManager.default.fileExists(atPath: tempPath.path) {
            try? FileManager.default.removeItem(at: tempPath)
        }

        try FileManager.default.copyItem(at: source, to: tempPath)

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        try FileManager.default.moveItem(at: tempPath, to: destination)
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
        let selectedDir = getBackupDirectory()
        let backupPath = selectedDir.appendingPathComponent(backupName, isDirectory: true)

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
                "deviceName": UIDevice.current.name,
                "deviceId": deviceId,
                "bookmarksCount": annotationStore.sortedBookmarks.count,
                "notesCount": annotationStore.notes.count
            ]
            let metadataData = try JSONSerialization.data(withJSONObject: metadata)
            try metadataData.write(to: backupPath.appendingPathComponent("metadata.json"))

            lastBackupDate = Date()
            return .success(backupPath)
        } catch {
            return .failure(error)
        }
    }

    // MARK: - 백업 복원

    func restore(from backupPath: URL, to annotationStore: AnnotationStore) -> Result<Void, Error> {
        do {
            // 책갈피 복원 (중복 방지)
            let bookmarksFile = backupPath.appendingPathComponent("bookmarks.json")
            if FileManager.default.fileExists(atPath: bookmarksFile.path) {
                let data = try Data(contentsOf: bookmarksFile)
                let bookmarks = try JSONDecoder().decode([VerseRef].self, from: data)

                // 기존 책갈피와 비교하여 새로운 것만 추가
                let existingBookmarks = Set(annotationStore.sortedBookmarks.map { "\($0.bookID),\($0.chapter),\($0.verse)" })
                for bookmark in bookmarks {
                    let key = "\(bookmark.bookID),\(bookmark.chapter),\(bookmark.verse)"
                    if !existingBookmarks.contains(key) {
                        annotationStore.addBookmark(bookmark)
                    }
                }
            }

            // 노트 복원 (중복 방지)
            let notesFile = backupPath.appendingPathComponent("notes.json")
            if FileManager.default.fileExists(atPath: notesFile.path) {
                let data = try Data(contentsOf: notesFile)
                let notes = try JSONDecoder().decode([Note].self, from: data)

                // 기존 노트와 비교하여 새로운 것만 추가
                let existingNoteIds = Set(annotationStore.notes.map { $0.id })
                for note in notes {
                    if !existingNoteIds.contains(note.id) {
                        annotationStore.save(note)
                    }
                }
            }

            // 미디어 파일 복원 (기존 파일이 있으면 건너뜀)
            let mediaBackupDir = backupPath.appendingPathComponent("NoteMedia")
            if FileManager.default.fileExists(atPath: mediaBackupDir.path) {
                try FileManager.default.createDirectory(at: annotationStore.mediaDir, withIntermediateDirectories: true)

                let mediaFiles = try FileManager.default.contentsOfDirectory(at: mediaBackupDir, includingPropertiesForKeys: nil)
                for file in mediaFiles {
                    let targetPath = annotationStore.mediaDir.appendingPathComponent(file.lastPathComponent)
                    if !FileManager.default.fileExists(atPath: targetPath.path) {
                        try FileManager.default.copyItem(at: file, to: targetPath)
                    }
                }
            }

            return .success(())
        } catch {
            return .failure(error)
        }
    }

    // MARK: - 백업 관리

    func listBackups() -> [BackupInfo] {
        let selectedDir = getBackupDirectory()
        guard let contents = try? FileManager.default.contentsOfDirectory(at: selectedDir, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return []
        }

        return contents.compactMap { url in
            let metadataFile = url.appendingPathComponent("metadata.json")
            guard let metadataData = try? Data(contentsOf: metadataFile),
                  let metadata = try? JSONSerialization.jsonObject(with: metadataData) as? [String: Any] else {
                print("[BackupManager] Warning: Corrupted backup metadata at \(url.lastPathComponent)")
                return nil
            }

            return BackupInfo(
                path: url,
                name: url.lastPathComponent,
                date: metadata["date"] as? String ?? "Unknown",
                bookmarksCount: metadata["bookmarksCount"] as? Int ?? 0,
                notesCount: metadata["notesCount"] as? Int ?? 0,
                deviceName: getDeviceName(),
                isFromCurrentDevice: true
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
    let deviceName: String?
    let isFromCurrentDevice: Bool

    init(path: URL, name: String, date: String, bookmarksCount: Int, notesCount: Int, deviceName: String? = nil, isFromCurrentDevice: Bool = true) {
        self.path = path
        self.name = name
        self.date = date
        self.bookmarksCount = bookmarksCount
        self.notesCount = notesCount
        self.deviceName = deviceName
        self.isFromCurrentDevice = isFromCurrentDevice
    }
}

extension Bundle {
    var appVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "Unknown"
    }
}
