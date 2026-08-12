//
//  SearchView.swift
//  CatholicBible
//
//  구절 검색. 범위를 '현재 판본' 또는 '모든 판본'으로 고를 수 있다.
//  결과를 누르면 그 판본으로 전환하며 해당 절로 이동한다.
//

import SwiftUI

enum SearchScope: String, CaseIterable, Identifiable {
    case current
    case all
    var id: String { rawValue }
    var label: String {
        switch self {
        case .current: return "현재 판본"
        case .all:     return "모든 판본"
        }
    }
}

enum SearchMode: String, CaseIterable, Identifiable {
    case text
    case reference
    var id: String { rawValue }
    var label: String {
        switch self {
        case .text: return "말씀 찾기"
        case .reference: return "장절찾기"
        }
    }
}

struct SearchView: View {
    @Environment(BibleStore.self) private var store
    @Environment(ReadingState.self) private var readingState
    @Environment(ReaderNavigation.self) private var navigation
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var scope: SearchScope = .current
    @State private var mode: SearchMode = .text
    @State private var results: [SearchHit] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var searchTask: Task<Void, Never>?
    @State private var selectedBookID: String = ""
    @State private var selectedChapter: Int = 1
    @State private var selectedVerse: Int = 1

    var body: some View {
        let edition = readingState.selectedEdition

        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Picker("검색 범위", selection: $scope) {
                        ForEach(SearchScope.allCases) { s in Text(s.label).tag(s) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: .infinity)

                    Picker("검색 방식", selection: $mode) {
                        ForEach(SearchMode.allCases) { m in Text(m.label).tag(m) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal).padding(.vertical, 8)

                if mode == .reference {
                    let selectedBook = Bible.book(selectedBookID)
                    let maxVerse = selectedBook.flatMap { book in
                        store.verses(edition: readingState.selectedEdition, bookID: book.id, chapter: selectedChapter)?
                            .map { $0.verse }.max()
                    } ?? 1

                    VStack(spacing: 8) {
                        Picker("명칭", selection: $selectedBookID) {
                            Text("책 선택").tag("")
                            ForEach(Bible.books) { book in
                                Text(book.name).tag(book.id)
                            }
                        }
                        .onChange(of: selectedBookID) { _, _ in
                            selectedChapter = 1
                            selectedVerse = 1
                            runSearch()
                        }

                        HStack(spacing: 8) {
                            if let book = selectedBook {
                                Picker("장", selection: $selectedChapter) {
                                    ForEach(1...book.chapterCount, id: \.self) { chapter in
                                        Text("\(chapter)").tag(chapter)
                                    }
                                }
                                .onChange(of: selectedChapter) { _, _ in
                                    selectedVerse = 1
                                    runSearch()
                                }

                                Picker("절", selection: $selectedVerse) {
                                    ForEach(1...max(maxVerse, 1), id: \.self) { verse in
                                        Text("\(verse)").tag(verse)
                                    }
                                }
                                .onChange(of: selectedVerse) { runSearch() }
                            }
                        }
                    }
                    .padding(.horizontal).padding(.vertical, 8)
                }

                Group {
                    if isSearching {
                        ProgressView("찾는 중 …").frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if results.isEmpty {
                        ContentUnavailableView(
                            hasSearched ? "결과 없음" : "구절 검색",
                            systemImage: "magnifyingglass",
                            description: Text(hasSearched
                                ? (mode == .text
                                   ? "’\(query)’이(가) 들어간 구절을 찾지 못했습니다."
                                   : "해당 장절을 찾지 못했습니다.")
                                : (mode == .text
                                   ? (scope == .current
                                      ? "두 글자 이상 입력하면 「\(edition.shortName)」에서 찾습니다."
                                      : "두 글자 이상 입력하면 수록된 모든 판본에서 찾습니다.")
                                   : "책, 장, 절을 지정하세요."))
                        )
                    } else {
                        List(results) { hit in
                            Button {
                                open(hit)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(reference(for: hit))
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(Color.accentColor)
                                        if scope == .all, let ed = Editions.edition(hit.editionID) {
                                            Text(ed.shortName)
                                                .font(.caption2.weight(.semibold))
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                                                .foregroundStyle(Color.accentColor)
                                        }
                                    }
                                    Text(hit.text).font(.subheadline).lineLimit(3)
                                }
                                .padding(.vertical, 2)
                            }
                            .buttonStyle(.plain)
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .navigationTitle("검색")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: mode == .text ? "말씀 검색 (예: 사랑 OR love)" : "")
            .searchableComparison(mode == .text)
            .onSubmit(of: .search) { runSearch() }
            .onChange(of: query) { runSearch() }
            .onChange(of: scope) { runSearch() }
            .onChange(of: mode) {
                query = ""
                selectedBookID = ""
                selectedChapter = 1
                selectedVerse = 1
                results = []
                hasSearched = false
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
            }
        }
    }


    private func reference(for hit: SearchHit) -> String {
        guard let book = Bible.book(hit.bookID) else { return "" }
        return "\(book.abbrev) \(hit.chapter),\(hit.verse)"
    }

    private func open(_ hit: SearchHit) {
        if scope == .all, Editions.edition(hit.editionID) != nil {
            readingState.selectedEditionID = hit.editionID
        }
        navigation.open(bookID: hit.bookID, chapter: hit.chapter, verse: hit.verse)
        dismiss()
    }

    private func runSearch() {
        searchTask?.cancel()

        if mode == .text {
            let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count >= 2 else {
                results = []; hasSearched = false; isSearching = false
                return
            }
            let currentEdition = readingState.selectedEdition
            let editionsToSearch = store.loadedEditions
            let scope = scope
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                isSearching = true
                let hits: [SearchHit]
                if scope == .all {
                    hits = await store.searchAll(text, editions: editionsToSearch, mode: .text)
                } else {
                    hits = await store.search(text, edition: currentEdition, mode: .text)
                }
                guard !Task.isCancelled else { return }
                results = hits
                hasSearched = true
                isSearching = false
            }
        } else {
            guard !selectedBookID.isEmpty else {
                results = []; hasSearched = false; isSearching = false
                return
            }

            let currentEdition = readingState.selectedEdition
            let editionsToSearch = scope == .all ? store.loadedEditions : [currentEdition]
            let chapter = selectedChapter
            let verse = selectedVerse

            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                isSearching = true

                var hits: [SearchHit] = []
                for edition in editionsToSearch {
                    if let verses = store.verses(edition: edition, bookID: selectedBookID, chapter: chapter) {
                        if let hit = verses.first(where: { $0.verse == verse }) {
                            hits.append(SearchHit(bookID: selectedBookID, chapter: chapter, verse: verse,
                                                 editionID: edition.id, text: hit.text))
                        }
                    }
                }

                guard !Task.isCancelled else { return }
                results = hits
                hasSearched = true
                isSearching = false
            }
        }
    }
}
