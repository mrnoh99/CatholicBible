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
    private static let deviceIdKey = "backupManager.deviceId"

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
    var lastSyncError: SyncError? = nil
    var isICloudConnected = false

    private let backupDir: URL
    private let iCloudBackupDir: URL?
    private let deviceId: String
    private var iCloudMonitorTask: Task<Void, Never>?

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

        // iCloud Drive 설정 (기기별 폴더)
        if let iCloudContainerURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            let iCloudBackupDirURL = iCloudContainerURL
                .appendingPathComponent(Self.iCloudBackupDirName, isDirectory: true)
                .appendingPathComponent(deviceId, isDirectory: true)
            try? FileManager.default.createDirectory(at: iCloudBackupDirURL, withIntermediateDirectories: true)
            self.iCloudBackupDir = iCloudBackupDirURL
            self.isICloudConnected = true
        } else {
            self.iCloudBackupDir = nil
            self.isICloudConnected = false
        }

        // iCloud 연결 상태 모니터링 시작
        startICloudMonitoring()
    }

    deinit {
        iCloudMonitorTask?.cancel()
    }

    private func startICloudMonitoring() {
        iCloudMonitorTask = Task {
            while !Task.isCancelled {
                let connected = FileManager.default.url(forUbiquityContainerIdentifier: nil) != nil
                await MainActor.run {
                    self.isICloudConnected = connected
                }
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    // MARK: - 기기 정보

    func getDeviceIdentifier() -> String {
        deviceId
    }

    func getDeviceName() -> String {
        UIDevice.current.name
    }

    // MARK: - iCloud 확인

    func isICloudAvailable() -> Bool {
        iCloudBackupDir != nil
    }

    // MARK: - Private Helpers

    private func copyBackupItem(from source: URL, to destination: URL) throws {
        // Create temporary path to avoid corruption if copy fails
        let tempPath = destination.deletingLastPathComponent().appendingPathComponent(destination.lastPathComponent + ".tmp")

        // Remove temp file if it exists from previous failed attempt
        if FileManager.default.fileExists(atPath: tempPath.path) {
            try? FileManager.default.removeItem(at: tempPath)
        }

        // Copy to temporary location first
        try FileManager.default.copyItem(at: source, to: tempPath)

        // If destination exists, remove it before moving temp to destination
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        // Move from temp to final destination
        try FileManager.default.moveItem(at: tempPath, to: destination)
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
            try copyBackupItem(from: backupPath, to: iCloudBackupPath)
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
                print("[BackupManager] Warning: Corrupted iCloud backup metadata at \(url.lastPathComponent)")
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

    func listAllDeviceBackups() -> [BackupInfo] {
        guard let iCloudContainerURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) else { return [] }
        let backupRootDir = iCloudContainerURL.appendingPathComponent(Self.iCloudBackupDirName, isDirectory: true)

        guard let devices = try? FileManager.default.contentsOfDirectory(at: backupRootDir, includingPropertiesForKeys: nil) else {
            return []
        }

        var allBackups: [BackupInfo] = []

        for deviceDir in devices {
            guard let backups = try? FileManager.default.contentsOfDirectory(at: deviceDir, includingPropertiesForKeys: [.contentModificationDateKey]) else {
                continue
            }

            for backupDir in backups {
                let metadataFile = backupDir.appendingPathComponent("metadata.json")
                guard let metadataData = try? Data(contentsOf: metadataFile),
                      let metadata = try? JSONSerialization.jsonObject(with: metadataData) as? [String: Any] else {
                    print("[BackupManager] Warning: Corrupted backup at \(backupDir.lastPathComponent) on device \(deviceDir.lastPathComponent)")
                    continue
                }

                let isCurrentDevice = deviceDir.lastPathComponent == deviceId
                allBackups.append(BackupInfo(
                    path: backupDir,
                    name: backupDir.lastPathComponent,
                    date: metadata["date"] as? String ?? "Unknown",
                    bookmarksCount: metadata["bookmarksCount"] as? Int ?? 0,
                    notesCount: metadata["notesCount"] as? Int ?? 0,
                    deviceName: metadata["deviceName"] as? String,
                    isFromCurrentDevice: isCurrentDevice
                ))
            }
        }

        return allBackups.sorted { ($0.date) > ($1.date) }
    }

    func downloadFromICloud(_ backup: BackupInfo) async -> Result<Void, Error> {
        isSyncing = true
        defer { isSyncing = false }

        do {
            let localBackupPath = backupDir.appendingPathComponent(backup.name, isDirectory: true)
            try copyBackupItem(from: backup.path, to: localBackupPath)
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
                "deviceName": UIDevice.current.name,
                "deviceId": deviceId,
                "bookmarksCount": annotationStore.sortedBookmarks.count,
                "notesCount": annotationStore.notes.count
            ]
            let metadataData = try JSONSerialization.data(withJSONObject: metadata)
            try metadataData.write(to: backupPath.appendingPathComponent("metadata.json"))

            lastBackupDate = Date()

            // iCloud 동기화 활성화 시 비동기로 업로드
            if isICloudEnabled {
                Task {
                    let syncResult = await self.syncToICloud(backupPath: backupPath)
                    await MainActor.run {
                        if case .failure(let error) = syncResult {
                            self.lastSyncError = error as? SyncError ?? .syncFailed(error.localizedDescription)
                        } else {
                            self.lastSyncError = nil
                        }
                    }
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
            // 책갈피 복원 (중복 방지)
            let bookmarksFile = backupPath.appendingPathComponent("bookmarks.json")
            if FileManager.default.fileExists(atPath: bookmarksFile.path) {
                let data = try Data(contentsOf: bookmarksFile)
                let bookmarks = try JSONDecoder().decode([VerseRef].self, from: data)

                // 기존 책갈피와 비교하여 새로운 것만 추가
                let existingBookmarks = Set(annotationStore.sortedBookmarks.map { "\($0.book),\($0.chapter),\($0.verse)" })
                for bookmark in bookmarks {
                    let key = "\(bookmark.book),\(bookmark.chapter),\(bookmark.verse)"
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
                    // 기존 파일이 없을 때만 복사
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
        guard let contents = try? FileManager.default.contentsOfDirectory(at: backupDir, includingPropertiesForKeys: [.contentModificationDateKey]) else {
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
