//
//  ScriptureRefLink.swift
//  CatholicBible
//
//  주석·상호참조 본문에 나오는 성경 인용(예: "Gn 2:1", "Ps 33:7",
//  "1 Cor 7:11", "Col 1:16–17", 이어지는 "33:6")을 탭 가능한 링크로 바꾸고,
//  탭하면 그 구절을 골라 놓은 판본으로 미리 보여 준다(RefPreviewSheet).
//

import SwiftUI

// MARK: - 인용 파서

enum ScriptureRef {
    /// USCCB 영어 약어 → 앱 책 id (fetch_cbck_bible.BOOKS 의 id 와 일치)
    static let abbrev: [String: String] = [
        "Gn": "gn", "Ex": "ex", "Lv": "lv", "Nm": "nm", "Dt": "dt", "Jos": "jos",
        "Jgs": "jgs", "Ru": "ru", "1 Sm": "1sm", "2 Sm": "2sm", "1 Kgs": "1kgs",
        "2 Kgs": "2kgs", "1 Chr": "1chr", "2 Chr": "2chr", "Ezr": "ezr", "Neh": "neh",
        "Tb": "tb", "Jdt": "jdt", "Est": "est", "1 Mc": "1mc", "2 Mc": "2mc",
        "Jb": "jb", "Ps": "ps", "Prv": "prv", "Eccl": "eccl", "Sg": "sg", "Wis": "wis",
        "Sir": "sir", "Is": "is", "Jer": "jer", "Lam": "lam", "Bar": "bar", "Ez": "ez",
        "Dn": "dn", "Hos": "hos", "Jl": "jl", "Am": "am", "Ob": "ob", "Jon": "jon",
        "Mi": "mi", "Na": "na", "Hb": "hb", "Zep": "zep", "Hg": "hg", "Zec": "zec",
        "Mal": "mal", "Mt": "mt", "Mk": "mk", "Lk": "lk", "Jn": "jn", "Acts": "acts",
        "Rom": "rom", "1 Cor": "1cor", "2 Cor": "2cor", "Gal": "gal", "Eph": "eph",
        "Phil": "phil", "Col": "col", "1 Thes": "1thes", "2 Thes": "2thes",
        "1 Tm": "1tm", "2 Tm": "2tm", "Ti": "ti", "Phlm": "phlm", "Heb": "heb",
        "Jas": "jas", "1 Pt": "1pt", "2 Pt": "2pt", "1 Jn": "1jn", "2 Jn": "2jn",
        "3 Jn": "3jn", "Jude": "jude", "Rev": "rv",
    ]

    // (선택적 책약어)(장):(절)(–끝절)?  — 이어지는 "33:6" 는 앞 책을 잇는다.
    private static let regex = try? NSRegularExpression(
        pattern: "((?:[1-4]\\s)?[A-Z][A-Za-z]{1,4})?\\s?(\\d{1,3}):(\\d{1,3})(?:[–-]\\d{1,3})?")

    /// text → 인용을 링크로 바꾼 AttributedString.
    /// currentBook: 책약어 없는 "33:6" 이 이을 기준 책(그 장의 책 id).
    static func linkify(_ text: String, currentBook: String?) -> AttributedString {
        guard let regex, !text.isEmpty else { return AttributedString(text) }
        let ns = text as NSString
        var result = AttributedString()
        var last = 0
        var lastBook = currentBook
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            var bookID: String?
            if m.range(at: 1).location != NSNotFound {
                let ab = ns.substring(with: m.range(at: 1))
                    .trimmingCharacters(in: .whitespaces)
                if let id = abbrev[ab] { bookID = id; lastBook = id }
                else { continue }          // 대문자 단어지만 성경 약어 아님 → 링크 안 함
            } else {
                bookID = lastBook
            }
            guard let bID = bookID,
                  let c = Int(ns.substring(with: m.range(at: 2))),
                  let v = Int(ns.substring(with: m.range(at: 3))) else { continue }
            if m.range.location > last {
                result += AttributedString(ns.substring(with:
                    NSRange(location: last, length: m.range.location - last)))
            }
            var link = AttributedString(ns.substring(with: m.range))
            link.foregroundColor = .accentColor
            link.underlineStyle = .single
            link.link = URL(string: "catholicbible://xref?b=\(bID)&c=\(c)&v=\(v)")
            result += link
            last = m.range.location + m.range.length
        }
        if last < ns.length { result += AttributedString(ns.substring(from: last)) }
        return result
    }
}

/// 상호참조/주석에서 탭한 인용 구절 대상
struct XrefTarget: Identifiable {
    let bookID: String
    let chapter: Int
    let verse: Int
    var id: String { "\(bookID).\(chapter).\(verse)" }
}

// MARK: - 인용 구절 미리보기(판본 선택 가능)

struct RefPreviewSheet: View {
    let target: XrefTarget
    /// 미리보기 판본(따로 저장·유지, 사용자가 고를 수 있음).
    @AppStorage("xref.editionID") private var editionID = "knb"
    @Environment(BibleStore.self) private var store
    @Environment(ReaderSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    private var book: BibleBook? { Bible.book(target.bookID) }
    private var edition: Edition {
        Editions.edition(editionID) ?? Editions.edition("knb") ?? Editions.all[0]
    }
    /// 이 책 본문을 가진 판본만 후보로.
    private var availableEditions: [Edition] {
        guard let book else { return Editions.all }
        let list = Editions.all.filter { store.hasText(edition: $0, book: book) }
        return list.isEmpty ? Editions.all : list
    }

    private var title: String {
        let name = book.map { store.bookShortName(edition: edition, book: $0) } ?? target.bookID
        return "\(name) \(target.chapter),\(target.verse)"
    }

    /// 대상 절과 이어지는 몇 절(문맥). 시작 절부터 최대 5절.
    private var verses: [Verse] {
        guard let book else { return [] }
        return store.verses(edition: edition, book: book, chapter: target.chapter)
            .filter { $0.number >= target.verse && $0.number < target.verse + 5 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("판본", selection: $editionID) {
                        ForEach(availableEditions) { ed in Text(ed.shortName).tag(ed.id) }
                    }
                    .pickerStyle(.menu)
                    .tint(Color.accentColor)

                    if verses.isEmpty {
                        Text("이 판본에는 해당 본문이 없습니다.")
                            .font(.footnote)
                            .foregroundStyle(settings.theme.secondary)
                    } else {
                        ForEach(verses) { v in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(v.number)")
                                    .font(settings.fontChoice.font(size: settings.fontSize * 0.72, bold: true))
                                    .foregroundStyle(Color.accentColor)
                                    .frame(minWidth: settings.fontSize, alignment: .trailing)
                                Text(AnnotationMarkup.stripMarkers(v.text))
                                    .font(settings.bodyFont())
                                    .foregroundStyle(settings.theme.text)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(settings.theme.background.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
            .preferredColorScheme(settings.theme.colorScheme)
        }
        .presentationDetents([.medium, .large])
    }
}
