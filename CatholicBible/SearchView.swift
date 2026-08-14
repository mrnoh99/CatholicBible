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
                    let maxVerse: Int = {
                        guard let book = selectedBook else { return 1 }
                        return store.verses(edition: readingState.selectedEdition, book: book, chapter: selectedChapter)
                            .map { $0.number }.max() ?? 1
                    }()

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
                        prompt: mode == .text ? "말씀 검색 (예: 사랑 OR love)" : "장절 검색 (예: 1코린 13,13)")
            .onSubmit {
                if mode == .reference {
                    parseAndSearch()
                } else {
                    runSearch()
                }
            }
            .onChange(of: query) {
                if mode == .reference {
                    parseAndSearch()
                } else {
                    runSearch()
                }
            }
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

    private func parseAndSearch() {
        let input = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            results = []; hasSearched = false; isSearching = false
            return
        }

        if let references = parseReferences(input) {
            searchMultipleReferences(references)
        } else {
            results = []; hasSearched = true; isSearching = false
        }
    }

    private func searchMultipleReferences(_ references: [(bookID: String, chapter: Int, verse: Int)]) {
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
                    if let hit = verses.first(where: { $0.number == verse }) {
                        hits.append(SearchHit(editionID: edition.id, bookID: bookID, chapter: chapter, verse: verse,
                                             text: hit.text))
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
        if let single = parseReference(input) {
            if let range = expandRange(single, input: input) {
                return range
            } else {
                return [single]
            }
        }
        return nil
    }

    private func expandRange(_ single: (String, Int, Int), input: String) -> [(String, Int, Int)]? {
        let (bookID, chapter, verse) = single

        if input.contains("-") {
            let rangePattern = try! NSRegularExpression(pattern: "(\\d{1,3})(?:,(\\d{1,3}))?\\s*-\\s*(\\d{1,3})(?:,(\\d{1,3}))?", options: [])
            let rangeRegex = NSRange(input.startIndex..<input.endIndex, in: input)

            if let match = rangePattern.firstMatch(in: input, range: rangeRegex) {
                var results: [(String, Int, Int)] = []

                if match.numberOfRanges == 5 {
                    let startChapterRange = Range(match.range(at: 1), in: input)
                    let startVerseRange = Range(match.range(at: 2), in: input)
                    let endChapterRange = Range(match.range(at: 3), in: input)
                    let endVerseRange = Range(match.range(at: 4), in: input)

                    guard let startChapter = startChapterRange.flatMap({ Int(input[$0]) }) else { return nil }
                    let startVerse = startVerseRange.flatMap({ Int(input[$0]) }) ?? 1
                    guard let endChapter = endChapterRange.flatMap({ Int(input[$0]) }) else { return nil }
                    let endVerse = endVerseRange.flatMap({ Int(input[$0]) }) ?? (startChapter == endChapter ? 999 : 999)

                    if startChapter == endChapter {
                        for v in startVerse...min(endVerse, 999) {
                            results.append((bookID, startChapter, v))
                        }
                    } else {
                        for c in startChapter...endChapter {
                            if c == startChapter {
                                for v in startVerse...999 {
                                    results.append((bookID, c, v))
                                }
                            } else if c == endChapter {
                                for v in 1...min(endVerse, 999) {
                                    results.append((bookID, c, v))
                                }
                            } else {
                                results.append((bookID, c, 1))
                            }
                        }
                    }

                    return results.isEmpty ? nil : results
                }
            }
        }

        return nil
    }

    private func parseReference(_ input: String) -> (String, Int, Int)? {
        let versePattern = try! NSRegularExpression(pattern: "(\\d{1,3})\\s*[,:;]\\s*(\\d{1,3})", options: [])
        let verseRange = NSRange(input.startIndex..<input.endIndex, in: input)

        guard let verseMatch = versePattern.firstMatch(in: input, range: verseRange),
              let chapterRange = Range(verseMatch.range(at: 1), in: input),
              let verseStrRange = Range(verseMatch.range(at: 2), in: input),
              let chapter = Int(input[chapterRange]),
              let verse = Int(input[verseStrRange]),
              let versePart = Range(verseMatch.range, in: input) else {
            return nil
        }

        let bookPartRaw = String(input[..<versePart.lowerBound]).trimmingCharacters(in: .whitespaces)
        guard !bookPartRaw.isEmpty else { return nil }

        let bookPattern = try! NSRegularExpression(pattern: "([가-힣]+)\\s*([1-3])", options: [])
        let bookRange = NSRange(bookPartRaw.startIndex..<bookPartRaw.endIndex, in: bookPartRaw)

        if let bookMatch = bookPattern.firstMatch(in: bookPartRaw, range: bookRange),
           let koreanRange = Range(bookMatch.range(at: 1), in: bookPartRaw),
           let digitRange = Range(bookMatch.range(at: 2), in: bookPartRaw) {
            let koreanName = String(bookPartRaw[koreanRange])
            let digitPrefix = String(bookPartRaw[digitRange])

            if let bookID = findBookByAbbrev(koreanName, digitPrefix: digitPrefix) {
                return (bookID, chapter, verse)
            }
        }

        var koreanName = ""
        for char in bookPartRaw {
            if ("가"..."힣").contains(char) {
                koreanName.append(char)
            } else if char.isNumber && "123".contains(char) {
                break
            }
        }

        if !koreanName.isEmpty, let bookID = findBookByAbbrev(koreanName, digitPrefix: "") {
            return (bookID, chapter, verse)
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
                guard let book = Bible.book(selectedBookID) else { return }
                for edition in editionsToSearch {
                    let verses = store.verses(edition: edition, book: book, chapter: chapter)
                    if let hit = verses.first(where: { $0.number == verse }) {
                        hits.append(SearchHit(editionID: edition.id, bookID: selectedBookID, chapter: chapter, verse: verse,
                                             text: hit.text))
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
