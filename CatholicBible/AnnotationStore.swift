//
//  AnnotationStore.swift
//  CatholicBible
//
//  판본 공통 책갈피와 노트를 관리한다.
//  - 책갈피: VerseRef 집합 (UserDefaults에 JSON)
//  - 노트: [Note] (Documents/notes.json), 미디어 파일은 Documents/NoteMedia/
//
//  절 하나(VerseRef)에는 노트가 하나 대응한다(있으면 편집, 없으면 새로 만듦).
//

import Foundation
import Observation
import UIKit

@Observable
final class AnnotationStore {
    private static let defaults = UserDefaults.standard
    private static let bookmarksKey = "annotation.bookmarks"

    private(set) var bookmarks: Set<VerseRef> = []
    private(set) var notes: [Note] = []

    private let notesURL: URL
    let mediaDir: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        notesURL = docs.appendingPathComponent("notes.json")
        mediaDir = docs.appendingPathComponent("NoteMedia", isDirectory: true)
        try? FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        loadBookmarks()
        loadNotes()
    }

    // MARK: - 책갈피 (판본 공통)

    func isBookmarked(_ ref: VerseRef) -> Bool { bookmarks.contains(ref) }

    func toggleBookmark(_ ref: VerseRef) {
        if bookmarks.contains(ref) { bookmarks.remove(ref) } else { bookmarks.insert(ref) }
        saveBookmarks()
    }

    func removeBookmark(_ ref: VerseRef) {
        bookmarks.remove(ref)
        saveBookmarks()
    }

    func addBookmark(_ ref: VerseRef) {
        bookmarks.insert(ref)
        saveBookmarks()
    }

    /// 성경 목차 순서로 정렬된 책갈피 목록
    var sortedBookmarks: [VerseRef] {
        bookmarks.sorted { $0.sortKey < $1.sortKey }
    }

    private func loadBookmarks() {
        guard let data = Self.defaults.data(forKey: Self.bookmarksKey),
              let saved = try? JSONDecoder().decode([VerseRef].self, from: data) else { return }
        bookmarks = Set(saved)
    }

    private func saveBookmarks() {
        if let data = try? JSONEncoder().encode(Array(bookmarks)) {
            Self.defaults.set(data, forKey: Self.bookmarksKey)
        }
    }

    // MARK: - 노트 (판본 공통)

    func note(for ref: VerseRef) -> Note? {
        notes.first { $0.verse == ref }
    }

    func hasNote(_ ref: VerseRef) -> Bool {
        guard let n = notes.first(where: { $0.verse == ref }) else { return false }
        return !n.isEmpty
    }

    /// 절에 대한 노트를 가져오거나 새로 만든다(저장은 save(_:)에서).
    func noteOrNew(for ref: VerseRef) -> Note {
        note(for: ref) ?? Note(verse: ref)
    }

    /// 노트를 저장(있으면 갱신, 없으면 추가). 빈 노트는 삭제한다.
    func save(_ note: Note) {
        var updated = note
        updated.modified = Date()
        if let idx = notes.firstIndex(where: { $0.id == note.id }) {
            if updated.isEmpty {
                deleteMedia(of: notes[idx])
                notes.remove(at: idx)
            } else {
                notes[idx] = updated
            }
        } else if !updated.isEmpty {
            notes.insert(updated, at: 0)
        }
        persistNotes()
    }

    func delete(_ note: Note) {
        deleteMedia(of: note)
        notes.removeAll { $0.id == note.id }
        persistNotes()
    }

    /// 최근 수정순 노트 목록
    var notesByRecency: [Note] {
        notes.sorted { $0.modified > $1.modified }
    }

    private func loadNotes() {
        guard let data = try? Data(contentsOf: notesURL),
              let saved = try? JSONDecoder().decode([Note].self, from: data) else { return }
        notes = saved
    }

    private func persistNotes() {
        if let data = try? JSONEncoder().encode(notes) {
            try? data.write(to: notesURL, options: .atomic)
        }
    }

    // MARK: - 미디어 파일

    func mediaURL(_ filename: String) -> URL {
        mediaDir.appendingPathComponent(filename)
    }

    func url(for attachment: Attachment) -> URL {
        mediaURL(attachment.filename)
    }

    /// 데이터를 미디어 폴더에 저장하고 첨부를 만든다.
    @discardableResult
    func addAttachment(kind: AttachmentKind, data: Data, ext: String) -> Attachment {
        let filename = "\(UUID().uuidString).\(ext)"
        try? data.write(to: mediaURL(filename), options: .atomic)
        return Attachment(kind: kind, filename: filename)
    }

    /// 기존 첨부 파일을 새 데이터로 덮어쓴다(손글씨 이어 그리기 등).
    func overwrite(_ attachment: Attachment, with data: Data) {
        try? data.write(to: mediaURL(attachment.filename), options: .atomic)
    }

    /// 첨부 파일의 원본 데이터를 읽는다.
    func data(for attachment: Attachment) -> Data? {
        try? Data(contentsOf: mediaURL(attachment.filename))
    }

    /// 외부 URL(카메라/피커 결과)을 미디어 폴더로 복사하고 첨부를 만든다.
    func addAttachment(kind: AttachmentKind, copyingFrom source: URL) -> Attachment? {
        let ext = source.pathExtension.isEmpty ? defaultExt(for: kind) : source.pathExtension
        let filename = "\(UUID().uuidString).\(ext)"
        let dest = mediaURL(filename)
        do {
            if source.startAccessingSecurityScopedResource() {
                defer { source.stopAccessingSecurityScopedResource() }
                try FileManager.default.copyItem(at: source, to: dest)
            } else {
                try FileManager.default.copyItem(at: source, to: dest)
            }
            return Attachment(kind: kind, filename: filename)
        } catch {
            return nil
        }
    }

    private func defaultExt(for kind: AttachmentKind) -> String {
        switch kind {
        case .photo:   return "jpg"
        case .drawing: return "png"
        case .audio:   return "m4a"
        case .video:   return "mov"
        }
    }

    private func deleteMedia(of note: Note) {
        for att in note.attachments {
            try? FileManager.default.removeItem(at: mediaURL(att.filename))
        }
    }

    // MARK: - 백업 / 복원 (외부 저장 — 버전 업·재설치에도 유지)

    /// 책갈피·노트·미디어를 한 파일로 묶어 내보낼 데이터를 만든다.
    /// 미디어 파일은 base64로 함께 담기므로 파일 하나만 보관하면 된다.
    func exportBackup() -> Data? {
        var mediaBlobs: [String: Data] = [:]
        for note in notes {
            for att in note.attachments where mediaBlobs[att.filename] == nil {
                if let bytes = try? Data(contentsOf: mediaURL(att.filename)) {
                    mediaBlobs[att.filename] = bytes
                }
            }
        }
        let backup = NoteBackup(exportedAt: Date(),
                                bookmarks: Array(bookmarks),
                                notes: notes,
                                media: mediaBlobs)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(backup)
    }

    /// 백업 데이터를 불러와 현재 자료에 병합한다(같은 절의 기존 노트는 보존).
    /// 돌려주는 값: (추가된 노트 수, 추가된 책갈피 수). 실패 시 nil.
    @discardableResult
    func importBackup(_ data: Data) -> (notes: Int, bookmarks: Int)? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let backup = try? decoder.decode(NoteBackup.self, from: data) else { return nil }

        // 미디어 파일 복원(없는 것만 씀)
        for (filename, bytes) in backup.media {
            let url = mediaURL(filename)
            if !FileManager.default.fileExists(atPath: url.path) {
                try? bytes.write(to: url, options: .atomic)
            }
        }
        // 노트 병합: 같은 id 또는 같은 절에 이미 노트가 있으면 건너뜀
        var addedNotes = 0
        for note in backup.notes {
            let exists = notes.contains { $0.id == note.id || $0.verse == note.verse }
            if !exists && !note.isEmpty {
                notes.append(note)
                addedNotes += 1
            }
        }
        // 책갈피 병합(합집합)
        let before = bookmarks.count
        bookmarks.formUnion(backup.bookmarks)
        let addedBookmarks = bookmarks.count - before

        persistNotes()
        saveBookmarks()
        return (addedNotes, addedBookmarks)
    }

    /// 노트에서 첨부를 지우고(파일도 삭제) 갱신된 노트를 돌려준다.
    func removingAttachment(_ attachment: Attachment, from note: Note) -> Note {
        try? FileManager.default.removeItem(at: mediaURL(attachment.filename))
        var updated = note
        updated.attachments.removeAll { $0.id == attachment.id }
        return updated
    }
}
