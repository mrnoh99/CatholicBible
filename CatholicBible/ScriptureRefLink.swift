//
//  ScriptureRefLink.swift
//  CatholicBible
//
//  주석·상호참조 본문에 나오는 성경 인용(예: "Gn 2:1", "Ps 33:7",
//  "1 Cor 7:11", "Col 1:16–17", 이어지는 "33:6")을 탭 가능한 링크로 바꾸고,
//  탭하면 그 구절을 골라 놓은 판본으로 미리 보여 준다(RefPreviewSheet).
//

import SwiftUI
import UIKit

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

    /// 한글 책 이름/약칭 → 앱 책 id
    static let koreanNames: [String: String] = {
        var map: [String: String] = [:]
        for book in Bible.books {
            map[book.name] = book.id
            map[book.shortName] = book.id
            map[book.abbrev] = book.id
        }
        // 추가 별칭 (주석에 자주 나오는 형태)
        map["마테오복음"] = "mt"
        map["마테오"] = "mt"
        map["마태오복음"] = "mt"
        map["마태오"] = "mt"
        map["마가복음"] = "mk"
        map["마가"] = "mk"
        map["누가복음"] = "lk"
        map["누가"] = "lk"
        map["요한복음"] = "jn"
        map["요한"] = "jn"
        map["사도행전"] = "acts"
        map["사도"] = "acts"
        // 주교회의 성경 약칭도 추가
        map["창세"] = "gn"
        map["탈출"] = "ex"
        map["레위"] = "lv"
        map["민수"] = "nm"
        map["신명"] = "dt"
        map["여호"] = "jos"
        map["판관"] = "jgs"
        map["시편"] = "ps"
        map["에즈"] = "ezr"
        map["느헤"] = "neh"
        map["욥"] = "jb"
        map["잠언"] = "prv"
        map["이사"] = "is"
        map["예레"] = "jer"
        map["에제"] = "ez"
        map["다니"] = "dn"
        map["로마"] = "rom"
        map["1코린"] = "1cor"
        map["2코린"] = "2cor"
        map["갈라"] = "gal"
        map["에페"] = "eph"
        map["필리"] = "phil"
        map["콜로"] = "col"
        map["1테살"] = "1thes"
        map["2테살"] = "2thes"
        map["1티모"] = "1tm"
        map["2티모"] = "2tm"
        map["티토"] = "ti"
        map["필레"] = "phlm"
        map["히브"] = "heb"
        map["야고"] = "jas"
        map["1베드"] = "1pt"
        map["2베드"] = "2pt"
        map["1요한"] = "1jn"
        map["2요한"] = "2jn"
        map["3요한"] = "3jn"
        map["유다"] = "jude"
        map["묵시"] = "rv"
        // 스페이스 포함 책 이름들 (주교회의 성경)
        map["사무 상"] = "1sm"
        map["사무엘 상"] = "1sm"
        map["사무 하"] = "2sm"
        map["사무엘 하"] = "2sm"
        map["열왕 상"] = "1kgs"
        map["열왕 하"] = "2kgs"
        map["역대 상"] = "1chr"
        map["역대기 상"] = "1chr"
        map["역대 하"] = "2chr"
        map["역대기 하"] = "2chr"
        map["마카 상"] = "1mc"
        map["마카비 상"] = "1mc"
        map["마카 하"] = "2mc"
        map["마카비 하"] = "2mc"
        map["고린도 전서"] = "1cor"
        map["고린도 후서"] = "2cor"
        map["테살로니가 전서"] = "1thes"
        map["테살로니가 후서"] = "2thes"
        map["베드로 전서"] = "1pt"
        map["베드로 후서"] = "2pt"
        map["요한 1서"] = "1jn"
        map["요한 2서"] = "2jn"
        map["요한 3서"] = "3jn"
        return map
    }()

    // (선택적 책약어)(장):(절)(–끝절 또는 –끝장:끝절)?  — "33:6" 는 앞 책을 잇는다.
    //  그룹: 1=책약어 2=장 3=절 4=대시뒤 첫 수 5=대시뒤 둘째 수(교차장일 때 끝절)
    private static let regex = try? NSRegularExpression(
        pattern: "((?:[1-4]\\s)?[A-Z][A-Za-z]{1,4})?\\s?(\\d{1,3}):(\\d{1,3})(?:[–-](\\d{1,3})(?::(\\d{1,3}))?)?")

    /// 한글 성경 참조 정규식: "책이름 장,절" 또는 "장,절" (점으로 구분된 절 범위 포함)
    /// 괄호 뒤 대시/점도 범위로 인식: "(민수 6,9)-11" → "민수 6,9-11", "(민수 31,8).16" → "민수 31,8-16"
    /// 스페이스 포함 책 이름 지원: "열왕 상", "역대 하", "고린도 전서" 등
    /// 그룹: 1=책이름(선택적, 1-3 숫자 접두사 포함) 2=장 3=절 4=대시뒤 첫 수 5=대시뒤 둘째 수 6=점뒤 절 7=점뒤 대시 절
    private static let koreanRegex = try? NSRegularExpression(
        pattern: "([1-3]?[가-힣]+(?:\\s[가-힣]+)*(?:복음|서간|기|편)?)?\\s*(\\d{1,3})[:,](\\d{1,3})(?:\\)?[–-](\\d{1,3})(?:[:,](\\d{1,3}))?)?(?:\\)?\\.(\\d{1,3})(?:[–-](\\d{1,3}))?)?")

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

    /// NSAttributedString 에 성경 인용 링크(catholicbible://xref)를 입힌다.
    /// (선택 가능한 UITextView 용 — 단어 선택과 링크 탭을 함께 지원.)
    static func addLinks(to attr: NSMutableAttributedString, currentBook: String?,
                         color: UIColor) {
        guard let regex else { return }
        let s = attr.string as NSString
        var lastBook = currentBook
        for m in regex.matches(in: attr.string,
                               range: NSRange(location: 0, length: s.length)) {
            var bookID: String?
            if m.range(at: 1).location != NSNotFound {
                let ab = s.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
                if let id = abbrev[ab] { bookID = id; lastBook = id } else { continue }
            } else {
                bookID = lastBook
            }
            guard let bID = bookID,
                  let c = Int(s.substring(with: m.range(at: 2))),
                  let v = Int(s.substring(with: m.range(at: 3))) else { continue }
            let d1 = m.range(at: 4).location != NSNotFound
                ? Int(s.substring(with: m.range(at: 4))) : nil
            let d2 = m.range(at: 5).location != NSNotFound
                ? Int(s.substring(with: m.range(at: 5))) : nil
            let d2_dot = m.numberOfRanges > 7 && m.range(at: 7).location != NSNotFound
                ? Int(s.substring(with: m.range(at: 7))) : nil
            let ec = d2 != nil ? (d1 ?? c) : c
            let ev = d2 ?? d2_dot ?? d1 ?? v
            if let url = URL(string:
                "catholicbible://xref?b=\(bID)&c=\(c)&v=\(v)&ec=\(ec)&ev=\(ev)") {
                attr.addAttributes([.link: url,
                                    .foregroundColor: color,
                                    .underlineStyle: NSUnderlineStyle.single.rawValue],
                                   range: m.range)
            }
        }
        addKoreanLinks(to: attr, currentBook: lastBook, color: color)
    }

    /// 한국어 인용(창세 2,4 / 1코린 15,22 / 창세 1,1-2,3 / 7,56; 10,11-16)을 링크로.
    /// 책 이름 없는 약자는 현재 책(원문)을 사용한다. 세미콜론 분리 내에서는 이전 책을 잇는다.
    /// 화이트리스트에 있는 것만 링크해 오탐(예: "명단은 17,5")을 막는다.
    /// 세미콜론 분리 인용도 지원(예: (1,11; 9,7) / (로마 1,1; 갈라 2,2)).
    static func addKoreanLinks(to attr: NSMutableAttributedString, currentBook: String?,
                               color: UIColor) {
        guard let kre = koreanRegex else { return }
        let s = attr.string as NSString
        let originalBook = currentBook  // preserve context book for unnamed references
        var processed: [NSRange] = []

        for m in kre.matches(in: attr.string,
                             range: NSRange(location: 0, length: s.length)) {
            var bookID: String?

            // 그룹 1: 책 이름 (선택적)
            if m.range(at: 1).location != NSNotFound {
                let bookName = s.substring(with: m.range(at: 1))
                if let id = koreanNames[bookName] {
                    bookID = id
                } else {
                    continue
                }
            } else {
                // 명시적 책 이름이 없으면 현재 책 사용 (세미콜론 분리는 addSemicolonSeparatedLinks에서 처리)
                bookID = originalBook
            }

            guard let bID = bookID,
                  let c = Int(s.substring(with: m.range(at: 2))),
                  let v = Int(s.substring(with: m.range(at: 3))) else { continue }
            let d1 = m.range(at: 4).location != NSNotFound
                ? Int(s.substring(with: m.range(at: 4))) : nil
            let d2 = m.range(at: 5).location != NSNotFound
                ? Int(s.substring(with: m.range(at: 5))) : nil
            let d2_dot = m.numberOfRanges > 6 && m.range(at: 6).location != NSNotFound
                ? Int(s.substring(with: m.range(at: 6))) : nil
            let d2_dot_range = m.numberOfRanges > 7 && m.range(at: 7).location != NSNotFound
                ? Int(s.substring(with: m.range(at: 7))) : nil
            let ec = d2 != nil ? (d1 ?? c) : c
            let ev = d2 ?? (d2_dot_range ?? d2_dot) ?? d1 ?? v
            if let url = URL(string:
                "catholicbible://xref?b=\(bID)&c=\(c)&v=\(v)&ec=\(ec)&ev=\(ev)") {
                attr.addAttributes([.link: url,
                                    .foregroundColor: color,
                                    .underlineStyle: NSUnderlineStyle.single.rawValue],
                                   range: m.range)
                processed.append(m.range)
            }
        }

        // 세미콜론 분리 인용 처리
        // 초기의 currentBook을 전달하여, 각 괄호 그룹이 독립적으로 처리되도록 함
        // 이렇게 하면 koreanRegex에서 처리한 명시적 참조(예: 시편 2,2)가
        // 이후 참조들의 책 컨텍스트에 영향을 주지 않음
        addSemicolonSeparatedLinks(to: attr, currentBook: currentBook, color: color, processed: processed)
    }

    /// 세미콜론으로 분리된 인용 처리: (1,11; 9,7), (로마 1,1; 갈라 2,2) 형식
    /// 괄호 안의 여러 인용을 각각 링크로 변환. 이미 처리된 부분은 건너뜀.
    private static func addSemicolonSeparatedLinks(to attr: NSMutableAttributedString, currentBook: String?,
                                                   color: UIColor, processed: [NSRange]) {
        let s = attr.string as NSString

        // 괄호 내 세미콜론 분리 인용을 찾는 패턴
        guard let semiPattern = try? NSRegularExpression(
            pattern: "\\([^)]*;[^)]*\\)") else { return }

        guard let versePattern = try? NSRegularExpression(
            pattern: "([가-힣]*)?\\s*(\\d{1,3})[,:]\\s?(\\d{1,3})(?:\\)?[–-](\\d{1,3}))?(?:\\)?\\.(\\d{1,3})(?:[–-](\\d{1,3}))?)?") else { return }

        for m in semiPattern.matches(in: attr.string, range: NSRange(location: 0, length: s.length)) {
            // 이미 처리된 범위인지 확인
            if processed.contains(where: { m.range.location >= $0.location && m.range.location < $0.location + $0.length }) {
                continue
            }

            let fullText = s.substring(with: m.range)
            let inner = String(fullText.dropFirst().dropLast()) // 괄호 제거
            let parts = inner.split(separator: ";").map { String($0).trimmingCharacters(in: .whitespaces) }

            var lastBook = currentBook
            let originalBook = currentBook  // preserve context book for unnamed references
            var searchStart = m.range.location + 1

            for part in parts {
                let partLen = (part as NSString).length
                let partRange = NSRange(location: 0, length: partLen)

                if let verseMatch = versePattern.firstMatch(in: part, range: partRange) {
                    var bookID: String?

                    // 책 이름 확인
                    if verseMatch.range(at: 1).location != NSNotFound {
                        let bookName = (part as NSString).substring(with: verseMatch.range(at: 1))
                        if let id = koreanNames[bookName] {
                            bookID = id
                            lastBook = id
                        }
                    } else {
                        bookID = lastBook ?? originalBook ?? "mk"
                    }

                    if let bID = bookID,
                       let c = Int((part as NSString).substring(with: verseMatch.range(at: 2))),
                       let v = Int((part as NSString).substring(with: verseMatch.range(at: 3))) {

                        let dashVerse = verseMatch.range(at: 4).location != NSNotFound
                            ? Int((part as NSString).substring(with: verseMatch.range(at: 4))) : nil
                        let dotVerse = verseMatch.numberOfRanges > 5 && verseMatch.range(at: 5).location != NSNotFound
                            ? Int((part as NSString).substring(with: verseMatch.range(at: 5))) : nil
                        let dotRangeVerse = verseMatch.numberOfRanges > 6 && verseMatch.range(at: 6).location != NSNotFound
                            ? Int((part as NSString).substring(with: verseMatch.range(at: 6))) : nil
                        let endVerse = dashVerse ?? (dotRangeVerse ?? dotVerse) ?? v

                        if let url = URL(string: "catholicbible://xref?b=\(bID)&c=\(c)&v=\(v)&ec=\(c)&ev=\(endVerse)") {
                            // 이 부분을 텍스트에서 찾아 링크 추가
                            let searchRange = NSRange(location: searchStart, length: s.length - searchStart)
                            let partNSRange = s.range(of: part, options: [], range: searchRange)
                            if partNSRange.location != NSNotFound {
                                attr.addAttributes([.link: url,
                                                  .foregroundColor: color,
                                                  .underlineStyle: NSUnderlineStyle.single.rawValue],
                                                 range: partNSRange)
                                searchStart = partNSRange.location + partNSRange.length
                            }
                        }
                    }
                }
            }
        }
    }
}

/// 주석·상호참조 본문 뷰 — 단어 선택(네이티브)과 성경 인용 링크 탭을 함께 지원.
/// SwiftUI Text(.textSelection)는 링크가 섞이면 선택이 막혀, UITextView 로 렌더한다.
struct SelectableNoteText: UIViewRepresentable {
    let text: String
    let currentBook: String?
    let chapter: Int  // 각주 마커 링크용
    let font: UIFont
    let color: UIColor
    let linkColor: UIColor
    let lineSpacing: CGFloat
    let searchQuery: String
    let onOpenURL: (URL) -> Void

    init(text: String, currentBook: String? = nil, chapter: Int = 0,
         font: UIFont, color: UIColor, linkColor: UIColor,
         lineSpacing: CGFloat, searchQuery: String = "",
         onOpenURL: @escaping (URL) -> Void) {
        self.text = text
        self.currentBook = currentBook
        self.chapter = chapter
        self.font = font
        self.color = color
        self.linkColor = linkColor
        self.lineSpacing = lineSpacing
        self.searchQuery = searchQuery
        self.onOpenURL = onOpenURL
    }

    func makeCoordinator() -> Coordinator { Coordinator(onOpenURL: onOpenURL) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.delegate = context.coordinator
        tv.setContentCompressionResistancePriority(.required, for: .vertical)
        tv.setContentHuggingPriority(.required, for: .vertical)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.onOpenURL = onOpenURL
        let para = NSMutableParagraphStyle()
        para.lineSpacing = lineSpacing
        let attr = NSMutableAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: para,
        ])
        ScriptureRef.addLinks(to: attr, currentBook: currentBook, color: linkColor)
        addMarkerLinks(to: attr, color: linkColor)  // 주석 마커 링크도 추가

        if !searchQuery.isEmpty {
            let pattern = NSRegularExpression.escapedPattern(for: searchQuery)
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let s = attr.string as NSString
                for match in regex.matches(in: attr.string, range: NSRange(location: 0, length: s.length)) {
                    attr.addAttribute(.backgroundColor,
                                    value: UIColor.yellow.withAlphaComponent(0.3),
                                    range: match.range)
                }
            }
        }

        tv.linkTextAttributes = [.foregroundColor: linkColor]
        tv.attributedText = attr
    }

    /// 각주 마커('N)')를 NSAttributedString에 링크로 추가
    private func addMarkerLinks(to attr: NSMutableAttributedString, color: UIColor) {
        guard let book = currentBook, chapter > 0 else { return }  // 책과 장 정보 필요
        let pattern = "(?<![-,.\\d(])(\\d{1,3})\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let s = attr.string as NSString
        for m in regex.matches(in: attr.string, range: NSRange(location: 0, length: s.length)) {
            if let n = m.range(at: 1).location != NSNotFound ? s.substring(with: m.range(at: 1)) : nil {
                if let url = URL(string: "catholicbible://note?b=\(book)&c=\(chapter)&n=\(n)") {
                    attr.addAttributes([.link: url, .foregroundColor: color,
                                       .underlineStyle: NSUnderlineStyle.single.rawValue],
                                      range: m.range)
                }
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView,
                      context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0, width.isFinite else { return nil }
        let fit = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fit.height))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onOpenURL: ((URL) -> Void)?
        init(onOpenURL: ((URL) -> Void)?) { self.onOpenURL = onOpenURL }

        func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem,
                      defaultAction: UIAction) -> UIAction? {
            if case .link(let url) = textItem.content {
                return UIAction { [onOpenURL] _ in onOpenURL?(url) }
            }
            return defaultAction
        }
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
    @Environment(KnbNotesStore.self) private var knb
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var parentOpenURL
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
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } } }
            .preferredColorScheme(settings.theme.colorScheme)
            // 중첩된 fullScreenCover 내에서 주석 표시 지연을 피하기 위해 fullScreenCover 사용
            .fullScreenCover(item: $noteTarget) { t in
                MarkerNoteSheet(n: "", text: t.text, bookID: t.ref.bookID, chapter: t.ref.chapter)
                    .environment(store)
                    .environment(settings)
                    .environment(annotations)
                    .environment(navigation)
                    .environment(knb)
            }
            .fullScreenCover(item: $dictRequest) { req in
                DictionaryView(initialTerm: req.term)
                    .environment(settings)
            }
            // NavigationStack 내부에서 openURL 환경 오버라이드
            // → NavigationStack 내의 VerseRowView가 올바른 openURL을 받음
            .environment(\.openURL, OpenURLAction { url in
                if url.scheme == "catholicbible", url.host == "note" {
                    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                    func q(_ k: String) -> String? { items.first { $0.name == k }?.value }
                    if let n = q("n"), let book, let text = knb.notes(edition: editionID, bookID: book.id, chapter: target.chapter)
                        .first(where: { $0.n == n })?.text {
                        noteTarget = RefNoteTarget(ref: VerseRef(bookID: book.id, chapter: target.chapter, verse: target.verse), text: text)
                    }
                    return .handled
                }
                parentOpenURL(url)
                return .handled
            })
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)   // 드래그로 위치·크기 변경
    }
}
