//
//  ContentView.swift
//  CatholicBible
//
//  iPad에 맞춘 2단 구성: 왼쪽 사이드바(판본 선택 + 책 목차) +
//  오른쪽 화면(서재 또는 ebook 리더).
//
//  서재에는 bible.cbck.or.kr의 8가지 책(성경·주석 성경·공동번역·200주년·
//  NAB·최민순 시편·Nova Vulgata·전례 시편)이 놓인다.
//

import SwiftUI

// MARK: - 화면 이동 상태

/// 사전 조회 요청 (초기 낱말을 담아 시트로 띄운다)
struct DictionaryRequest: Identifiable {
    let id = UUID()
    var term: String = ""
}

@Observable
final class ReaderNavigation {
    var selectedBookID: String?
    /// 리더가 열릴 때 이동할 장/절 (검색·책갈피에서 설정)
    var pendingChapter: Int?
    var pendingVerse: Int?
    /// 사전 시트 요청 (nil이 아니면 사전이 열린다)
    var dictionaryRequest: DictionaryRequest?

    func open(bookID: String, chapter: Int, verse: Int? = nil) {
        pendingChapter = chapter
        pendingVerse = verse
        selectedBookID = bookID
    }

    func lookUp(_ term: String = "") {
        dictionaryRequest = DictionaryRequest(term: term)
    }
}

// MARK: - 루트 화면

struct ContentView: View {
    @Environment(ReadingState.self) private var readingState

    @State private var navigation = ReaderNavigation()
    @State private var showSearch = false
    @State private var showBookmarks = false
    @State private var showNotes = false

    var body: some View {
        @Bindable var nav = navigation
        NavigationSplitView {
            LibraryView()
                .navigationTitle("서재")
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("검색", systemImage: "magnifyingglass") { showSearch = true }
                        Button("사전", systemImage: "character.book.closed") { navigation.lookUp() }
                        Button("책갈피", systemImage: "bookmark") { showBookmarks = true }
                        Button("노트", systemImage: "note.text") { showNotes = true }
                    }
                }
        } detail: {
            if let bookID = navigation.selectedBookID, let book = Bible.book(bookID) {
                ReaderView(book: book)
                    .id(book.id) // 책이 바뀌면 리더를 새로 만든다 (판본 전환은 열 안에서)
            } else {
                ShelfView()
            }
        }
        .environment(navigation)
        .sheet(isPresented: $showSearch) {
            SearchView().environment(navigation)
        }
        .sheet(isPresented: $showBookmarks) {
            BookmarksView().environment(navigation)
        }
        .sheet(isPresented: $showNotes) {
            NotesListView().environment(navigation)
        }
        .sheet(item: $nav.dictionaryRequest) { req in
            DictionaryView(initialTerm: req.term)
        }
    }
}

// MARK: - 서재 (8가지 책)

struct ShelfView: View {
    @Environment(BibleStore.self) private var store
    @Environment(ReadingState.self) private var readingState
    @Environment(ReaderNavigation.self) private var navigation
    @Environment(ReaderSettings.self) private var settings

    private let columns = [GridItem(.adaptive(minimum: 280), spacing: 20)]

    var body: some View {
        ZStack {
            settings.theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 6) {
                        Text("가톨릭 성경 서재")
                            .font(settings.fontChoice.font(size: 32, relativeTo: .largeTitle, bold: true))
                            .foregroundStyle(settings.theme.text)
                        Text("한국천주교주교회의 bible.cbck.or.kr의 8가지 책")
                            .font(.subheadline)
                            .foregroundStyle(settings.theme.secondary)
                    }
                    .padding(.top, 40)

                    continueReadingCard

                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(Editions.all) { edition in
                            EditionCard(edition: edition) { open(edition) }
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 48)
                }
                .frame(maxWidth: 1000)
                .frame(maxWidth: .infinity)
            }
        }
        .preferredColorScheme(settings.theme.colorScheme)
    }

    /// 판본을 고르면: 시편 판본은 곧장 리더로, 나머지는 사이드바에서 책을 고르게 한다.
    private func open(_ edition: Edition) {
        readingState.selectedEditionID = edition.id
        if edition.scope == .psalter, let psalms = Bible.book("ps") {
            navigation.open(bookID: psalms.id,
                            chapter: readingState.lastChapter(edition: edition, book: psalms))
        } else if let lastID = readingState.lastBookID(edition: edition),
                  let book = Bible.book(lastID), edition.scope.contains(book) {
            navigation.open(bookID: book.id,
                            chapter: readingState.lastChapter(edition: edition, book: book))
        } else {
            navigation.selectedBookID = nil // 사이드바에서 책 선택
        }
    }

    @ViewBuilder
    private var continueReadingCard: some View {
        let edition = readingState.selectedEdition
        if let lastID = readingState.lastBookID(edition: edition),
           let book = Bible.book(lastID), edition.scope.contains(book) {
            Button {
                navigation.open(bookID: book.id,
                                chapter: readingState.lastChapter(edition: edition, book: book))
            } label: {
                Label("이어 읽기 — \(edition.shortName) · \(store.bookShortName(edition: edition, book: book)) \(book.chapterLabel(readingState.lastChapter(edition: edition, book: book)))",
                      systemImage: "book")
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - 서재 카드 (ebook 한 권)

struct EditionCard: View {
    let edition: Edition
    let action: () -> Void

    @Environment(BibleStore.self) private var store
    @Environment(ReaderSettings.self) private var settings

    var body: some View {
        let availability = store.availability(edition: edition)
        let hasAny = availability.loaded > 0

        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Image(systemName: edition.scope == .psalter ? "music.note.list" : "book.closed.fill")
                        .font(.title2)
                        .foregroundStyle(hasAny ? Color.accentColor : settings.theme.secondary)
                    Spacer()
                    Text(languageBadge)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(settings.theme.secondary.opacity(0.15)))
                        .foregroundStyle(settings.theme.secondary)
                }

                Text(edition.name)
                    .font(settings.fontChoice.font(size: 20, relativeTo: .title3, bold: true))
                    .foregroundStyle(settings.theme.text)
                    .multilineTextAlignment(.leading)

                Text(edition.summary)
                    .font(.footnote)
                    .foregroundStyle(settings.theme.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                Spacer(minLength: 4)

                Text(availabilityLabel(availability))
                    .font(.caption2)
                    .foregroundStyle(hasAny ? Color.accentColor : settings.theme.secondary.opacity(0.8))
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(settings.theme.text.opacity(0.04))
                    .stroke(settings.theme.secondary.opacity(0.25), lineWidth: 1)
            )
            .opacity(hasAny ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(edition.name), \(availabilityLabel(availability))")
    }

    private var languageBadge: String {
        switch edition.language {
        case "en": return "영어"
        case "la": return "라틴어"
        default:   return "한국어"
        }
    }

    private func availabilityLabel(_ availability: (loaded: Int, total: Int)) -> String {
        if availability.loaded == 0 { return "본문 준비 중" }
        let unit = edition.scope == .psalter ? "편" : "권"
        if edition.scope == .psalter {
            return "수록됨"
        }
        return "본문 수록: \(availability.loaded)\(unit) / \(availability.total)\(unit)"
    }
}

#Preview {
    ContentView()
        .environment(BibleStore())
        .environment(ReaderSettings())
        .environment(ReadingState())
}
