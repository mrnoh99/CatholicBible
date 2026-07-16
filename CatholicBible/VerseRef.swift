//
//  VerseRef.swift
//  CatholicBible
//
//  판본과 무관한 절 식별자와 노트 모델.
//  책갈피·노트는 이 VerseRef를 키로 저장되므로, 어떤 판본을 보든
//  같은 절이면 같은 책갈피·노트로 나타난다.
//

import Foundation

// MARK: - 절 식별자 (판본 공통)

struct VerseRef: Codable, Hashable, Identifiable, Sendable {
    let bookID: String
    let chapter: Int
    let verse: Int

    var id: String { "\(bookID)-\(chapter)-\(verse)" }

    /// "마태 5,3" 식의 짧은 성구 표기
    var reference: String {
        guard let book = Bible.book(bookID) else { return "\(bookID) \(chapter),\(verse)" }
        return "\(book.abbrev) \(chapter),\(verse)"
    }

    /// "마태오 복음 5장 3절" 식의 긴 표기 (접근성/목록용)
    var longReference: String {
        guard let book = Bible.book(bookID) else { return "\(bookID) \(chapter),\(verse)" }
        return "\(book.shortName) \(book.chapterLabel(chapter)) \(verse)절"
    }

    /// 성경 목차 순서 정렬용 키 (책 순서, 장, 절)
    var sortKey: (Int, Int, Int) {
        let bookIndex = Bible.books.firstIndex { $0.id == bookID } ?? Int.max
        return (bookIndex, chapter, verse)
    }
}

// MARK: - 노트 첨부

enum AttachmentKind: String, Codable, Sendable {
    case photo
    case drawing   // PencilKit 손글씨
    case audio
    case video

    var label: String {
        switch self {
        case .photo:   return "사진"
        case .drawing: return "손글씨"
        case .audio:   return "오디오"
        case .video:   return "비디오"
        }
    }

    var systemImage: String {
        switch self {
        case .photo:   return "photo"
        case .drawing: return "pencil.tip"
        case .audio:   return "waveform"
        case .video:   return "video"
        }
    }
}

struct Attachment: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var kind: AttachmentKind
    /// NoteMedia 폴더 기준 파일 이름 (예: "9F3A….jpg")
    var filename: String
    var created = Date()
}

// MARK: - 노트 (절 하나에 대한 판본 공통 메모)

struct Note: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var verse: VerseRef
    var text: String = ""
    var attachments: [Attachment] = []
    var created = Date()
    var modified = Date()

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty
    }

    func attachments(of kind: AttachmentKind) -> [Attachment] {
        attachments.filter { $0.kind == kind }
    }
}

// MARK: - 백업 (책갈피 + 노트 + 미디어를 한 파일로)

struct NoteBackup: Codable, Sendable {
    var version = 1
    var exportedAt: Date
    var bookmarks: [VerseRef]
    var notes: [Note]
    /// 미디어 파일 이름 → 원본 바이트(JSON에는 base64로 저장)
    var media: [String: Data]
}
