//
//  ReaderView.swift
//  CatholicBible
//
//  ebook 리더. iPad(가로 넓은 화면)에서는 두 개의 독립된 열을 나란히 보여 준다.
//  각 열은 판본·책·장을 따로 고를 수 있어, 같은 성경을 서로 다른 곳에 펼치거나
//  다른 성경을 나란히 볼 수 있다. iPhone에서는 한 열만 보여 준다.
//  절마다 판본 공통 책갈피·노트를 달 수 있다.
//

import SwiftUI
import UIKit

/// 노트 편집 시트 대상 (절 + 참고 본문)
private struct NoteTarget: Identifiable {
    let ref: VerseRef
    let text: String
    var id: String { ref.id }
}

struct ReaderView: View {
    /// 사이드바에서 고른 책 — 첫째 열의 책이 된다.
    let book: BibleBook

    @Environment(BibleStore.self) private var store
    @Environment(ReaderSettings.self) private var settings
    @Environment(ReadingState.self) private var readingState
    @Environment(ReaderNavigation.self) private var navigation
    @Environment(AnnotationStore.self) private var annotations
    @Environment(KnbNotesStore.self) private var knbNotes
    @Environment(LiturgyStore.self) private var liturgy
    @Environment(\.horizontalSizeClass) private var hSize

    @State private var showMass = false
    @State private var showSearch = false
    @State private var showBookmarks = false
    @State private var showNotes = false
    @State private var showAppearance = false
    @State private var noteTarget: NoteTarget?
    @State private var markerNote: MarkerNoteTarget?
    /// 두 판본 비교에서 두 열이 공유하는 장(연동 시 양쪽이 같은 장을 본다).
    @State private var compareChapter = 0
    /// 연동 비교에서 두 열이 맞추는 '맨 위 절'.
    @State private var compareTopVerse: Int?

    private var canDual: Bool { hSize == .regular }
    /// 좁은 화면(iPhone)에서는 항상 한 페이지
    private var layout: ReaderLayout { canDual ? readingState.readerLayout : .single }
    /// 주석 판본(주석성경·NABRE) 본문|주석 화면을 쓸지 (비교 모드가 아니면 사용)
    private var showAnnotated: Bool {
        (Editions.edition(readingState.selectedEditionID)?.isAnnotated ?? false)
            && !(canDual && readingState.readerLayout == .compare)
    }

    var body: some View {
        @Bindable var rs = readingState

        VStack(spacing: 0) {
            ZStack {
                settings.theme.background.ignoresSafeArea()
                if showAnnotated {
                    // 주석 성경: 왼쪽 본문 · 오른쪽 주석 (입문 접근 포함)
                    AnnotatedReader(editionID: $rs.selectedEditionID,
                                    bookID: primaryBookBinding,
                                    ownerBookID: book.id,
                                    showHeader: true,
                                    onOpenNote: openNote)
                } else {
                    switch layout {
                    case .single:
                        ReaderPane(role: .primary,
                                   editionID: $rs.selectedEditionID,
                                   bookID: primaryBookBinding,
                                   ownerBookID: book.id,
                                   onOpenNote: openNote)
                    case .spread:
                        SpreadReader(editionID: $rs.selectedEditionID,
                                     bookID: primaryBookBinding,
                                     ownerBookID: book.id,
                                     onOpenNote: openNote)
                    case .compare:
                        let linked = readingState.compareLinked
                        let compareBook = Bible.book(navigation.selectedBookID ?? book.id) ?? book
                        VStack(spacing: 0) {
                            HStack(spacing: 0) {
                                ReaderPane(role: .primary,
                                           editionID: $rs.selectedEditionID,
                                           bookID: primaryBookBinding,
                                           linkedChapter: $compareChapter,
                                           showChapterBar: !linked,
                                           ownerBookID: book.id,
                                           syncVerse: linked ? $compareTopVerse : nil,
                                           onOpenNote: openNote)
                                Divider()
                                ReaderPane(role: .secondary,
                                           editionID: $rs.secondaryEditionID,
                                           bookID: linked ? primaryBookBinding : secondaryBookBinding,
                                           onClose: { readingState.readerLayout = .single },
                                           linkedChapter: linked ? $compareChapter : nil,
                                           isFollower: linked,
                                           showChapterBar: !linked,
                                           syncVerse: linked ? $compareTopVerse : nil,
                                           onOpenNote: openNote)
                                    // 연동 ↔ 분리를 바꾸면 둘째 열을 새로 만들어 위치를 다시 잡는다.
                                    .id(linked)
                            }
                            // 연동 시: 두 열을 함께 움직이는 공용 이동줄 하나만 아래에 둔다.
                            if linked {
                                ChapterNavBar(book: compareBook, chapter: $compareChapter,
                                              onChange: { compareTopVerse = nil })  // 장 이동 시 각 열 맨 위
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { readerToolbar }
        .preferredColorScheme(settings.theme.colorScheme)
        .sheet(isPresented: $showAppearance) {
            injectShared(AppearanceControls())
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showSearch) {
            injectShared(SearchView().environment(navigation))
        }
        .sheet(isPresented: $showBookmarks) {
            injectShared(BookmarksView().environment(navigation))
        }
        .sheet(isPresented: $showNotes) {
            injectShared(NotesListView().environment(navigation))
        }
        .fullScreenCover(isPresented: $showMass) {
            injectShared(DailyMassView().environment(navigation))
        }
        .sheet(item: $noteTarget) { target in
            injectShared(NoteEditorView(verse: target.ref,
                                        verseText: target.text,
                                        existing: annotations.noteOrNew(for: target.ref)))
        }
        // 각주 마커 'N)' 탭 → 해당 주석 팝업
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "catholicbible", url.host == "note" else { return .systemAction }
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func q(_ k: String) -> String? { items.first { $0.name == k }?.value }
            if let b = q("b"), let cs = q("c"), let c = Int(cs), let n = q("n") {
                let note = knbNotes.notes(edition: readingState.selectedEditionID,
                                          bookID: b, chapter: c).first { $0.n == n }
                markerNote = MarkerNoteTarget(n: n, text: note?.text ?? "이 주석을 찾지 못했습니다.", bookID: b, chapter: c)
            }
            return .handled
        })
        .fullScreenCover(item: $markerNote) { mn in
            injectShared(MarkerNoteSheet(n: mn.n, text: mn.text, bookID: mn.bookID, chapter: mn.chapter))
        }
    }

    /// 모달에 공유 저장소를 다시 주입(Mac Catalyst 환경 전파 끊김 대비).
    private func injectShared<V: View>(_ view: V) -> some View {
        view.injectSharedStores(store, settings, readingState, annotations, knbNotes, liturgy)
            .environment(navigation)
    }

    /// 첫째 열의 책은 사이드바 선택(navigation)과 연동된다.
    private var primaryBookBinding: Binding<String> {
        Binding(get: { navigation.selectedBookID ?? book.id },
                set: { navigation.selectedBookID = $0 })
    }

    /// 둘째 열은 독립적인 책(비어 있으면 첫째 열과 같은 책으로 시작).
    private var secondaryBookBinding: Binding<String> {
        Binding(get: { readingState.secondaryBookID.isEmpty ? book.id : readingState.secondaryBookID },
                set: { readingState.secondaryBookID = $0 })
    }

    private func openNote(ref: VerseRef, text: String) {
        noteTarget = NoteTarget(ref: ref, text: text)
    }

    @ToolbarContentBuilder
    private var readerToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            HStack(spacing: 4) {
                Button { navigation.goBack() } label: {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                }
                .disabled(!navigation.canGoBack)
                .help("이전 페이지")

                Text("성경 읽기")
                    .font(.headline)
                    .fontWeight(.semibold)

                Button { navigation.goForward() } label: {
                    Image(systemName: "chevron.right")
                        .font(.title2)
                }
                .disabled(!navigation.canGoForward)
                .help("다음 페이지")
            }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                if canDual && (Editions.edition(readingState.selectedEditionID)?.isAnnotated ?? false) {
                    // 주석 판본(주석성경·NABRE): 본문·주석 vs 판본 비교
                    Section("보기") {
                        Button {
                            readingState.readerLayout = .single
                        } label: { Label("본문·주석", systemImage: "book.pages") }
                        Button {
                            readingState.readerLayout = .compare
                        } label: { Label("판본 비교", systemImage: "rectangle.split.2x1") }
                    }
                } else if canDual {
                    Section("페이지") {
                        Picker("페이지", selection: Binding(
                            get: { readingState.readerLayout },
                            set: { readingState.readerLayout = $0 })) {
                            ForEach(ReaderLayout.allCases) { l in
                                Label(l.label, systemImage: l.systemImage).tag(l)
                            }
                        }
                    }
                }
                if canDual && readingState.readerLayout == .compare {
                    Section {
                        Button {
                            readingState.compareLinked.toggle()
                        } label: {
                            Label(readingState.compareLinked ? "두 열 연동됨" : "두 열 분리됨",
                                  systemImage: readingState.compareLinked ? "link.circle.fill" : "link.circle")
                        }
                    }
                }
                Section("도구") {
                    Button("오늘의 미사", systemImage: "sun.max") { showMass = true }
                    Button("찾기", systemImage: "magnifyingglass") { showSearch = true }
                    Button("사전", systemImage: "character.book.closed") { navigation.lookUp() }
                    Button("책갈피", systemImage: "bookmark") { showBookmarks = true }
                    Button("노트", systemImage: "note.text") { showNotes = true }
                    Button("보기 설정", systemImage: "textformat.size") { showAppearance = true }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }
}

// MARK: - 독립 열 (판본·책·장을 스스로 관리)

struct ReaderPane: View {
    enum Role { case primary, secondary }
    let role: Role
    @Binding var editionID: String
    @Binding var bookID: String
    var onClose: (() -> Void)? = nil
    /// 두 판본 비교에서 두 열을 같은 장으로 묶을 때 쓰는 공유 장(없으면 각 열 독립).
    var linkedChapter: Binding<Int>? = nil
    /// 연동된 둘째 열: 장을 스스로 정하지 않고 첫째 열을 따라가기만 한다.
    var isFollower: Bool = false
    /// 하단 장 이동줄을 이 열 안에 표시할지 (연동 비교에서는 공용 줄 하나만 쓰므로 끈다).
    var showChapterBar: Bool = true
    /// 첫 열 헤더를 표시할지 (False면 상단 툴바에서 판본·책을 선택).
    var showHeader: Bool = true
    /// 이 리더가 담당하는 책(리더가 다시 만들어질 때 고정). 책이 바뀌는 순간
    /// 사라지는 옛 리더가 대기 이동을 가로채지 않도록 목표 책과 대조한다.
    var ownerBookID: String = ""
    /// 연동 비교에서 두 열이 맞추는 '맨 위 절'. nil이면 스크롤 연동 안 함(각 열 독립).
    var syncVerse: Binding<Int?>? = nil
    let onOpenNote: (VerseRef, String) -> Void

    @Environment(BibleStore.self) private var store
    @Environment(ReaderSettings.self) private var settings
    @Environment(ReadingState.self) private var readingState
    @Environment(ReaderNavigation.self) private var navigation
    @Environment(KnbNotesStore.self) private var knbNotes

    @State private var localChapter = 0
    /// 대기 이동 직후 한 번 스크롤할 절(강조 색은 navigation.activeHighlight가 담당).
    @State private var scrollTarget: Int?
    /// 지금 맨 위에 보이는 절(연동 스크롤 공유용으로 읽는다).
    @State private var topVerse: Int?
    @State private var showBookPicker = false
    /// ReaderPane 초기화 완료 후 책 선택 변경만 감지하기 위한 플래그
    @State private var isInitialized = false

    private var edition: Edition { Editions.edition(editionID) ?? Editions.all[0] }
    private var book: BibleBook { Bible.book(bookID) ?? Bible.books[0] }

    /// 한국어 성경(「성경」·「한국어 NAB」·「주석 성경」)이나 영어 성경(NAB, NABRE)은 절 앞에 소제목을 보여 준다.
    private var showsTitles: Bool {
        // 한국어 성경
        if (edition.id == "knb" || edition.id == "knab" || edition.isAnnotated) && edition.language == "ko" {
            return true
        }
        // 영어 성경 (NAB, NABRE)
        if edition.id == "nab" || edition.id == "nabre" {
            return true
        }
        return false
    }
    /// 절 번호 → 그 절 앞에 놓일 소제목(각주 마커는 지운다).
    private var titleMap: [Int: String] {
        guard showsTitles, chapter > 0 else { return [:] }

        var titlesByVerse: [Int: String] = [:]

        // 한국어 성경의 경우 KnbNotes의 제목 사용
        if (edition.id == "knb" || edition.id == "knab" || edition.isAnnotated) && edition.language == "ko" {
            // KNAB은 knbnotes의 소제목을 재사용
            let titleEdition = edition.id == "knab" ? "knbnotes" : edition.id
            titlesByVerse = knbNotes.titlesByVerse(edition: titleEdition, bookID: book.id, chapter: chapter)
                .mapValues { AnnotationMarkup.stripMarkers($0) }

            // BibleStore의 제목 추가 (NABRE 등)
            let storeTitle = store.titles(edition: edition, book: book, chapter: chapter)
            for title in storeTitle {
                if titlesByVerse[title.verse] == nil {
                    titlesByVerse[title.verse] = title.text
                }
            }
        } else if edition.id == "nab" || edition.id == "nabre" {
            // 영어 성경 (NAB, NABRE)의 경우 BibleStore의 제목 사용
            let storeTitle = store.titles(edition: edition, book: book, chapter: chapter)
            for title in storeTitle {
                titlesByVerse[title.verse] = title.text
            }
        }

        return titlesByVerse
    }

    /// 표시 중인 장. 연동 시 공유 장, 아니면 이 열의 자기 장.
    private var chapter: Int { linkedChapter?.wrappedValue ?? localChapter }
    private func setChapter(_ value: Int) {
        if let linkedChapter { linkedChapter.wrappedValue = value } else { localChapter = value }
    }

    var body: some View {
        VStack(spacing: 0) {
            if showHeader {
                paneHeader
            }
            versesScroll
            chapterBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            initChapterIfNeeded()
            isInitialized = true
        }
        .onChange(of: bookID) { _, _ in
            if !isFollower {
                let chapter = readingState.lastChapter(edition: edition, book: book)
                setChapter(chapter)
                // 처음 로드 이후 책 선택 변경만 히스토리에 추가
                if isInitialized && role == .primary {
                    navigation.open(bookID: book.id, chapter: chapter)
                }
            }
        }
        .onChange(of: editionID) { _, _ in
            if !isFollower { setChapter(min(max(chapter, 1), book.chapterCount)) }
        }
        .onChange(of: chapter) { _, new in
            guard new > 0, !isFollower else { return }
            // 장 네비게이션으로 변경: 첫 절로 (위의 네비게이션 chevron은 scrollTarget을 이미 설정함)
            if isInitialized && scrollTarget == nil {
                scrollTarget = 1
            }
            readingState.savePosition(edition: edition, book: book, chapter: new)
        }
        .modifier(PendingChapterModifier(active: role == .primary, apply: applyPending))
        .sheet(isPresented: $showBookPicker) {
            BookPickerView(edition: edition, current: bookID) { picked in
                parseBookSelection(picked)
                showBookPicker = false
            }
            .environment(store)   // Mac Catalyst: 모달로 환경이 전파되지 않아 다시 주입
        }
    }

    // MARK: 시작/이동 위치

    private func initChapterIfNeeded() {
        // 연동된 둘째 열: 장은 첫째 열을 따라가되, 강조 독서로의 첫 스크롤은 스스로 한다
        // (교차 열 동기화는 처음엔 상대 열 절이 아직 안 그려져 실패하므로, 각자 확실히 이동).
        if isFollower {
            if let h = navigation.activeHighlight, h.bookID == book.id { scrollTarget = h.startVerse }
            return
        }
        guard chapter == 0 else { return }
        if role == .primary, navigation.hasPending(forBook: ownerBookID),
           let pending = navigation.pendingChapter {
            let c = clampChapter(pending)
            setChapter(c)
            navigation.pendingChapter = nil
            scrollTarget = navigation.consumePending(forBook: ownerBookID)
        } else {
            setChapter(readingState.lastChapter(edition: edition, book: book))
        }
    }

    private func applyPending() {
        guard role == .primary, navigation.hasPending(forBook: ownerBookID),
              let pending = navigation.pendingChapter else { return }
        let c = clampChapter(pending)
        setChapter(c)
        navigation.pendingChapter = nil
        scrollTarget = navigation.consumePending(forBook: ownerBookID)
    }

    private func clampChapter(_ c: Int) -> Int { min(max(c, 1), book.chapterCount) }

    private func step(_ delta: Int) {
        let next = chapter + delta
        guard (1...book.chapterCount).contains(next) else { return }
        scrollTarget = 1
        withAnimation(.easeInOut(duration: 0.2)) { setChapter(next) }
    }

    // MARK: 헤더 (판본 · 책 선택)

    private var paneHeader: some View {
        HStack(spacing: 10) {
            Menu {
                Picker("판본", selection: $editionID) {
                    ForEach(Editions.all) { ed in Text(ed.name).tag(ed.id) }
                }
            } label: {
                labelChip(edition.id)
            }

            Button { showBookPicker = true } label: {
                labelChip(store.bookShortName(edition: edition, book: book))
            }

            Spacer(minLength: 0)

            if let onClose {
                Button { onClose() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .accessibilityLabel("이 열 닫기")
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(settings.theme.background)
        .overlay(alignment: .bottom) {
            Rectangle().fill(settings.theme.secondary.opacity(0.2)).frame(height: 0.5)
        }
    }

    private func labelChip(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text(text).fontWeight(.semibold)
            Image(systemName: "chevron.down").font(.caption2)
        }
        .foregroundStyle(Color.accentColor)
    }

    // MARK: 본문

    private var versesScroll: some View {
        let verses = chapter > 0 ? store.verses(edition: edition, book: book, chapter: chapter) : []
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    chapterHeader
                    if verses.isEmpty {
                        MissingTextView(edition: edition, book: book).padding(.top, 40)
                    } else {
                        LazyVStack(alignment: .leading, spacing: settings.lineSpacing * 0.9) {
                            ForEach(verses) { verse in
                                VStack(alignment: .leading, spacing: settings.lineSpacing * 0.9) {
                                    if let title = titleMap[verse.number] {
                                        SectionTitleView(text: title, bookID: book.id, chapter: chapter,
                                                         linkable: edition.id == "knbnotes")
                                    }
                                    VerseRowView(edition: edition, book: book, chapter: chapter,
                                                 verse: verse,
                                                 highlighted: navigation.activeHighlight?.matches(bookID: book.id, chapter: chapter, verse: verse.number) ?? false,
                                                 onOpenNote: onOpenNote)
                                }
                                .id(verse.number)
                            }
                        }
                        .scrollTargetLayout()
                        .padding(.top, 24)
                        copyrightFooter
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity)
            }
            // 연동 비교: 맨 위에 보이는 '절'을 읽어(topVerse) 공유하고, 상대가 바뀌면 그 절로 이동.
            // 절 기준이라 번역마다 길이가 달라도 같은 절끼리 맞춰진다.
            .scrollPosition(id: $topVerse, anchor: .top)
            .onChange(of: topVerse) { _, v in
                guard let sync = syncVerse, let v, v != sync.wrappedValue else { return }
                sync.wrappedValue = v
            }
            .onChange(of: syncVerse?.wrappedValue) { _, v in
                guard let v, v != topVerse else { return }
                proxy.scrollTo(v, anchor: .top)
            }
            .onChange(of: scrollTarget) { _, _ in performScroll(proxy, verses: verses) }
            .onChange(of: chapter) { _, _ in topVerse = nil; performScroll(proxy, verses: verses) }
            .onAppear { performScroll(proxy, verses: verses) }
        }
    }

    /// 대기 이동 직후 강조 시작 절로 한 번 스크롤한다(레이아웃 뒤로 미룸). 한 번 하면 지운다.
    private func performScroll(_ proxy: ScrollViewProxy, verses: [Verse]) {
        guard let n = scrollTarget, verses.contains(where: { $0.number == n }) else { return }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(n, anchor: .center) }
            scrollTarget = nil
        }
    }

    private var chapterHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.bookName(edition: edition, book: book))
                .font(settings.fontChoice.font(size: settings.fontSize * 0.8, relativeTo: .subheadline))
                .foregroundStyle(settings.theme.secondary)
            Text(book.chapterLabel(max(chapter, 1)))
                .font(settings.fontChoice.font(size: settings.fontSize * 1.9, relativeTo: .largeTitle, bold: true))
                .foregroundStyle(settings.theme.text)
            Rectangle().fill(settings.theme.secondary.opacity(0.35)).frame(width: 40, height: 1)
        }
        .padding(.top, 24)
    }

    private var copyrightFooter: some View {
        Text(edition.copyright)
            .font(.caption2)
            .foregroundStyle(settings.theme.secondary.opacity(0.8))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 40)
    }

    private func parseBookSelection(_ picked: String) {
        let components = picked.split(separator: "-", maxSplits: 1).map(String.init)
        if components.count == 2, let chapterNum = Int(components[1]) {
            bookID = components[0]
            setChapter(chapterNum)
        } else {
            bookID = picked
        }
    }

    // MARK: 하단 장 이동 바

    @ViewBuilder
    private var chapterBar: some View {
        if showChapterBar {
            ChapterNavBar(book: book,
                          chapter: Binding(get: { chapter }, set: { setChapter($0) }))
        }
    }
}

// MARK: - 하단 장 이동줄 (한 열용 · 연동 비교 공용)

/// 슬라이더·앞뒤 버튼·장 선택으로 장을 옮기는 하단 바.
/// 연동 비교에서는 이 바 하나가 두 열의 공유 장을 함께 움직인다.
struct ChapterNavBar: View {
    let book: BibleBook
    @Binding var chapter: Int
    /// 사용자가 장을 옮길 때(예: 강조 해제) 부가 동작.
    var onChange: () -> Void = {}

    @Environment(ReaderSettings.self) private var settings
    @State private var showPicker = false

    var body: some View {
        if book.chapterCount > 1 && chapter > 0 {
            HStack(spacing: 10) {
                Button { step(-1) } label: { Image(systemName: "chevron.left") }
                    .disabled(chapter <= 1)
                Slider(value: Binding(get: { Double(chapter) },
                                      set: { move(to: Int($0.rounded())) }),
                       in: 1...Double(book.chapterCount), step: 1)
                    .accessibilityLabel("장 이동")
                    .accessibilityValue(book.chapterLabel(chapter))
                Button { step(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(chapter >= book.chapterCount)
                Button { showPicker = true } label: {
                    Text(book.chapterLabel(chapter))
                        .font(.caption.monospacedDigit())
                        .frame(minWidth: 40)
                }
                .foregroundStyle(settings.theme.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(settings.theme.background.opacity(0.94))
            .overlay(alignment: .top) {
                Rectangle().fill(settings.theme.secondary.opacity(0.2)).frame(height: 0.5)
            }
            .sheet(isPresented: $showPicker) {
                ChapterPickerView(book: book, current: max(chapter, 1)) { picked in
                    move(to: picked); showPicker = false
                }
            }
        }
    }

    private func step(_ delta: Int) {
        let n = chapter + delta
        guard (1...book.chapterCount).contains(n) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { move(to: n) }
    }

    private func move(to n: Int) {
        guard n != chapter else { return }
        onChange()
        chapter = n
    }
}

/// 첫째 열에서만 검색·책갈피에서 넘어온 이동 요청(pendingChapter)에 반응한다.
private struct PendingChapterModifier: ViewModifier {
    let active: Bool
    let apply: () -> Void
    @Environment(ReaderNavigation.self) private var navigation

    func body(content: Content) -> some View {
        if active {
            content.onChange(of: navigation.pendingChapter) { _, _ in apply() }
        } else {
            content
        }
    }
}

// MARK: - 책 펼침면 (같은 성경을 좌→우 두 페이지로)

struct SpreadReader: View {
    @Binding var editionID: String
    @Binding var bookID: String
    /// 이 리더가 담당하는 책(대기 이동 가로채기 방지용).
    var ownerBookID: String = ""
    let onOpenNote: (VerseRef, String) -> Void

    @Environment(BibleStore.self) private var store
    @Environment(ReaderSettings.self) private var settings
    @Environment(ReadingState.self) private var readingState
    @Environment(ReaderNavigation.self) private var navigation
    @Environment(KnbNotesStore.self) private var knbNotes

    @State private var chapter = 0
    @State private var spreadIndex = 0
    @State private var wantLastSpread = false
    /// 대기 이동 직후 그 절이 있는 펼침면으로 한 번 이동하기 위한 목표 절.
    @State private var scrollTarget: Int?
    @State private var contentSize: CGSize = .zero
    @State private var showBookPicker = false
    @State private var showChapterPicker = false

    private var edition: Edition { Editions.edition(editionID) ?? Editions.all[0] }
    private var book: BibleBook { Bible.book(bookID) ?? Bible.books[0] }
    private var verses: [Verse] {
        chapter > 0 ? store.verses(edition: edition, book: book, chapter: chapter) : []
    }
    private var pages: [[Verse]] { paginate(verses, size: contentSize) }
    private var spreadCount: Int { max(1, Int(ceil(Double(pages.count) / 2.0))) }

    private var showsTitles: Bool { edition.id == "knb" || edition.isAnnotated }
    private var titleMap: [Int: String] {
        guard showsTitles, chapter > 0 else { return [:] }

        // KNB Notes의 제목 먼저 확인
        var titlesByVerse = knbNotes.titlesByVerse(edition: edition.id, bookID: book.id, chapter: chapter)
            .mapValues { AnnotationMarkup.stripMarkers($0) }

        // BibleStore의 제목 추가 (NABRE 등)
        let storeTitle = store.titles(edition: edition, book: book, chapter: chapter)
        for title in storeTitle {
            if titlesByVerse[title.verse] == nil {
                titlesByVerse[title.verse] = title.text
            }
        }

        return titlesByVerse
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            spreadContent
            bottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { initChapterIfNeeded() }
        .onChange(of: bookID) { _, _ in
            chapter = readingState.lastChapter(edition: edition, book: book)
            spreadIndex = 0
        }
        .onChange(of: editionID) { _, _ in
            chapter = min(max(chapter, 1), book.chapterCount); spreadIndex = 0
        }
        .onChange(of: chapter) { _, new in
            guard new > 0 else { return }
            readingState.savePosition(edition: edition, book: book, chapter: new)
        }
        .onChange(of: navigation.pendingChapter) { _, _ in applyPending() }
        .onChange(of: pages.count) { _, _ in reconcileSpreadIndex() }
        .sheet(isPresented: $showBookPicker) {
            BookPickerView(edition: edition, current: bookID) { picked in
                parseBookSelection(picked)
                showBookPicker = false
            }
            .environment(store)   // Mac Catalyst: 모달 환경 전파 대비
        }
        .sheet(isPresented: $showChapterPicker) {
            ChapterPickerView(book: book, current: max(chapter, 1)) { picked in
                chapter = picked; spreadIndex = 0; showChapterPicker = false
            }
        }
    }

    // MARK: 위치

    private func initChapterIfNeeded() {
        guard chapter == 0 else { return }
        if navigation.hasPending(forBook: ownerBookID), let p = navigation.pendingChapter {
            chapter = clampChapter(p); navigation.pendingChapter = nil
            scrollTarget = navigation.consumePending(forBook: ownerBookID)
        } else {
            chapter = readingState.lastChapter(edition: edition, book: book)
        }
    }

    private func applyPending() {
        guard navigation.hasPending(forBook: ownerBookID), let p = navigation.pendingChapter else { return }
        chapter = clampChapter(p); navigation.pendingChapter = nil
        scrollTarget = navigation.consumePending(forBook: ownerBookID)
        spreadIndex = 0
    }

    private func clampChapter(_ c: Int) -> Int { min(max(c, 1), book.chapterCount) }

    /// 페이지 수가 바뀌면 목표 스프레드(마지막/강조 절)로 맞춘다.
    private func reconcileSpreadIndex() {
        if wantLastSpread {
            spreadIndex = max(0, spreadCount - 1); wantLastSpread = false
        } else if let h = scrollTarget,
                  let pageIdx = pages.firstIndex(where: { $0.contains { $0.number == h } }) {
            spreadIndex = pageIdx / 2
            scrollTarget = nil
        } else {
            spreadIndex = min(spreadIndex, max(0, spreadCount - 1))
        }
    }

    private func nextSpread() {
        if spreadIndex + 1 < spreadCount { spreadIndex += 1 }
        else { stepChapter(1) }
    }

    private func prevSpread() {
        if spreadIndex > 0 { spreadIndex -= 1 }
        else { wantLastSpread = true; stepChapter(-1) }
    }

    private func stepChapter(_ delta: Int) {
        let n = chapter + delta
        guard (1...book.chapterCount).contains(n) else { wantLastSpread = false; return }
        spreadIndex = 0
        chapter = n
    }

    private var atFirst: Bool { spreadIndex == 0 && chapter <= 1 }
    private var atLast: Bool { spreadIndex >= spreadCount - 1 && chapter >= book.chapterCount }

    // MARK: 헤더

    private var header: some View {
        HStack(spacing: 10) {
            Menu {
                Picker("판본", selection: $editionID) {
                    ForEach(Editions.all) { ed in Text(ed.name).tag(ed.id) }
                }
            } label: { chip(edition.id) }
            Button { showBookPicker = true } label: {
                chip(store.bookShortName(edition: edition, book: book))
            }
            Spacer(minLength: 0)
        }
        .font(.subheadline)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(settings.theme.background)
        .overlay(alignment: .bottom) {
            Rectangle().fill(settings.theme.secondary.opacity(0.2)).frame(height: 0.5)
        }
    }

    private func chip(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text(text).fontWeight(.semibold)
            Image(systemName: "chevron.down").font(.caption2)
        }
        .foregroundStyle(Color.accentColor)
    }

    // MARK: 펼침 본문 (좌·우 두 페이지)

    private var spreadContent: some View {
        GeometryReader { geo in
            let ps = pages
            let leftIdx = spreadIndex * 2
            HStack(spacing: 0) {
                page(ps.indices.contains(leftIdx) ? ps[leftIdx] : nil, isFirst: leftIdx == 0)
                Divider()
                page(ps.indices.contains(leftIdx + 1) ? ps[leftIdx + 1] : nil, isFirst: false)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { g in
                        if g.translation.width < -40 { withAnimation(.easeInOut(duration: 0.2)) { nextSpread() } }
                        else if g.translation.width > 40 { withAnimation(.easeInOut(duration: 0.2)) { prevSpread() } }
                    }
            )
            .onAppear { if contentSize != geo.size { contentSize = geo.size } }
            .onChange(of: geo.size) { _, s in contentSize = s }
        }
    }

    @ViewBuilder
    private func page(_ verses: [Verse]?, isFirst: Bool) -> some View {
        VStack(alignment: .leading, spacing: settings.lineSpacing * 0.9) {
            if isFirst { chapterHeader }
            if let verses {
                ForEach(verses) { verse in
                    if let title = titleMap[verse.number] {
                        SectionTitleView(text: title, bookID: book.id, chapter: chapter,
                                                         linkable: edition.id == "knbnotes")
                    }
                    VerseRowView(edition: edition, book: book, chapter: chapter,
                                 verse: verse,
                                 highlighted: navigation.activeHighlight?.matches(bookID: book.id, chapter: chapter, verse: verse.number) ?? false,
                                 onOpenNote: onOpenNote)
                }
            } else if isFirst && pages.isEmpty {
                MissingTextView(edition: edition, book: book).padding(.top, 24)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 30)
        .padding(.vertical, 22)
        .clipped()
    }

    private var chapterHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(store.bookName(edition: edition, book: book))
                .font(settings.fontChoice.font(size: settings.fontSize * 0.8, relativeTo: .subheadline))
                .foregroundStyle(settings.theme.secondary)
            Text(book.chapterLabel(max(chapter, 1)))
                .font(settings.fontChoice.font(size: settings.fontSize * 1.7, relativeTo: .largeTitle, bold: true))
                .foregroundStyle(settings.theme.text)
            Rectangle().fill(settings.theme.secondary.opacity(0.35)).frame(width: 40, height: 1)
        }
        .padding(.bottom, 6)
    }

    // MARK: 하단 (펼침·장 이동)

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button { withAnimation(.easeInOut(duration: 0.2)) { prevSpread() } } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(atFirst)
            Spacer()
            Button { showChapterPicker = true } label: {
                Text("\(book.chapterLabel(chapter)) · 펼침 \(spreadIndex + 1)/\(spreadCount)")
                    .font(.caption.monospacedDigit())
            }
            .foregroundStyle(settings.theme.secondary)
            Spacer()
            Button { withAnimation(.easeInOut(duration: 0.2)) { nextSpread() } } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(atLast)
        }
        .padding(.horizontal, 20).padding(.vertical, 7)
        .background(settings.theme.background.opacity(0.94))
        .overlay(alignment: .top) {
            Rectangle().fill(settings.theme.secondary.opacity(0.2)).frame(height: 0.5)
        }
    }

    // MARK: 페이지 나누기 (추정 기반)

    private func paginate(_ verses: [Verse], size: CGSize) -> [[Verse]] {
        guard !verses.isEmpty else { return [] }
        // 각 페이지는 전체 폭의 절반(좌·우). 좌우 여백 제외.
        let usableW = max(120, size.width / 2 - 72)
        let usableH = (size.height - 40) * 0.96
        guard usableH > 60 else { return [verses] }

        let fs = settings.fontSize
        let charsPerLine = max(6, Int(usableW / (fs * 0.98)))   // 한글 한 글자 ≈ 1em
        let lineH = fs + settings.lineSpacing
        let gap = settings.lineSpacing * 0.9
        let headerH = fs * 3.4    // 첫 페이지의 장 머리글 높이

        var pages: [[Verse]] = []
        var cur: [Verse] = []
        var curH: CGFloat = 0
        for v in verses {
            let chars = v.text.count + 4
            let lines = max(1, Int(ceil(Double(chars) / Double(charsPerLine))))
            let h = CGFloat(lines) * lineH + gap
            let budget = usableH - (pages.isEmpty ? headerH : 0)
            if !cur.isEmpty && curH + h > budget {
                pages.append(cur); cur = []; curH = 0
            }
            cur.append(v); curH += h
        }
        if !cur.isEmpty { pages.append(cur) }
        return pages
    }

    private func parseBookSelection(_ picked: String) {
        let components = picked.split(separator: "-", maxSplits: 1).map(String.init)
        if components.count == 2, let chapterNum = Int(components[1]) {
            bookID = components[0]
            chapter = chapterNum
        } else {
            bookID = picked
        }
    }
}

// MARK: - 선택 가능한 본문 (UIKit)

/// 낱말을 선택하면 네이티브 하이라이트가 보이고, 선택 메뉴의 ‘찾아보기’로
/// 시스템 사전이 열리는 본문 뷰. SwiftUI Text의 .textSelection보다 선택이
/// 확실히 보이고 스크롤 안에서도 잘 동작한다.
struct SelectableVerseText: UIViewRepresentable {
    let text: String
    let font: UIFont
    let color: UIColor
    let lineSpacing: CGFloat
    /// 각주 마커('N)')를 강조·링크로 만들 때의 색(주석 성경일 때만 지정). nil이면 강조 안 함.
    var markerColor: UIColor? = nil
    var bookID: String = ""
    var chapter: Int = 0
    /// 마커를 눌렀을 때 열 URL 처리(주석 팝업). SwiftUI의 openURL 액션을 넘긴다.
    var onOpenURL: ((URL) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(onOpenURL: onOpenURL) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.delegate = context.coordinator
        tv.setContentCompressionResistancePriority(.required, for: .vertical)
        tv.setContentHuggingPriority(.required, for: .vertical)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.onOpenURL = onOpenURL
        let para = NSMutableParagraphStyle()
        para.lineSpacing = lineSpacing
        let attr = NSMutableAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: para,
        ])
        // 각주 마커 'N)'를 본문과 다른 색·작은 위첨자로 표시하고, 탭하면 주석이 열리게 한다.
        if let markerColor, let regex = Self.markerRegex {
            let ns = text as NSString
            let markerFont = font.withSize(max(font.pointSize * 0.72, 9))
            for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let n = ns.substring(with: m.range(at: 1))
                var attrs: [NSAttributedString.Key: Any] = [
                    .foregroundColor: markerColor,
                    .font: markerFont,
                    .baselineOffset: font.pointSize * 0.28,
                ]
                if let url = URL(string: "catholicbible://note?b=\(bookID)&c=\(chapter)&n=\(n)") {
                    attrs[.link] = url
                }
                attr.addAttributes(attrs, range: m.range)
            }
            tv.linkTextAttributes = [.foregroundColor: markerColor]
        }
        tv.attributedText = attr
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0, width.isFinite else { return nil }
        let fit = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fit.height))
    }

    // 인용 참조의 닫는 괄호(예: "1,19-28)")를 각주 마커로 오인하지 않도록
    // 숫자 앞이 하이픈·쉼표·마침표·숫자·'('이면 마커로 보지 않는다.
    private static let markerRegex = try? NSRegularExpression(pattern: "(?<![-,.\\d(])(\\d{1,3})\\)")

    final class Coordinator: NSObject, UITextViewDelegate {
        var onOpenURL: ((URL) -> Void)?
        init(onOpenURL: ((URL) -> Void)?) { self.onOpenURL = onOpenURL }

        /// 마커 링크 탭 → 기본 동작(Safari 열기) 대신 앱 내 주석 팝업으로 보낸다.
        func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem,
                      defaultAction: UIAction) -> UIAction? {
            if case .link(let url) = textItem.content {
                return UIAction { [onOpenURL] _ in onOpenURL?(url) }
            }
            return defaultAction
        }
    }
}

// MARK: - 절 한 줄 (판본 공통 책갈피·노트)

struct VerseRowView: View {
    let edition: Edition
    let book: BibleBook
    let chapter: Int
    let verse: Verse
    let highlighted: Bool
    let onOpenNote: (VerseRef, String) -> Void
    /// '사전 열기' 처리를 상위가 직접 하고 싶을 때(예: 전체 화면인 오늘의 미사).
    /// nil이면 공용 navigation.lookUp()을 쓴다.
    var onLookUp: (() -> Void)? = nil

    @Environment(ReaderSettings.self) private var settings
    @Environment(AnnotationStore.self) private var annotations
    @Environment(ReaderNavigation.self) private var navigation
    @Environment(\.openURL) private var openURL

    private var ref: VerseRef { VerseRef(bookID: book.id, chapter: chapter, verse: verse.number) }

    /// 주석 성경일 때만 각주 마커('N)')를 강조·링크로 만든다.
    private var isAnnotationEdition: Bool { edition.id == "knbnotes" }

    /// 본문 뷰: UIKit 선택 텍스트뷰. 낱말을 선택하면 네이티브 하이라이트가 보이고,
    /// 선택 메뉴의 ‘찾아보기’로 시스템 사전이 열린다. 주석 성경에서는 각주 마커가
    /// 본문과 다른 색·위첨자로 표시되고, 탭하면 해당 주석이 열린다.
    private var verseTextView: some View {
        SelectableVerseText(text: verse.text,
                            font: uiBodyFont,
                            color: UIColor(settings.theme.text),
                            lineSpacing: settings.lineSpacing,
                            markerColor: isAnnotationEdition ? UIColor(Color.accentColor) : nil,
                            bookID: book.id,
                            chapter: chapter,
                            onOpenURL: { openURL($0) })
    }

    private var uiBodyFont: UIFont {
        let size = settings.fontSize
        switch settings.fontChoice {
        case .myeongjo: return UIFont(name: "NanumMyeongjo", size: size) ?? .systemFont(ofSize: size)
        case .gothic:   return .systemFont(ofSize: size)
        }
    }

    var body: some View {
        let bookmarked = annotations.isBookmarked(ref)
        let hasNote = annotations.hasNote(ref)

        HStack(alignment: .firstTextBaseline, spacing: 6) {
            // 앞의 번호(또는 점) = 동작 메뉴 손잡이. 본문 낱말 선택과 겹치지 않는다.
            actionMenu(bookmarked: bookmarked, hasNote: hasNote)

            verseTextView
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(highlighted ? Color.accentColor.opacity(0.18) : .clear)
        )
        .overlay(alignment: .topTrailing) { indicators(bookmarked: bookmarked, hasNote: hasNote) }
        .animation(.easeInOut(duration: 0.25), value: highlighted)
        .animation(.easeInOut(duration: 0.25), value: bookmarked)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(verse.number)절, \(verse.text)")
    }

    /// 절 번호(또는 점)를 눌러 여는 동작 메뉴
    private func actionMenu(bookmarked: Bool, hasNote: Bool) -> some View {
        Menu {
            Button(bookmarked ? "책갈피 지우기" : "책갈피",
                   systemImage: bookmarked ? "bookmark.slash" : "bookmark") {
                annotations.toggleBookmark(ref)
            }
            Button(hasNote ? "노트 보기·편집" : "노트 추가", systemImage: "note.text") {
                onOpenNote(ref, verse.text)
            }
            Button("사전 열기", systemImage: "character.book.closed") {
                if let onLookUp { onLookUp() } else { navigation.lookUp() }
            }
            Button("복사", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = "\(verse.text) (\(ref.reference))"
            }
        } label: {
            handleLabel(bookmarked: bookmarked, hasNote: hasNote)
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("\(verse.number)절 동작")
    }

    @ViewBuilder
    private func handleLabel(bookmarked: Bool, hasNote: Bool) -> some View {
        if settings.showVerseNumbers {
            Text("\(verse.number)")
                .font(settings.fontChoice.font(size: settings.fontSize * 0.62))
                .foregroundStyle(bookmarked || hasNote ? Color.accentColor : settings.theme.secondary)
                .frame(minWidth: settings.fontSize * 1.1, alignment: .trailing)
        } else {
            Image(systemName: bookmarked || hasNote ? "circle.fill" : "circle")
                .font(.system(size: max(6, settings.fontSize * 0.28)))
                .foregroundStyle((bookmarked || hasNote ? Color.accentColor : settings.theme.secondary).opacity(0.5))
                .frame(width: settings.fontSize * 0.9)
        }
    }

    @ViewBuilder
    private func indicators(bookmarked: Bool, hasNote: Bool) -> some View {
        HStack(spacing: 3) {
            if hasNote {
                Image(systemName: "note.text").font(.caption2)
                    .foregroundStyle(Color.accentColor.opacity(0.75))
            }
            if bookmarked {
                Image(systemName: "bookmark.fill").font(.caption2)
                    .foregroundStyle(Color.accentColor.opacity(0.8))
            }
        }
        .padding(.trailing, 2)
        .accessibilityHidden(true)
    }
}

// MARK: - 본문 미수집 안내

struct MissingTextView: View {
    let edition: Edition
    let book: BibleBook
    @Environment(ReaderSettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("본문 준비 중", systemImage: "tray")
                .font(.headline)
                .foregroundStyle(settings.theme.text)
            Text("\(edition.name)의 \(book.name) 본문이 아직 이 앱에 담기지 않았습니다.")
                .foregroundStyle(settings.theme.text)
            Text("저장소의 scripts/fetch_cbck_bible.py --edition \(edition.id) 로 bible.cbck.or.kr에서 본문을 받은 뒤 다시 빌드하면 이 책을 읽을 수 있습니다. 본문 저작권은 각 판본 저작권자에게 있습니다.")
                .font(.footnote)
                .foregroundStyle(settings.theme.secondary)
        }
        .frame(maxWidth: 520, alignment: .leading)
    }
}

// MARK: - 책 선택 (열마다)

struct BookPickerView: View {
    let edition: Edition
    let current: String
    let onPick: (String) -> Void

    @Environment(BibleStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selectedBook: BibleBook?

    var body: some View {
        NavigationStack {
            if let book = selectedBook {
                chapterView(book)
            } else {
                bookList
            }
        }
    }

    private var bookList: some View {
        List {
            ForEach(Testament.allCases) { testament in
                let books = edition.scope.books.filter { $0.testament == testament }
                if !books.isEmpty {
                    Section(testament.title) {
                        ForEach(books) { book in row(book) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("\(edition.shortName) · 책 선택")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } }
        }
    }

    @ViewBuilder
    private func chapterView(_ book: BibleBook) -> some View {
        if book.id == "ps" {
            psalmsView(book)
        } else {
            chaptersView(book)
        }
    }

    private func psalmsView(_ book: BibleBook) -> some View {
        let sections: [(num: Int, range: String)] = [
            (1, "1-41"), (2, "42-72"), (3, "73-89"), (4, "90-106"), (5, "107-150")
        ]
        return ScrollView {
            VStack(spacing: 12) {
                ForEach(sections, id: \.num) { section in
                    Button {
                        onPick("ps-\(section.num)")
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(section.num)편").font(.headline.weight(.semibold))
                                Text("시편 \(section.range)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .navigationTitle("시편 선택")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { selectedBook = nil }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.body.weight(.semibold))
                        Text("책 선택")
                    }
                }
            }
        }
    }

    private func chaptersView(_ book: BibleBook) -> some View {
        let columns = [GridItem(.adaptive(minimum: 56), spacing: 10)]
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(1...book.chapterCount, id: \.self) { number in
                    Button {
                        onPick("\(book.id)-\(number)")
                        dismiss()
                    } label: {
                        Text("\(number)")
                            .font(.body.monospacedDigit())
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.secondary.opacity(0.1))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(book.chapterLabel(number))
                }
            }
            .padding(20)
        }
        .navigationTitle(store.bookShortName(edition: edition, book: book))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { selectedBook = nil }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.body.weight(.semibold))
                        Text("책 선택")
                    }
                }
            }
        }
    }

    private func row(_ book: BibleBook) -> some View {
        let available = store.hasText(edition: edition, book: book)
        return Button { selectedBook = book } label: {
            HStack {
                Text(store.bookShortName(edition: edition, book: book))
                    .foregroundStyle(available ? .primary : .secondary)
                Spacer()
                if book.id == current {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                } else if !available {
                    Text("준비 중").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .disabled(!available)
    }
}

// MARK: - 장 선택

struct ChapterPickerView: View {
    let book: BibleBook
    let current: Int
    let onPick: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    private let columns = [GridItem(.adaptive(minimum: 56), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(1...book.chapterCount, id: \.self) { number in
                        Button { onPick(number) } label: {
                            Text("\(number)")
                                .font(.body.monospacedDigit())
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(number == current
                                              ? Color.accentColor.opacity(0.25)
                                              : Color.secondary.opacity(0.1))
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(book.chapterLabel(number))
                    }
                }
                .padding(20)
            }
            .navigationTitle(book.shortName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } }
            }
        }
    }
}

// MARK: - Aa 보기 설정

struct AppearanceControls: View {
    @Environment(ReaderSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section("글자") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("글자 크기").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Text("가").font(.footnote)
                            Slider(value: $settings.fontSize, in: ReaderSettings.fontSizeRange, step: 1)
                            Text("가").font(.title2)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("줄 간격").font(.caption).foregroundStyle(.secondary)
                        Slider(value: $settings.lineSpacingFactor, in: 0.35...1.1)
                    }
                    Picker("서체", selection: $settings.fontChoice) {
                        ForEach(FontChoice.allCases) { choice in Text(choice.label).tag(choice) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("절 번호 표시", isOn: $settings.showVerseNumbers)
                }
                Section("배경") {
                    HStack(spacing: 12) {
                        ForEach(ReaderTheme.allCases) { theme in
                            Button { settings.theme = theme } label: {
                                Circle()
                                    .fill(theme.background)
                                    .stroke(settings.theme == theme ? Color.accentColor : .secondary.opacity(0.4),
                                            lineWidth: settings.theme == theme ? 2.5 : 1)
                                    .frame(width: 36, height: 36)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(theme.label)
                        }
                    }
                }
            }
            .navigationTitle("보기 설정")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
