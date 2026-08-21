//
//  ReadingState.swift
//  CatholicBible
//
//  선택된 판본(1·2단), 2단 보기 여부, 이어 읽기 위치. UserDefaults에 저장.
//  (책갈피·노트는 판본 공통이므로 AnnotationStore가 맡는다.)
//

import Foundation
import Observation

/// iPad 리더 레이아웃
enum ReaderLayout: String, CaseIterable, Identifiable, Sendable {
    case single   // 한 페이지 (한 판본, 스크롤)
    case spread   // 두 페이지 (같은 성경을 책 펼침면처럼 좌→우 이어서)
    case compare  // 두 판본 나란히 비교 (각 열 독립)

    var id: String { rawValue }

    var label: String {
        switch self {
        case .single:  return "한 페이지"
        case .spread:  return "두 페이지 (펼침)"
        case .compare: return "두 판본 비교"
        }
    }

    var systemImage: String {
        switch self {
        case .single:  return "rectangle.portrait"
        case .spread:  return "book.pages"
        case .compare: return "rectangle.split.2x1"
        }
    }
}

@Observable
final class ReadingState {
    private static let defaults = UserDefaults.standard
    private static let editionKey = "reading.editionID"
    private static let secondaryKey = "reading.secondaryEditionID"
    private static let secondaryBookKey = "reading.secondaryBookID"
    private static let layoutKey = "reading.layout"
    private static let compareLinkedKey = "reading.compareLinked"
    private static let showAnnotatedNotesKey = "reading.showAnnotatedNotes"
    private static let lastBookKey = "reading.lastBookID"
    private static let chapterPrefix = "reading.chapter."

    /// 첫째 열(주 판본)
    var selectedEditionID: String {
        didSet { Self.defaults.set(selectedEditionID, forKey: Self.editionKey) }
    }

    /// 둘째 열(iPad 2단에서 나란히 볼 판본)
    var secondaryEditionID: String {
        didSet { Self.defaults.set(secondaryEditionID, forKey: Self.secondaryKey) }
    }

    /// 둘째 열이 펼친 책 (빈 값이면 첫째 열과 같은 책으로 시작)
    var secondaryBookID: String {
        didSet { Self.defaults.set(secondaryBookID, forKey: Self.secondaryBookKey) }
    }

    /// iPad 리더 레이아웃(한 페이지 / 펼침 / 비교)
    var readerLayout: ReaderLayout {
        didSet { Self.defaults.set(readerLayout.rawValue, forKey: Self.layoutKey) }
    }

    /// 두 판본 비교에서 두 열을 같은 책·장으로 연동할지 (기본: 연동).
    var compareLinked: Bool {
        didSet { Self.defaults.set(compareLinked, forKey: Self.compareLinkedKey) }
    }

    /// 주석 판본에서 본문·주석 보기를 사용할지 (기본: true, 활성화 시 AnnotatedReader 표시)
    var showAnnotatedNotes: Bool {
        didSet { Self.defaults.set(showAnnotatedNotes, forKey: Self.showAnnotatedNotesKey) }
    }

    /// 마지막으로 읽던 책 (판본별)
    private var lastBookIDs: [String: String] {
        didSet { Self.defaults.set(lastBookIDs, forKey: Self.lastBookKey) }
    }

    init() {
        selectedEditionID = Self.defaults.string(forKey: Self.editionKey) ?? Editions.defaultEditionID
        secondaryEditionID = Self.defaults.string(forKey: Self.secondaryKey) ?? "ncb"
        secondaryBookID = Self.defaults.string(forKey: Self.secondaryBookKey) ?? ""
        readerLayout = ReaderLayout(rawValue: Self.defaults.string(forKey: Self.layoutKey) ?? "") ?? .single
        compareLinked = Self.defaults.object(forKey: Self.compareLinkedKey) as? Bool ?? true
        showAnnotatedNotes = Self.defaults.object(forKey: Self.showAnnotatedNotesKey) as? Bool ?? false
        lastBookIDs = Self.defaults.dictionary(forKey: Self.lastBookKey) as? [String: String] ?? [:]
    }

    var selectedEdition: Edition {
        Editions.edition(selectedEditionID) ?? Editions.all[0]
    }

    var secondaryEdition: Edition {
        Editions.edition(secondaryEditionID) ?? Editions.all[min(1, Editions.all.count - 1)]
    }

    // MARK: - 이어 읽기 (판본×책별 마지막 장)

    func lastBookID(edition: Edition) -> String? {
        lastBookIDs[edition.id]
    }

    func lastChapter(edition: Edition, book: BibleBook) -> Int {
        let saved = Self.defaults.integer(forKey: Self.chapterPrefix + edition.id + "." + book.id)
        return (1...book.chapterCount).contains(saved) ? saved : 1
    }

    func savePosition(edition: Edition, book: BibleBook, chapter: Int) {
        Self.defaults.set(chapter, forKey: Self.chapterPrefix + edition.id + "." + book.id)
        lastBookIDs[edition.id] = book.id
    }
}
