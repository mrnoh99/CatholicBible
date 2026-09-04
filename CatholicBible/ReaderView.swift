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
    @State private var xrefTarget: XrefTarget?
    /// 첫째 열의 현재 장(판본 전환 시 유지됨).
    @State private var primaryChapter = 0
    /// 두 판본 비교에서 두 열이 공유하는 장(연동 시 양쪽이 같은 장을 본다).
    @State private var compareChapter = 0
    /// 주석 성경(본문·주석) 모드의 장 (다른 모드와 독립적으로 유지)
    @State private var annotatedChapter = 0
    /// 책 선택 시 마지막 장을 복원하지 않도록 하는 플래그 (picker에서 특정 장 선택 시 사용)
    @State private var skipChapterRestore = false
    /// 비교 모드에서 secondary 패널의 책 선택 시 마지막 장을 복원하지 않도록 하는 플래그
    @State private var skipSecondaryChapterRestore = false
    /// 연동 비교에서 두 열이 맞추는 '맨 위 절'.
    @State private var compareTopVerse: String?

    /// 책이 바뀔 때 상태를 초기화하기 위한 추적용 state
    @State private var previousBookID = ""

    private var selectedEditionIDBinding: Binding<String> {
        Binding(get: { readingState.selectedEditionID },
                set: { readingState.selectedEditionID = $0 })
    }

    private var secondaryEditionIDBinding: Binding<String> {
        Binding(get: { readingState.secondaryEditionID },
                set: { readingState.secondaryEditionID = $0 })
    }

    private var canDual: Bool { hSize == .regular }
    /// 좁은 화면(iPhone)에서는 항상 한 페이지
    private var layout: ReaderLayout { canDual ? readingState.readerLayout : .single }
    /// 주석 판본(주석성경·NABRE) 본문|주석 화면을 쓸지 (본문·주석 옵션 선택 시)
    private var showAnnotated: Bool {
        (Editions.edition(readingState.selectedEditionID)?.isAnnotated ?? false)
            && readingState.showAnnotatedNotes
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                settings.theme.background.ignoresSafeArea()
                if showAnnotated {
                    // 주석 성경: 왼쪽 본문 · 오른쪽 주석 (입문 접근 포함)
                    // 독립적인 annotatedChapter 사용: 다른 모드로 전환했다가 돌아와도 같은 장 유지
                    AnnotatedReader(editionID: selectedEditionIDBinding,
                                    bookID: primaryBookBinding,
                                    currentBook: book,
                                    sharedChapter: $annotatedChapter,
                                    ownerBookID: book.id,
                                    showHeader: true,
                                    fullWidth: true,
                                    onOpenNote: openNote,
                                    onOpenXref: { xrefTarget = $0 })
                } else {
                    switch layout {
                    case .single:
                        ReaderPane(role: .primary,
                                   editionID: selectedEditionIDBinding,
                                   bookID: primaryBookBinding,
                                   linkedChapter: $primaryChapter,
                                   skipChapterRestore: $skipChapterRestore,
                                   ownerBookID: book.id,
                                   fullWidth: true,
                                   onOpenNote: openNote,
                                   onOpenXref: { xrefTarget = $0 })
                    case .spread:
                        SpreadReader(editionID: selectedEditionIDBinding,
                                     bookID: primaryBookBinding,
                                     sharedChapter: $primaryChapter,
                                     ownerBookID: book.id,
                                     onOpenNote: openNote,
                                     onOpenXref: { xrefTarget = $0 })
                    case .compare:
                        let linked = readingState.compareLinked
                        let compareBook = Bible.book(navigation.selectedBookID ?? book.id) ?? book
                        VStack(spacing: 0) {
                            HStack(spacing: 0) {
                                ReaderPane(role: .primary,
                                           editionID: selectedEditionIDBinding,
                                           bookID: primaryBookBinding,
                                           linkedChapter: $compareChapter,
                                           skipChapterRestore: $skipChapterRestore,
                                           showChapterBar: !linked,
                                           ownerBookID: book.id,
                                           syncVerse: linked ? $compareTopVerse : nil,
                                           onOpenNote: openNote,
                                           onOpenXref: { xrefTarget = $0 })
                                Divider()
                                ReaderPane(role: .secondary,
                                           editionID: secondaryEditionIDBinding,
                                           bookID: linked ? primaryBookBinding : secondaryBookBinding,
                                           onClose: { readingState.readerLayout = .single },
                                           linkedChapter: linked ? $compareChapter : nil,
                                           skipChapterRestore: $skipSecondaryChapterRestore,
                                           isFollower: linked,
                                           showChapterBar: !linked,
                                           syncVerse: linked ? $compareTopVerse : nil,
                                           onOpenNote: openNote,
                                           onOpenXref: { xrefTarget = $0 })
                                    // 연동 ↔ 분리를 바꾸면 둘째 열을 새로 만들어 위치를 다시 잡는다.
                                    .id(linked)
                            }
                            // 연동 시: 두 열을 함께 움직이는 공용 이동줄 하나만 아래에 둔다.
                            if linked {
                                ChapterNavBar(book: compareBook, chapter: $compareChapter,
                                              onChange: { compareTopVerse = nil })
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: book.id) { _, newBookID in
            // 책이 바뀌면 상태를 초기화 (성능 최적화: .id() 제거로 인한 상태 관리)
            if previousBookID != newBookID {
                navigation.selectedBookID = newBookID  // AnnotatedReader에 전파
                compareChapter = 0
                compareTopVerse = nil
                // skipChapterRestore가 false인 경우에만 마지막 장을 복원하도록 리셋
                if !skipChapterRestore {
                    primaryChapter = 0  // initChapterIfNeeded()가 작동하려면 필요
                    annotatedChapter = 0  // 주석 성경 모드도 같이 초기화
                }
                // skipChapterRestore는 ReaderPane.onChange(of: bookID)에서 초기화하므로 여기서 초기화하지 않음
                previousBookID = newBookID
            }
        }
        .onChange(of: navigation.selectedBookID) { _, newBookID in
            // 사이드 패널에서 책이 선택될 때 직접 감지
            if let newBookID, previousBookID != newBookID {
                compareChapter = 0
                compareTopVerse = nil
                // skipChapterRestore는 책 선택기에서만 사용되므로, 사이드패널 선택 시 무조건 해제
                // (이전 선택기 동작의 영향을 받지 않도록)
                skipChapterRestore = false
                // skipChapterRestore가 false인 경우에만 마지막 장을 복원하도록 리셋
                primaryChapter = 0  // initChapterIfNeeded()가 작동하려면 필요
                annotatedChapter = 0  // 주석 성경 모드도 같이 초기화
                previousBookID = newBookID
            }
        }
        .onChange(of: readingState.readerLayout) { _, newLayout in
            if newLayout == .compare && compareChapter == 0 {
                compareChapter = primaryChapter
            }
        }
        .onChange(of: readingState.showAnnotatedNotes) { _, isShowingAnnotated in
            // 모드 전환 시 chapter 동기화
            // 한페이지/펼침 ↔ 본문·주석 전환할 때 현재 장을 보존했다가 복원
            if isShowingAnnotated {
                // 한페이지/펼침 → 본문·주석으로 전환
                // annotatedChapter가 0이면 primaryChapter 값으로 초기화 (처음 진입)
                if annotatedChapter == 0 && primaryChapter > 0 {
                    annotatedChapter = primaryChapter
                    print("📖 Switching to annotated: syncing chapter \(primaryChapter)")
                }
            } else {
                // 본문·주석 → 한페이지/펼침으로 전환
                // primaryChapter가 0이면 annotatedChapter 값으로 초기화 (처음 진입)
                if primaryChapter == 0 && annotatedChapter > 0 {
                    primaryChapter = annotatedChapter
                    print("📖 Switching from annotated: syncing chapter \(annotatedChapter)")
                }
            }
        }
        .toolbar { readerToolbar }
        .preferredColorScheme(settings.theme.colorScheme)
        .sheet(isPresented: $showAppearance) {
            injectShared(AppSettingsView())
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
        // 각주 마커 'N)' 탭 → 해당 주석 팝업, 소제목 cross link → xref 이동
        .environment(\.openURL, OpenURLAction { url in
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func q(_ k: String) -> String? { items.first { $0.name == k }?.value }

            if url.scheme == "catholicbible", url.host == "xref" {
                if let b = q("b"), let cs = q("c"), let c = Int(cs),
                   let vs = q("v"), let v = Int(vs) {
                    xrefTarget = XrefTarget(bookID: b, chapter: c, verse: v,
                                            endChapter: q("ec").flatMap { Int($0) } ?? 0,
                                            endVerse: q("ev").flatMap { Int($0) } ?? 0)
                }
                return .handled
            }

            if url.scheme == "catholicbible", url.host == "note" {
                if let b = q("b"), let cs = q("c"), let c = Int(cs), let n = q("n") {
                    let note = knbNotes.notes(edition: readingState.selectedEditionID,
                                              bookID: b, chapter: c).first { $0.n == n }
                    markerNote = MarkerNoteTarget(n: n, text: note?.text ?? "이 주석을 찾지 못했습니다.", bookID: b, chapter: c)
                }
                return .handled
            }

            return .systemAction
        })
        .fullScreenCover(item: $markerNote) { mn in
            injectShared(MarkerNoteSheet(n: mn.n, text: mn.text, bookID: mn.bookID, chapter: mn.chapter))
        }
        .fullScreenCover(item: $xrefTarget) { t in
            injectShared(RefPreviewSheet(target: t).environment(navigation))
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
        let noteText = knbNotes.notes(edition: readingState.selectedEditionID,
                                      bookID: ref.bookID,
                                      chapter: ref.chapter)
            .first(where: { $0.n == ref.verse })?.text ?? "이 주석을 찾지 못했습니다."
        markerNote = MarkerNoteTarget(n: ref.verse, text: noteText,
                                      bookID: ref.bookID, chapter: ref.chapter)
    }

    @ToolbarContentBuilder
    private var readerToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button { navigation.selectedBookID = nil } label: {
                Label("첫화면으로", systemImage: "house.fill")
            }
            .help("첫화면으로")
        }

        ToolbarItem(placement: .principal) {
            HStack(spacing: 8) {
                Button { navigation.goBack() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .contentShape(Circle())
                }
                .disabled(!navigation.canGoBack)
                .help("이전 페이지")
                .opacity(navigation.canGoBack ? 1 : 0.4)

                Text("성경 읽기")
                    .font(.system(size: 16, weight: .semibold, design: .default))

                Button { navigation.goForward() } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                        .contentShape(Circle())
                }
                .disabled(!navigation.canGoForward)
                .help("다음 페이지")
                .opacity(navigation.canGoForward ? 1 : 0.4)
            }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                    let isAnnotated = Editions.edition(readingState.selectedEditionID)?.isAnnotated ?? false

                    if canDual {
                        if isAnnotated {
                            Section("보기") {
                                Button(action: {
                                    readingState.readerLayout = .single
                                    readingState.showAnnotatedNotes = false
                                }) { Label("한 페이지", systemImage: "rectangle.portrait") }

                                Button(action: {
                                    readingState.readerLayout = .spread
                                    readingState.showAnnotatedNotes = false
                                }) { Label("두 페이지 (펼침)", systemImage: "book.pages") }

                                Button(action: {
                                    readingState.readerLayout = .single
                                    readingState.showAnnotatedNotes = true
                                }) { Label("본문·주석", systemImage: "books.vertical") }

                                Button(action: {
                                    readingState.readerLayout = .compare
                                    readingState.showAnnotatedNotes = false
                                }) { Label("판본 비교", systemImage: "rectangle.split.2x1") }
                            }
                        } else {
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
                    }
                    if canDual && readingState.readerLayout == .compare {
                        Section {
                            Button(action: { readingState.compareLinked.toggle() }) {
                                Label(readingState.compareLinked ? "두 열 연동됨" : "두 열 분리됨",
                                      systemImage: readingState.compareLinked ? "link.circle.fill" : "link.circle")
                            }
                        }
                    }
                    Section("도구") {
                        Button(action: { showMass = true }) {
                            Label("매일미사", systemImage: "sun.max")
                        }
                        Button(action: { showSearch = true }) {
                            Label("찾기", systemImage: "magnifyingglass")
                        }
                        Button(action: { navigation.lookUp() }) {
                            Label("사전", systemImage: "character.book.closed")
                        }
                        Button(action: { showBookmarks = true }) {
                            Label("책갈피", systemImage: "bookmark")
                        }
                        Button(action: { showNotes = true }) {
                            Label("노트", systemImage: "note.text")
                        }
                        Button(action: { showAppearance = true }) {
                            Label("설정", systemImage: "gear")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 15, weight: .semibold))
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
    /// 공유하는 장 바인딩(없으면 자체 장 관리). 판본 전환 시 장을 유지하는 데 사용됨.
    var linkedChapter: Binding<Int>? = nil
    /// 책 선택 시 마지막 장을 복원하지 않도록 하는 플래그 (picker에서 특정 장 선택 시)
    @Binding var skipChapterRestore: Bool
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
    var syncVerse: Binding<String?>? = nil
    /// 한 페이지 모드에서 전체 너비 사용 (기본: false - 720 제한)
    var fullWidth: Bool = false
    let onOpenNote: (VerseRef, String) -> Void
    let onOpenXref: (XrefTarget) -> Void

    @Environment(BibleStore.self) private var store
    @Environment(ReaderSettings.self) private var settings
    @Environment(ReadingState.self) private var readingState
    @Environment(ReaderNavigation.self) private var navigation
    @Environment(KnbNotesStore.self) private var knbNotes

    /// 원본 헤딩 데이터 (Sirach 프롤로그용, BibleStore의 정제 로직 우회)
    @State private var rawHeadings: [String: [String: [String: String]]] = [:]

    @State private var localChapter = 0
    /// 대기 이동 직후 한 번 스크롤할 절(강조 색은 navigation.activeHighlight가 담당).
    @State private var scrollTarget: Int?
    /// 지금 맨 위에 보이는 절(연동 스크롤 공유용으로 읽는다).
    @State private var topVerse: String?
    @State private var showBookPicker = false
    /// ReaderPane 초기화 완료 후 책 선택 변경만 감지하기 위한 플래그
    @State private var isInitialized = false
    /// 캐시된 소제목 맵 (성능 최적화)
    @State private var cachedTitleMap: [String: String] = [:]
    @State private var cachedTitleChapter: Int = -1
    @State private var cachedTitleEditionID: String = ""
    @State private var cachedTitleBookID: String = ""
    /// 캐시된 절 목록 (성능 최적화 - 반복적인 store.verses() 호출 방지)
    @State private var cachedVerses: [Verse] = []
    @State private var cachedChapter: Int = -1
    @State private var cachedEditionID: String = ""
    @State private var cachedBookID: String = ""

    private var edition: Edition { Editions.edition(editionID) ?? Editions.all[0] }
    private var book: BibleBook { Bible.book(bookID) ?? Bible.books[0] }

    /// 소제목 표시 여부 판단
    private var showsTitles: Bool {
        // JSON headings에서 제목 표시
        chapter > 0
    }

    /// 절 번호 → 소제목 맵 (캐시됨)
    private var titleMap: [String: String] {
        showsTitles ? cachedTitleMap : [:]
    }

    /// 원본 헤딩 데이터에서 프롤로그 추출 (knb 판본에만 표시)
    private var prologueText: String? {
        guard chapter == 1 && book.id == "sir" else { return nil }
        guard editionID == "knb" else { return nil }
        let sirHeadings = rawHeadings["sir"] ?? [:]
        guard let headingsForCh1 = sirHeadings["1"] else { return nil }
        guard let rawText = headingsForCh1["1"] else { return nil }
        return isPrologueText(rawText) ? rawText : nil
    }

    /// 프롤로그 텍스트 여부 (verse markers like (1), (5), (10)... 포함)
    private func isPrologueText(_ text: String) -> Bool {
        let verseMarkerPattern = try? NSRegularExpression(pattern: "\\(\\d+\\)", options: [])
        guard let regex = verseMarkerPattern else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    /// knb 판본에서만 프롤로그로 인한 중복 제목 제외
    private func filteredTitleMap() -> [String: String] {
        var result = titleMap
        if editionID == "knb" && chapter == 1 && book.id == "sir" && prologueText != nil {
            result.removeValue(forKey: "1")
        }
        return result
    }

    /// 프롤로그 절인지 확인 (key가 "1(1)", "1(5)" 등인지 확인)
    private func isPrologueVerse(verseKey: String) -> Bool {
        if !["knb", "knbnotes"].contains(editionID) || chapter != 1 || book.id != "sir" { return false }
        return verseKey.contains("(") && verseKey.contains(")")
    }

    /// 프롤로그 절 번호 추출 (예: "1(5)" → 5)
    private func prologueVerseNumber(verseKey: String) -> Int? {
        guard let match = verseKey.range(of: "\\((\\d+)\\)", options: .regularExpression) else { return nil }
        let numStr = String(verseKey[match]).dropFirst().dropLast()
        return Int(numStr)
    }

    /// 프롤로그 절들을 정렬된 순서로 반환
    private var prologueVerses: [Verse] {
        let verses = cachedVerses
        let prologue = verses.filter { isPrologueVerse(verseKey: $0.number) }
        return prologue.sorted { a, b in
            let numA = prologueVerseNumber(verseKey: a.number) ?? 0
            let numB = prologueVerseNumber(verseKey: b.number) ?? 0
            return numA < numB
        }
    }

    /// 일반 절들 (프롤로그 절 제외)
    private var regularVerses: [Verse] {
        let verses = cachedVerses
        return verses.filter { !isPrologueVerse(verseKey: $0.number) }
    }

    /// 표시 중인 장. 연동 시 공유 장, 아니면 이 열의 자기 장.
    private var chapter: Int {
        get { linkedChapter?.wrappedValue ?? localChapter }
        set {
            if let linkedChapter { linkedChapter.wrappedValue = newValue } else { localChapter = newValue }
        }
    }
    private func setChapter(_ value: Int) {
        if let linkedChapter {
            print("      📌 setChapter(\(value)): updating linkedChapter (role=\(role))")
            let oldValue = linkedChapter.wrappedValue
            linkedChapter.wrappedValue = value
            print("         ✓ linkedChapter updated: \(oldValue) → \(linkedChapter.wrappedValue)")
            print("         ✓ chapter property now returns: \(chapter)")
        } else {
            print("      📌 setChapter(\(value)): updating localChapter (role=\(role))")
            let oldValue = localChapter
            localChapter = value
            print("         ✓ localChapter updated: \(oldValue) → \(localChapter)")
            print("         ✓ chapter property now returns: \(chapter)")
        }
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
            let linkedValue = linkedChapter?.wrappedValue ?? -1
            print("📱 ReaderPane.onAppear: role=\(role), book=\(book.id), chapter=\(chapter), linked=\(linkedValue), local=\(localChapter)")
            loadRawHeadings()
            initChapterIfNeeded()
            updateTitleMapCache()
            updateVersesCache()
            isInitialized = true

            // 초기화 후 상태 불일치 재검사: chapter=0, linked≤0, local=0 시 자동 새로고침
            if chapter == 0 && linkedValue <= 0 && localChapter == 0 {
                print("⚠️  State mismatch detected after init (chap0 linked\(linkedValue) local0) - auto-refreshing")
                refreshCache()
            }
        }
        .onChange(of: bookID) { _, _ in
            let roleStr = role == .secondary ? "Secondary" : "Primary"
            print("📖 \(roleStr) bookID changed: \(book.id), chapter=\(chapter), isFollower=\(isFollower), skipChapterRestore=\(skipChapterRestore)")
            // 캐시 무효화 (새 책의 장이 이전 책과 같은 번호일 수 있으므로 항상 무효화)
            cachedBookID = ""
            // 대기 이동이 없을 때만 장 복원 (applyPending()이 대기 장을 처리함)
            if navigation.pendingChapter == nil {
                if !isFollower && !skipChapterRestore {
                    let restoredChapter = readingState.lastChapter(edition: edition, book: book)
                    print("   → Restoring chapter \(restoredChapter) for \(book.id)")
                    setChapter(restoredChapter)
                    // 처음 로드 이후 책 선택 변경만 히스토리에 추가
                    if isInitialized && role == .primary {
                        navigation.open(bookID: book.id, chapter: restoredChapter)
                    }
                } else if isFollower && chapter <= 0 {
                    // Linked secondary: ensure chapter is valid (shouldn't be 0)
                    let validChapter = max(1, readingState.lastChapter(edition: edition, book: book))
                    setChapter(validChapter)
                    print("   ✓ Secondary linked: set chapter to \(validChapter) for \(book.id)")
                }
                // 또는: skipChapterRestore가 true인데도 chapter가 0이면 강제로 초기화
                // (사이드패널 선택 후 책 선택기 선택 순서 변경 등의 엣지 케이스)
                if skipChapterRestore && chapter == 0 {
                    print("⚠️  skipChapterRestore=true but chapter=0 - force initializing for \(book.id)")
                    let validChapter = max(1, readingState.lastChapter(edition: edition, book: book))
                    setChapter(validChapter)
                }
            }
            // 캐시 업데이트 (chapter가 같아서 onChange(of: chapter)가 안 될 수 있으므로 여기서도 함)
            updateTitleMapCache()
            updateVersesCache()
            skipChapterRestore = false
        }
        .onChange(of: editionID) { _, _ in
            if !isFollower {
                // 판본 전환 시 현재 장을 유지하되, 해당 장이 없으면 첫 장으로 이동
                setChapter(clampChapter(chapter))
            }
            // Always update cache for new edition, clearing cache to force refresh
            cachedEditionID = ""  // Invalidate cache to force update
            updateTitleMapCache()
            updateVersesCache()
        }
        .onChange(of: chapter) { _, new in
            // 장이 0인 경우 자동 새로고침 (경고 상태 "ch:0 linked:0 local:0" 감지)
            if new == 0 {
                let linkedValue = linkedChapter?.wrappedValue ?? -1
                if linkedValue <= 0 && localChapter == 0 {
                    print("⚠️  Chapter became 0 with linked:\(linkedValue) local:0 - auto-refreshing")
                    refreshCache()
                    return
                }
            }

            guard new > 0 else { return }
            // 캐시 업데이트 (모든 pane에서 필요)
            updateTitleMapCache()
            updateVersesCacheWithChapter(new)

            // Follower가 아닌 경우만 추가 처리
            guard !isFollower else { return }
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
        if role == .primary, let pending = navigation.pendingChapter,
           navigation.hasPending(forBook: book.id) {
            let c = clampChapter(pending)
            setChapter(c)
            navigation.pendingChapter = nil
            scrollTarget = navigation.consumePending(forBook: book.id)
        } else {
            setChapter(readingState.lastChapter(edition: edition, book: book))
        }
    }

    private func applyPending() {
        guard role == .primary, let pending = navigation.pendingChapter else { return }
        guard navigation.hasPending(forBook: book.id) else { return }
        let c = clampChapter(pending)
        setChapter(c)
        navigation.pendingChapter = nil
        scrollTarget = navigation.consumePending(forBook: book.id)
    }

    private func clampChapter(_ c: Int) -> Int { min(max(c, 1), book.chapterCount) }

    private func step(_ delta: Int) {
        let next = chapter + delta
        guard (1...book.chapterCount).contains(next) else { return }
        scrollTarget = 1
        withAnimation(.easeInOut(duration: 0.2)) { setChapter(next) }
    }

    private func updateTitleMapCache() {
        guard chapter > 0 else {
            cachedTitleMap = [:]
            return
        }
        if cachedTitleChapter == chapter && cachedTitleEditionID == editionID && cachedTitleBookID == book.id {
            return
        }
        cachedTitleChapter = chapter
        cachedTitleEditionID = editionID
        cachedTitleBookID = book.id
        let titles = store.titles(edition: edition, book: book, chapter: chapter)
        var newMap: [String: String] = [:]
        for title in titles {
            newMap[title.verse] = title.text
        }
        cachedTitleMap = newMap
    }

    private func updateVersesCache() {
        updateVersesCacheWithChapter(chapter)
    }

    private func loadRawHeadings() {
        guard rawHeadings.isEmpty else { return }
        if let headingsURL = Bundle.main.url(forResource: "KnbHeadings_ko", withExtension: "json"),
           let headingsData = try? Data(contentsOf: headingsURL) {
            struct HeadingsFile: Decodable {
                let headings: [String: [String: [String: String]]]
            }
            if let file = try? JSONDecoder().decode(HeadingsFile.self, from: headingsData) {
                rawHeadings = file.headings
            }
        }
    }

    private func updateVersesCacheWithChapter(_ ch: Int) {
        if cachedChapter == ch && cachedEditionID == editionID && cachedBookID == book.id {
            if role == .secondary && ch > 0 {
                print("   📚 Secondary cache hit: ch=\(ch), book=\(book.id), ed=\(editionID)")
            }
            return
        }
        cachedChapter = ch
        cachedEditionID = editionID
        cachedBookID = book.id
        if ch > 0 {
            cachedVerses = store.verses(edition: edition, book: book, chapter: ch)
            if role == .secondary {
                print("   📚 Secondary loaded: ch=\(ch), book=\(book.id), ed=\(editionID), verses=\(cachedVerses.count)")
                if cachedVerses.isEmpty {
                    print("      ⚠️  EMPTY: Check if \(edition.id):\(book.id):ch\(ch) exists in store")
                }
            }
        } else {
            cachedVerses = []
            if role == .secondary {
                print("   📚 Secondary cleared: ch=\(ch)")
            }
        }
    }

    // MARK: 헤더 (판본 · 책 선택)

    private var paneHeader: some View {
        HStack(spacing: 10) {
            Menu {
                Picker("판본", selection: $editionID) {
                    ForEach(Editions.all) { ed in Text(ed.name).tag(ed.id) }
                }
            } label: {
                labelChip(edition.shortName)
            }

            Button { showBookPicker = true } label: {
                labelChip(store.bookShortName(edition: edition, book: book))
            }

            Spacer(minLength: 0)

            // Refresh button - clears cache and reloads content
            Button { refreshCache() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .accessibilityLabel("새로고침")

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

    private func verseRowContent(verse: Verse) -> some View {
        let filteredTitles = filteredTitleMap()
        return VStack(alignment: .leading, spacing: settings.lineSpacing * 0.9) {
            if let title = filteredTitles[verse.number] {
                SectionTitleView(text: title, bookID: book.id, chapter: chapter,
                                 linkable: true)
                    .environment(\.openURL, OpenURLAction { url in
                        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                        func q(_ k: String) -> String? { items.first { $0.name == k }?.value }
                        if url.scheme == "catholicbible" {
                            // 주석 마커 링크 (N))
                            if url.host == "note" {
                                if let b = q("b"), let cs = q("c"), let c = Int(cs), let n = q("n") {
                                    onOpenNote(VerseRef(bookID: b, chapter: c, verse: n), "")
                                }
                                return .handled
                            }
                            // 교차 참조 링크 (cross-reference)
                            if url.host == "xref" {
                                if let b = q("b"), let cs = q("c"), let c = Int(cs),
                                   let vs = q("v"), let v = Int(vs) {
                                    onOpenXref(XrefTarget(bookID: b, chapter: c, verse: v,
                                                          endChapter: q("ec").flatMap { Int($0) } ?? 0,
                                                          endVerse: q("ev").flatMap { Int($0) } ?? 0))
                                }
                                return .handled
                            }
                        }
                        return .systemAction
                    })
            }
            VerseRowView(edition: edition, book: book, chapter: chapter,
                         verse: verse,
                         highlighted: navigation.activeHighlight?.matches(bookID: book.id, chapter: chapter, verse: verse.number) ?? false,
                         onOpenNote: onOpenNote,
                         markerColor: UIColor(Color.accentColor))
                .environment(\.openURL, OpenURLAction { url in
                    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                    func q(_ k: String) -> String? { items.first { $0.name == k }?.value }
                    if url.scheme == "catholicbible", url.host == "xref" {
                        if let b = q("b"), let cs = q("c"), let c = Int(cs),
                           let vs = q("v"), let v = Int(vs) {
                            onOpenXref(XrefTarget(bookID: b, chapter: c, verse: v,
                                                  endChapter: q("ec").flatMap { Int($0) } ?? 0,
                                                  endVerse: q("ev").flatMap { Int($0) } ?? 0))
                        }
                        return .handled
                    }
                    if url.scheme == "catholicbible", url.host == "note" {
                        if let b = q("b"), let cs = q("c"), let c = Int(cs), let n = q("n") {
                            onOpenNote(VerseRef(bookID: b, chapter: c, verse: n), "")
                        }
                        return .handled
                    }
                    return .systemAction
                })
        }
    }

    private var versesContent: some View {
        let verses = cachedVerses
        let prologue = prologueVerses
        let regular = regularVerses
        return VStack(alignment: .leading, spacing: 0) {
            chapterHeader
            if verses.isEmpty {
                MissingTextView(edition: edition, book: book).padding(.top, 40)
            } else {
                LazyVStack(alignment: .leading, spacing: settings.lineSpacing * 0.9) {
                    // Sirach 1장 특수 제목 처리
                    if ["knb", "knbnotes"].contains(editionID) && chapter == 1 && book.id == "sir" {
                        // "시라의 지혜" (1_intro)
                        if let title = titleMap["1_intro"] {
                            SectionTitleView(text: title, bookID: book.id, chapter: chapter, linkable: true)
                                .padding(.bottom, 12)
                        }
                    }

                    // 프롤로그 절들 표시
                    if !prologue.isEmpty {
                        ForEach(prologue) { verse in
                            prologueVerseView(verse: verse)
                                .id(verse.number)
                        }
                    }

                    // Sirach 1장: "제 1 부 지혜와 금언들" (0)
                    if ["knb", "knbnotes"].contains(editionID) && chapter == 1 && book.id == "sir" {
                        if let title = titleMap["0"] {
                            SectionTitleView(text: title, bookID: book.id, chapter: chapter, linkable: true)
                                .padding(.top, prologue.isEmpty ? 0 : 12)
                                .padding(.bottom, 12)
                        }
                    }

                    // 일반 절들 표시
                    ForEach(regular) { verse in
                        // Sirach 1장: 절 11 앞에 "지혜의 신비" (1h)
                        if ["knb", "knbnotes"].contains(editionID) && chapter == 1 && book.id == "sir" && verse.number == "11" {
                            if let title = titleMap["1h"] {
                                SectionTitleView(text: title, bookID: book.id, chapter: chapter, linkable: true)
                                    .padding(.bottom, 12)
                            }
                        }
                        verseRowContent(verse: verse)
                            .id(verse.number)
                    }
                }
                .scrollTargetLayout()
                .padding(.top, 24)
                copyrightFooter
            }
        }
        .frame(maxWidth: fullWidth ? .infinity : 720, alignment: .leading)
        .padding(.horizontal, fullWidth ? 16 : 28)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity)
        .onChange(of: verses) { _, newVerses in
            if newVerses.isEmpty && role == .secondary {
                print("🔴 Secondary panel empty: edition=\(editionID), book=\(book.id), chapter=\(chapter), cachedBookID=\(cachedBookID), cachedChapter=\(cachedChapter)")
            }
        }
    }

    private func prologueView(text: String) -> some View {
        Text(text)
            .font(.system(size: settings.fontSize, weight: .regular, design: .default))
            .lineSpacing(settings.lineSpacing * 0.5)
            .foregroundStyle(settings.theme.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 8)
            .padding(.vertical, 12)
            .overlay(alignment: .leading) {
                Rectangle().fill(Color.accentColor.opacity(0.3)).frame(width: 3)
            }
    }

    /// 프롤로그 절 표시 (verse 객체 기반) - 본문과 동일한 스타일
    private func prologueVerseView(verse: Verse) -> some View {
        VerseRowView(edition: edition, book: book, chapter: chapter,
                     verse: verse,
                     highlighted: navigation.activeHighlight?.matches(bookID: book.id, chapter: chapter, verse: verse.number) ?? false,
                     onOpenNote: onOpenNote,
                     markerColor: UIColor(Color.accentColor))
    }

    private var versesScroll: some View {
        let verses = cachedVerses
        return ScrollViewReader { proxy in
            ScrollView {
                versesContent
            }
            .scrollPosition(id: $topVerse, anchor: .top)
            .onChange(of: topVerse) { _, v in
                guard let sync = syncVerse, let v, v != sync.wrappedValue else { return }
                sync.wrappedValue = v
            }
            .onChange(of: scrollTarget) { _, _ in performScroll(proxy, verses: verses) }
            .onChange(of: chapter) { _, _ in topVerse = nil; performScroll(proxy, verses: verses) }
            .task(id: syncVerse?.wrappedValue) {
                guard let sync = syncVerse, let v = sync.wrappedValue, v != topVerse else { return }
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(v, anchor: .top)
                    }
                }
            }
            .onAppear { performScroll(proxy, verses: verses) }
        }
    }

    /// 대기 이동 직후 강조 시작 절로 한 번 스크롤한다(레이아웃 뒤로 미룸). 한 번 하면 지운다.
    private func performScroll(_ proxy: ScrollViewProxy, verses: [Verse]) {
        guard let n = scrollTarget, verses.contains(where: { $0.number == String(n) }) else { return }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(String(n), anchor: .center) }
            scrollTarget = nil
        }
    }

    private var chapterHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                Text(store.bookName(edition: edition, book: book))
                    .font(.system(size: settings.fontSize * 0.85, weight: .regular, design: .default))
                    .foregroundStyle(settings.theme.secondary)
                Spacer()
                // DEBUG: Show actual chapter value
                if chapter == 0 {
                    Text("⚠️ ch:\(chapter) linked:\(linkedChapter?.wrappedValue ?? -1) local:\(localChapter)")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }

            Text(book.chapterLabel(max(chapter, 1)))
                .font(.system(size: settings.fontSize * 1.85, weight: .bold, design: .default))
                .foregroundStyle(settings.theme.text)

            HStack(spacing: 8) {
                Capsule()
                    .fill(Color.accentColor.opacity(0.4))
                    .frame(width: 44, height: 3)
                Spacer()
            }
        }
        .padding(.top, 28)
        .padding(.bottom, 8)
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
        print("🎯 parseBookSelection: role=\(role), picked=\(picked)")
        if components.count == 2, let chapterNum = Int(components[1]) {
            let newBookID = components[0]
            print("   → setting skipChapterRestore=true (prevent lastChapter restore)")
            skipChapterRestore = true

            print("   → setting chapter=\(chapterNum) first")
            // Set chapter FIRST (before bookID) so onChange(of: chapter) triggers with correct value
            if let linked = linkedChapter {
                linked.wrappedValue = chapterNum
            } else {
                localChapter = chapterNum
            }

            print("   → setting bookID=\(newBookID)")
            // Change bookID last - this triggers onChange(of: bookID) which handles cache
            bookID = newBookID

            print("   ✓ Done. onChange handlers will handle cache updates")
        } else {
            print("   → setting bookID=\(picked)")
            bookID = picked
        }
    }

    /// 캐시를 완전히 무효화하고 데이터를 다시 로드 (상태 불일치, 본문준비중 해결용)
    private func refreshCache() {
        print("🔄 Refreshing cache for role=\(role), book=\(book.id), chapter=\(chapter), edition=\(editionID)")

        // 1. Clear all caches
        cachedBookID = ""
        cachedChapter = -1
        cachedEditionID = ""
        cachedVerses = []
        cachedTitleMap = [:]
        cachedTitleChapter = -1
        cachedTitleEditionID = ""
        cachedTitleBookID = ""

        // 2. Ensure chapter is valid (not 0)
        let validChapter = chapter > 0 ? chapter : 1
        if chapter <= 0 {
            print("   ⚠️  Chapter was \(chapter), setting to 1")
            if let linked = linkedChapter {
                linked.wrappedValue = validChapter
            } else {
                localChapter = validChapter
            }
        }

        // 3. Reload everything with valid chapter
        updateTitleMapCache()
        updateVersesCacheWithChapter(validChapter)

        print("✅ Cache refreshed: got \(cachedVerses.count) verses for \(book.id) ch.\(validChapter)")
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
            HStack(spacing: 12) {
                Button { step(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                }
                .disabled(chapter <= 1)
                .opacity(chapter <= 1 ? 0.4 : 1)

                Slider(value: Binding(get: { Double(chapter) },
                                      set: { move(to: Int($0.rounded())) }),
                       in: 1...Double(book.chapterCount), step: 1)
                    .accessibilityLabel("장 이동")
                    .accessibilityValue(book.chapterLabel(chapter))

                Button { step(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                }
                .disabled(chapter >= book.chapterCount)
                .opacity(chapter >= book.chapterCount ? 0.4 : 1)

                Button { showPicker = true } label: {
                    Text(book.chapterLabel(chapter))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .frame(minWidth: 44, alignment: .center)
                }
                .foregroundStyle(settings.theme.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(settings.theme.background.opacity(0.95))
            .overlay(alignment: .top) {
                Rectangle().fill(settings.theme.secondary.opacity(0.15)).frame(height: 1)
            }
            .sheet(isPresented: $showPicker) {
                ChapterPickerView(book: book, current: max(chapter, 1)) { picked in
                    move(to: picked)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        showPicker = false
                    }
                }
            }
        }
    }

    private func setChapter(_ value: Int) {
        chapter = value
    }

    private func step(_ delta: Int) {
        let n = chapter + delta
        guard (1...book.chapterCount).contains(n) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { move(to: n) }
    }

    private func move(to n: Int) {
        // 상태 동기화 문제를 피하기 위해 조건 없이 항상 chapter을 업데이트
        onChange()
        setChapter(n)
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
    /// 공유하는 장 바인딩(없으면 자체 장 관리).
    var sharedChapter: Binding<Int>? = nil
    /// 이 리더가 담당하는 책(대기 이동 가로채기 방지용).
    var ownerBookID: String = ""
    let onOpenNote: (VerseRef, String) -> Void
    let onOpenXref: (XrefTarget) -> Void

    @Environment(BibleStore.self) private var store
    @Environment(ReaderSettings.self) private var settings
    @Environment(ReadingState.self) private var readingState
    @Environment(ReaderNavigation.self) private var navigation
    @Environment(KnbNotesStore.self) private var knbNotes

    @State private var localChapter = 0
    @State private var spreadIndex = 0
    @State private var wantLastSpread = false
    /// 대기 이동 직후 그 절이 있는 펼침면으로 한 번 이동하기 위한 목표 절.
    @State private var scrollTarget: Int?
    @State private var contentSize: CGSize = .zero
    @State private var showBookPicker = false
    @State private var showChapterPicker = false
    @State private var skipChapterRestore = false

    private var edition: Edition { Editions.edition(editionID) ?? Editions.all[0] }
    private var book: BibleBook { Bible.book(bookID) ?? Bible.books[0] }
    /// 공유 장이 있으면 그것을 사용, 없으면 로컬 장
    private var chapter: Int {
        get { sharedChapter?.wrappedValue ?? localChapter }
        set {
            if let sharedChapter { sharedChapter.wrappedValue = newValue } else { localChapter = newValue }
        }
    }
    private func setChapter(_ value: Int) {
        print("🔧 SpreadReader.setChapter(\(value)): sharedChapter=\(sharedChapter != nil)")
        if let sharedChapter { sharedChapter.wrappedValue = value } else { localChapter = value }
    }
    private var verses: [Verse] {
        guard chapter > 0 else { return [] }
        let rawVerses = store.verses(edition: edition, book: book, chapter: chapter)
        // Sirach 1장: 프롤로그 절들을 먼저, 일반 절들을 나중에 표시
        if book.id == "sir" && chapter == 1 {
            let prologue = rawVerses.filter { $0.number.contains("(") && $0.number.contains(")") }
            let regular = rawVerses.filter { !($0.number.contains("(") && $0.number.contains(")")) }
            // 프롤로그 절들을 번호 순서대로 정렬
            let sortedPrologue = prologue.sorted { a, b in
                let numA = Int(a.number.dropFirst().dropLast()) ?? 0
                let numB = Int(b.number.dropFirst().dropLast()) ?? 0
                return numA < numB
            }
            return sortedPrologue + regular
        }
        return rawVerses
    }
    private var pages: [[Verse]] { paginate(verses, size: contentSize) }
    private var spreadCount: Int { max(1, Int(ceil(Double(pages.count) / 2.0))) }

    private var showsTitles: Bool { true }
    private var titleMap: [String: String] {
        guard showsTitles, chapter > 0 else { return [:] }

        // KNB Notes의 제목 먼저 확인 (Int 키를 String으로 변환)
        var titlesByVerse: [String: String] = knbNotes.titlesByVerse(edition: edition.id, bookID: book.id, chapter: chapter)
            .mapValues { AnnotationMarkup.stripMarkers($0) }
            .reduce(into: [:]) { result, pair in result[String(pair.key)] = pair.value }

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
            // 대기 이동이 없을 때만 마지막 장을 복원 (applyPending()이 대기 장을 처리함)
            if navigation.pendingChapter == nil && !skipChapterRestore {
                setChapter(readingState.lastChapter(edition: edition, book: book))
                spreadIndex = 0
            }
            skipChapterRestore = false
        }
        .onChange(of: editionID) { _, _ in
            setChapter(min(max(chapter, 1), book.chapterCount)); spreadIndex = 0
        }
        .onChange(of: chapter) { _, new in
            guard new > 0 else { return }
            // Reset spreadIndex when chapter changes (unless scrollTarget is set for pending navigation)
            if scrollTarget == nil {
                spreadIndex = 0
            }
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
                setChapter(picked); spreadIndex = 0; showChapterPicker = false
            }
        }
    }

    // MARK: 위치

    private func initChapterIfNeeded() {
        guard chapter == 0 else { return }
        if navigation.hasPending(forBook: ownerBookID), let p = navigation.pendingChapter {
            setChapter(clampChapter(p)); navigation.pendingChapter = nil
            scrollTarget = navigation.consumePending(forBook: ownerBookID)
        } else {
            setChapter(readingState.lastChapter(edition: edition, book: book))
        }
    }

    private func applyPending() {
        guard let p = navigation.pendingChapter else { return }
        guard navigation.hasPending(forBook: book.id) else { return }
        setChapter(clampChapter(p)); navigation.pendingChapter = nil
        scrollTarget = navigation.consumePending(forBook: book.id)
        spreadIndex = 0
    }

    private func refreshCache() {
        guard chapter <= 0 else { return }
        let validChapter = readingState.lastChapter(edition: edition, book: book)
        setChapter(validChapter)
        spreadIndex = 0
    }

    private func clampChapter(_ c: Int) -> Int { min(max(c, 1), book.chapterCount) }

    /// 페이지 수가 바뀌면 목표 스프레드(마지막/강조 절)로 맞춘다.
    private func reconcileSpreadIndex() {
        if wantLastSpread {
            spreadIndex = max(0, spreadCount - 1); wantLastSpread = false
        } else if let h = scrollTarget,
                  let pageIdx = pages.firstIndex(where: { $0.contains { $0.number == String(h) } }) {
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
        setChapter(n)
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
            } label: { chip(edition.shortName) }
            Button { showBookPicker = true } label: {
                chip(store.bookShortName(edition: edition, book: book))
            }
            Spacer(minLength: 0)
            Button { refreshCache() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .accessibilityLabel("새로고침")
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
        let firstRegularVerseNumber = verses?.first(where: { !$0.number.contains("(") && !$0.number.contains(")") })?.number

        VStack(alignment: .leading, spacing: settings.lineSpacing * 0.9) {
            if isFirst { chapterHeader }

            // Sirach 1장 특수 제목들 (첫 페이지에만 표시)
            if isFirst && ["knb", "knbnotes"].contains(editionID) && chapter == 1 && book.id == "sir" {
                if let title = titleMap["1_intro"] {
                    SectionTitleView(text: title, bookID: book.id, chapter: chapter, linkable: true)
                        .padding(.bottom, 12)
                }
            }

            if let verses {
                ForEach(verses) { verse in
                    // Sirach 1장: 첫 번째 일반 절 앞에 "제 1 부 지혜와 금언들" (0)
                    if isFirst && ["knb", "knbnotes"].contains(editionID) && chapter == 1 && book.id == "sir"
                        && verse.number == firstRegularVerseNumber {
                        if let title = titleMap["0"] {
                            SectionTitleView(text: title, bookID: book.id, chapter: chapter, linkable: true)
                                .padding(.bottom, 12)
                        }
                    }
                    if let title = titleMap[verse.number] {
                        SectionTitleView(text: title, bookID: book.id, chapter: chapter,
                                                         linkable: true)
                            .environment(\.openURL, OpenURLAction { url in
                                let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                                func q(_ k: String) -> String? { items.first { $0.name == k }?.value }
                                if url.scheme == "catholicbible" {
                                    // 주석 마커 링크 (N))
                                    if url.host == "note" {
                                        if let b = q("b"), let cs = q("c"), let c = Int(cs), let n = q("n") {
                                            onOpenNote(VerseRef(bookID: b, chapter: c, verse: n), "")
                                        }
                                        return .handled
                                    }
                                    // 교차 참조 링크 (cross-reference)
                                    if url.host == "xref" {
                                        if let b = q("b"), let cs = q("c"), let c = Int(cs),
                                           let vs = q("v"), let v = Int(vs) {
                                            onOpenXref(XrefTarget(bookID: b, chapter: c, verse: v,
                                                                  endChapter: q("ec").flatMap { Int($0) } ?? 0,
                                                                  endVerse: q("ev").flatMap { Int($0) } ?? 0))
                                        }
                                        return .handled
                                    }
                                }
                                return .systemAction
                            })
                    }

                    // Sirach 1장: 절 11 앞에 "지혜의 신비" (1h)
                    if isFirst && ["knb", "knbnotes"].contains(editionID) && chapter == 1 && book.id == "sir" && verse.number == "11" {
                        if let title = titleMap["1h"] {
                            SectionTitleView(text: title, bookID: book.id, chapter: chapter, linkable: true)
                                .padding(.top, 12)
                                .padding(.bottom, 12)
                        }
                    }

                    VerseRowView(edition: edition, book: book, chapter: chapter,
                                 verse: verse,
                                 highlighted: navigation.activeHighlight?.matches(bookID: book.id, chapter: chapter, verse: verse.number) ?? false,
                                 onOpenNote: onOpenNote,
                                 markerColor: UIColor(Color.accentColor))
                        .environment(\.openURL, OpenURLAction { url in
                            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                            func q(_ k: String) -> String? { items.first { $0.name == k }?.value }
                            if url.scheme == "catholicbible", url.host == "xref" {
                                if let b = q("b"), let cs = q("c"), let c = Int(cs),
                                   let vs = q("v"), let v = Int(vs) {
                                    onOpenXref(XrefTarget(bookID: b, chapter: c, verse: v,
                                                          endChapter: q("ec").flatMap { Int($0) } ?? 0,
                                                          endVerse: q("ev").flatMap { Int($0) } ?? 0))
                                }
                                return .handled
                            }
                            if url.scheme == "catholicbible", url.host == "note" {
                                if let b = q("b"), let cs = q("c"), let c = Int(cs), let n = q("n") {
                                    onOpenNote(VerseRef(bookID: b, chapter: c, verse: n), "")
                                }
                                return .handled
                            }
                            return .systemAction
                        })
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
            print("📖 parseBookSelection(SpreadReader): picked=\(picked), chapterNum=\(chapterNum), book=\(components[0])")
            print("   → setting skipChapterRestore=true (prevent lastChapter restore)")
            skipChapterRestore = true

            print("   → setting chapter=\(chapterNum) first")
            // Set chapter FIRST (before bookID) so onChange(of: chapter) triggers with correct value
            setChapter(chapterNum)
            spreadIndex = 0

            print("   → setting bookID=\(picked)")
            // Change bookID last - this triggers onChange(of: bookID) which handles cache/restore
            bookID = components[0]

            print("   ✓ Done. onChange handlers will handle state updates")
        } else {
            print("   → setting bookID=\(picked)")
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
    /// 검색 쿼리 - 해당 단어를 하이라이트
    var searchQuery: String = ""

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

        // 마크다운 링크([텍스트](URL)) → NSAttributedString 링크로 변환
        let (processedText, markdownLinks) = Self.processMarkdownLinks(text)

        let para = NSMutableParagraphStyle()
        para.lineSpacing = lineSpacing
        let attr = NSMutableAttributedString(string: processedText, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: para,
        ])

        // 마크다운 링크([텍스트](URL)) 처리
        for link in markdownLinks {
            if let url = URL(string: link.urlString) {
                // 범위 검증
                if link.range.location >= 0 && link.range.location + link.range.length <= attr.length {
                    var linkAttrs: [NSAttributedString.Key: Any] = [.link: url]
                    // 링크 텍스트 색상 설정 (accent color)
                    linkAttrs[.foregroundColor] = UIColor(Color.accentColor)
                    attr.addAttributes(linkAttrs, range: link.range)
                    print("🔗 [SelectableVerseText] markdown link added: '\(link.text)' → \(link.urlString)")
                } else {
                    print("⚠️ [SelectableVerseText] markdown link range invalid: location=\(link.range.location), length=\(link.range.length), attr.length=\(attr.length)")
                }
            }
        }

        // 각주 마커 'N)'를 본문과 다른 색·작은 위첨자로 표시하고, 탭하면 주석이 열리게 한다.
        if let markerColor, let regex = Self.markerRegex {
            let ns = processedText as NSString
            let markerFont = font.withSize(max(font.pointSize * 0.72, 9))
            let matches = regex.matches(in: processedText, range: NSRange(location: 0, length: ns.length))
            print("📌 [SelectableVerseText] marker regex: found \(matches.count) matches in text")
            for m in matches {
                // 범위 검증
                if m.range.location >= 0 && m.range.location + m.range.length <= attr.length {
                    let n = ns.substring(with: m.range(at: 1))
                    let urlString = "catholicbible://note?b=\(bookID)&c=\(chapter)&n=\(n)"
                    print("   📌 marker match: '\(n)' at range \(m.range) → url: \(urlString)")
                    var attrs: [NSAttributedString.Key: Any] = [
                        .foregroundColor: markerColor,
                        .font: markerFont,
                        .baselineOffset: font.pointSize * 0.28,
                    ]
                    if let url = URL(string: urlString) {
                        attrs[.link] = url
                        print("   ✓ link added for marker '\(n)'")
                    } else {
                        print("   ✗ failed to create URL for marker '\(n)'")
                    }
                    attr.addAttributes(attrs, range: m.range)
                } else {
                    print("   ⚠️ marker range out of bounds: \(m.range) vs attr.length \(attr.length)")
                }
            }
            tv.linkTextAttributes = [.foregroundColor: markerColor]
            print("📌 [SelectableVerseText] linkTextAttributes set")
        } else {
            if markerColor == nil {
                print("📌 [SelectableVerseText] no markerColor, skipping marker setup")
            } else {
                print("📌 [SelectableVerseText] regex is nil, cannot process markers")
            }
        }

        // 본문 내 상호참조(예: "마르 8,11-13") 파싱 및 링크화
        ScriptureRef.addLinks(to: attr, currentBook: bookID, color: UIColor(Color.accentColor), chapter: chapter)

        // 검색 쿼리에 해당하는 단어 하이라이트
        if !searchQuery.isEmpty {
            let ns = processedText as NSString
            let searchLower = searchQuery.lowercased()
            let textLower = processedText.lowercased()
            var searchRange = NSRange(location: 0, length: 0)
            while searchRange.location + searchRange.length < ns.length {
                searchRange = (textLower as NSString).range(
                    of: searchLower,
                    options: [.caseInsensitive],
                    range: NSRange(location: searchRange.location + searchRange.length,
                                 length: ns.length - (searchRange.location + searchRange.length))
                )
                if searchRange.location == NSNotFound { break }
                if searchRange.location >= 0 && searchRange.location + searchRange.length <= attr.length {
                    attr.addAttribute(.backgroundColor, value: UIColor.yellow.withAlphaComponent(0.3), range: searchRange)
                }
            }
        }

        tv.attributedText = attr
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0, width.isFinite else { return nil }
        let fit = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fit.height))
    }

    /// 마크다운 링크 [텍스트](URL)를 처리: 텍스트만 남기고 URL 범위 정보 반환
    private static func processMarkdownLinks(_ text: String) -> (String, [MarkdownLink]) {
        let pattern = "\\[([^\\]]+)\\]\\(([^)]+)\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return (text, [])
        }

        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))

        var links: [MarkdownLink] = []
        let processedText = NSMutableString(string: text)

        // 뒤에서부터 처리해야 앞의 인덱스가 영향을 받지 않음
        for match in matches.reversed() {
            let fullRange = match.range  // [텍스트](URL) 전체
            let textRange = match.range(at: 1)  // [텍스트] 부분
            let urlRange = match.range(at: 2)   // (URL) 부분

            let linkText = ns.substring(with: textRange)
            let urlString = ns.substring(with: urlRange)

            // [텍스트](URL)를 텍스트만 남기도록 제거
            processedText.replaceCharacters(in: fullRange, with: linkText)

            // 새로운 위치에서의 텍스트 범위 계산
            let newStart = fullRange.location
            let newLength = linkText.count

            links.append(MarkdownLink(text: linkText, urlString: urlString, range: NSRange(location: newStart, length: newLength)))
        }

        return (processedText as String, links.reversed())
    }

    /// 마크다운 링크 정보
    struct MarkdownLink {
        let text: String
        let urlString: String
        let range: NSRange
    }

    // 인용 참조의 닫는 괄호(예: "1,19-28)")를 각주 마커로 오인하지 않도록
    // 숫자 앞이 하이픈·쉼표·마침표·숫자·'('이면 마커로 보지 않는다.
    private static let markerRegex = try? NSRegularExpression(pattern: "(?<![-,.\\d(])(\\d{1,3})\\)")

    final class Coordinator: NSObject, UITextViewDelegate {
        var onOpenURL: ((URL) -> Void)?
        init(onOpenURL: ((URL) -> Void)?) { self.onOpenURL = onOpenURL }

        /// iOS 17+: 마커 링크 탭 → 앱 내 주석 팝업으로 보낸다.
        func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem,
                      defaultAction: UIAction) -> UIAction? {
            print("🔗 [SelectableVerseText.Coordinator] primaryActionFor called, item content: \(textItem.content)")
            if case .link(let url) = textItem.content {
                print("🔗 [SelectableVerseText.Coordinator] link tapped: \(url)")
                return UIAction { [onOpenURL] _ in
                    print("🔗 [SelectableVerseText.Coordinator] calling onOpenURL with: \(url)")
                    onOpenURL?(url)
                }
            }
            print("🔗 [SelectableVerseText.Coordinator] not a link, returning defaultAction")
            return defaultAction
        }

        /// iOS 15-16: shouldInteractWith를 사용한 링크 처리
        func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
            print("🔗 [SelectableVerseText.Coordinator] shouldInteractWith called: \(URL)")
            if interaction == .invokeDefaultAction {
                print("🔗 [SelectableVerseText.Coordinator] invoking default action for: \(URL)")
                onOpenURL?(URL)
                return false  // 기본 동작(Safari 열기) 방지
            }
            return true
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
    /// '사전 열기' 처리를 상위가 직접 하고 싶을 때(예: 전체 화면인 매일미사).
    /// nil이면 공용 navigation.lookUp()을 쓴다.
    var onLookUp: (() -> Void)? = nil
    /// 각주 마커 색상. nil이면 마커를 표시하지 않는다. AnnotatedReader에서 명시적으로 설정 가능.
    var markerColor: UIColor? = nil

    @Environment(ReaderSettings.self) private var settings
    @Environment(AnnotationStore.self) private var annotations
    @Environment(ReaderNavigation.self) private var navigation
    @Environment(\.openURL) private var openURL

    private var ref: VerseRef { VerseRef(bookID: book.id, chapter: chapter, verse: verse.number) }

    /// 주석 성경일 때만 각주 마커('N)')를 강조·링크로 만든다.
    private var isAnnotationEdition: Bool { markerColor != nil || edition.id == "knbnotes" }

    /// 본문 뷰: UIKit 선택 텍스트뷰. 낱말을 선택하면 네이티브 하이라이트가 보이고,
    /// 선택 메뉴의 ‘찾아보기’로 시스템 사전이 열린다. 주석 성경에서는 각주 마커가
    /// 본문과 다른 색·위첨자로 표시되고, 탭하면 해당 주석이 열린다.
    private var verseTextView: some View {
        let formattedText = formatVerseTextWithParenthetical(verse.text)
        let color = markerColor ?? (isAnnotationEdition ? UIColor(Color.accentColor) : nil)
        return SelectableVerseText(text: formattedText,
                            font: uiBodyFont,
                            color: UIColor(settings.theme.text),
                            lineSpacing: settings.lineSpacing,
                            markerColor: color,
                            bookID: book.id,
                            chapter: chapter,
                            onOpenURL: { openURL($0) },
                            searchQuery: navigation.searchQuery)
    }

    private func formatVerseTextWithParenthetical(_ text: String) -> String {
        // Parenthetical 절 마커(예: 1(1), 2(3) 등) 앞에 줄바꿈 추가
        // 패턴: 공백 + 숫자 + 괄호 (예: " 1(", " 12(")
        do {
            let pattern = "\\s+(\\d+\\()"
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, options: [], range: range)

            var result = text
            // 뒤에서 앞으로 순회하여 문자열 인덱스 변화 방지
            for match in matches.reversed() {
                if let range = Range(match.range, in: text) {
                    let startIndex = range.lowerBound
                    let markerStart = text.index(after: startIndex)
                    result.replaceSubrange(startIndex..<markerStart, with: "\n")
                }
            }
            return result
        } catch {
            return text
        }
    }

    private var uiBodyFont: UIFont {
        let size = settings.fontSize
        if edition.language == "en" {
            switch settings.englishFontChoice {
            case .georgia: return UIFont(name: "Georgia", size: size) ?? .systemFont(ofSize: size)
            case .sanfrancisco: return .systemFont(ofSize: size)
            case .palatino: return UIFont(name: "Palatino", size: size) ?? UIFont(name: "Palatino Linotype", size: size) ?? .systemFont(ofSize: size)
            case .charter: return UIFont(name: "Charter", size: size) ?? UIFont(name: "Bitstream Charter", size: size) ?? .systemFont(ofSize: size)
            }
        } else {
            switch settings.fontChoice {
            case .myeongjo: return UIFont(name: "NanumMyeongjo", size: size) ?? .systemFont(ofSize: size)
            case .gothic:   return .systemFont(ofSize: size)
            }
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
            Button(action: { annotations.toggleBookmark(ref) }) {
                Label(bookmarked ? "책갈피 지우기" : "책갈피",
                      systemImage: bookmarked ? "bookmark.slash" : "bookmark")
            }
            Button(action: { onOpenNote(ref, verse.text) }) {
                Label(hasNote ? "노트 보기·편집" : "노트 추가", systemImage: "note.text")
            }
            Button(action: { if let onLookUp { onLookUp() } else { navigation.lookUp() } }) {
                Label("사전 열기", systemImage: "character.book.closed")
            }
            Button(action: { UIPasteboard.general.string = "\(verse.text) (\(ref.reference))" }) {
                Label("복사", systemImage: "doc.on.doc")
            }
        } label: {
            handleLabel(bookmarked: bookmarked, hasNote: hasNote)
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("\(verse.number)절 동작")
    }

    private func handleLabel(bookmarked: Bool, hasNote: Bool) -> some View {
        let textColor = bookmarked || hasNote ? Color.accentColor : settings.theme.secondary
        return Text("\(verse.number)")
            .font(settings.fontChoice.font(size: settings.fontSize * 0.62, bold: bookmarked || hasNote))
            .foregroundStyle(textColor)
            .frame(minWidth: settings.fontSize * 1.1, alignment: .trailing)
            .opacity(bookmarked || hasNote ? 1 : 0.7)
    }

    @ViewBuilder
    private func indicators(bookmarked: Bool, hasNote: Bool) -> some View {
        HStack(spacing: 6) {
            if hasNote {
                Image(systemName: "note.text.badge.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            if bookmarked {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.trailing, 4)
        .padding(.top, 2)
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
    @State private var searchText = ""
    @State private var selectedCategory: BookCategory?

    var body: some View {
        NavigationStack {
            if let book = selectedBook {
                chapterView(book)
            } else {
                bookList
            }
        }
    }

    private var filteredBooks: [BibleBook] {
        let books = edition.scope.books
        if searchText.isEmpty {
            return books
        }
        return books.filter { book in
            let name = store.bookName(edition: edition, book: book)
            let shortName = store.bookShortName(edition: edition, book: book)
            return name.localizedCaseInsensitiveContains(searchText) ||
                   shortName.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var availableCategories: [BookCategory] {
        let books = filteredBooks
        return BookCategory.allCases.filter { category in
            books.contains { $0.category == category }
        }
    }

    private var bookList: some View {
        VStack(spacing: 0) {
            if searchText.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(availableCategories) { category in
                            Button(action: { selectedCategory = category }) {
                                Text(category.title)
                                    .font(.body.weight(selectedCategory == category ? .semibold : .regular))
                                    .foregroundStyle(selectedCategory == category ? .white : .primary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(selectedCategory == category ? Color.blue : Color(.systemGray6))
                                    .cornerRadius(8)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                Divider()
            }

            List {
                if filteredBooks.isEmpty && !searchText.isEmpty {
                    Section {
                        Text("검색 결과 없음")
                            .foregroundStyle(.secondary)
                    }
                } else if !searchText.isEmpty {
                    ForEach(availableCategories) { category in
                        let books = filteredBooks.filter { $0.category == category }
                        if !books.isEmpty {
                            Section(category.title) {
                                ForEach(books) { book in row(book) }
                            }
                        }
                    }
                } else if let selected = selectedCategory {
                    let books = filteredBooks.filter { $0.category == selected }
                    ForEach(books) { book in row(book) }
                }
            }
            .listStyle(.insetGrouped)
        }
        .searchable(text: $searchText, prompt: "책 이름으로 검색")
        .navigationTitle("\(edition.shortName) · 책 선택")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } }
        }
        .onAppear {
            if selectedCategory == nil, let first = availableCategories.first {
                selectedCategory = first
            }
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
        return Button {
            // Select book → go to chapter 1 directly
            onPick("\(book.id)-1")
            dismiss()
        } label: {
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    Picker("배경", selection: $settings.theme) {
                        ForEach(ReaderTheme.allCases) { theme in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(theme.background)
                                    .stroke(theme.secondary.opacity(0.3), lineWidth: 1.5)
                                    .frame(width: 28, height: 28)

                                Text(theme.label)
                                    .font(.system(size: 15, weight: .regular, design: .default))
                            }
                            .tag(theme)
                        }
                    }
                    .pickerStyle(.navigationLink)
                } header: {
                    Label("테마 선택", systemImage: "paintpalette")
                        .font(.system(size: 14, weight: .semibold, design: .default))
                }

                Section {
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Text("A")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(.secondary)
                            Slider(value: $settings.fontSize, in: ReaderSettings.fontSizeRange, step: 1)
                            Text("A")
                                .font(.system(size: 20, weight: .regular))
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Text("현재 크기")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(settings.fontSize))pt")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Label("가독성", systemImage: "textformat.size")
                        .font(.system(size: 14, weight: .semibold, design: .default))
                }

                Section("줄 간격") {
                    VStack(spacing: 12) {
                        Slider(value: $settings.lineSpacingFactor, in: 0.35...1.1)

                        HStack {
                            Text("좁음")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("넓음")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Picker("한글 서체", selection: $settings.fontChoice) {
                        ForEach(FontChoice.allCases) { choice in
                            Text(choice.label)
                                .font(.system(size: 15, weight: .regular, design: .default))
                                .tag(choice)
                        }
                    }
                    .pickerStyle(.navigationLink)
                } header: {
                    Label("글꼴", systemImage: "character.textbox")
                        .font(.system(size: 14, weight: .semibold, design: .default))
                }

                Section {
                    Picker("영문 서체", selection: $settings.englishFontChoice) {
                        ForEach(EnglishFontChoice.allCases) { choice in
                            Text(choice.label)
                                .font(.system(size: 15, weight: .regular, design: .default))
                                .tag(choice)
                        }
                    }
                    .pickerStyle(.navigationLink)
                } header: {
                    Label("영문 글꼴", systemImage: "a")
                        .font(.system(size: 14, weight: .semibold, design: .default))
                }
            }
            .navigationTitle("보기 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                        .font(.system(size: 15, weight: .semibold, design: .default))
                }
            }
        }
    }
}
