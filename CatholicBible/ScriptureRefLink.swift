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

    // (선택적 책약어)(장):(절)(–끝절 또는 –끝장:끝절)?  — "33:6" 는 앞 책을 잇는다.
    //  그룹: 1=책약어 2=장 3=절 4=대시뒤 첫 수 5=대시뒤 둘째 수(교차장일 때 끝절)
    private static let regex = try? NSRegularExpression(
        pattern: "((?:[1-4]\\s)?[A-Z][A-Za-z]{1,4})?\\s?(\\d{1,3}):(\\d{1,3})(?:[–-](\\d{1,3})(?::(\\d{1,3}))?)?")

    /// text → 인용을 링크로 바꾼 AttributedString.
    /// currentBook: 책약어 없는 "33:6" 이 이을 기준 책(그 장의 책 id).
    /// font: 링크·비링크 런에 똑같이 적용할 글꼴(링크 런이 기본 크기로 커지는 것 방지).
    static func linkify(_ text: String, currentBook: String?,
                        font: Font? = nil) -> AttributedString {
        guard let regex, !text.isEmpty else {
            var a = AttributedString(text); if let font { a.font = font }; return a
        }
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
            // 범위 끝(장·절) 계산: "1:16–17"→같은 장 17절, "1:1–2:3"→2장 3절.
            let d1 = m.range(at: 4).location != NSNotFound
                ? Int(ns.substring(with: m.range(at: 4))) : nil
            let d2 = m.range(at: 5).location != NSNotFound
                ? Int(ns.substring(with: m.range(at: 5))) : nil
            let endChapter = d2 != nil ? (d1 ?? c) : c
            let endVerse = d2 ?? d1 ?? v
            if m.range.location > last {
                result += AttributedString(ns.substring(with:
                    NSRange(location: last, length: m.range.location - last)))
            }
            var link = AttributedString(ns.substring(with: m.range))
            link.foregroundColor = .accentColor
            link.underlineStyle = .single
            link.link = URL(string:
                "catholicbible://xref?b=\(bID)&c=\(c)&v=\(v)&ec=\(endChapter)&ev=\(endVerse)")
            result += link
            last = m.range.location + m.range.length
        }
        if last < ns.length { result += AttributedString(ns.substring(from: last)) }
        // 링크 런은 Text 의 .font() 를 무시하므로, 모든 런에 같은 글꼴을 직접 준다.
        if let font { result.font = font }
        return result
    }
}

/// 상호참조/주석에서 탭한 인용 구절 대상(범위 끝 포함)
struct XrefTarget: Identifiable {
    let bookID: String
    let chapter: Int
    let verse: Int
    var endChapter: Int = 0    // 0 또는 <chapter 이면 시작과 같은 단일 절
    var endVerse: Int = 0
    var id: String { "\(bookID).\(chapter).\(verse).\(endChapter).\(endVerse)" }
}

/// 미리보기 창에서 노트 편집 요청 대상
private struct RefNoteTarget: Identifiable {
    let ref: VerseRef
    let text: String
    var id: String { ref.id }
}

/// 미리보기에 표시할 (장, 절) 한 항목
private struct RangeVerse: Identifiable {
    let chapter: Int
    let verse: Verse
    let newChapter: Bool   // 여러 장에 걸칠 때 장 라벨을 붙일 첫 절
    var id: String { "\(chapter).\(verse.number)" }
}

// MARK: - 인용 구절 미리보기(판본 선택 가능)

struct RefPreviewSheet: View {
    let target: XrefTarget
    /// 미리보기 판본(따로 저장·유지, 사용자가 고를 수 있음).
    @AppStorage("xref.editionID") private var editionID = "knb"
    @Environment(BibleStore.self) private var store
    @Environment(ReaderSettings.self) private var settings
    @Environment(AnnotationStore.self) private var annotations
    @Environment(ReaderNavigation.self) private var navigation
    @Environment(\.dismiss) private var dismiss
    @State private var noteTarget: RefNoteTarget?
    @State private var dictRequest: DictionaryRequest?

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

    /// 범위 끝(장·절). endChapter 가 시작보다 작으면 단일 절.
    private var endChapter: Int { max(target.endChapter, target.chapter) }
    private var endVerse: Int {
        endChapter == target.chapter ? max(target.endVerse, target.verse) : target.endVerse
    }

    private var title: String {
        let name = book.map { store.bookShortName(edition: edition, book: $0) } ?? target.bookID
        if endChapter > target.chapter {
            return "\(name) \(target.chapter),\(target.verse)–\(endChapter),\(endVerse)"
        }
        if endVerse > target.verse {
            return "\(name) \(target.chapter),\(target.verse)-\(endVerse)"
        }
        return "\(name) \(target.chapter),\(target.verse)"
    }

    /// 인용 범위에 해당하는 절 목록. 아주 큰 범위는 40절로 제한한다.
    private var rangeVerses: [RangeVerse] {
        guard let book else { return [] }
        var out: [RangeVerse] = []
        let cap = 40
        let multi = endChapter > target.chapter
        var ch = target.chapter
        while ch <= endChapter && out.count < cap {
            let lo = ch == target.chapter ? target.verse : 1
            let hi = ch == endChapter ? endVerse : Int.max
            var first = true
            for v in store.verses(edition: edition, book: book, chapter: ch)
                where v.number >= lo && v.number <= hi {
                out.append(RangeVerse(chapter: ch, verse: v, newChapter: multi && first))
                first = false
                if out.count >= cap { break }
            }
            ch += 1
        }
        return out
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

                    if let book, !rangeVerses.isEmpty {
                        // 절 번호를 눌러 책갈피·노트·사전·복사(리더와 동일한 절 행).
                        ForEach(rangeVerses) { item in
                            if item.newChapter {
                                Text(book.chapterLabel(item.chapter))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(settings.theme.secondary)
                                    .padding(.top, 4)
                            }
                            VerseRowView(edition: edition, book: book,
                                         chapter: item.chapter, verse: item.verse,
                                         highlighted: item.chapter == target.chapter
                                             && item.verse.number == target.verse,
                                         onOpenNote: { ref, text in
                                             noteTarget = RefNoteTarget(ref: ref, text: text)
                                         },
                                         onLookUp: { dictRequest = DictionaryRequest() })
                        }
                    } else {
                        Text("이 판본에는 해당 본문이 없습니다.")
                            .font(.footnote)
                            .foregroundStyle(settings.theme.secondary)
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
            .sheet(item: $noteTarget) { t in
                NoteEditorView(verse: t.ref, verseText: t.text,
                               existing: annotations.noteOrNew(for: t.ref))
                    .environment(annotations)
                    .environment(settings)
            }
            .sheet(item: $dictRequest) { req in
                DictionaryView(initialTerm: req.term)
                    .environment(settings)
            }
        }
        .presentationDetents([.medium, .large])
    }
}
