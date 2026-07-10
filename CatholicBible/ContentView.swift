//
//  ContentView.swift
//  CatholicBible
//
//  iPad에 맞춘 2단 구성: 왼쪽 서가(73권 목차) + 오른쪽 ebook 리더.
//

import SwiftUI

// MARK: - 화면 이동 상태

@Observable
final class ReaderNavigation {
    var selectedBookID: String?
    /// 리더가 열릴 때 이동할 장/절 (검색·책갈피에서 설정)
    var pendingChapter: Int?
    var pendingVerse: Int?

    func open(bookID: String, chapter: Int, verse: Int? = nil) {
        pendingChapter = chapter
        pendingVerse = verse
        selectedBookID = bookID
    }
}

// MARK: - 루트 화면

struct ContentView: View {
    @State private var navigation = ReaderNavigation()
    @State private var showSearch = false
    @State private var showBookmarks = false

    var body: some View {
        NavigationSplitView {
            LibraryView()
                .navigationTitle("성경")
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("검색", systemImage: "magnifyingglass") { showSearch = true }
                        Button("책갈피", systemImage: "bookmark") { showBookmarks = true }
                    }
                }
        } detail: {
            if let bookID = navigation.selectedBookID, let book = Bible.book(bookID) {
                ReaderView(book: book)
                    .id(book.id) // 책이 바뀌면 리더를 새로 만든다
            } else {
                WelcomeView()
            }
        }
        .environment(navigation)
        .sheet(isPresented: $showSearch) {
            SearchView()
                .environment(navigation)
        }
        .sheet(isPresented: $showBookmarks) {
            BookmarksView()
                .environment(navigation)
        }
    }
}

// MARK: - 첫 화면 (책을 고르기 전)

struct WelcomeView: View {
    @Environment(BibleStore.self) private var store
    @Environment(ReadingState.self) private var readingState
    @Environment(ReaderNavigation.self) private var navigation
    @Environment(ReaderSettings.self) private var settings

    var body: some View {
        ZStack {
            settings.theme.background.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "book.closed")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(settings.theme.secondary)
                Text("성경")
                    .font(settings.fontChoice.font(size: 40, relativeTo: .largeTitle, bold: true))
                    .foregroundStyle(settings.theme.text)
                Text(store.translation)
                    .font(.subheadline)
                    .foregroundStyle(settings.theme.secondary)

                if store.isLoaded {
                    Text("본문 수록: \(store.availableBookCount)권 / \(Bible.books.count)권")
                        .font(.footnote)
                        .foregroundStyle(settings.theme.secondary)
                }

                if let lastBookID = readingState.lastBookID,
                   let book = Bible.book(lastBookID) {
                    Button {
                        navigation.open(bookID: book.id,
                                        chapter: readingState.lastChapter(for: book))
                    } label: {
                        Label("이어 읽기 — \(book.shortName) \(book.chapterLabel(readingState.lastChapter(for: book)))",
                              systemImage: "book")
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 12)
                } else {
                    Text("왼쪽 서가에서 책을 선택하세요")
                        .font(.footnote)
                        .foregroundStyle(settings.theme.secondary)
                        .padding(.top, 12)
                }
            }
            .padding(40)
        }
        .preferredColorScheme(settings.theme.colorScheme)
    }
}

#Preview {
    ContentView()
        .environment(BibleStore())
        .environment(ReaderSettings())
        .environment(ReadingState())
}
