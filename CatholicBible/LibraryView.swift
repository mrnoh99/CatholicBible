//
//  LibraryView.swift
//  CatholicBible
//
//  서가: 구약·신약을 분류(오경/역사서/…)별로 나눠 73권을 보여 준다.
//  본문이 아직 수집되지 않은 책은 흐리게 표시된다.
//

import SwiftUI

struct LibraryView: View {
    @Environment(BibleStore.self) private var store
    @Environment(ReadingState.self) private var readingState
    @Environment(ReaderNavigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
        List(selection: $navigation.selectedBookID) {
            ForEach(Testament.allCases) { testament in
                Section {
                    ForEach(BookCategory.allCases.filter { $0.testament == testament }) { category in
                        categorySection(category)
                    }
                } header: {
                    Text(testament.title)
                        .font(.headline)
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private func categorySection(_ category: BookCategory) -> some View {
        // 사도행전·묵시록처럼 한 권뿐인 분류는 소제목 없이 바로 나열
        let books = Bible.books(in: category)
        if books.count > 1 {
            DisclosureGroup {
                ForEach(books) { book in bookRow(book) }
            } label: {
                Text(category.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        } else {
            ForEach(books) { book in bookRow(book) }
        }
    }

    private func bookRow(_ book: BibleBook) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(book.shortName)
                if book.name != book.shortName {
                    Text(book.name)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if store.hasText(book) {
                Text(book.id == "ps" ? "\(book.chapterCount)편" : "\(book.chapterCount)장")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("본문 준비 중")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .opacity(store.hasText(book) ? 1 : 0.45)
        .tag(book.id)
        .accessibilityLabel(store.hasText(book) ? book.name : "\(book.name), 본문 준비 중")
    }
}
