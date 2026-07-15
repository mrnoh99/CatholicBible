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
    @Environment(\.horizontalSizeClass) private var hSize

    @State private var showAppearance = false
    @State private var noteTarget: NoteTarget?

    private var canDual: Bool { hSize == .regular }
    private var showsDual: Bool { canDual && readingState.dualPaneEnabled }

    var body: some View {
        @Bindable var rs = readingState

        ZStack {
            settings.theme.background.ignoresSafeArea()
            HStack(spacing: 0) {
                ReaderPane(role: .primary,
                           editionID: $rs.selectedEditionID,
                           bookID: primaryBookBinding,
                           onOpenNote: openNote)

                if showsDual {
                    Divider()
                    ReaderPane(role: .secondary,
                               editionID: $rs.secondaryEditionID,
                               bookID: secondaryBookBinding,
                               onClose: { readingState.dualPaneEnabled = false },
                               onOpenNote: openNote)
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
            if canDual {
                Button {
                    readingState.dualPaneEnabled.toggle()
                } label: {
                    Label("2단 보기",
                          systemImage: readingState.dualPaneEnabled
                              ? "rectangle.split.2x1.fill" : "rectangle.split.2x1")
                }
            }
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

    private var ref: VerseRef { VerseRef(bookID: book.id, chapter: chapter, verse: verse.number) }

    var body: some View {
        let bookmarked = annotations.isBookmarked(ref)
        let hasNote = annotations.hasNote(ref)

        verseText
            .lineSpacing(settings.lineSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(highlighted ? Color.accentColor.opacity(0.18) : .clear)
            )
            .overlay(alignment: .topTrailing) { indicators(bookmarked: bookmarked, hasNote: hasNote) }
            .contentShape(Rectangle())
            .onTapGesture { if hasNote { onOpenNote(ref, verse.text) } }
            .contextMenu {
                Button(bookmarked ? "책갈피 지우기" : "책갈피",
                       systemImage: bookmarked ? "bookmark.slash" : "bookmark") {
                    annotations.toggleBookmark(ref)
                }
                Button(hasNote ? "노트 보기·편집" : "노트 추가", systemImage: "note.text") {
                    onOpenNote(ref, verse.text)
                }
                Button("복사", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = "\(verse.text) (\(ref.reference))"
                }
            }
            .animation(.easeInOut(duration: 0.25), value: highlighted)
            .animation(.easeInOut(duration: 0.25), value: bookmarked)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(verse.number)절, \(verse.text)")
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

    private var verseText: Text {
        let body = Text(verse.text)
            .font(settings.bodyFont())
            .foregroundStyle(settings.theme.text)
        guard settings.showVerseNumbers else { return body }
        let number = Text("\(verse.number) ")
            .font(settings.fontChoice.font(size: settings.fontSize * 0.62))
            .foregroundStyle(settings.theme.secondary)
            .baselineOffset(settings.fontSize * 0.28)
        return number + body
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
