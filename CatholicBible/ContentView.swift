//
//  ContentView.swift
//  CatholicBible
//
//  iPad에 맞춘 2단 구성: 왼쪽 사이드바(판본 선택 + 책 목차) +
//  오른쪽 화면(서재 또는 ebook 리더).
//
//  서재에는 천주교회의 아홉가지 책이 놓인다.
//

import SwiftUI

// MARK: - 화면 이동 상태

/// 사전 조회 요청 (초기 낱말을 담아 시트로 띄운다)
struct DictionaryRequest: Identifiable {
    let id = UUID()
    var term: String = ""
}

/// 강조할 절 범위. 오늘의 말씀 '본문 읽기'처럼 여러 절에 걸친 독서는
/// 시작 절만이 아니라 범위 전체를 칠한다. 불연속 독서(예: "1-4.6-8")는
/// 빠진 절(5절)을 칠하지 않도록 구간(segment) 목록으로 담는다.
struct VerseHighlight: Equatable {
    /// 한 강조 구간: 같은 장의 low~high 절.
    struct Segment: Equatable { var chapter: Int; var low: Int; var high: Int }

    /// 이 강조가 속한 책. 다른 책을 볼 때는 칠하지 않도록 대조한다.
    var bookID: String = ""
    var segments: [Segment]
    /// 스크롤을 맞출 시작 위치.
    var startChapter: Int
    var startVerse: Int

    /// 연속 범위(한 절 또는 시작~끝) 편의 생성자.
    init(startChapter: Int, startVerse: Int, endChapter: Int? = nil,
         endVerse: Int? = nil, bookID: String = "") {
        let ec = endChapter ?? startChapter
        let ev = endVerse ?? startVerse
        var segs: [Segment] = []
        if ec == startChapter {
            segs.append(Segment(chapter: startChapter, low: startVerse, high: max(ev, startVerse)))
        } else {
            segs.append(Segment(chapter: startChapter, low: startVerse, high: Int.max))
            var c = startChapter + 1
            while c < ec { segs.append(Segment(chapter: c, low: 1, high: Int.max)); c += 1 }
            segs.append(Segment(chapter: ec, low: 1, high: ev))
        }
        self.bookID = bookID
        self.segments = segs
        self.startChapter = startChapter
        self.startVerse = startVerse
    }

    /// 구간을 직접 준다(불연속 독서용).
    init(segments: [Segment], startChapter: Int, startVerse: Int, bookID: String = "") {
        self.bookID = bookID
        self.segments = segments.isEmpty
            ? [Segment(chapter: startChapter, low: startVerse, high: startVerse)]
            : segments
        self.startChapter = startChapter
        self.startVerse = startVerse
    }

    /// 지금 보고 있는 (책·장)의 이 절이 강조 구간에 드는가.
    func matches(bookID: String, chapter: Int, verse: String) -> Bool {
        guard self.bookID == bookID else { return false }
        guard let verseNum = Int(verse) else { return false }
        return segments.contains { $0.chapter == chapter && verseNum >= $0.low && verseNum <= $0.high }
    }
}

/// 네비게이션 히스토리 항목
struct NavigationHistoryItem: Equatable {
    let bookID: String
    let chapter: Int
}

@Observable
final class ReaderNavigation {
    var selectedBookID: String?
    /// 리더가 열릴 때 이동할 장 (검색·책갈피·오늘의 말씀에서 설정)
    var pendingChapter: Int?
    /// 이 대기 이동이 향하는 책. 책이 바뀌는 순간 사라지는 옛 리더가 잘못
    /// 대기값을 먹지 않도록, 목표 책과 일치하는 리더만 소비하게 한다.
    var pendingBookID: String?
    /// 지속되는 강조. 판본을 바꾸거나 장을 넘겨도 유지되고,
    /// 오늘의 미사를 다시 열면(또는 다른 독서를 고르면) 교체·해제된다.
    var activeHighlight: VerseHighlight?
    /// 사전 시트 요청 (nil이 아니면 사전이 열린다)
    var dictionaryRequest: DictionaryRequest?
    /// 주석 검색에서 하이라이트할 쿼리
    var searchQuery: String = ""
    /// 주석 검색 여부
    var isAnnotationSearch: Bool = false
    /// 검색에서 선택한 주석 번호 (스크롤용)
    var selectedAnnotationNumber: String?

    /// 네비게이션 히스토리
    private var history: [NavigationHistoryItem] = []
    /// 현재 히스토리 위치 (history 배열의 인덱스)
    private var historyIndex: Int = -1

    /// 한 절 또는 연속 범위로 연다(검색·책갈피 등).
    func open(bookID: String, chapter: Int, verse: Int? = nil,
              verseEnd: Int? = nil, endChapter: Int? = nil) {
        let hl = verse.map {
            VerseHighlight(startChapter: chapter, startVerse: $0,
                           endChapter: endChapter, endVerse: verseEnd, bookID: bookID)
        }
        open(bookID: bookID, chapter: chapter, highlight: hl)
    }

    /// 불연속 구간까지 담은 강조로 연다(오늘의 말씀 '본문 읽기').
    func open(bookID: String, chapter: Int, highlight: VerseHighlight?) {
        var hl = highlight
        hl?.bookID = bookID
        activeHighlight = hl
        pendingBookID = bookID
        pendingChapter = chapter
        selectedBookID = bookID

        // 히스토리 추가
        addToHistory(bookID: bookID, chapter: chapter)
    }

    /// 히스토리에 항목 추가
    private func addToHistory(bookID: String, chapter: Int) {
        let item = NavigationHistoryItem(bookID: bookID, chapter: chapter)

        // 현재 위치 이후의 앞으로가기 히스토리 제거
        if historyIndex >= 0 && historyIndex < history.count - 1 {
            history.removeSubrange((historyIndex + 1)...)
        }

        // 마지막 항목과 같으면 추가하지 않음 (중복 방지)
        if history.last != item {
            history.append(item)
            historyIndex = history.count - 1
        }
    }

    /// 이전 페이지로 돌아가기
    func goBack() {
        guard historyIndex > 0 else { return }
        historyIndex -= 1
        let item = history[historyIndex]
        pendingBookID = item.bookID
        pendingChapter = item.chapter
        selectedBookID = item.bookID
    }

    /// 다음 페이지로 이동 (뒤로가기 후)
    func goForward() {
        guard historyIndex < history.count - 1 else { return }
        historyIndex += 1
        let item = history[historyIndex]
        pendingBookID = item.bookID
        pendingChapter = item.chapter
        selectedBookID = item.bookID
    }

    /// 뒤로가기 가능 여부
    var canGoBack: Bool { historyIndex > 0 }

    /// 앞으로가기 가능 여부
    var canGoForward: Bool { historyIndex < history.count - 1 }

    /// 이 책을 여는 리더가 지금 소비할 대기 이동이 있는가.
    func hasPending(forBook bookID: String) -> Bool {
        pendingChapter != nil && (pendingBookID == nil || pendingBookID == bookID)
    }

    /// 대기 이동(장 이동)을 소비한다. 강조 자체는 activeHighlight로 계속 유지된다.
    /// 이 책의 강조 시작 절을 돌려주어(같은 책일 때) 한 번 스크롤하게 한다.
    func consumePending(forBook bookID: String) -> Int? {
        pendingBookID = nil
        guard let h = activeHighlight, h.bookID == bookID else { return nil }
        return h.startVerse
    }

    func lookUp(_ term: String = "") {
        dictionaryRequest = DictionaryRequest(term: term)
    }
}

// MARK: - 루트 화면

struct ContentView: View {
    @Environment(BibleStore.self) private var store
    @Environment(ReaderSettings.self) private var settings
    @Environment(ReadingState.self) private var readingState
    @Environment(AnnotationStore.self) private var annotations
    @Environment(KnbNotesStore.self) private var knbNotes
    @Environment(LiturgyStore.self) private var liturgy
    @Environment(\.horizontalSizeClass) private var hSize

    @State private var navigation = ReaderNavigation()
    @State private var showSearch = false
    @State private var showBookmarks = false
    @State private var showNotes = false
    @State private var showMass = false
    @State private var showSettings = false

    var body: some View {
        @Bindable var nav = navigation
        NavigationSplitView {
            LibraryView()
                .navigationTitle("서재")
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button(action: { showMass = true }) {
                            Image(systemName: "sun.max")
                        }
                        .help("오늘의 미사")
                        Button(action: { showSearch = true }) {
                            Image(systemName: "magnifyingglass")
                        }
                        .help("검색")
                        Button(action: { navigation.lookUp() }) {
                            Image(systemName: "character.book.closed")
                        }
                        .help("사전")
                        Button(action: { showBookmarks = true }) {
                            Image(systemName: "bookmark")
                        }
                        .help("책갈피")
                        Button(action: { showNotes = true }) {
                            Image(systemName: "note.text")
                        }
                        .help("노트")
                        Button(action: { showSettings = true }) {
                            Image(systemName: "gear")
                        }
                        .help("설정")
                        Menu(content: {
                            Section {
                                Button {
                                    showBookmarks = true
                                } label: {
                                    Label("책갈피", systemImage: "bookmark")
                                }
                                Button {
                                    showNotes = true
                                } label: {
                                    Label("노트", systemImage: "note.text")
                                }
                                Button {
                                    showSettings = true
                                } label: {
                                    Label("설정", systemImage: "gear")
                                }
                            }
                        }, label: {
                            Image(systemName: "ellipsis.circle")
                        })
                        .help("더보기")
                    }
                }
        } detail: {
            if let bookID = navigation.selectedBookID, let book = Bible.book(bookID) {
                ReaderView(book: book)
                    .id(book.id) // 책이 바뀌면 리더를 새로 만든다 (판본 전환은 열 안에서)
            } else {
                VStack(spacing: 0) {
                    // iPad/Mac에서 상단 메뉴 표시
                    if hSize == .regular {
                        HStack(spacing: 16) {
                            Text("성경 읽기")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity, alignment: .center)

                            Spacer()

                            Button("", systemImage: "sun.max") { showMass = true }
                                .help("오늘의 미사")
                            Button("", systemImage: "magnifyingglass") { showSearch = true }
                                .help("검색")
                            Button("", systemImage: "character.book.closed") { navigation.lookUp() }
                                .help("사전")
                            Button("", systemImage: "bookmark") { showBookmarks = true }
                                .help("책갈피")
                            Button("", systemImage: "note.text") { showNotes = true }
                                .help("노트")
                            Button("", systemImage: "gear") { showSettings = true }
                                .help("설정")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 2)
                        .background(settings.theme.background)
                        .border(settings.theme.secondary.opacity(0.1), width: 1)
                    }

                    ShelfView()
                }
            }
        }
        .environment(navigation)
        .sheet(isPresented: $showSearch) {
            injectShared(SearchView().environment(navigation))
        }
        .sheet(isPresented: $showBookmarks) {
            injectShared(BookmarksView().environment(navigation))
        }
        .sheet(isPresented: $showNotes) {
            injectShared(NotesListView().environment(navigation))
        }
        .sheet(isPresented: $showSettings) {
            injectShared(AppSettingsView())
        }
        .fullScreenCover(isPresented: $showMass) {
            injectShared(DailyMassView().environment(navigation))
        }
        .sheet(item: $nav.dictionaryRequest) { req in
            injectShared(DictionaryView(initialTerm: req.term))
        }
    }

    /// 모달에 공유 저장소를 다시 주입(Mac Catalyst 환경 전파 끊김 대비).
    private func injectShared<V: View>(_ view: V) -> some View {
        view.injectSharedStores(store, settings, readingState, annotations, knbNotes, liturgy)
    }
}

// MARK: - 서재 (8가지 책)

struct ShelfView: View {
    @Environment(BibleStore.self) private var store
    @Environment(ReadingState.self) private var readingState
    @Environment(ReaderNavigation.self) private var navigation
    @Environment(ReaderSettings.self) private var settings
    @Environment(AnnotationStore.self) private var annotations
    @Environment(KnbNotesStore.self) private var knbNotes
    @Environment(LiturgyStore.self) private var liturgy

    @State private var showMass = false

    private let columns = [GridItem(.adaptive(minimum: 280), spacing: 20)]

    var body: some View {
        ZStack {
            settings.theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 8) {
                        Text("가톨릭 성경 서재")
                            .font(.system(size: 34, weight: .bold, design: .default))
                            .foregroundStyle(settings.theme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("천주교회의 아홉가지 책과 전례 독서")
                            .font(.system(size: 15, weight: .regular, design: .default))
                            .foregroundStyle(settings.theme.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.top, 48)
                    .padding(.horizontal, 32)

                    VStack(spacing: 20) {
                        massCard
                        continueReadingCard
                    }
                    .padding(.horizontal, 32)

                    VStack(spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("모든 성경 판본")
                                    .font(.system(size: 18, weight: .semibold, design: .default))
                                    .foregroundStyle(settings.theme.text)
                                Text("새 판본을 선택하세요")
                                    .font(.system(size: 13, weight: .regular, design: .default))
                                    .foregroundStyle(settings.theme.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 32)

                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(Editions.all) { edition in
                                EditionCard(edition: edition) { open(edition) }
                            }
                        }
                        .padding(.horizontal, 32)
                    }
                    .padding(.bottom, 48)
                }
                .frame(maxWidth: 1000)
                .frame(maxWidth: .infinity)
            }
        }
        .preferredColorScheme(settings.theme.colorScheme)
        .fullScreenCover(isPresented: $showMass) {
            DailyMassView().environment(navigation)
                .injectSharedStores(store, settings, readingState, annotations, knbNotes, liturgy)
        }
    }

    /// 오늘의 미사·전례력으로 가는 카드
    @ViewBuilder
    private var massCard: some View {
        Button { showMass = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(LiturgicalCalendar.liturgicalColor().color)
                    .frame(width: 44, height: 44)
                    .background(LiturgicalCalendar.liturgicalColor().color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text("오늘의 미사")
                        .font(.system(size: 17, weight: .semibold, design: .default))
                        .foregroundStyle(settings.theme.text)
                    Text(LiturgicalCalendar.liturgicalDayName())
                        .font(.system(size: 14, weight: .regular, design: .default))
                        .foregroundStyle(settings.theme.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(settings.theme.secondary.opacity(0.6))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(LinearGradient(
                        gradient: Gradient(colors: [
                            settings.theme.text.opacity(0.04),
                            settings.theme.text.opacity(0.02)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .stroke(settings.theme.secondary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 32)
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
                HStack(spacing: 12) {
                    Image(systemName: "book.fill")
                        .font(.system(size: 18, weight: .semibold))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("이어 읽기")
                            .font(.system(size: 16, weight: .semibold, design: .default))
                        Text("\(edition.shortName) · \(store.bookShortName(edition: edition, book: book)) \(book.chapterLabel(readingState.lastChapter(edition: edition, book: book)))")
                            .font(.system(size: 13, weight: .regular, design: .default))
                            .opacity(0.8)
                    }

                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .opacity(0.6)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.accentColor.opacity(0.1))
                        .stroke(Color.accentColor.opacity(0.2), lineWidth: 1.5)
                )
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
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
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: edition.scope == .psalter ? "music.note.list" : "book.closed.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(hasAny ? Color.accentColor : settings.theme.secondary)
                        .frame(width: 40, height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(settings.theme.text.opacity(hasAny ? 0.08 : 0.04))
                        )

                    Spacer()

                    Text(languageBadge)
                        .font(.system(size: 12, weight: .semibold, design: .default))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(settings.theme.secondary.opacity(0.15)))
                        .foregroundStyle(settings.theme.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(edition.name)
                        .font(.system(size: 18, weight: .semibold, design: .default))
                        .foregroundStyle(settings.theme.text)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(edition.summary)
                        .font(.system(size: 13, weight: .regular, design: .default))
                        .foregroundStyle(settings.theme.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Image(systemName: hasAny ? "checkmark.circle.fill" : "clock.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(hasAny ? Color.green : settings.theme.secondary)

                    Text(availabilityLabel(availability))
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .foregroundStyle(hasAny ? Color.green : settings.theme.secondary.opacity(0.8))

                    Spacer(minLength: 0)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(settings.theme.text.opacity(0.04))
                    .stroke(settings.theme.secondary.opacity(hasAny ? 0.2 : 0.1), lineWidth: 1.5)
            )
            .opacity(hasAny ? 1 : 0.7)
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
        .environment(AnnotationStore())
        .environment(KnbNotesStore())
        .environment(LiturgyStore())
}
