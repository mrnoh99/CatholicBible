//
//  SearchView.swift
//  CatholicBible
//
//  수록된 모든 책에서 구절 검색. 결과를 누르면 해당 장·절로 이동한다.
//

import SwiftUI

struct SearchView: View {
    @Environment(BibleStore.self) private var store
    @Environment(ReaderNavigation.self) private var navigation
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [SearchHit] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Group {
                if isSearching {
                    ProgressView("찾는 중 …")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if results.isEmpty {
                    ContentUnavailableView(
                        hasSearched ? "결과 없음" : "구절 검색",
                        systemImage: "magnifyingglass",
                        description: Text(hasSearched
                                          ? "‘\(query)’이(가) 들어간 구절을 찾지 못했습니다."
                                          : "두 글자 이상 입력하면 수록된 모든 책에서 찾습니다.")
                    )
                } else {
                    List(results) { hit in
                        Button {
                            navigation.open(bookID: hit.bookID, chapter: hit.chapter, verse: hit.verse)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(reference(for: hit))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                                Text(hit.text)
                                    .font(.subheadline)
                                    .lineLimit(3)
                            }
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("검색")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "말씀 검색 (예: 사랑, 빛)")
            .onSubmit(of: .search) { runSearch() }
            .onChange(of: query) { runSearch() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }

    private func reference(for hit: SearchHit) -> String {
        guard let book = Bible.book(hit.bookID) else { return "" }
        return "\(book.abbrev) \(hit.chapter),\(hit.verse)"
    }

    private func runSearch() {
        searchTask?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else {
            results = []
            hasSearched = false
            isSearching = false
            return
        }
        searchTask = Task {
            // 타이핑이 멈춘 뒤에만 검색 (디바운스)
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            isSearching = true
            let hits = await store.search(text)
            guard !Task.isCancelled else { return }
            results = hits
            hasSearched = true
            isSearching = false
        }
    }
}
