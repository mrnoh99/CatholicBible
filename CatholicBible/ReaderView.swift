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

    @Environment(ReaderSettings.self) private var settings
    @Environment(ReadingState.self) private var readingState
    @Environment(ReaderNavigation.self) private var navigation
    @Environment(AnnotationStore.self) private var annotations
    @Environment(KnbNotesStore.self) private var knbNotes
    @Environment(\.horizontalSizeClass) private var hSize

    @State private var showAppearance = false
    @State private var noteTarget: NoteTarget?
    @State private var markerNote: MarkerNoteTarget?

    private var canDual: Bool { hSize == .regular }
    /// 좁은 화면(iPhone)에서는 항상 한 페이지
    private var layout: ReaderLayout { canDual ? readingState.readerLayout : .single }
    /// 주석 성경 전용 본문|주석 화면을 쓸지 (비교 모드가 아니면 사용)
    private var showAnnotated: Bool {
        readingState.selectedEditionID == "knbnotes"
            && !(canDual && readingState.readerLayout == .compare)
    }

    var body: some View {
        @Bindable var rs = readingState

        ZStack {
            settings.theme.background.ignoresSafeArea()
            if showAnnotated {
                // 주석 성경: 왼쪽 본문 · 오른쪽 주석 (입문 접근 포함)
                AnnotatedReader(editionID: $rs.selectedEditionID,
                                bookID: primaryBookBinding,
                                onOpenNote: openNote)
            } else {
            switch layout {
            case .single:
                ReaderPane(role: .primary,
                           editionID: $rs.selectedEditionID,
                           bookID: primaryBookBinding,
                           onOpenNote: openNote)
            case .spread:
                SpreadReader(editionID: $rs.selectedEditionID,
                             bookID: primaryBookBinding,
                             onOpenNote: openNote)
            case .compare:
                HStack(spacing: 0) {
                    ReaderPane(role: .primary,
                               editionID: $rs.selectedEditionID,
                               bookID: primaryBookBinding,
                               onOpenNote: openNote)
                    Divider()
                    ReaderPane(role: .secondary,
                               editionID: $rs.secondaryEditionID,
                               bookID: secondaryBookBinding,
                               onClose: { readingState.readerLayout = .single },
                               onOpenNote: openNote)
                }
            }
            }
        }
        .navigationTitle("성경 읽기")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { readerToolbar }
        .preferredColorScheme(settings.theme.colorScheme)
        .sheet(isPresented: $showAppearance) {
            AppearanceControls()
                .presentationDetents([.medium])
        }
        .sheet(item: $noteTarget) { target in
            NoteEditorView(verse: target.ref,
                           verseText: target.text,
                           existing: annotations.noteOrNew(for: target.ref))
        }
        // 각주 마커 'N)' 탭 → 주석 팝업 / 낱말 탭 → 사전
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "catholicbible" else { return .systemAction }
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func q(_ k: String) -> String? { items.first { $0.name == k }?.value }
            switch url.host {
            case "note":
                if let b = q("b"), let cs = q("c"), let c = Int(cs), let n = q("n") {
                    let note = knbNotes.notes(bookID: b, chapter: c).first { $0.n == n }
                    markerNote = MarkerNoteTarget(n: n, text: note?.text ?? "이 주석을 찾지 못했습니다.")
                }
                return .handled
            case "define":
                if let w = q("w")?.removingPercentEncoding, !w.isEmpty {
                    navigation.lookUp(w)
                }
                return .handled
            default:
                return .systemAction
            }
        })
        .sheet(item: $markerNote) { mn in
            MarkerNoteSheet(n: mn.n, text: mn.text)
        }
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
        ToolbarItemGroup(placement: .primaryAction) {
            if canDual && readingState.selectedEditionID == "knbnotes" {
                // 주석 성경: 본문·주석 vs 판본 비교
                Menu {
                    Button {
                        readingState.readerLayout = .single
                    } label: { Label("본문·주석", systemImage: "book.pages") }
                    Button {
                        readingState.readerLayout = .compare
                    } label: { Label("판본 비교", systemImage: "rectangle.split.2x1") }
                } label: {
                    Label("보기", systemImage: readingState.readerLayout == .compare
                          ? "rectangle.split.2x1" : "book.pages")
                }
            } else if canDual {
                Menu {
                    Picker("페이지", selection: Binding(
                        get: { readingState.readerLayout },
                        set: { readingState.readerLayout = $0 })) {
                        ForEach(ReaderLayout.allCases) { l in
                            Label(l.label, systemImage: l.systemImage).tag(l)
                        }
                    }
                } label: {
                    Label("페이지", systemImage: layout.systemImage)
                }
            }
            // 사전 찾기 모드: 켜면 본문 낱말을 눌러 사전으로 보낸다.
            Button {
                readingState.wordLookupMode.toggle()
            } label: {
                Label("사전 찾기", systemImage: "character.book.closed")
            }
            .tint(readingState.wordLookupMode ? Color.accentColor : nil)

            Button("보기 설정", systemImage: "textformat.size") { showAppearance = true }
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
    let onOpenNote: (VerseRef, String) -> Void

    @Environment(BibleStore.self) private var store
    @Environment(ReaderSettings.self) private var settings
    @Environment(ReadingState.self) private var readingState
    @Environment(ReaderNavigation.self) private var navigation

    @State private var chapter = 0
    @State private var highlight: Int?
    @State private var scrolledVerse: Int?
    @State private var showBookPicker = false
    @State private var showChapterPicker = false

    private var edition: Edition { Editions.edition(editionID) ?? Editions.all[0] }
    private var book: BibleBook { Bible.book(bookID) ?? Bible.books[0] }

    var body: some View {
        VStack(spacing: 0) {
            paneHeader
            versesScroll
            chapterBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { initChapterIfNeeded() }
        .onChange(of: bookID) { _, _ in
            chapter = readingState.lastChapter(edition: edition, book: book)
            highlight = nil
        }
        .onChange(of: editionID) { _, _ in
            chapter = min(max(chapter, 1), book.chapterCount)
        }
        .onChange(of: chapter) { _, new in
            guard new > 0 else { return }
            readingState.savePosition(edition: edition, book: book, chapter: new)
        }
        .modifier(PendingChapterModifier(active: role == .primary, apply: applyPending))
        .sheet(isPresented: $showBookPicker) {
            BookPickerView(edition: edition, current: bookID) { picked in
                bookID = picked
                showBookPicker = false
            }
        }
        .sheet(isPresented: $showChapterPicker) {
            ChapterPickerView(book: book, current: max(chapter, 1)) { picked in
                chapter = picked
                showChapterPicker = false
            }
        }
    }

    // MARK: 시작/이동 위치

    private func initChapterIfNeeded() {
        guard chapter == 0 else { return }
        if role == .primary, let pending = navigation.pendingChapter {
            chapter = clampChapter(pending)
            highlight = navigation.pendingVerse
            navigation.pendingChapter = nil
            navigation.pendingVerse = nil
        } else {
            chapter = readingState.lastChapter(edition: edition, book: book)
        }
    }

    private func applyPending() {
        if let pending = navigation.pendingChapter {
            chapter = clampChapter(pending)
            highlight = navigation.pendingVerse
            navigation.pendingChapter = nil
            navigation.pendingVerse = nil
        }
    }

    private func clampChapter(_ c: Int) -> Int { min(max(c, 1), book.chapterCount) }

    private func step(_ delta: Int) {
        let next = chapter + delta
        guard (1...book.chapterCount).contains(next) else { return }
        highlight = nil
        withAnimation(.easeInOut(duration: 0.2)) { chapter = next }
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
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                chapterHeader
                if verses.isEmpty {
                    MissingTextView(edition: edition, book: book).padding(.top, 40)
                } else {
                    LazyVStack(alignment: .leading, spacing: settings.lineSpacing * 0.9) {
                        ForEach(verses) { verse in
                            VerseRowView(edition: edition, book: book, chapter: chapter,
                                         verse: verse, highlighted: highlight == verse.number,
                                         onOpenNote: onOpenNote)
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
        .scrollPosition(id: $scrolledVerse, anchor: .center)
        .onChange(of: highlight) { _, v in if let v { scrolledVerse = v } }
        .onChange(of: chapter) { _, _ in scrolledVerse = nil }
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

    // MARK: 하단 장 이동 바

    @ViewBuilder
    private var chapterBar: some View {
        if book.chapterCount > 1 && chapter > 0 {
            HStack(spacing: 10) {
                Button { step(-1) } label: { Image(systemName: "chevron.left") }
                    .disabled(chapter <= 1)
                Slider(value: Binding(get: { Double(chapter) },
                                      set: { chapter = Int($0.rounded()) }),
                       in: 1...Double(book.chapterCount), step: 1)
                    .accessibilityLabel("장 이동")
                    .accessibilityValue(book.chapterLabel(chapter))
                Button { step(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(chapter >= book.chapterCount)
                Button { showChapterPicker = true } label: {
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
        }
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
    let onOpenNote: (VerseRef, String) -> Void

    @Environment(BibleStore.self) private var store
    @Environment(ReaderSettings.self) private var settings
    @Environment(ReadingState.self) private var readingState
    @Environment(ReaderNavigation.self) private var navigation

    @State private var chapter = 0
    @State private var spreadIndex = 0
    @State private var wantLastSpread = false
    @State private var highlight: Int?
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
            highlight = nil; spreadIndex = 0
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
                bookID = picked; showBookPicker = false
            }
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
        if let p = navigation.pendingChapter {
            chapter = clampChapter(p); highlight = navigation.pendingVerse
            navigation.pendingChapter = nil; navigation.pendingVerse = nil
        } else {
            chapter = readingState.lastChapter(edition: edition, book: book)
        }
    }

    private func applyPending() {
        if let p = navigation.pendingChapter {
            chapter = clampChapter(p); highlight = navigation.pendingVerse
            navigation.pendingChapter = nil; navigation.pendingVerse = nil
            spreadIndex = 0
        }
    }

    private func clampChapter(_ c: Int) -> Int { min(max(c, 1), book.chapterCount) }

    /// 페이지 수가 바뀌면 목표 스프레드(마지막/강조 절)로 맞춘다.
    private func reconcileSpreadIndex() {
        if wantLastSpread {
            spreadIndex = max(0, spreadCount - 1); wantLastSpread = false
        } else if let h = highlight,
                  let pageIdx = pages.firstIndex(where: { $0.contains { $0.number == h } }) {
            spreadIndex = pageIdx / 2
        } else {
            spreadIndex = min(spreadIndex, max(0, spreadCount - 1))
        }
    }

    private func nextSpread() {
        highlight = nil
        if spreadIndex + 1 < spreadCount { spreadIndex += 1 }
        else { stepChapter(1) }
    }

    private func prevSpread() {
        highlight = nil
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
            } label: { chip(edition.shortName) }
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
                    VerseRowView(edition: edition, book: book, chapter: chapter,
                                 verse: verse, highlighted: highlight == verse.number,
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
}

// MARK: - 절 한 줄 (판본 공통 책갈피·노트)

struct VerseRowView: View {
    let edition: Edition
    let book: BibleBook
    let chapter: Int
    let verse: Verse
    let highlighted: Bool
    let onOpenNote: (VerseRef, String) -> Void

    @Environment(ReaderSettings.self) private var settings
    @Environment(AnnotationStore.self) private var annotations
    @Environment(ReaderNavigation.self) private var navigation
    @Environment(ReadingState.self) private var readingState

    private var ref: VerseRef { VerseRef(bookID: book.id, chapter: chapter, verse: verse.number) }

    /// 사전 찾기 모드면 낱말을, 주석 성경이면 각주 마커 'N)'를 탭 가능한 링크로.
    private var bodyText: AttributedString {
        if readingState.wordLookupMode {
            return AnnotationMarkup.wordLookup(verse.text, textColor: settings.theme.text)
        }
        return AnnotationMarkup.attributed(verse.text,
                                           linkable: edition.id == "knbnotes",
                                           bookID: book.id, chapter: chapter)
    }

    var body: some View {
        let bookmarked = annotations.isBookmarked(ref)
        let hasNote = annotations.hasNote(ref)

        HStack(alignment: .firstTextBaseline, spacing: 6) {
            // 앞의 번호(또는 점) = 동작 메뉴 손잡이. 본문 낱말 선택과 겹치지 않는다.
            actionMenu(bookmarked: bookmarked, hasNote: hasNote)

            // 본문: 낱말을 길게 눌러 선택 → iOS ‘찾아보기’로 사전 조회.
            // 주석 성경이면 각주 마커 'N)'가 탭 가능한 링크가 된다.
            Text(bodyText)
                .font(settings.bodyFont())
                .foregroundStyle(settings.theme.text)
                .lineSpacing(settings.lineSpacing)
                .textSelection(.enabled)
                .tint(Color.accentColor)
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
                navigation.lookUp()
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

    var body: some View {
        NavigationStack {
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
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
            }
        }
    }

    private func row(_ book: BibleBook) -> some View {
        let available = store.hasText(edition: edition, book: book)
        return Button { onPick(book.id) } label: {
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
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
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
