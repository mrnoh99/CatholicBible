//
//  LibraryView.swift
//  CatholicBible
//
//  사이드바: 판본(8가지 책) 선택 + 선택된 판본의 목차.
//  본문이 아직 수집되지 않은 책은 흐리게 표시된다.
//

import SwiftUI
import AVFoundation

/// 사이드바 credit을 누르면 생일 축하 노래를 재생한다.
/// (AVAudioPlayer는 재생 중 유지되어야 하므로 shared로 붙잡아 둔다.)
final class BirthdaySound {
    static let shared = BirthdaySound()
    private var player: AVAudioPlayer?

    func play() {
        guard let url = Bundle.main.url(forResource: "happy_birthday", withExtension: "m4a") else { return }
        #if !targetEnvironment(macCatalyst)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return }
        player = p
        p.prepareToPlay()
        p.play()
    }
}

struct LibraryView: View {
    @Environment(BibleStore.self) private var store
    @Environment(ReadingState.self) private var readingState
    @Environment(ReaderNavigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
        @Bindable var readingState = readingState
        let edition = readingState.selectedEdition

        List(selection: $navigation.selectedBookID) {
            Section {
                Picker("판본", selection: $readingState.selectedEditionID) {
                    ForEach(Editions.all) { edition in
                        Text(edition.name).tag(edition.id)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("책 (판본)")
            }

            switch edition.scope {
            case .full:
                ForEach(Testament.allCases) { testament in
                    Section {
                        ForEach(BookCategory.allCases.filter { $0.testament == testament }) { category in
                            categorySection(category, edition: edition)
                        }
                    } header: {
                        Text(testament.title)
                            .font(.headline)
                    }
                }
            case .newTestament:
                Section {
                    ForEach(BookCategory.allCases.filter { $0.testament == .new }) { category in
                        categorySection(category, edition: edition)
                    }
                } header: {
                    Text(Testament.new.title)
                        .font(.headline)
                }
            case .psalter:
                Section("목차") {
                    ForEach(edition.scope.books) { book in
                        bookRow(book, edition: edition)
                    }
                }
            }

            creditFooter
        }
        .listStyle(.sidebar)
        .onChange(of: readingState.selectedEditionID) { _, newID in
            // 판본을 바꾸면 새 판본 범위에 없는 책 선택은 해제한다.
            if let bookID = navigation.selectedBookID,
               let book = Bible.book(bookID),
               let edition = Editions.edition(newID),
               !edition.scope.contains(book) {
                navigation.selectedBookID = nil
            }
        }
    }

    /// 사이드바 맨 아래 개발자·버전·빌드 표기.
    /// 문구를 누르면 생일 축하 노래가 재생된다(길게 누르면 이메일).
    private var creditFooter: some View {
        VStack(spacing: 2) {
            Button {
                BirthdaySound.shared.play()
            } label: {
                Text("Developed by JaiSung NOH MD.,\nas a birthday gift for Eunkyung (Teresa) Kim\n— July 30, 2026")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("생일 축하 노래 재생")
            .accessibilityHint("눌러서 생일 축하 노래를 듣습니다")

            Text(appVersionText)
                .foregroundStyle(.tertiary)
        }
        .font(.caption2)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 8)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    /// "v1.0 (build 2)" 형태의 버전·빌드 문자열 (Info.plist에서 읽음)
    private var appVersionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "v\(version) (build \(build))"
    }

    @ViewBuilder
    private func categorySection(_ category: BookCategory, edition: Edition) -> some View {
        // 사도행전·묵시록처럼 한 권뿐인 분류는 소제목 없이 바로 나열
        let books = Bible.books(in: category)
        if books.count > 1 {
            DisclosureGroup {
                ForEach(books) { book in bookRow(book, edition: edition) }
            } label: {
                Text(category.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        } else {
            ForEach(books) { book in bookRow(book, edition: edition) }
        }
    }

    private func bookRow(_ book: BibleBook, edition: Edition) -> some View {
        let displayName = store.bookShortName(edition: edition, book: book)
        let fullName = store.bookName(edition: edition, book: book)
        let available = store.hasText(edition: edition, book: book)

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                if fullName != displayName {
                    Text(fullName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if available {
                Text(book.id == "ps" ? "\(book.chapterCount)편" : "\(book.chapterCount)장")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("본문 준비 중")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .opacity(available ? 1 : 0.45)
        .tag(book.id)
        .accessibilityLabel(available ? fullName : "\(fullName), 본문 준비 중")
    }
}
