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
    case bookName
    case reference
    var id: String { rawValue }
    var label: String {
        switch self {
        case .text: return "말씀"
        case .bookName: return "명칭"
        case .reference: return "장:절"
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

                    Menu {
                        Picker("검색 방식", selection: $mode) {
                            ForEach(SearchMode.allCases) { m in Text(m.label).tag(m) }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(mode.label)
                            Image(systemName: "chevron.down")
                        }
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.horizontal).padding(.vertical, 8)

                Group {
                    if isSearching {
                        ProgressView("찾는 중 …").frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if results.isEmpty {
                        ContentUnavailableView(
                            hasSearched ? "결과 없음" : "구절 검색",
                            systemImage: "magnifyingglass",
                            description: Text(hasSearched
                                ? "‘\(query)’이(가) 들어간 구절을 찾지 못했습니다."
                                : (scope == .current
                                   ? "두 글자 이상 입력하면 「\(edition.shortName)」에서 찾습니다."
                                   : "두 글자 이상 입력하면 수록된 모든 판본에서 찾습니다."))
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
                        prompt: searchPrompt)
            .onSubmit(of: .search) { runSearch() }
            .onChange(of: query) { runSearch() }
            .onChange(of: scope) { runSearch() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
            }
        }
    }

    private var searchPrompt: String {
        switch mode {
        case .text: return "말씀 검색 (예: 사랑 OR love)"
        case .bookName: return "명칭 검색 (예: 창세기, 마태)"
        case .reference: return "장:절 검색 (예: 1:1, 2:3-5)"
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
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else {
            results = []; hasSearched = false; isSearching = false
            return
        }
        let currentEdition = readingState.selectedEdition
        let editionsToSearch = store.loadedEditions
        let scope = scope
        let mode = mode
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            isSearching = true
            let hits: [SearchHit]
            if scope == .all {
                hits = await store.searchAll(text, editions: editionsToSearch, mode: mode)
            } else {
                hits = await store.search(text, edition: currentEdition, mode: mode)
            }
            guard !Task.isCancelled else { return }
            results = hits
            hasSearched = true
            isSearching = false
        }
    }
}
