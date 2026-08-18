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
    case results
    case commentary
    var id: String { rawValue }
    var label: String {
        switch self {
        case .current: return "현재 판본"
        case .all:     return "모든 판본"
        case .results: return "검색 결과"
        case .commentary: return "주석"
        }
    }
}

enum SearchMode: String, CaseIterable, Identifiable {
    case text
    case reference
    var id: String { rawValue }
    var label: String {
        switch self {
        case .text: return "단어찾기"
        case .reference: return "장절찾기"
        }
    }
}

struct SearchView: View {
    @Environment(BibleStore.self) private var store
    @Environment(ReadingState.self) private var readingState
    @Environment(ReaderNavigation.self) private var navigation
    @Environment(\.dismiss) private var dismiss

    @AppStorage("lastSearchQuery") private var lastSearchQuery = ""
    @AppStorage("lastSearchScope") private var lastSearchScope = SearchScope.current.rawValue
    @AppStorage("lastSearchMode") private var lastSearchMode = SearchMode.text.rawValue
    @AppStorage("textSearchHistory") private var textSearchHistoryData = "[]"
    @AppStorage("referenceSearchHistory") private var referenceSearchHistoryData = "[]"

    @State private var query = ""
    @State private var scope: SearchScope = .current
    @State private var mode: SearchMode = .text
    @State private var results: [SearchHit] = []
    @State private var previousResults: [SearchHit] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var searchTask: Task<Void, Never>?
    @State private var selectedBookID: String = ""
    @State private var selectedChapter: Int = 1
    @State private var selectedVerse: Int = 1
    @State private var selectedEditionIDs: Set<String> = []
    @State private var selectedAnnotationEditionIDs: Set<String> = []

    // 단어찾기 상태 저장
    @State private var textQuery = ""
    @State private var textResults: [SearchHit] = []
    @State private var textPreviousResults: [SearchHit] = []
    @State private var textHasSearched = false

    // 장절 찾기 상태 저장
    @State private var referenceBookID = ""
    @State private var referenceChapter = 1
    @State private var referenceVerse = 1
    @State private var referenceResults: [SearchHit] = []
    @State private var referencePreviousResults: [SearchHit] = []
    @State private var referenceHasSearched = false

    // 검색 히스토리
    @State private var textSearchHistory: [String] = []
    @State private var referenceSearchHistory: [String] = []

    // 책 선택을 위한 입력 필드
    @State private var bookSearchText = ""
    @State private var referenceQueryInput = ""

    // 검색 결과 시트
    @State private var showResults = false

    var body: some View {
        let edition = readingState.selectedEdition

        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 8) {
                        // 검색 입력 필드
                        ZStack(alignment: .topTrailing) {
                            TextField(mode == .text ? "단어 검색 (예: 사랑)" : "장절 검색 (예: 1코린 13,13)",
                                      text: $query)
                                .font(.system(size: 14, weight: .regular))
                                .padding(.vertical, 4)
                                .padding(.horizontal, 12)
                                .submitLabel(.search)
                                .onSubmit(performSearchAction)
                                .frame(minHeight: 24)

                            if !query.isEmpty {
                                Button(action: { query = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.all, 8)
                            }
                        }
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.blue, lineWidth: 2)
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                        // 검색 및 삭제 버튼
                        HStack(spacing: 12) {
                            Button(action: {
                                performSearchAction()
                                showResults = true
                            }) {
                                HStack {
                                    Image(systemName: "magnifyingglass")
                                    Text("검색")
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .font(.system(size: 14, weight: .regular))
                                .background(Color.blue)
                                .foregroundStyle(.white)
                                .cornerRadius(10)
                            }
                            .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            if !results.isEmpty {
                                Button(action: {
                                    results = []
                                    previousResults = []
                                    hasSearched = false
                                    if scope == .results {
                                        scope = .current
                                    }
                                    showResults = false
                                }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 14))
                                }
                                .frame(width: 36, height: 36)
                                .background(Color(.systemRed))
                                .foregroundStyle(.white)
                                .cornerRadius(8)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)

                        Divider().padding(.horizontal, 16)

                        // 검색 조건
                        VStack(alignment: .leading, spacing: 16) {
                            // 검색 방식 선택기 (모드 전환용, 라벨 없음)
                            Picker("검색 방식", selection: $mode) {
                                ForEach(SearchMode.allCases) { m in
                                    Text(m.label).tag(m)
                                }
                            }
                            .pickerStyle(.segmented)

                            Divider()

                            // 책 선택 및 장절 입력 (장절 모드일 때만)
                            if mode == .reference {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("장절 찾기")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)

                                    HStack(spacing: 12) {
                                        // 책 선택
                                        Picker("책", selection: $selectedBookID) {
                                            Text("책 선택").tag("")
                                            ForEach(Bible.books) { book in
                                                Text(book.name).tag(book.id)
                                            }
                                        }
                                        .pickerStyle(.menu)
                                        .frame(maxWidth: .infinity)

                                        // 장절 휠 (책 선택 후)
                                        if !selectedBookID.isEmpty {
                                            // 장 선택
                                            VStack(spacing: 4) {
                                                Button(action: { selectedChapter = max(1, selectedChapter - 1) }) {
                                                    Image(systemName: "chevron.up")
                                                        .font(.system(size: 12, weight: .semibold))
                                                        .foregroundStyle(.blue)
                                                }
                                                Text("\(selectedChapter)")
                                                    .font(.system(size: 16, weight: .semibold))
                                                    .foregroundStyle(.primary)
                                                Button(action: { selectedChapter = min(200, selectedChapter + 1) }) {
                                                    Image(systemName: "chevron.down")
                                                        .font(.system(size: 12, weight: .semibold))
                                                        .foregroundStyle(.blue)
                                                }
                                            }
                                            .frame(maxWidth: .infinity)

                                            // 절 선택
                                            VStack(spacing: 4) {
                                                Button(action: { selectedVerse = max(0, selectedVerse - 1) }) {
                                                    Image(systemName: "chevron.up")
                                                        .font(.system(size: 12, weight: .semibold))
                                                        .foregroundStyle(.blue)
                                                }
                                                Text(selectedVerse == 0 ? "전체" : String(selectedVerse))
                                                    .font(.system(size: 16, weight: .semibold))
                                                    .foregroundStyle(.primary)
                                                Button(action: { selectedVerse = min(999, selectedVerse + 1) }) {
                                                    Image(systemName: "chevron.down")
                                                        .font(.system(size: 12, weight: .semibold))
                                                        .foregroundStyle(.blue)
                                                }
                                            }
                                            .frame(maxWidth: .infinity)
                                        }
                                    }
                                }

                                Divider()
                            }

                            // 판본 선택
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("판본 선택")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button("전체선택") {
                                        selectedEditionIDs = Set(store.loadedEditions.map { $0.id })
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.blue)

                                    Button("선택해지") {
                                        selectedEditionIDs.removeAll()
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(store.loadedEditions) { edition in
                                        VStack(alignment: .leading, spacing: 4) {
                                            Button(action: {
                                                if selectedEditionIDs.contains(edition.id) {
                                                    selectedEditionIDs.remove(edition.id)
                                                } else {
                                                    selectedEditionIDs.insert(edition.id)
                                                }
                                            }) {
                                                HStack(spacing: 8) {
                                                    Image(systemName: selectedEditionIDs.contains(edition.id) ? "checkmark.square.fill" : "square")
                                                        .font(.body)
                                                        .foregroundStyle(selectedEditionIDs.contains(edition.id) ? .blue : .secondary)
                                                    Text(edition.name)
                                                        .font(.caption)
                                                        .foregroundStyle(.primary)
                                                        .lineLimit(1)
                                                    Spacer()
                                                }
                                            }
                                            .buttonStyle(.plain)

                                            // 주석 포함 옵션 (주석성경, NABRE 판본만)
                                            if hasAnnotationSupport(edition) && selectedEditionIDs.contains(edition.id) {
                                                Button(action: {
                                                    if selectedAnnotationEditionIDs.contains(edition.id) {
                                                        selectedAnnotationEditionIDs.remove(edition.id)
                                                    } else {
                                                        selectedAnnotationEditionIDs.insert(edition.id)
                                                    }
                                                }) {
                                                    HStack(spacing: 8) {
                                                        Image(systemName: selectedAnnotationEditionIDs.contains(edition.id) ? "checkmark.square.fill" : "square")
                                                            .font(.caption)
                                                            .foregroundStyle(selectedAnnotationEditionIDs.contains(edition.id) ? .blue : .secondary)
                                                        Text("주석 포함")
                                                            .font(.caption2)
                                                            .foregroundStyle(.secondary)
                                                        Spacer()
                                                    }
                                                }
                                                .buttonStyle(.plain)
                                                .padding(.leading, 24)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        Divider().padding(.horizontal, 16)

                        // 최근 검색 (텍스트 검색용)
                        if mode == .text && !textSearchHistory.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("최근 검색")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button("전체 지우기") {
                                        clearTextSearchHistory()
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(textSearchHistory, id: \.self) { item in
                                            HStack(spacing: 4) {
                                                Button {
                                                    query = item
                                                    runSearch()
                                                    showResults = true
                                                } label: {
                                                    Text(item)
                                                        .lineLimit(1)
                                                        .font(.caption)
                                                }

                                                Button {
                                                    removeFromTextSearchHistory(item)
                                                } label: {
                                                    Image(systemName: "xmark")
                                                        .font(.caption2.weight(.semibold))
                                                }
                                            }
                                            .padding(.horizontal, 10).padding(.vertical, 6)
                                            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                                            .foregroundStyle(Color.accentColor)
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                            .padding(.vertical, 8)
                        }

                        // 최근 검색 (장절 검색용)
                        if mode == .reference && !referenceSearchHistory.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("최근 검색")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button("전체 지우기") {
                                        clearReferenceSearchHistory()
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(referenceSearchHistory, id: \.self) { item in
                                            HStack(spacing: 4) {
                                                Button {
                                                    let parts = item.split(separator: " ", maxSplits: 1).map(String.init)
                                                    if parts.count >= 2 {
                                                        let bookAbbrev = parts[0]
                                                        let reference = parts[1]

                                                        if let book = Bible.books.first(where: { $0.abbrev == bookAbbrev }) {
                                                            selectedBookID = book.id
                                                            if let comma = reference.firstIndex(of: ",") {
                                                                let chapterStr = String(reference[..<comma])
                                                                let verseStr = String(reference[reference.index(after: comma)...])
                                                                if let chapter = Int(chapterStr), let verse = Int(verseStr) {
                                                                    selectedChapter = chapter
                                                                    selectedVerse = verse
                                                                    runSearch()
                                                                    showResults = true
                                                                }
                                                            }
                                                        }
                                                    }
                                                } label: {
                                                    Text(item)
                                                        .lineLimit(1)
                                                        .font(.caption)
                                                }

                                                Button {
                                                    removeFromReferenceSearchHistory(item)
                                                } label: {
                                                    Image(systemName: "xmark")
                                                        .font(.caption2.weight(.semibold))
                                                }
                                            }
                                            .padding(.horizontal, 10).padding(.vertical, 6)
                                            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                                            .foregroundStyle(Color.accentColor)
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
            .navigationTitle("검색")
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $showResults) {
                NavigationStack {
                    ZStack {
                        if isSearching {
                            ProgressView("찾는 중 …")
                        } else if results.isEmpty {
                            ContentUnavailableView(
                                hasSearched ? "결과 없음" : "구절 검색",
                                systemImage: "magnifyingglass",
                                description: Text(hasSearched
                                    ? (mode == .text
                                       ? "'\(query)'이(가) 들어간 구절을 찾지 못했습니다."
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
                                            highlightedText(hit.text, query: query, mode: mode)
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
                    .navigationTitle("검색 결과 (\(results.count)개)")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("닫기") { showResults = false }
                        }
                    }
                }
            }
            .onChange(of: query) { _, newQuery in
                // Only save query history, don't search
                if !newQuery.isEmpty {
                    lastSearchQuery = newQuery
                }
            }
            .onChange(of: scope) { _, newScope in
                lastSearchScope = newScope.rawValue
                runSearch()
            }
            .onChange(of: mode) { _, newMode in
                // 현재 mode의 상태 저장
                if mode == .text {
                    textQuery = query
                    textResults = results
                    textPreviousResults = previousResults
                    textHasSearched = hasSearched
                    bookSearchText = ""
                    referenceQueryInput = ""
                } else {
                    referenceBookID = selectedBookID
                    referenceChapter = selectedChapter
                    referenceVerse = selectedVerse
                    referenceResults = results
                    referencePreviousResults = previousResults
                    referenceHasSearched = hasSearched
                }

                // 새 mode의 상태 복원
                if newMode == .text {
                    query = textQuery
                    results = textResults
                    previousResults = textPreviousResults
                    hasSearched = textHasSearched
                    selectedBookID = ""
                    selectedChapter = 1
                    selectedVerse = 1
                } else {
                    selectedBookID = referenceBookID
                    selectedChapter = referenceChapter
                    selectedVerse = referenceVerse
                    results = referenceResults
                    previousResults = referencePreviousResults
                    hasSearched = referenceHasSearched
                    // Set bookSearchText when entering reference mode
                    if let book = Bible.book(referenceBookID) {
                        bookSearchText = book.name
                    } else {
                        bookSearchText = ""
                    }
                }

                lastSearchMode = newMode.rawValue
            }
            .onAppear {
                loadSearchHistory()
                if selectedEditionIDs.isEmpty {
                    selectedEditionIDs = Set(store.loadedEditions.map { $0.id })
                }
                if query.isEmpty && !lastSearchQuery.isEmpty {
                    query = lastSearchQuery
                    scope = SearchScope(rawValue: lastSearchScope) ?? .current
                    mode = SearchMode(rawValue: lastSearchMode) ?? .text
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }


    private func reference(for hit: SearchHit) -> String {
        guard let book = Bible.book(hit.bookID) else { return "" }
        return "\(book.abbrev) \(hit.chapter),\(hit.verse)"
    }

    private func hasAnnotationSupport(_ edition: Edition) -> Bool {
        // 주석성경 또는 NABRE 판본만 주석 기능 지원
        let name = edition.name.lowercased()
        return name.contains("주석") || name.contains("nabre")
    }

    private func open(_ hit: SearchHit) {
        if scope == .all, Editions.edition(hit.editionID) != nil {
            readingState.selectedEditionID = hit.editionID
        }
        navigation.open(bookID: hit.bookID, chapter: hit.chapter, verse: hit.verse)
        dismiss()
    }

    private func parseAndSearch() {
        let input = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            results = []; hasSearched = false; isSearching = false
            return
        }

        // Try to parse as reference format first
        if let references = parseReferences(input) {
            // Successfully parsed as reference - switch to reference mode if needed
            if mode != .reference {
                mode = .reference
            }
            searchMultipleReferences(references, query: input)
        } else {
            // Failed to parse as reference - try as text search
            if mode != .text {
                mode = .text
            }
            // Remove book name prefix if present (e.g., "1사무 사랑" → "사랑")
            let searchText = input.split(separator: " ", maxSplits: 1).map(String.init)
            let textToSearch = searchText.count > 1 ? searchText[1] : input

            if textToSearch.count >= 2 {
                query = textToSearch
                runSearch()
            } else {
                results = []; hasSearched = true; isSearching = false
            }
        }
    }

    private func searchMultipleReferences(_ references: [(bookID: String, chapter: Int, verse: Int)], query: String = "") {
        searchTask?.cancel()

        let currentEdition = readingState.selectedEdition
        let editionsToSearch = scope == .all ? store.loadedEditions : [currentEdition]

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            isSearching = true

            var hits: [SearchHit] = []

            for (bookID, chapter, verse) in references {
                guard let book = Bible.book(bookID) else { continue }
                for edition in editionsToSearch {
                    let verses = store.verses(edition: edition, book: book, chapter: chapter)

                    if verse == 0 {
                        // verse = 0 means all verses in chapter
                        for hit in verses {
                            hits.append(SearchHit(editionID: edition.id, bookID: bookID, chapter: chapter, verse: hit.number,
                                                 text: hit.text))
                        }
                    } else {
                        // specific verse
                        if let hit = verses.first(where: { $0.number == verse }) {
                            hits.append(SearchHit(editionID: edition.id, bookID: bookID, chapter: chapter, verse: verse,
                                                 text: hit.text))
                        }
                    }
                }
            }

            guard !Task.isCancelled else { return }
            results = hits
            hasSearched = true
            isSearching = false
        }
    }

    private func parseReferences(_ input: String) -> [(bookID: String, chapter: Int, verse: Int)]? {
        let rangeStrings = input.split(separator: ";").map { String($0).trimmingCharacters(in: .whitespaces) }

        var allReferences: [(bookID: String, chapter: Int, verse: Int)] = []
        var currentBookID: String?

        for rangeStr in rangeStrings {
            guard !rangeStr.isEmpty else { continue }

            var rangeToProcess = rangeStr

            // If range doesn't start with Korean characters, try prepending the last book
            if let lastBook = currentBookID, (rangeStr.first?.isLetter ?? false) == false {
                if let book = Bible.book(lastBook) {
                    rangeToProcess = book.abbrev + " " + rangeStr
                }
            }

            if let single = parseReference(rangeToProcess) {
                currentBookID = single.0
                if let range = expandRange(single, input: rangeToProcess) {
                    allReferences.append(contentsOf: range)
                } else {
                    allReferences.append(single)
                }
            } else {
                // Try direct parsing for formats like "1사무 5,5" or "창세기 1,2"
                let pattern = try! NSRegularExpression(
                    pattern: "^(\\d?)([가-힣]+)\\s+(\\d+)[.,;]?(\\d+)?$",
                    options: []
                )
                let nsRange = NSRange(rangeStr.startIndex..<rangeStr.endIndex, in: rangeStr)

                if let match = pattern.firstMatch(in: rangeStr, range: nsRange) {
                    if let digitRange = Range(match.range(at: 1), in: rangeStr),
                       let bookRange = Range(match.range(at: 2), in: rangeStr),
                       let chapterRange = Range(match.range(at: 3), in: rangeStr) {

                        let digit = String(rangeStr[digitRange])
                        let bookName = String(rangeStr[bookRange])
                        let chapter = Int(String(rangeStr[chapterRange])) ?? 0

                        var verse = 0
                        if match.range(at: 4).location != NSNotFound,
                           let verseRange = Range(match.range(at: 4), in: rangeStr) {
                            verse = Int(String(rangeStr[verseRange])) ?? 0
                        }

                        if chapter > 0 {
                            // Try to find book using findBookByAbbrev
                            var bookID: String?
                            if let id = findBookByAbbrev(bookName, digitPrefix: digit) {
                                bookID = id
                            } else {
                                // Try with common suffixes
                                for suffix in ["기", "서", "편", "복음"] {
                                    if let id = findBookByAbbrev(bookName + suffix, digitPrefix: digit) {
                                        bookID = id
                                        break
                                    }
                                }
                            }

                            if let bookID = bookID {
                                currentBookID = bookID
                                allReferences.append((bookID, chapter, verse))
                            }
                        }
                    }
                }
            }
        }

        return allReferences.isEmpty ? nil : allReferences
    }

    private func expandRange(_ single: (String, Int, Int), input: String) -> [(String, Int, Int)]? {
        let (bookID, chapter, verse) = single

        if input.contains("-") {
            let parts = input.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
            guard parts.count == 2 else { return nil }

            let beforeRange = parts[0].trimmingCharacters(in: .whitespaces)
            let afterRange = parts[1].trimmingCharacters(in: .whitespaces)

            var startChapter = 0
            var startVerse = 1

            if let (_, c, v) = parseReference(beforeRange) {
                startChapter = c
                startVerse = v == 0 ? 1 : v // verse = 0 means all verses, use 1 as start
            } else if let c = extractChapterNumber(from: beforeRange) {
                startChapter = c
                startVerse = 1
            }

            guard startChapter > 0 else { return nil }

            var results: [(String, Int, Int)] = []

            if startChapter == chapter {
                let endVerse: Int
                if let parsedVerse = Int(afterRange), parsedVerse > 0 {
                    endVerse = parsedVerse
                } else if let (_, _, v) = parseReference(afterRange), v > 0 {
                    endVerse = v
                } else if let book = Bible.book(bookID),
                          let (_, _, v) = parseReference(book.abbrev + " " + afterRange), v > 0 {
                    endVerse = v
                } else if let v = extractVerseNumber(from: afterRange), v > 0 {
                    endVerse = v
                } else {
                    return nil
                }

                let minVerse = min(startVerse, endVerse)
                let maxVerse = max(startVerse, endVerse)

                for v in minVerse...maxVerse {
                    results.append((bookID, startChapter, v))
                }
            } else {
                let endChapter: Int
                let endVerse: Int

                if let parsedChapter = Int(afterRange), parsedChapter > 0 {
                    endChapter = parsedChapter
                    endVerse = 999
                } else if let (_, c, v) = parseReference(afterRange), c > 0 {
                    endChapter = c
                    endVerse = v == 0 ? 999 : v // verse = 0 means all verses, use 999 as end
                } else if let book = Bible.book(bookID),
                          let (_, c, v) = parseReference(book.abbrev + " " + afterRange), c > 0 {
                    endChapter = c
                    endVerse = v == 0 ? 999 : v
                } else if let c = extractChapterNumber(from: afterRange), c > 0 {
                    endChapter = c
                    endVerse = 999
                } else {
                    return nil
                }

                var chap1 = startChapter
                var verse1 = startVerse
                var chap2 = endChapter
                var verse2 = endVerse

                if chap1 > chap2 || (chap1 == chap2 && verse1 > verse2) {
                    (chap1, verse1, chap2, verse2) = (chap2, verse2, chap1, verse1)
                }

                for c in chap1...chap2 {
                    if c == chap1 && c == chap2 {
                        for v in verse1...verse2 {
                            results.append((bookID, c, v))
                        }
                    } else if c == chap1 {
                        for v in verse1...999 {
                            results.append((bookID, c, v))
                        }
                    } else if c == chap2 {
                        for v in 1...verse2 {
                            results.append((bookID, c, v))
                        }
                    } else {
                        results.append((bookID, c, 1))
                    }
                }
            }

            return results.isEmpty ? nil : results
        } else {
            // Handle simple references without range (e.g., "창세 1" or "1사무 10")
            // Single chapter or single verse reference
            var results: [(String, Int, Int)] = []

            if verse == 0 {
                // Chapter only (e.g., "창세 1" means entire chapter 1)
                // Return all verses in the chapter as individual entries
                for v in 1...999 {
                    results.append((bookID, chapter, v))
                }
            } else {
                // Single verse reference
                results.append((bookID, chapter, verse))
            }

            return results.isEmpty ? nil : results
        }
    }

    private func parseReference(_ input: String) -> (String, Int, Int)? {
        let versePattern = try! NSRegularExpression(pattern: "(\\d{1,3})\\s*[.,:;]\\s*(\\d{1,3})", options: [])
        let chapterOnlyPattern = try! NSRegularExpression(pattern: "(\\d{1,3})\\s*$", options: [])
        let verseRange = NSRange(input.startIndex..<input.endIndex, in: input)

        var chapter = 0, verse = 0, versePart: Range<String.Index>?

        // Try to match verse pattern (e.g., "13,13" or "13:13")
        if let verseMatch = versePattern.firstMatch(in: input, range: verseRange),
           let chapterRange = Range(verseMatch.range(at: 1), in: input),
           let verseStrRange = Range(verseMatch.range(at: 2), in: input),
           let ch = Int(input[chapterRange]),
           let v = Int(input[verseStrRange]),
           let vPart = Range(verseMatch.range, in: input) {
            chapter = ch
            verse = v
            versePart = vPart
        }
        // Try to match chapter-only pattern (e.g., "13")
        else if let chapterMatch = chapterOnlyPattern.firstMatch(in: input, range: verseRange),
                let chapterRange = Range(chapterMatch.range(at: 1), in: input),
                let ch = Int(input[chapterRange]),
                let cPart = Range(chapterMatch.range, in: input) {
            chapter = ch
            verse = 0 // 0 indicates "all verses in chapter"
            versePart = cPart
        } else {
            return nil
        }

        guard let versionPart = versePart else { return nil }
        let bookPartRaw = String(input[..<versionPart.lowerBound]).trimmingCharacters(in: .whitespaces)
        guard !bookPartRaw.isEmpty else { return nil }

        // Extract book name (handles "코린", "1코린", "사무엘기 상" formats)
        var bookName = ""
        var digitPrefix = ""

        for char in bookPartRaw {
            if char.isNumber && "123".contains(char) {
                if bookName.isEmpty {
                    digitPrefix.append(char)
                } else {
                    break
                }
            } else if ("가"..."힣").contains(char) {
                bookName.append(char)
            } else if char.isWhitespace {
                // Skip whitespace, continue to next char
                continue
            } else if !bookName.isEmpty {
                break
            }
        }

        if !bookName.isEmpty {
            if let bookID = findBookByAbbrev(bookName, digitPrefix: digitPrefix) {
                return (bookID, chapter, verse)
            }

            // Try with common suffixes if not found
            for suffix in ["기", "서", "편", "복음"] {
                if let bookID = findBookByAbbrev(bookName + suffix, digitPrefix: digitPrefix) {
                    return (bookID, chapter, verse)
                }
            }
        }

        return nil
    }

    private func findBookByAbbrev(_ abbrev: String, digitPrefix: String = "") -> String? {
        let searchAbbrev = digitPrefix + abbrev
        let searchInput = abbrev + digitPrefix

        for book in Bible.books {
            let variants = generateBookVariants(from: book.abbrev)
            let lowerBookAbbrev = book.abbrev.lowercased()

            if book.abbrev == searchAbbrev || book.abbrev == searchInput {
                return book.id
            }

            if !digitPrefix.isEmpty {
                if lowerBookAbbrev == searchAbbrev.lowercased() ||
                   lowerBookAbbrev == searchInput.lowercased() {
                    return book.id
                }

                for variant in variants {
                    if variant == searchAbbrev || variant == searchInput ||
                       variant.lowercased() == searchAbbrev.lowercased() ||
                       variant.lowercased() == searchInput.lowercased() {
                        return book.id
                    }
                }

                if book.shortName.contains(abbrev) && book.shortName.contains(digitPrefix) {
                    return book.id
                }
            } else {
                if book.abbrev == abbrev {
                    return book.id
                }

                if lowerBookAbbrev == abbrev.lowercased() {
                    return book.id
                }

                for variant in variants {
                    if variant == abbrev ||
                       variant.lowercased() == abbrev.lowercased() {
                        return book.id
                    }
                }
            }
        }

        for book in Bible.books {
            let bookNameBase = extractBookNameBase(from: book.abbrev)
            let inputBase = extractBookNameBase(from: abbrev)

            if bookNameBase.lowercased() == inputBase.lowercased() &&
               (digitPrefix.isEmpty || book.abbrev.contains(digitPrefix)) {
                return book.id
            }

            // Try partial matching (e.g., "사무" matches "사무엘상")
            if bookNameBase.lowercased().contains(inputBase.lowercased()) &&
               !inputBase.isEmpty &&
               (digitPrefix.isEmpty || book.abbrev.contains(digitPrefix)) {
                return book.id
            }
        }

        // Try matching with common Korean suffixes removed
        let inputClean = abbrev.replacingOccurrences(of: "복음서", with: "")
                               .replacingOccurrences(of: "오", with: "")
                               .replacingOccurrences(of: "코", with: "")
                               .replacingOccurrences(of: "서", with: "")

        if inputClean != abbrev {
            for book in Bible.books {
                if book.abbrev == inputClean ||
                   book.abbrev.lowercased() == inputClean.lowercased() {
                    return book.id
                }
            }
        }

        // Try matching with full name or short name (e.g., "사무엘기 상권")
        let searchText = abbrev.lowercased()
        for book in Bible.books {
            if book.name == abbrev ||
               book.name.lowercased() == searchText ||
               book.shortName == abbrev ||
               book.shortName.lowercased() == searchText {
                return book.id
            }
        }

        return nil
    }

    private func generateBookVariants(from abbrev: String) -> [String] {
        var variants: [String] = []

        let digit = abbrev.first?.isNumber == true ? String(abbrev.first!) : ""
        let withoutDigit = abbrev.filter { !$0.isNumber }

        if !digit.isEmpty {
            variants.append(digit + withoutDigit)
            variants.append(withoutDigit + digit)
            variants.append(withoutDigit)
        }

        if abbrev.contains("서") || abbrev.contains("편") || abbrev.contains("기") {
            let cleaned = abbrev.replacingOccurrences(of: "서", with: "")
                                .replacingOccurrences(of: "편", with: "")
                                .replacingOccurrences(of: "기", with: "")
            if !cleaned.isEmpty && cleaned != abbrev {
                variants.append(cleaned)
                variants.append(digit + cleaned.filter { !$0.isNumber })
            }
        }

        if abbrev.contains("복음") {
            variants.append(abbrev.replacingOccurrences(of: "복음", with: ""))
        }

        return variants
    }

    private func extractBookNameBase(from abbrev: String) -> String {
        var result = abbrev
        result = result.filter { !$0.isNumber }
        result = result.replacingOccurrences(of: "서", with: "")
        result = result.replacingOccurrences(of: "편", with: "")
        result = result.replacingOccurrences(of: "기", with: "")
        result = result.replacingOccurrences(of: "복음", with: "")
        return result
    }

    private func extractChapterNumber(from text: String) -> Int? {
        let pattern = try! NSRegularExpression(pattern: "\\d{1,3}", options: [])
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        if let match = pattern.firstMatch(in: text, range: range),
           let numberRange = Range(match.range, in: text),
           let chapter = Int(text[numberRange]) {
            return chapter
        }
        return nil
    }

    private func extractVerseNumber(from text: String) -> Int? {
        let pattern = try! NSRegularExpression(pattern: "\\d{1,3}", options: [])
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        if let match = pattern.firstMatch(in: text, range: range),
           let numberRange = Range(match.range, in: text),
           let verse = Int(text[numberRange]) {
            return verse
        }
        return nil
    }


    private func runSearch() {
        searchTask?.cancel()

        if mode == .text {
            let fullQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let isExplicitPartial = fullQuery.starts(with: "*")
            let text = isExplicitPartial ? String(fullQuery.dropFirst()) : fullQuery

            guard text.count >= 2 else {
                results = []; hasSearched = false; isSearching = false
                return
            }

            // 검색 결과 내에서 재검색
            if scope == .results {
                let filtered = previousResults.filter { hit in
                    hit.text.localizedCaseInsensitiveContains(text)
                }
                results = filtered
                addToTextSearchHistory(text)
                hasSearched = true
                isSearching = false
                return
            }

            let currentEdition = readingState.selectedEdition
            let editionsToSearch: [Edition]
            if scope == .commentary {
                editionsToSearch = store.loadedEditions.filter { edition in
                    selectedEditionIDs.contains(edition.id) && selectedAnnotationEditionIDs.contains(edition.id)
                }
            } else if scope == .all {
                editionsToSearch = store.loadedEditions.filter { selectedEditionIDs.contains($0.id) }
            } else {
                editionsToSearch = [currentEdition]
            }

            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                isSearching = true
                let hits: [SearchHit]
                if scope == .all || scope == .commentary {
                    hits = await store.searchAll(text, editions: editionsToSearch, mode: .text)
                } else {
                    hits = await store.search(text, edition: currentEdition, mode: .text)
                }
                guard !Task.isCancelled else { return }
                previousResults = hits
                results = hits
                addToTextSearchHistory(text)
                hasSearched = true
                isSearching = false
            }
        } else {
            // Reference mode: search with selected book/chapter/verse or query
            let input = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if !input.isEmpty {
                // Input exists - parse as reference
                if let references = parseReferences(input) {
                    // Directly call searchMultipleReferences with proper scope handling
                    searchTask?.cancel()

                    let currentEdition = readingState.selectedEdition
                    let editionsToSearch: [Edition]
                    if scope == .commentary {
                        editionsToSearch = store.loadedEditions.filter { edition in
                            selectedEditionIDs.contains(edition.id) && selectedAnnotationEditionIDs.contains(edition.id)
                        }
                    } else if scope == .all {
                        editionsToSearch = store.loadedEditions.filter { selectedEditionIDs.contains($0.id) }
                    } else {
                        editionsToSearch = [currentEdition]
                    }

                    searchTask = Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        guard !Task.isCancelled else { return }
                        isSearching = true

                        var hits: [SearchHit] = []

                        for (bookID, chapter, verse) in references {
                            guard let book = Bible.book(bookID) else { continue }
                            for edition in editionsToSearch {
                                let verses = store.verses(edition: edition, book: book, chapter: chapter)

                                if verse == 0 {
                                    // verse = 0 means all verses in chapter
                                    for hit in verses {
                                        hits.append(SearchHit(editionID: edition.id, bookID: bookID, chapter: chapter, verse: hit.number,
                                                             text: hit.text))
                                    }
                                } else {
                                    // specific verse
                                    if let hit = verses.first(where: { $0.number == verse }) {
                                        hits.append(SearchHit(editionID: edition.id, bookID: bookID, chapter: chapter, verse: verse,
                                                             text: hit.text))
                                    }
                                }
                            }
                        }

                        await MainActor.run {
                            results = hits
                            hasSearched = true
                            isSearching = false
                        }
                    }
                } else {
                    // Shouldn't reach here if onSubmit handled it correctly
                    // But as fallback, just clear results
                    results = []
                    hasSearched = true
                    isSearching = false
                }
            } else if !selectedBookID.isEmpty {
                // If query is empty but selectedBookID is set, search with current selection
                let currentEdition = readingState.selectedEdition
                let editionsToSearch: [Edition]
                if scope == .commentary {
                    editionsToSearch = store.loadedEditions.filter { edition in
                        selectedEditionIDs.contains(edition.id) && selectedAnnotationEditionIDs.contains(edition.id)
                    }
                } else if scope == .all {
                    editionsToSearch = store.loadedEditions.filter { selectedEditionIDs.contains($0.id) }
                } else {
                    editionsToSearch = [currentEdition]
                }
                let chapter = selectedChapter
                let verse = selectedVerse
                let bookID = selectedBookID

                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    isSearching = true

                    var hits: [SearchHit] = []
                    guard let book = Bible.book(bookID) else { return }
                    for edition in editionsToSearch {
                        let verses = store.verses(edition: edition, book: book, chapter: chapter)
                        if verse == 0 {
                            // verse = 0 means all verses in chapter
                            for hit in verses {
                                hits.append(SearchHit(editionID: edition.id, bookID: bookID, chapter: chapter, verse: hit.number,
                                                     text: hit.text))
                            }
                        } else if let hit = verses.first(where: { $0.number == verse }) {
                            hits.append(SearchHit(editionID: edition.id, bookID: bookID, chapter: chapter, verse: verse,
                                                 text: hit.text))
                        }
                    }

                    guard !Task.isCancelled else { return }
                    results = hits
                    hasSearched = true
                    isSearching = false

                    await MainActor.run {
                        addToReferenceSearchHistory(bookID: bookID, chapter: chapter, verse: verse)
                    }
                }
            } else {
                results = []; hasSearched = false; isSearching = false
            }
        }
    }

    private func highlightedText(_ text: String, query: String, mode: SearchMode) -> some View {
        guard !query.isEmpty && mode == .text else {
            return Text(text)
        }

        let searchTerm = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "*", with: "")

        guard !searchTerm.isEmpty else { return Text(text) }

        var attributedString = AttributedString(text)
        let lowercaseText = text.lowercased()

        // Extract search terms from the query (handles logical operators)
        let hasOperators = containsLogicalOperators(searchTerm)
        let termsToHighlight: [String]
        if hasOperators {
            termsToHighlight = extractSearchTerms(from: searchTerm)
        } else {
            termsToHighlight = [searchTerm]
        }

        // Highlight all search terms
        for term in termsToHighlight {
            let lowerTerm = term.lowercased()
            var searchStartIndex = lowercaseText.startIndex
            while let range = lowercaseText.range(of: lowerTerm, range: searchStartIndex..<lowercaseText.endIndex) {
                if let attrRange = Range(range, in: attributedString) {
                    attributedString[attrRange].backgroundColor = .yellow
                    attributedString[attrRange].foregroundColor = .white
                }

                searchStartIndex = range.upperBound
            }
        }

        return Text(attributedString)
    }

    private func performSearchAction() {
        let input = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        print("[DEBUG] performSearchAction: input='\(input)', currentScope=\(scope)")

        // Auto-detect format and execute search directly
        if let references = parseReferences(input) {
            print("[DEBUG] parseReferences succeeded: \(references)")
            // It's a reference format - execute reference search
            mode = .reference
            performReferenceSearch(references, scope: scope)
        } else {
            print("[DEBUG] parseReferences failed, treating as text search")
            // It's text search - reset scope to .current and execute
            mode = .text
            let textSearchScope = SearchScope.current
            performTextSearch(input, scope: textSearchScope)
            scope = textSearchScope
        }
    }

    private func containsLogicalOperators(_ query: String) -> Bool {
        query.contains("&&") || query.contains("||") || query.contains("!")
    }

    private func splitByOperator(_ expression: String, by opStr: String) -> [String] {
        var results: [String] = []
        var current = ""
        var i = 0
        let chars = Array(expression)
        let opLen = opStr.count

        while i < chars.count {
            if i <= chars.count - opLen {
                let slice = String(chars[i..<(i + opLen)])
                if slice == opStr {
                    if !current.isEmpty {
                        results.append(current.trimmingCharacters(in: .whitespaces))
                    }
                    current = ""
                    i += opLen
                    continue
                }
            }
            current.append(chars[i])
            i += 1
        }
        if !current.isEmpty {
            results.append(current.trimmingCharacters(in: .whitespaces))
        }
        return results
    }

    private func evaluateLogicalExpression(_ text: String, expression: String) -> Bool {
        let lowercaseText = text.lowercased()
        let orParts = splitByOperator(expression, by: "||")

        // Evaluate OR conditions
        for orPart in orParts {
            if evaluateANDExpression(lowercaseText, expression: orPart) {
                return true
            }
        }
        return false
    }

    private func evaluateANDExpression(_ text: String, expression: String) -> Bool {
        let andParts = splitByOperator(expression, by: "&&")

        // Evaluate AND conditions
        for andPart in andParts {
            if !evaluateNOTExpression(text, expression: andPart) {
                return false
            }
        }
        return true
    }

    private func evaluateNOTExpression(_ text: String, expression: String) -> Bool {
        let trimmed = expression.trimmingCharacters(in: .whitespaces)
        if trimmed.starts(with: "!") {
            let term = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
            return !text.localizedCaseInsensitiveContains(term)
        } else {
            return text.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private func extractSearchTerms(from expression: String) -> [String] {
        var terms: [String] = []
        let components = splitByOperator(expression, by: "||")

        for component in components {
            let andTerms = splitByOperator(component, by: "&&")
            for term in andTerms {
                let cleaned = term.trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "!"))
                    .trimmingCharacters(in: .whitespaces)
                if !cleaned.isEmpty {
                    terms.append(cleaned)
                }
            }
        }

        return Array(Set(terms))
    }

    private func performTextSearch(_ text: String, scope: SearchScope) {
        let fullQuery = text
        let isExplicitPartial = fullQuery.starts(with: "*")
        let searchText = isExplicitPartial ? String(fullQuery.dropFirst()) : fullQuery

        guard searchText.count >= 1 else {
            results = []; hasSearched = false; isSearching = false
            return
        }

        let hasOperators = containsLogicalOperators(searchText)

        // Validate minimum length only for non-operator queries
        if !hasOperators && searchText.count < 2 {
            results = []; hasSearched = false; isSearching = false
            return
        }

        // 검색 결과 내에서 재검색
        if scope == .results {
            let filtered = previousResults.filter { hit in
                if hasOperators {
                    return evaluateLogicalExpression(hit.text, expression: searchText)
                } else {
                    return hit.text.localizedCaseInsensitiveContains(searchText)
                }
            }
            results = filtered
            addToTextSearchHistory(searchText)
            hasSearched = true
            isSearching = false
            return
        }

        isSearching = true
        results = []

        let currentEdition = readingState.selectedEdition
        let editionsToSearch: [Edition]
        if scope == .commentary {
            // 주석 검색: 주석 포함이 활성화된 판본만 검색
            editionsToSearch = store.loadedEditions.filter { edition in
                selectedEditionIDs.contains(edition.id) && selectedAnnotationEditionIDs.contains(edition.id)
            }
        } else if scope == .all {
            editionsToSearch = store.loadedEditions.filter { selectedEditionIDs.contains($0.id) }
        } else {
            editionsToSearch = [currentEdition]
        }

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            var hits: [SearchHit] = []
            if hasOperators {
                // For logical operator queries, extract search terms and get combined results
                let terms = extractSearchTerms(from: searchText)
                var allHits: [SearchHit] = []

                for term in terms {
                    if scope == .all || scope == .commentary {
                        let termHits = await store.searchAll(term, editions: editionsToSearch, mode: .text)
                        allHits.append(contentsOf: termHits)
                    } else {
                        let termHits = await store.search(term, edition: currentEdition, mode: .text)
                        allHits.append(contentsOf: termHits)
                    }
                }

                // Remove duplicates while preserving order
                var seen = Set<String>()
                var uniqueHits: [SearchHit] = []
                for hit in allHits {
                    let key = "\(hit.editionID)-\(hit.bookID)-\(hit.chapter)-\(hit.verse)"
                    if !seen.contains(key) {
                        seen.insert(key)
                        uniqueHits.append(hit)
                    }
                }

                // Filter using logical expression
                hits = uniqueHits.filter { hit in
                    evaluateLogicalExpression(hit.text, expression: searchText)
                }
            } else {
                // Original behavior for non-operator queries
                if scope == .all || scope == .commentary {
                    hits = await store.searchAll(searchText, editions: editionsToSearch, mode: .text)
                } else {
                    hits = await store.search(searchText, edition: currentEdition, mode: .text)
                }
            }

            guard !Task.isCancelled else { return }
            previousResults = hits
            results = hits
            addToTextSearchHistory(searchText)
            hasSearched = true
            isSearching = false
        }
    }

    private func performReferenceSearch(_ references: [(String, Int, Int)], scope: SearchScope) {
        searchTask?.cancel()
        isSearching = true
        results = []

        let currentEdition = readingState.selectedEdition
        let editionsToSearch: [Edition]
        if scope == .commentary {
            // 주석 검색: 주석 포함이 활성화된 판본만 검색
            editionsToSearch = store.loadedEditions.filter { edition in
                selectedEditionIDs.contains(edition.id) && selectedAnnotationEditionIDs.contains(edition.id)
            }
        } else if scope == .all {
            editionsToSearch = store.loadedEditions.filter { selectedEditionIDs.contains($0.id) }
        } else {
            editionsToSearch = [currentEdition]
        }

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            var hits: [SearchHit] = []

            for (bookID, chapter, verse) in references {
                guard let book = Bible.book(bookID) else { continue }
                for edition in editionsToSearch {
                    let verses = store.verses(edition: edition, book: book, chapter: chapter)

                    if verse == 0 {
                        // verse = 0 means all verses in chapter
                        for hit in verses {
                            hits.append(SearchHit(editionID: edition.id, bookID: bookID, chapter: chapter, verse: hit.number,
                                                 text: hit.text))
                        }
                    } else {
                        // specific verse
                        if let hit = verses.first(where: { $0.number == verse }) {
                            hits.append(SearchHit(editionID: edition.id, bookID: bookID, chapter: chapter, verse: verse,
                                                 text: hit.text))
                        }
                    }
                }
            }

            await MainActor.run {
                results = hits
                hasSearched = true
                isSearching = false
            }
        }
    }

    private func removeFromTextSearchHistory(_ item: String) {
        textSearchHistory.removeAll { $0 == item }
        if let encoded = try? JSONEncoder().encode(textSearchHistory),
           let json = String(data: encoded, encoding: .utf8) {
            textSearchHistoryData = json
        }
    }

    private func removeFromReferenceSearchHistory(_ item: String) {
        referenceSearchHistory.removeAll { $0 == item }
        if let encoded = try? JSONEncoder().encode(referenceSearchHistory),
           let json = String(data: encoded, encoding: .utf8) {
            referenceSearchHistoryData = json
        }
    }

    private func clearTextSearchHistory() {
        textSearchHistory.removeAll()
        textSearchHistoryData = "[]"
    }

    private func clearReferenceSearchHistory() {
        referenceSearchHistory.removeAll()
        referenceSearchHistoryData = "[]"
    }

    private func loadSearchHistory() {
        if let data = textSearchHistoryData.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            textSearchHistory = decoded
        }
        if let data = referenceSearchHistoryData.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            referenceSearchHistory = decoded
        }
    }

    private func addToTextSearchHistory(_ query: String) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        textSearchHistory.removeAll { $0 == trimmed }
        textSearchHistory.insert(trimmed, at: 0)
        if textSearchHistory.count > 20 {
            textSearchHistory.removeLast()
        }
        if let encoded = try? JSONEncoder().encode(textSearchHistory),
           let json = String(data: encoded, encoding: .utf8) {
            textSearchHistoryData = json
        }
    }

    private func addToReferenceSearchHistory(bookID: String = "", chapter: Int = 0, verse: Int = 0) {
        let targetBookID = bookID.isEmpty ? selectedBookID : bookID
        let targetChapter = chapter == 0 ? selectedChapter : chapter
        let targetVerse = verse == 0 ? selectedVerse : verse

        guard !targetBookID.isEmpty else { return }
        if let book = Bible.book(targetBookID) {
            let reference = "\(book.abbrev) \(targetChapter),\(targetVerse)"
            referenceSearchHistory.removeAll { $0 == reference }
            referenceSearchHistory.insert(reference, at: 0)
            if referenceSearchHistory.count > 20 {
                referenceSearchHistory.removeLast()
            }
            if let encoded = try? JSONEncoder().encode(referenceSearchHistory),
               let json = String(data: encoded, encoding: .utf8) {
                referenceSearchHistoryData = json
            }
        }
    }
}
