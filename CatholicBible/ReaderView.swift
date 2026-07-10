//
//  ReaderView.swift
//  CatholicBible
//
//  ebook 리더 본체. 장 단위 가로 페이지 넘김(TabView .page),
//  하단 장 슬라이더, Aa 보기 설정, 장/절 책갈피.
//

import SwiftUI
import UIKit

struct ReaderView: View {
    let edition: Edition
    let book: BibleBook

    @Environment(BibleStore.self) private var store
    @Environment(ReaderSettings.self) private var settings
    @Environment(ReadingState.self) private var readingState
    @Environment(ReaderNavigation.self) private var navigation

    /// 0이면 아직 시작 위치를 정하지 않은 상태
    @State private var chapter = 0
    @State private var highlightVerse: Int?
    @State private var showChapterPicker = false
    @State private var showAppearance = false

    var body: some View {
        ZStack {
            settings.theme.background.ignoresSafeArea()

            if chapter > 0 {
                TabView(selection: $chapter) {
                    ForEach(1...book.chapterCount, id: \.self) { number in
                        ChapterPageView(edition: edition,
                                        book: book,
                                        chapter: number,
                                        highlightVerse: number == chapter ? $highlightVerse : .constant(nil))
                            .tag(number)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .safeAreaInset(edge: .bottom) { chapterSlider }
        .navigationTitle("\(edition.shortName) · \(store.bookShortName(edition: edition, book: book)) \(book.chapterLabel(max(chapter, 1)))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { readerToolbar }
        .preferredColorScheme(settings.theme.colorScheme)
        .onAppear(perform: applyStartPosition)
        .onChange(of: navigation.pendingChapter) { applyStartPosition() }
        .onChange(of: chapter) { _, newValue in
            guard newValue > 0 else { return }
            readingState.savePosition(edition: edition, book: book, chapter: newValue)
        }
        .sheet(isPresented: $showChapterPicker) {
            ChapterPickerView(book: book, current: max(chapter, 1)) { picked in
                chapter = picked
                showChapterPicker = false
            }
        }
    }

    private func applyStartPosition() {
        if let pending = navigation.pendingChapter {
            chapter = min(max(pending, 1), book.chapterCount)
            highlightVerse = navigation.pendingVerse
            navigation.pendingChapter = nil
            navigation.pendingVerse = nil
        } else if chapter == 0 {
            chapter = readingState.lastChapter(edition: edition, book: book)
        }
    }

    // MARK: - 툴바

    @ToolbarContentBuilder
    private var readerToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button("장 선택", systemImage: "list.number") { showChapterPicker = true }

            Button {
                readingState.toggleBookmark(editionID: edition.id, bookID: book.id, chapter: max(chapter, 1))
            } label: {
                Label("책갈피",
                      systemImage: readingState.isBookmarked(editionID: edition.id, bookID: book.id, chapter: max(chapter, 1))
                          ? "bookmark.fill" : "bookmark")
            }

            Button("보기 설정", systemImage: "textformat.size") { showAppearance = true }
                .popover(isPresented: $showAppearance, arrowEdge: .top) {
                    AppearanceControls()
                        .presentationCompactAdaptation(.popover)
                }
        }
    }

    // MARK: - 하단 장 슬라이더

    @ViewBuilder
    private var chapterSlider: some View {
        if book.chapterCount > 1 && chapter > 0 {
            HStack(spacing: 14) {
                Text("1")
                    .font(.caption2)
                    .foregroundStyle(settings.theme.secondary)
                Slider(
                    value: Binding(
                        get: { Double(chapter) },
                        set: { chapter = Int($0.rounded()) }
                    ),
                    in: 1...Double(book.chapterCount),
                    step: 1
                )
                .accessibilityLabel("장 이동")
                .accessibilityValue("\(book.chapterLabel(chapter))")
                Text("\(book.chapterCount)")
                    .font(.caption2)
                    .foregroundStyle(settings.theme.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .background(settings.theme.background.opacity(0.92))
        }
    }
}

// MARK: - 한 장(챕터) 페이지

struct ChapterPageView: View {
    let edition: Edition
    let book: BibleBook
    let chapter: Int
    @Binding var highlightVerse: Int?

    @Environment(BibleStore.self) private var store
    @Environment(ReaderSettings.self) private var settings
    @Environment(ReadingState.self) private var readingState

    /// scrollPosition(id:)용 — LazyVStack에서도 아직 만들어지지 않은 절로 이동할 수 있다
    @State private var scrolledVerse: Int?

    var body: some View {
        let verses = store.verses(edition: edition, book: book, chapter: chapter)

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                if verses.isEmpty {
                    MissingTextView(edition: edition, book: book)
                        .padding(.top, 48)
                } else {
                    LazyVStack(alignment: .leading, spacing: settings.lineSpacing * 0.9) {
                        ForEach(verses) { verse in
                            verseView(verse)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.top, 28)

                    copyrightFooter
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.bottom, 60)
            .frame(maxWidth: .infinity) // 본문 열을 가운데로
        }
        .scrollPosition(id: $scrolledVerse, anchor: .center)
        .onChange(of: highlightVerse) { _, verse in
            jump(to: verse)
        }
        .onAppear {
            jump(to: highlightVerse)
        }
    }

    private func jump(to verse: Int?) {
        guard let verse else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            scrolledVerse = verse
        }
        // 강조 표시가 잠시 보인 뒤 사라지도록
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            if highlightVerse == verse { highlightVerse = nil }
        }
    }

    // MARK: 장 머리글

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(store.bookName(edition: edition, book: book))
                .font(settings.fontChoice.font(size: settings.fontSize * 0.8, relativeTo: .subheadline))
                .foregroundStyle(settings.theme.secondary)
                .kerning(1)
            Text(book.chapterLabel(chapter))
                .font(settings.fontChoice.font(size: settings.fontSize * 2.0, relativeTo: .largeTitle, bold: true))
                .foregroundStyle(settings.theme.text)
            Rectangle()
                .fill(settings.theme.secondary.opacity(0.35))
                .frame(width: 44, height: 1)
        }
        .padding(.top, 36)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(store.bookName(edition: edition, book: book)) \(book.chapterLabel(chapter))")
    }

    // MARK: 절

    private func verseView(_ verse: Verse) -> some View {
        let highlighted = highlightVerse == verse.number
        let bookmarked = readingState.isBookmarked(editionID: edition.id, bookID: book.id, chapter: chapter, verse: verse.number)

        return verseText(verse)
            .lineSpacing(settings.lineSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(highlighted ? Color.accentColor.opacity(0.18) : .clear)
            )
            .overlay(alignment: .topTrailing) {
                if bookmarked {
                    Image(systemName: "bookmark.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor.opacity(0.7))
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
            .contextMenu {
                Button(bookmarked ? "절 책갈피 지우기" : "이 절 책갈피",
                       systemImage: bookmarked ? "bookmark.slash" : "bookmark") {
                    readingState.toggleBookmark(editionID: edition.id, bookID: book.id, chapter: chapter, verse: verse.number)
                }
                Button("복사", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = "\(verse.text) (\(book.abbrev) \(chapter),\(verse.number))"
                }
            }
            .animation(.easeInOut(duration: 0.3), value: highlighted)
            .accessibilityLabel("\(verse.number)절, \(verse.text)")
    }

    private func verseText(_ verse: Verse) -> Text {
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

    // MARK: 저작권 꼬리글

    private var copyrightFooter: some View {
        Text(edition.copyright)
            .font(.caption2)
            .foregroundStyle(settings.theme.secondary.opacity(0.8))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 44)
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
            Text("개발용 안내: 저장소의 scripts/fetch_cbck_bible.py --edition \(edition.id) 를 실행해 bible.cbck.or.kr에서 본문을 내려받은 뒤 다시 빌드하면 이 책을 읽을 수 있습니다. 본문 저작권은 각 판본의 저작권자에게 있으므로 배포 전에 이용 허가가 필요합니다.")
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
                        Button {
                            onPick(number)
                        } label: {
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
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
            // 글자 크기
            VStack(alignment: .leading, spacing: 6) {
                Text("글자 크기").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("가").font(.footnote)
                    Slider(value: $settings.fontSize, in: ReaderSettings.fontSizeRange, step: 1)
                        .accessibilityLabel("글자 크기")
                    Text("가").font(.title2)
                }
            }

            // 줄 간격
            VStack(alignment: .leading, spacing: 6) {
                Text("줄 간격").font(.caption).foregroundStyle(.secondary)
                Slider(value: $settings.lineSpacingFactor, in: 0.35...1.1)
                    .accessibilityLabel("줄 간격")
            }

            // 서체
            Picker("서체", selection: $settings.fontChoice) {
                ForEach(FontChoice.allCases) { choice in
                    Text(choice.label).tag(choice)
                }
            }
            .pickerStyle(.segmented)

            // 절 번호 표시
            Toggle("절 번호 표시", isOn: $settings.showVerseNumbers)
                .font(.subheadline)

            // 종이 테마
            VStack(alignment: .leading, spacing: 6) {
                Text("배경").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    ForEach(ReaderTheme.allCases) { theme in
                        Button {
                            settings.theme = theme
                        } label: {
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
