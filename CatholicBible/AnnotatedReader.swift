//
//  AnnotatedReader.swift
//  CatholicBible
//
//  주석 성경(knbnotes) 전용 리더: 왼쪽에 본문(주석 마커 포함), 오른쪽에 주석.
//  '입문(Introduction)'도 같은 방식(본문 + 주석)으로 본다.
//  넓은 화면(iPad)은 좌·우 나란히, 좁은 화면(iPhone)은 본문 아래 주석.
//

import SwiftUI
import UIKit

struct AnnotatedReader: View {
    @Binding var editionID: String
    @Binding var bookID: String
    /// 공유하는 장 바인딩(없으면 자체 장 관리).
    var sharedChapter: Binding<Int>? = nil
    /// 이 리더가 담당하는 책(대기 이동 가로채기 방지용).
    var ownerBookID: String = ""
    /// 헤더를 표시할지 (False면 상단 툴바에서 판본·책을 선택).
    var showHeader: Bool = true
    let onOpenNote: (VerseRef, String) -> Void

    @Environment(BibleStore.self) private var store
    @Environment(ReaderSettings.self) private var settings
    @Environment(ReadingState.self) private var readingState
    @Environment(ReaderNavigation.self) private var navigation
    @Environment(KnbNotesStore.self) private var knb
    @Environment(AnnotationStore.self) private var annotations
    @Environment(\.horizontalSizeClass) private var hSize

    @State private var localChapter = 0
    /// 대기 이동 직후 한 번 스크롤할 절(강조 색은 navigation.activeHighlight가 담당).
    @State private var scrollTarget: Int?
    @State private var showBookPicker = false
    @State private var showChapterPicker = false
    @State private var showIntros = false
    /// AnnotatedReader 초기화 완료 후 장 선택 변경만 감지하기 위한 플래그
    @State private var isInitialized = false
    /// 주석·상호참조에서 탭한 인용 구절 미리보기 대상
    @State private var xrefTarget: XrefTarget?
    /// 각주 마커 팝업 대상
    @State private var noteTarget: MarkerNoteTarget?
    /// 부모(ReaderView 등)가 설치한 각주 마커 처리 액션에 위임하기 위해 보관
    @Environment(\.openURL) private var parentOpenURL

    private var edition: Edition { Editions.edition(editionID) ?? Editions.all[0] }
    private var book: BibleBook { Bible.book(bookID) ?? Bible.books[0] }
    private var wide: Bool { hSize == .regular }
    /// 공유 장이 있으면 그것을 사용, 없으면 로컬 장
    private var chapter: Int {
        get { sharedChapter?.wrappedValue ?? localChapter }
        set {
            if let sharedChapter { sharedChapter.wrappedValue = newValue } else { localChapter = newValue }
        }
    }

    private func setChapter(_ value: Int) {
        if let sharedChapter { sharedChapter.wrappedValue = value } else { localChapter = value }
    }

    var body: some View {
        Group {
            VStack(spacing: 0) {
                if showHeader { header }
                content
                chapterBar
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                initChapterIfNeeded()
                isInitialized = true
            }
            .onChange(of: bookID) { _, _ in
                setChapter(readingState.lastChapter(edition: edition, book: book))
            }
            .onChange(of: chapter) { _, new in
                guard new > 0 else { return }
                // 장 네비게이션으로 변경: 첫 절로 (위의 네비게이션 chevron은 scrollTarget을 이미 설정함)
                if isInitialized && scrollTarget == nil {
                    scrollTarget = 1
                }
                readingState.savePosition(edition: edition, book: book, chapter: new)
            }
            .onChange(of: navigation.pendingChapter) { _, _ in applyPending() }
            .sheet(isPresented: $showBookPicker) {
                BookPickerView(edition: edition, current: bookID) { picked in
                    parseBookSelection(picked)
                    showBookPicker = false
                }
                .environment(store)   // Mac Catalyst: 모달 환경 전파 대비
            }
            .fullScreenCover(isPresented: $showChapterPicker) {
                ChapterPickerView(book: book, current: max(chapter, 1)) { picked in
                    setChapter(picked); showChapterPicker = false
                }
            }
            .fullScreenCover(isPresented: $showIntros) {
                IntroductionsView(currentBookID: bookID, editionID: editionID)
                    .environment(knb)
                    .environment(settings)
                    .environment(store)
                    .environment(annotations)
                    .environment(navigation)
            }
            .fullScreenCover(item: $xrefTarget) { t in
                RefPreviewSheet(target: t)
                    .environment(store)
                    .environment(settings)
                    .environment(annotations)
                    .environment(navigation)
                    .environment(knb)
            }
            .fullScreenCover(item: $noteTarget) { t in
                MarkerNoteSheet(n: t.n, text: t.text, bookID: t.bookID, chapter: t.chapter)
                    .environment(store)
                    .environment(settings)
                    .environment(annotations)
                    .environment(navigation)
                    .environment(knb)
            }
        }
        // 주석·상호참조의 성경 인용(catholicbible://xref)과 각주 마커(catholicbible://note)는
        // 여기서 중첩 미리보기로 처리하고, 나머지는 부모 처리에 위임한다.
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == "catholicbible", url.host == "xref" {
                let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                func q(_ k: String) -> String? { items.first { $0.name == k }?.value }
                if let b = q("b"), let cs = q("c"), let c = Int(cs),
                   let vs = q("v"), let v = Int(vs) {
                    xrefTarget = XrefTarget(bookID: b, chapter: c, verse: v,
                                            endChapter: q("ec").flatMap { Int($0) } ?? 0,
                                            endVerse: q("ev").flatMap { Int($0) } ?? 0)
                }
                return .handled
            }
            if url.scheme == "catholicbible", url.host == "note" {
                let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                func q(_ k: String) -> String? { items.first { $0.name == k }?.value }
                if let b = q("b"), let cs = q("c"), let c = Int(cs), let n = q("n"),
                   let text = knb.notes(edition: editionID, bookID: b, chapter: c)
                    .first(where: { $0.n == n })?.text {
                    noteTarget = MarkerNoteTarget(n: n, text: text, bookID: b, chapter: c)
                }
                return .handled
            }
            parentOpenURL(url)          // 나머지는 부모(ReaderView)가 처리
            return .handled
        })
    }

    // MARK: 위치

    private func initChapterIfNeeded() {
        guard chapter == 0 else { return }
        if navigation.hasPending(forBook: ownerBookID), let p = navigation.pendingChapter {
            setChapter(min(max(p, 1), book.chapterCount))
            navigation.pendingChapter = nil
            scrollTarget = navigation.consumePending(forBook: ownerBookID)
        } else {
            setChapter(readingState.lastChapter(edition: edition, book: book))
        }
    }

    private func applyPending() {
        guard navigation.hasPending(forBook: ownerBookID), let p = navigation.pendingChapter else { return }
        setChapter(min(max(p, 1), book.chapterCount))
        navigation.pendingChapter = nil
        scrollTarget = navigation.consumePending(forBook: ownerBookID)
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

    private func step(_ d: Int) {
        let n = chapter + d
        guard (1...book.chapterCount).contains(n) else { return }
        scrollTarget = 1
        withAnimation(.easeInOut(duration: 0.2)) { setChapter(n) }
    }

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
            if knb.hasIntros(edition: editionID) {
                Button { showIntros = true } label: {
                    Label("입문", systemImage: "text.book.closed")
                }
                .font(.subheadline)
            }
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

    // MARK: 본문 | 주석

    private var content: some View {
        let verses = chapter > 0 ? store.verses(edition: edition, book: book, chapter: chapter) : []
        let ch = max(chapter, 1)
        let notes = knb.notes(edition: editionID, bookID: book.id, chapter: ch)
        let xrefs = knb.crossrefs(edition: editionID, bookID: book.id, chapter: ch)
        return Group {
            if wide {
                HStack(spacing: 0) {
                    textColumn(verses)
                    Divider()
                    AnnotationsPane(notes: notes, xrefs: xrefs,
                                    emptyHint: emptyNotesHint, bookID: book.id, wide: true,
                                    searchQuery: navigation.searchQuery)
                        .frame(maxWidth: .infinity)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        versesBlock(verses)
                        Divider().padding(.vertical, 16)
                        AnnotationsPane(notes: notes, xrefs: xrefs,
                                        emptyHint: emptyNotesHint, bookID: book.id,
                                        searchQuery: navigation.searchQuery)
                    }
                    .frame(maxWidth: 720, alignment: .leading)
                    .padding(.horizontal, 28).padding(.bottom, 40)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var emptyNotesHint: String {
        knb.hasData(edition: editionID) ? "이 장에는 주석이 없습니다." : "주석 자료 준비 중입니다."
    }

    private func textColumn(_ verses: [Verse]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    versesBlock(verses)
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, 28).padding(.bottom, 40)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: scrollTarget) { _, _ in performScroll(proxy, verses: verses) }
            .onChange(of: chapter) { _, _ in performScroll(proxy, verses: verses) }
            .onAppear { performScroll(proxy, verses: verses) }
        }
        .frame(maxWidth: .infinity)
    }

    /// 대기 이동 직후 강조 시작 절로 한 번 스크롤(레이아웃 뒤로 미룸). 한 번 하면 지운다.
    private func performScroll(_ proxy: ScrollViewProxy, verses: [Verse]) {
        guard let n = scrollTarget, verses.contains(where: { $0.number == n }) else { return }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(n, anchor: .center) }
            scrollTarget = nil
        }
    }

    @ViewBuilder
    private func versesBlock(_ verses: [Verse]) -> some View {
        chapterHeader
        if verses.isEmpty {
            MissingTextView(edition: edition, book: book).padding(.top, 32)
        } else {
            let titleMap = getTitleMap()
            LazyVStack(alignment: .leading, spacing: settings.lineSpacing * 0.9) {
                ForEach(verses) { verse in
                    VStack(alignment: .leading, spacing: settings.lineSpacing * 0.9) {
                        if let title = titleMap[verse.number] {
                            SectionTitleView(text: title, bookID: book.id, chapter: chapter,
                                             linkable: true, searchQuery: navigation.searchQuery)
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
            .padding(.top, 20)
        }
    }

    private func getTitleMap() -> [Int: String] {
        let knbEditionID = editionID == "knb" ? "knbnotes" : editionID
        let titleMap = knb.titlesByVerse(edition: knbEditionID, bookID: book.id, chapter: max(chapter, 1))
            .mapValues { AnnotationMarkup.stripMarkers($0) }
        return titleMap
    }

    private var chapterHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(store.bookName(edition: edition, book: book))
                .font(settings.fontChoice.font(size: settings.fontSize * 0.8, relativeTo: .subheadline))
                .foregroundStyle(settings.theme.secondary)
            Text(book.chapterLabel(max(chapter, 1)))
                .font(settings.fontChoice.font(size: settings.fontSize * 1.8, relativeTo: .largeTitle, bold: true))
                .foregroundStyle(settings.theme.text)
            Rectangle().fill(settings.theme.secondary.opacity(0.35)).frame(width: 40, height: 1)
        }
        .padding(.top, 24)
    }

    // MARK: 하단 장 이동

    @ViewBuilder
    private var chapterBar: some View {
        if book.chapterCount > 1 && chapter > 0 {
            HStack(spacing: 10) {
                Button { step(-1) } label: { Image(systemName: "chevron.left") }.disabled(chapter <= 1)
                Slider(value: Binding(get: { Double(chapter) }, set: { setChapter(Int($0.rounded())) }),
                       in: 1...Double(book.chapterCount), step: 1)
                Button { step(1) } label: { Image(systemName: "chevron.right") }.disabled(chapter >= book.chapterCount)
                Button { showChapterPicker = true } label: {
                    Text(book.chapterLabel(chapter)).font(.caption.monospacedDigit()).frame(minWidth: 40)
                }
                .foregroundStyle(settings.theme.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 7)
            .background(settings.theme.background.opacity(0.94))
            .overlay(alignment: .top) {
                Rectangle().fill(settings.theme.secondary.opacity(0.2)).frame(height: 0.5)
            }
        }
    }
}

// MARK: - 소제목

struct SectionTitleView: View {
    let text: String
    let bookID: String
    let chapter: Int
    var linkable: Bool = true
    var searchQuery: String = ""

    @Environment(ReaderSettings.self) private var settings
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if linkable {
                // 링크 활성화 (주석성경, NABRE)
                SelectableNoteText(
                    text: text,
                    currentBook: bookID,
                    chapter: chapter,
                    font: titleFont,
                    color: UIColor(settings.theme.text),
                    linkColor: UIColor(Color.accentColor),
                    lineSpacing: settings.lineSpacing,
                    searchQuery: searchQuery,
                    onOpenURL: { openURL($0) }
                )
            } else {
                // 단순 텍스트
                Text(text)
                    .font(.system(size: settings.fontSize * 1.05, weight: .semibold, design: .default))
                    .foregroundStyle(settings.theme.text)
                    .textSelection(.enabled)
                    .lineLimit(nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, max(4, settings.lineSpacing * 0.5))
    }

    private var titleFont: UIFont {
        let size = settings.fontSize * 1.05
        switch settings.fontChoice {
        case .myeongjo:
            return UIFont(name: "NanumMyeongjo", size: size) ?? .systemFont(ofSize: size)
        case .gothic:
            return .systemFont(ofSize: size, weight: .semibold)
        }
    }
}

// MARK: - 각주 마커 팝업

struct MarkerNoteSheet: View {
    let n: String
    let text: String
    let bookID: String  // 소제목 링크의 각주 마커를 위해 필요
    let chapter: Int    // 소제목 링크의 각주 마커를 위해 필요
    @Environment(\.dismiss) private var dismiss
    @Environment(ReaderSettings.self) private var settings
    @Environment(BibleStore.self) private var store
    @Environment(AnnotationStore.self) private var annotations
    @Environment(ReaderNavigation.self) private var navigation
    @Environment(KnbNotesStore.self) private var knb
    @Environment(\.openURL) private var parentOpenURL
    @State private var xrefTarget: XrefTarget?
    @State private var noteTarget: MarkerNoteTarget?

    private var bodyUIFont: UIFont {
        let size = settings.fontSize
        switch settings.fontChoice {
        case .myeongjo: return UIFont(name: "NanumMyeongjo", size: size) ?? .systemFont(ofSize: size)
        case .gothic:   return .systemFont(ofSize: size)
        }
    }

    /// 인용 링크/주석 마커 탭 → 구절 미리보기/주석 팝업
    private func handleURL(_ url: URL) -> OpenURLAction.Result {
        guard url.scheme == "catholicbible" else { return .discarded }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func q(_ k: String) -> String? { items.first { $0.name == k }?.value }

        if url.host == "xref" {
            if let b = q("b"), let cs = q("c"), let c = Int(cs), let vs = q("v"), let v = Int(vs) {
                xrefTarget = XrefTarget(bookID: b, chapter: c, verse: v,
                                        endChapter: q("ec").flatMap { Int($0) } ?? 0,
                                        endVerse: q("ev").flatMap { Int($0) } ?? 0)
                return .handled
            }
        } else if url.host == "note" {
            if let b = q("b"), let cs = q("c"), let c = Int(cs), let n = q("n"),
               let noteText = knb.notes(edition: "knbnotes", bookID: b, chapter: c)
                .first(where: { $0.n == n })?.text {
                noteTarget = MarkerNoteTarget(n: n, text: noteText, bookID: b, chapter: c)
                return .handled
            }
        }
        return .discarded
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                // 단어 선택(네이티브) 가능한 뷰로 렌더한다.
                SelectableNoteText(text: text, currentBook: bookID, chapter: chapter,
                                   font: bodyUIFont,
                                   color: UIColor(settings.theme.text),
                                   linkColor: UIColor(Color.accentColor),
                                   lineSpacing: settings.lineSpacing,
                                   onOpenURL: { _ = handleURL($0) })
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .background(settings.theme.background.ignoresSafeArea())
            .navigationTitle("주석 \(n)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } } }
            .preferredColorScheme(settings.theme.colorScheme)
            .fullScreenCover(item: $xrefTarget) { t in
                RefPreviewSheet(target: t)
                    .environment(store)
                    .environment(settings)
                    .environment(annotations)
                    .environment(navigation)
                    .environment(knb)
            }
            // 중첩된 presentation 상황에서 sheet 표시 지연을 피하기 위해 fullScreenCover 사용
            .fullScreenCover(item: $noteTarget) { t in
                MarkerNoteSheet(n: t.n, text: t.text, bookID: t.bookID, chapter: t.chapter)
                    .environment(store)
                    .environment(settings)
                    .environment(annotations)
                    .environment(navigation)
                    .environment(knb)
            }
            // NavigationStack 내부에서 openURL 환경 오버라이드
            .environment(\.openURL, OpenURLAction { url in
                handleURL(url)
            })
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)   // 드래그로 위치·크기 변경
    }
}

// MARK: - 주석 열/목록

/// 오른쪽 주석 열(스크롤 포함)
struct NotesColumn: View {
    let title: String
    let notes: [ChapterNote]
    let emptyHint: String
    /// 인용의 '이어지는 절' 기준 책 id (링크 연결용).
    var bookID: String = ""
    @Environment(ReaderSettings.self) private var settings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                NotesList(title: title, notes: notes, emptyHint: emptyHint, bookID: bookID)
            }
            .padding(.horizontal, 22).padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(settings.theme.background)
    }
}

/// 주석 / 상호참조 탭 패널. 상호참조(xrefs)가 있으면 세그먼트로 전환한다.
/// wide=true 면 자체 스크롤·배경을 가진 오른쪽 칼럼, false 면 인라인(상위 스크롤).
struct AnnotationsPane: View {
    let notes: [ChapterNote]
    let xrefs: [ChapterNote]
    let emptyHint: String
    var bookID: String = ""
    var wide: Bool = false
    var searchQuery: String = ""
    @State private var tab = 0        // 0=주석, 1=상호참조
    @Environment(ReaderSettings.self) private var settings

    private var hasXrefs: Bool { !xrefs.isEmpty }

    @ViewBuilder private var inner: some View {
        VStack(alignment: .leading, spacing: 14) {
            if hasXrefs {
                Picker("보기", selection: $tab) {
                    Text("주석").tag(0)
                    Text("상호참조").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                NotesList(title: "",
                          notes: tab == 1 ? xrefs : notes,
                          emptyHint: tab == 1 ? "이 장에는 상호참조가 없습니다." : emptyHint,
                          bookID: bookID,
                          searchQuery: searchQuery)
            } else {
                NotesList(title: "주석", notes: notes, emptyHint: emptyHint, bookID: bookID,
                          searchQuery: searchQuery)
            }
        }
    }

    var body: some View {
        if wide {
            ScrollView {
                inner
                    .padding(.horizontal, 22).padding(.vertical, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(settings.theme.background)
        } else {
            inner
        }
    }
}

/// 주석 목록 본문(제목 + 항목들)
struct NotesList: View {
    let title: String
    let notes: [ChapterNote]
    let emptyHint: String
    /// 인용의 '이어지는 절'(예: "33:6")이 이을 기준 책 id.
    var bookID: String = ""
    /// 각주 마커 링크를 위해 필요
    var chapter: Int = 0
    var searchQuery: String = ""
    @Environment(ReaderSettings.self) private var settings
    @Environment(\.openURL) private var openURL

    private var noteUIFont: UIFont {
        let size = settings.fontSize * 0.9
        switch settings.fontChoice {
        case .myeongjo: return UIFont(name: "NanumMyeongjo", size: size) ?? .systemFont(ofSize: size)
        case .gothic:   return .systemFont(ofSize: size)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !title.isEmpty {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(settings.theme.secondary)
            }
            if notes.isEmpty {
                Text(emptyHint)
                    .font(.footnote)
                    .foregroundStyle(settings.theme.secondary.opacity(0.8))
            } else {
                ForEach(notes) { note in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(note.n)
                            .font(settings.fontChoice.font(size: settings.fontSize * 0.72, bold: true))
                            .foregroundStyle(Color.accentColor)
                            .frame(minWidth: settings.fontSize * 1.3, alignment: .trailing)
                        // 단어 선택(네이티브)과 성경 인용 링크 탭을 함께 지원.
                        SelectableNoteText(text: note.text, currentBook: bookID, chapter: chapter,
                                           font: noteUIFont,
                                           color: UIColor(settings.theme.text),
                                           linkColor: UIColor(Color.accentColor),
                                           lineSpacing: settings.lineSpacing,
                                           searchQuery: searchQuery,
                                           onOpenURL: { openURL($0) })
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

// MARK: - 입문 목록

struct IntroductionsView: View {
    let currentBookID: String
    var editionID: String = "knbnotes"
    @Environment(KnbNotesStore.self) private var knb
    @Environment(ReaderSettings.self) private var settings
    @Environment(BibleStore.self) private var store
    @Environment(AnnotationStore.self) private var annotations
    @Environment(ReaderNavigation.self) private var navigation
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Introduction?

    var body: some View {
        NavigationStack {
            Group {
                if !knb.hasIntros(edition: editionID) {
                    ContentUnavailableView(
                        "입문 자료 없음",
                        systemImage: "text.book.closed",
                        description: Text("이 판본의 입문 자료가 아직 없습니다.")
                    )
                } else {
                    List {
                        if let book = knb.intro(edition: editionID, forBook: currentBookID) {
                            Section("현재 책") { introRow(book) }
                        }
                        section("성경 전체", .bible)
                        section("구약·신약", .testament)
                        section("분류별", .category)
                        section("책별", .book)
                    }
                }
            }
            .navigationTitle("입문")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } } }
            .fullScreenCover(item: $selected) { intro in
                IntroDetailView(intro: intro)
                    .environment(settings)
                    .environment(store)
                    .environment(annotations)
                    .environment(navigation)
                    .environment(knb)
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ level: IntroLevel) -> some View {
        let items = knb.intros(edition: editionID, of: level)
        if !items.isEmpty {
            Section(title) { ForEach(items) { introRow($0) } }
        }
    }

    private func introRow(_ intro: Introduction) -> some View {
        Button { selected = intro } label: {
            HStack {
                Text(intro.title.isEmpty ? "입문 \(intro.id)" : intro.title)
                Spacer()
                if !intro.notes.isEmpty {
                    Label("\(intro.notes.count)", systemImage: "text.append")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 입문 상세 (본문 + 주석)

struct IntroDetailView: View {
    let intro: Introduction
    @Environment(ReaderSettings.self) private var settings
    @Environment(BibleStore.self) private var store
    @Environment(AnnotationStore.self) private var annotations
    @Environment(ReaderNavigation.self) private var navigation
    @Environment(KnbNotesStore.self) private var knb
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.dismiss) private var dismiss
    @State private var xrefTarget: XrefTarget?

    private var wide: Bool { hSize == .regular }

    private var bodyUIFont: UIFont {
        let size = settings.fontSize
        switch settings.fontChoice {
        case .myeongjo: return UIFont(name: "NanumMyeongjo", size: size) ?? .systemFont(ofSize: size)
        case .gothic:   return .systemFont(ofSize: size)
        }
    }

    /// 입문 본문·주석의 성경 인용(catholicbible://xref) 탭 → 구절 미리보기.
    private func handleURL(_ url: URL) -> OpenURLAction.Result {
        guard url.scheme == "catholicbible", url.host == "xref" else { return .discarded }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func q(_ k: String) -> String? { items.first { $0.name == k }?.value }
        if let b = q("b"), let cs = q("c"), let c = Int(cs), let vs = q("v"), let v = Int(vs) {
            xrefTarget = XrefTarget(bookID: b, chapter: c, verse: v,
                                    endChapter: q("ec").flatMap { Int($0) } ?? 0,
                                    endVerse: q("ev").flatMap { Int($0) } ?? 0)
            return .handled
        }
        return .discarded
    }

    var body: some View {
        NavigationStack {
            Group {
                if wide {
                    HStack(spacing: 0) {
                        bodyColumn
                        Divider()
                        NotesColumn(title: "주석", notes: intro.notes,
                                    emptyHint: "이 입문에는 주석이 없습니다.")
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            bodyText
                            if !intro.notes.isEmpty {
                                Divider().padding(.vertical, 16)
                                NotesList(title: "주석", notes: intro.notes, emptyHint: "")
                            }
                        }
                        .padding(.horizontal, 24).padding(.vertical, 20)
                    }
                }
            }
            .background(settings.theme.background.ignoresSafeArea())
            .navigationTitle(intro.title.isEmpty ? "입문" : intro.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } } }
            .preferredColorScheme(settings.theme.colorScheme)
            // 주석 열(NotesList)의 인용 링크도 여기서 처리하도록 openURL 재정의
            .environment(\.openURL, OpenURLAction { url in handleURL(url); return .handled })
            .fullScreenCover(item: $xrefTarget) { t in
                RefPreviewSheet(target: t)
                    .environment(store)
                    .environment(settings)
                    .environment(annotations)
                    .environment(navigation)
                    .environment(knb)
            }
        }
    }

    private var bodyColumn: some View {
        ScrollView {
            bodyText
                .padding(.horizontal, 28).padding(.vertical, 24)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
    }

    private var bodyText: some View {
        SelectableNoteText(text: intro.body.isEmpty ? "본문이 비어 있습니다." : intro.body,
                           currentBook: intro.bookID,
                           font: bodyUIFont,
                           color: UIColor(settings.theme.text),
                           linkColor: UIColor(Color.accentColor),
                           lineSpacing: settings.lineSpacing,
                           onOpenURL: { handleURL($0) })
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
