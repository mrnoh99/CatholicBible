//
//  BackupSettingsView.swift
//  CatholicBible
//
//  책갈피와 노트의 백업 설정 및 관리
//

import SwiftUI
import UniformTypeIdentifiers

struct BackupSettingsView: View {
    @Environment(AnnotationStore.self) private var annotationStore
    @Environment(\.dismiss) private var dismiss
    @State private var backupManager = BackupManager.shared
    @State private var showBackupResult = false
    @State private var backupResultMessage = ""
    @State private var isBackuping = false
    @State private var backups: [BackupInfo] = []
    @State private var showBackupList = false
    @State private var showFolderPicker = false
    @State private var backupFolderName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("자동 백업") {
                    Toggle("자동 백업 활성화", isOn: $backupManager.isAutoBackupEnabled)

                    if backupManager.isAutoBackupEnabled {
                        Picker("백업 빈도", selection: $backupManager.backupFrequency) {
                            ForEach(BackupFrequency.allCases, id: \.self) { frequency in
                                Text(frequency.rawValue).tag(frequency)
                            }
                        }
                    }

                    if let lastDate = backupManager.lastBackupDate {
                        HStack {
                            Text("마지막 백업")
                            Spacer()
                            Text(lastDate.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                }

                Section {
                    Button(action: { performBackup() }) {
                        HStack {
                            Image(systemName: "arrow.up.doc")
                            Text("지금 백업")
                            if isBackuping {
                                Spacer()
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .disabled(isBackuping)
                }

                Section("백업 위치") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("저장 위치")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(backupManager.getBackupDirectory().path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                    }

                    Button(action: { showFolderPicker = true }) {
                        HStack {
                            Image(systemName: "folder.badge.plus")
                            Text("폴더 선택")
                        }
                    }
                }

                Section("백업 관리") {
                    Button(action: { loadBackups(); showBackupList = true }) {
                        HStack {
                            Image(systemName: "list.bullet")
                            Text("로컬 백업 목록")
                            Spacer()
                            Text("\(backups.count)")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("백업")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") { dismiss() }
                }
            }
            .sheet(isPresented: $showBackupList) {
                BackupListView(backups: $backups, backupManager: backupManager, annotationStore: annotationStore)
            }
            .alert("백업 완료", isPresented: $showBackupResult) {
                Button("확인") { }
            } message: {
                Text(backupResultMessage)
            }
            .fileImporter(
                isPresented: $showFolderPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false,
                onCompletion: { result in
                    switch result {
                    case .success(let urls):
                        if let selectedFolder = urls.first {
                            if selectedFolder.startAccessingSecurityScopedResource() {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    backupManager.setCustomBackupDirectory(selectedFolder)
                                    updateBackupFolderName()
                                    loadBackups()
                                }
                            }
                        }
                    case .failure(let error):
                        print("폴더 선택 실패: \(error)")
                    }
                }
            )
            .onAppear {
                loadBackups()
                updateBackupFolderName()
            }
        }
    }

    private func performBackup() {
        isBackuping = true
        Task {
            let result = backupManager.backup(annotationStore: annotationStore)
            await MainActor.run {
                isBackuping = false
                switch result {
                case .success(let url):
                    backupResultMessage = "백업이 완료되었습니다.\n위치: \(url.lastPathComponent)"
                    loadBackups()
                case .failure(let error):
                    backupResultMessage = "백업 실패: \(error.localizedDescription)"
                }
                showBackupResult = true
            }
        }
    }

    private func loadBackups() {
        backups = backupManager.listBackups()
    }

    private func updateBackupFolderName() {
        backupFolderName = backupManager.getBackupDirectoryName()
    }
}

struct BackupListView: View {
    @Binding var backups: [BackupInfo]
    let backupManager: BackupManager
    let annotationStore: AnnotationStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedBackup: BackupInfo?
    @State private var showDeleteConfirm = false
    @State private var showRestoreResult = false
    @State private var resultMessage = ""

    var body: some View {
        NavigationStack {
            Group {
                if backups.isEmpty {
                    ContentUnavailableView(
                        "백업 없음",
                        systemImage: "archivebox",
                        description: Text("백업 목록이 비어있습니다.")
                    )
                } else {
                    List {
                        ForEach(backups) { backup in
                            backupRow(backup)
                        }
                    }
                }
            }
            .navigationTitle("백업 목록")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") { dismiss() }
                }
            }
        }
        .alert("백업 삭제", isPresented: $showDeleteConfirm) {
            Button("삭제", role: .destructive) {
                if let backup = selectedBackup {
                    deleteBackup(backup)
                }
            }
            Button("취소", role: .cancel) { }
        } message: {
            Text("선택한 백업을 삭제하시겠습니까?")
        }
        .alert("복원 결과", isPresented: $showRestoreResult) {
            Button("확인") { }
        } message: {
            Text(resultMessage)
        }
    }

    private func backupRow(_ backup: BackupInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(backup.date)
                        .font(.subheadline.weight(.semibold))
                    Text("\(backup.bookmarksCount) 책갈피 • \(backup.notesCount) 노트")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Button(action: { restoreBackup(backup) }) {
                    Label("복원", systemImage: "arrow.down.doc")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)

                Button(action: {
                    selectedBackup = backup
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        showDeleteConfirm = true
                    }
                }) {
                    Label("삭제", systemImage: "trash")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .tint(.red)

                Spacer()
            }
        }
        .padding(.vertical, 4)
    }

    private func restoreBackup(_ backup: BackupInfo) {
        let result = backupManager.restore(from: backup.path, to: annotationStore)
        switch result {
        case .success():
            resultMessage = "백업이 복원되었습니다."
        case .failure(let error):
            resultMessage = "복원 실패: \(error.localizedDescription)"
        }
        showRestoreResult = true
    }

    private func deleteBackup(_ backup: BackupInfo) {
        let result = backupManager.deleteBackup(backup)
        if case .success = result {
            backups.removeAll { $0.id == backup.id }
        }
    }
}

#Preview {
    let annotationStore = AnnotationStore()
    return BackupSettingsView()
        .environment(annotationStore)
}
