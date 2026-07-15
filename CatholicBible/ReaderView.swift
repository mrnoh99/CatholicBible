//
//  ReaderView.swift
//  CatholicBible
//
//  ebook 리더. iPad(가로 넓은 화면)에서는 두 판본을 나란히(2단),
//  iPhone에서는 한 판본만(1단) 보여 준다. 장은 두 열이 함께 움직인다.
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
    let book: BibleBook

    @Environment(BibleStore.self) private var store
    @Environment(ReaderSettings.self) private var settings
    @Environment(ReadingState.self) private var readingState
    @Environment(ReaderNavigation.self) private var navigation
    @Environment(\.horizontalSizeClass) private var hSize

    /// 0이면 아직 시작 위치를 정하지 않은 상태
    @State private var chapter = 0
    @State private var highlightVerse: Int?
    @State private var showChapterPicker = false
    @State private var showAppearance = false
    @State private var noteTarget: NoteTarget?

    /// iPad에서 가로로 넓을 때만 2단 가능
    private var canDual: Bool { hSize == .regular }
    private var showsDual: Bool { canDual && readingState.dualPaneEnabled }

    var body: some View {
        @Bindable var rs = readingState

        ZStack {
            settings.theme.background.ignoresSafeArea()
            if chapter > 0 {
                HStack(spacing: 0) {
                    EditionColumn(editionID: $rs.selectedEditionID,
                                  book: book, chapter: chapter,
                                  highlightVerse: highlightVerse,
                                  showsPicker: true,
                                  onOpenNote: openNote)

                    if showsDual {
                        Divider()
                        EditionColumn(editionID: $rs.secondaryEditionID,
                                      book: book, chapter: chapter,
                                      highlightVerse: nil,
                                      showsPicker: true,
                                      onCloseColumn: { readingState.dualPaneEnabled = false },
                                      onOpenNote: openNote)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) { chapterNavBar }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { readerToolbar }
        .preferredColorScheme(settings.theme.colorScheme)
        .onAppear(perform: applyStartPosition)
        .onChange(of: navigation.pendingChapter) { applyStartPosition() }
        .onChange(of: chapter) { _, newValue in
            guard newValue > 0 else { return }
            readingState.savePosition(edition: readingState.selectedEdition, book: book, chapter: newValue)
        }
        .sheet(isPresented: $showChapterPicker) {
            ChapterPickerView(book: book, current: max(chapter, 1)) { picked in
                chapter = picked; showChapterPicker = false
            }
        }
        .sheet(item: $noteTarget) { target in
            NoteEditorView(verse: target.ref,
                           verseText: target.text,
                           existing: annotationsNote(for: target.ref))
        }
    }

    @Environment(AnnotationStore.self) private var annotations
    private func annotationsNote(for ref: VerseRef) -> Note { annotations.noteOrNew(for: ref) }

    private func openNote(ref: VerseRef, text: String) {
        noteTarget = NoteTarget(ref: ref, text: text)
    }

    private var title: String {
        let primary = readingState.selectedEdition
        return "\(store.bookShortName(edition: primary, book: book)) \(book.chapterLabel(max(chapter, 1)))"
    }

    private func applyStartPosition() {
        if let pending = navigation.pendingChapter {
            chapter = min(max(pending, 1), book.chapterCount)
            highlightVerse = navigation.pendingVerse
            navigation.pendingChapter = nil
            navigation.pendingVerse = nil
        } else if chapter == 0 {
            chapter = readingState.lastChapter(edition: readingState.selectedEdition, book: book)
        }
    }

    private func step(_ delta: Int) {
        let next = chapter + delta
        guard (1...book.chapterCount).contains(next) else { return }
        highlightVerse = nil
        withAnimation(.easeInOut(duration: 0.2)) { chapter = next }
    }

    // MARK: - 툴바

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
            Button("장 선택", systemImage: "list.number") { showChapterPicker = true }
            Button("보기 설정", systemImage: "textformat.size") { showAppearance = true }
                .popover(isPresented: $showAppearance, arrowEdge: .top) {
                    AppearanceControls().presentationCompactAdaptation(.popover)
                }
        }
    }

    // MARK: - 하단 장 이동 바

    @ViewBuilder
    private var chapterNavBar: some View {
        if book.chapterCount > 1 && chapter > 0 {
            HStack(spacing: 12) {
                Button { step(-1) } label: { Image(systemName: "chevron.left") }
                    .disabled(chapter <= 1)
                Slider(
                    value: Binding(get: { Double(chapter) },
                                   set: { chapter = Int($0.rounded()) }),
                    in: 1...Double(book.chapterCount), step: 1
                )
                .accessibilityLabel("장 이동")
                .accessibilityValue(book.chapterLabel(chapter))
                Button { step(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(chapter >= book.chapterCount)
                Text(book.chapterLabel(chapter))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(settings.theme.secondary)
                    .frame(minWidth: 44)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(settings.theme.background.opacity(0.94))
        }
    }
}

// MARK: - 한 판본 열

struct EditionColumn: View {
    @Binding var editionID: String
    let book: BibleBook
    let chapter: Int
    var highlightVerse: Int?
    var showsPicker: Bool
    var onCloseColumn: (() -> Void)? = nil
    let onOpenNote: (VerseRef, String) -> Void

    @Environment(BibleStore.self) private var store
    @Environment(ReaderSettings.self) private var settings

    private var edition: Edition { Editions.edition(editionID) ?? Editions.all[0] }

    @State private var scrolledVerse: Int?

    var body: some View {
        VStack(spacing: 0) {
            if showsPicker { columnHeader }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var columnHeader: some View {
        HStack {
            Menu {
                Picker("판본", selection: $editionID) {
                    ForEach(Editions.all) { ed in Text(ed.name).tag(ed.id) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(edition.shortName).fontWeight(.semibold)
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .font(.subheadline)
                .foregroundStyle(Color.accentColor)
            }
            Spacer()
            if let onCloseColumn {
                Button { onCloseColumn() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .accessibilityLabel("이 열 닫기")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(settings.theme.background)
        .overlay(alignment: .bottom) {
            Rectangle().fill(settings.theme.secondary.opacity(0.2)).frame(height: 0.5)
        }
    }

    private var content: some View {
        let verses = store.verses(edition: edition, book: book, chapter: chapter)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if verses.isEmpty {
                    MissingTextView(edition: edition, book: book).padding(.top, 40)
                } else {
                    LazyVStack(alignment: .leading, spacing: settings.lineSpacing * 0.9) {
                        ForEach(verses) { verse in
                            VerseRowView(edition: edition, book: book, chapter: chapter,
                                         verse: verse, highlighted: highlightVerse == verse.number,
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
            .padding(.bottom, 56)
            .frame(maxWidth: .infinity)
        }
        .scrollPosition(id: $scrolledVerse, anchor: .center)
        .onChange(of: highlightVerse) { _, v in if let v { scrolledVerse = v } }
        .onAppear { if let v = highlightVerse { scrolledVerse = v } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.bookName(edition: edition, book: book))
                .font(settings.fontChoice.font(size: settings.fontSize * 0.8, relativeTo: .subheadline))
                .foregroundStyle(settings.theme.secondary)
            Text(book.chapterLabel(chapter))
                .font(settings.fontChoice.font(size: settings.fontSize * 1.9, relativeTo: .largeTitle, bold: true))
                .foregroundStyle(settings.theme.text)
            Rectangle().fill(settings.theme.secondary.opacity(0.35)).frame(width: 40, height: 1)
        }
        .padding(.top, 28)
    }

    private var copyrightFooter: some View {
        Text(edition.copyright)
            .font(.caption2)
            .foregroundStyle(settings.theme.secondary.opacity(0.8))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 40)
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
            .onTapGesture {
                if hasNote { onOpenNote(ref, verse.text) }
            }
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
            .accessibilityHint(bookmarked ? "책갈피됨" : "")
    }

    @ViewBuilder
    private func indicators(bookmarked: Bool, hasNote: Bool) -> some View {
        HStack(spacing: 3) {
            if hasNote {
                Image(systemName: "note.text")
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor.opacity(0.75))
            }
            if bookmarked {
                Image(systemName: "bookmark.fill")
                    .font(.caption2)
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
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("글자 크기").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("가").font(.footnote)
                    Slider(value: $settings.fontSize, in: ReaderSettings.fontSizeRange, step: 1)
                        .accessibilityLabel("글자 크기")
                    Text("가").font(.title2)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("줄 간격").font(.caption).foregroundStyle(.secondary)
                Slider(value: $settings.lineSpacingFactor, in: 0.35...1.1)
                    .accessibilityLabel("줄 간격")
            }
            Picker("서체", selection: $settings.fontChoice) {
                ForEach(FontChoice.allCases) { choice in Text(choice.label).tag(choice) }
            }
            .pickerStyle(.segmented)
            Toggle("절 번호 표시", isOn: $settings.showVerseNumbers).font(.subheadline)
            VStack(alignment: .leading, spacing: 6) {
                Text("배경").font(.caption).foregroundStyle(.secondary)
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
                        .accessibilityAddTraits(settings.theme == theme ? .isSelected : [])
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
