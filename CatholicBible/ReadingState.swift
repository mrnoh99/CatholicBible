//
//  ReadingState.swift
//  CatholicBible
//
//  선택된 판본(1·2단), 2단 보기 여부, 이어 읽기 위치. UserDefaults에 저장.
//  (책갈피·노트는 판본 공통이므로 AnnotationStore가 맡는다.)
//

import Foundation
import Observation

@Observable
final class ReadingState {
    private static let defaults = UserDefaults.standard
    private static let editionKey = "reading.editionID"
    private static let secondaryKey = "reading.secondaryEditionID"
    private static let secondaryBookKey = "reading.secondaryBookID"
    private static let dualKey = "reading.dualPane"
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

    /// iPad에서 2단(나란히 두 판본) 보기 사용 여부
    var dualPaneEnabled: Bool {
        didSet { Self.defaults.set(dualPaneEnabled, forKey: Self.dualKey) }
    }

    /// 마지막으로 읽던 책 (판본별)
    private var lastBookIDs: [String: String] {
        didSet { Self.defaults.set(lastBookIDs, forKey: Self.lastBookKey) }
    }

    init() {
        selectedEditionID = Self.defaults.string(forKey: Self.editionKey) ?? Editions.defaultEditionID
        secondaryEditionID = Self.defaults.string(forKey: Self.secondaryKey) ?? "ncb"
        secondaryBookID = Self.defaults.string(forKey: Self.secondaryBookKey) ?? ""
        dualPaneEnabled = Self.defaults.object(forKey: Self.dualKey) as? Bool ?? true
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
