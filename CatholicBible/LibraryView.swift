//
//  LibraryView.swift
//  CatholicBible
//
//  사이드바: 판본(8가지 책) 선택 + 선택된 판본의 목차.
//  본문이 아직 수집되지 않은 책은 흐리게 표시된다.
//

import SwiftUI
import AVFoundation

/// 앱 에디션 구분.
/// - 기본(플래그 없음): 생일 선물 버전 — credit을 누르면 생일 축하 노래 재생.
/// - `GENERAL_EDITION` 컴파일 플래그를 켜면: 일반 버전 — 사운드 없이
///   "Developed by JaiSung NOH MD., 2026"만 표시.
/// (Build Settings ▸ Swift Compiler - Custom Flags ▸ Active Compilation
///  Conditions 에 GENERAL_EDITION 을 추가하면 일반 버전으로 빌드된다.)
enum AppEdition {
    #if GENERAL_EDITION
    static let isBirthday = false
    #else
    static let isBirthday = true
    #endif
}

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

    private var oldTestamentCategories: [BookCategory] {
        BookCategory.allCases.filter { $0.testament == .old }
    }

    private var newTestamentCategories: [BookCategory] {
        BookCategory.allCases.filter { $0.testament == .new }
    }

    var body: some View {
        let edition = readingState.selectedEdition

        List(selection: Binding(
            get: { navigation.selectedBookID },
            set: { navigation.selectedBookID = $0 }
        )) {
            Section {
                Picker("판본", selection: Binding(
                    get: { readingState.selectedEditionID },
                    set: { readingState.selectedEditionID = $0 }
                )) {
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
                Section {
                    ForEach(oldTestamentCategories) { category in
                        categorySection(category, edition: edition)
                    }
                } header: {
                    Text(Testament.old.title)
                        .font(.headline)
                }
                Section {
                    ForEach(newTestamentCategories) { category in
                        categorySection(category, edition: edition)
                    }
                } header: {
                    Text(Testament.new.title)
                        .font(.headline)
                }
            case .newTestament:
                Section {
                    ForEach(newTestamentCategories) { category in
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
    /// 생일 버전(기본): 문구를 누르면 생일 축하 노래가 재생된다.
    /// 일반 버전(GENERAL_EDITION 플래그): 사운드 없이 개발자·연도만 표시.
    private var creditFooter: some View {
        VStack(spacing: 6) {
            if AppEdition.isBirthday {
                Button {
                    BirthdaySound.shared.play()
                } label: {
                    VStack(spacing: 3) {
                        Text("Developed by JaiSung NOH MD.")
                            .font(.system(size: 12, weight: .semibold, design: .default))
                        Text("as a birthday gift for\nEunkyung (Teresa) Kim\n— July 30, 2026")
                            .font(.system(size: 11, weight: .regular, design: .default))
                    }
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("생일 축하 노래 재생")
                .accessibilityHint("눌러서 생일 축하 노래를 듣습니다")
            } else {
                Text("Developed by JaiSung NOH MD.\n2026")
                    .multilineTextAlignment(.center)
                    .font(.system(size: 12, weight: .semibold, design: .default))
                    .foregroundStyle(.primary)
            }

            Text(appVersionText)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 12)
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
        let books = Bible.books(in: category)
        let bookData = books.map { book in
            (book: book, displayName: store.bookShortName(edition: edition, book: book),
             fullName: store.bookName(edition: edition, book: book),
             available: store.hasText(edition: edition, book: book))
        }
        if bookData.count > 1 {
            DisclosureGroup {
                ForEach(bookData, id: \.book.id) { data in
                    bookRow(book: data.book, displayName: data.displayName,
                           fullName: data.fullName, available: data.available)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: category == .gospels ? "book.pages" : "book")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 16)

                    Text(category.title)
                        .font(.system(size: 14, weight: .semibold, design: .default))
                        .foregroundStyle(.primary)
                }
            }
        } else {
            ForEach(bookData, id: \.book.id) { data in
                bookRow(book: data.book, displayName: data.displayName,
                       fullName: data.fullName, available: data.available)
            }
        }
    }

    private func bookRow(book: BibleBook, displayName: String, fullName: String, available: Bool) -> some View {
        let _ = (displayName, fullName, available)

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.system(size: 15, weight: available ? .semibold : .regular, design: .default))
                    .foregroundStyle(available ? .primary : .secondary)

                if fullName != displayName {
                    Text(fullName)
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if available {
                Text(book.id == "ps" ? "\(book.chapterCount)편" : "\(book.chapterCount)장")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.08))
                    .clipShape(Capsule())
            } else {
                Text("준비 중")
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundStyle(.tertiary)
            }
        }
        .opacity(available ? 1 : 0.6)
        .tag(book.id)
        .accessibilityLabel(available ? fullName : "\(fullName), 본문 준비 중")
    }
}
