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
    /// 이 리더가 담당하는 책(대기 이동 가로채기 방지용).
    var ownerBookID: String = ""
    let onOpenNote: (VerseRef, String) -> Void

    @Environment(BibleStore.self) private var store
    @Environment(ReaderSettings.self) private var settings
    @Environment(ReadingState.self) private var readingState
    @Environment(ReaderNavigation.self) private var navigation
    @Environment(KnbNotesStore.self) private var knb
    @Environment(\.horizontalSizeClass) private var hSize

    @State private var chapter = 0
    @State private var highlight: VerseHighlight?
    @State private var showBookPicker = false
    @State private var showChapterPicker = false
    @State private var showIntros = false

    private var edition: Edition { Editions.edition(editionID) ?? Editions.all[0] }
    private var book: BibleBook { Bible.book(bookID) ?? Bible.books[0] }
    private var wide: Bool { hSize == .regular }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            chapterBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { initChapterIfNeeded() }
        .onChange(of: bookID) { _, _ in
            chapter = readingState.lastChapter(edition: edition, book: book)
            highlight = nil
        }
        .onChange(of: chapter) { _, new in
            guard new > 0 else { return }
            readingState.savePosition(edition: edition, book: book, chapter: new)
        }
        .onChange(of: navigation.pendingChapter) { _, _ in applyPending() }
        .sheet(isPresented: $showBookPicker) {
            BookPickerView(edition: edition, current: bookID) { picked in
                bookID = picked; showBookPicker = false
            }
            .environment(store)   // Mac Catalyst: 모달 환경 전파 대비
        }
        .sheet(isPresented: $showChapterPicker) {
            ChapterPickerView(book: book, current: max(chapter, 1)) { picked in
                chapter = picked; showChapterPicker = false
            }
        }
        .sheet(isPresented: $showIntros) {
            IntroductionsView(currentBookID: bookID)
                .environment(knb)
                .environment(settings)
        }
    }

    // MARK: 위치

    private func initChapterIfNeeded() {
        guard chapter == 0 else { return }
        if navigation.hasPending(forBook: ownerBookID), let p = navigation.pendingChapter {
            chapter = min(max(p, 1), book.chapterCount)
            navigation.pendingChapter = nil
            highlight = navigation.takePendingHighlight()
        } else {
            chapter = readingState.lastChapter(edition: edition, book: book)
        }
    }

    private func applyPending() {
        guard navigation.hasPending(forBook: ownerBookID), let p = navigation.pendingChapter else { return }
        chapter = min(max(p, 1), book.chapterCount)
        navigation.pendingChapter = nil
        highlight = navigation.takePendingHighlight()
    }

    private func step(_ d: Int) {
        let n = chapter + d
        guard (1...book.chapterCount).contains(n) else { return }
        highlight = nil
        withAnimation(.easeInOut(duration: 0.2)) { chapter = n }
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
            Button { showIntros = true } label: {
                Label("입문", systemImage: "text.book.closed")
            }
            .font(.subheadline)
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
        let notes = knb.notes(bookID: book.id, chapter: max(chapter, 1))
        return Group {
            if wide {
                HStack(spacing: 0) {
                    textColumn(verses)
                    Divider()
                    NotesColumn(title: "주석", notes: notes, emptyHint: emptyNotesHint)
                        .frame(maxWidth: .infinity)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        versesBlock(verses)
                        Divider().padding(.vertical, 16)
                        NotesList(title: "주석", notes: notes, emptyHint: emptyNotesHint)
                    }
                    .frame(maxWidth: 720, alignment: .leading)
                    .padding(.horizontal, 28).padding(.bottom, 40)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var emptyNotesHint: String {
        knb.hasData ? "이 장에는 주석이 없습니다." : "주석 자료 준비 중 — scripts/fetch_knbnotes.py 로 받으세요."
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
            .onChange(of: highlight) { _, _ in scrollToHighlight(proxy, verses: verses) }
            .onChange(of: chapter) { _, _ in scrollToHighlight(proxy, verses: verses) }
            .onAppear { scrollToHighlight(proxy, verses: verses) }
        }
        .frame(maxWidth: .infinity)
    }

    /// 강조된 독서의 시작 절이 보이도록 스크롤(레이아웃 뒤로 한 번 미룸).
    private func scrollToHighlight(_ proxy: ScrollViewProxy, verses: [Verse]) {
        guard let n = highlight?.startVerse, verses.contains(where: { $0.number == n }) else { return }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(n, anchor: .center) }
        }
    }

    @ViewBuilder
    private func versesBlock(_ verses: [Verse]) -> some View {
        chapterHeader
        if verses.isEmpty {
            MissingTextView(edition: edition, book: book).padding(.top, 32)
        } else {
            let titleMap = knb.titlesByVerse(bookID: book.id, chapter: max(chapter, 1))
            LazyVStack(alignment: .leading, spacing: settings.lineSpacing * 0.9) {
                ForEach(verses) { verse in
                    VStack(alignment: .leading, spacing: settings.lineSpacing * 0.9) {
                        if let title = titleMap[verse.number] {
                            SectionTitleView(text: title, bookID: book.id, chapter: chapter)
                        }
                        VerseRowView(edition: edition, book: book, chapter: chapter,
                                     verse: verse,
                                     highlighted: highlight?.contains(chapter: chapter, verse: verse.number) ?? false,
                                     onOpenNote: onOpenNote)
                    }
                    .id(verse.number)
                }
            }
            .scrollTargetLayout()
            .padding(.top, 20)
        }
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
                Slider(value: Binding(get: { Double(chapter) }, set: { chapter = Int($0.rounded()) }),
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
    @Environment(ReaderSettings.self) private var settings

    var body: some View {
        Text(AnnotationMarkup.attributed(text, linkable: true, bookID: bookID, chapter: chapter))
            .font(settings.fontChoice.font(size: settings.fontSize * 1.05, relativeTo: .headline, bold: true))
            .foregroundStyle(settings.theme.text)
            .tint(Color.accentColor)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, settings.lineSpacing)
    }
}

// MARK: - 각주 마커 팝업

struct MarkerNoteSheet: View {
    let n: String
    let text: String
    @Environment(\.dismiss) private var dismiss
    @Environment(ReaderSettings.self) private var settings

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(settings.bodyFont())
                    .foregroundStyle(settings.theme.text)
                    .lineSpacing(settings.lineSpacing)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .background(settings.theme.background.ignoresSafeArea())
            .navigationTitle("주석 \(n)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
            .preferredColorScheme(settings.theme.colorScheme)
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - 주석 열/목록

/// 오른쪽 주석 열(스크롤 포함)
struct NotesColumn: View {
    let title: String
    let notes: [ChapterNote]
    let emptyHint: String
    @Environment(ReaderSettings.self) private var settings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                NotesList(title: title, notes: notes, emptyHint: emptyHint)
            }
            .padding(.horizontal, 22).padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(settings.theme.background)
    }
}

/// 주석 목록 본문(제목 + 항목들)
struct NotesList: View {
    let title: String
    let notes: [ChapterNote]
    let emptyHint: String
    @Environment(ReaderSettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(settings.theme.secondary)
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
                        Text(note.text)
                            .font(settings.fontChoice.font(size: settings.fontSize * 0.9))
                            .foregroundStyle(settings.theme.text)
                            .textSelection(.enabled)
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
    @Environment(KnbNotesStore.self) private var knb
    @Environment(ReaderSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Introduction?

    var body: some View {
        NavigationStack {
            Group {
                if !knb.hasData || knb.intros.isEmpty {
                    ContentUnavailableView(
                        "입문 자료 없음",
                        systemImage: "text.book.closed",
                        description: Text("scripts/fetch_knbnotes.py 로 주석 성경의 입문을 내려받은 뒤 다시 빌드하세요.")
                    )
                } else {
                    List {
                        if let book = knb.intro(forBook: currentBookID) {
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
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
            .fullScreenCover(item: $selected) { intro in
                IntroDetailView(intro: intro).environment(settings)
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ level: IntroLevel) -> some View {
        let items = knb.intros(of: level)
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
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.dismiss) private var dismiss

    private var wide: Bool { hSize == .regular }

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
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
            .preferredColorScheme(settings.theme.colorScheme)
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
        Text(intro.body.isEmpty ? "본문이 비어 있습니다." : intro.body)
            .font(settings.bodyFont())
            .foregroundStyle(settings.theme.text)
            .lineSpacing(settings.lineSpacing)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
