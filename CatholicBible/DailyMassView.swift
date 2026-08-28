//
//  DailyMassView.swift
//  CatholicBible
//
//  '매일미사': 전례일 이름·전례색·독서 주기(가/나/다해)와 그 날 독서
//  (제1독서·화답송·제2독서·복음)를 보여 준다. 표시법은 형제 앱 GospelForIpad의
//  '오늘의 말씀'을 따른다(날짜 이동 + 전례일 이름 + 성구). 각 독서의 성구를
//  누르면 리더가 해당 본문을 연다. 본문 미리보기는 번들된 「성경」에서 가져온다.
//
//  '전례력' 달력은 한 달을 전례색으로 물들여 보여 주고, 날짜를 누르면 그 날
//  미사로 이동한다.
//

import SwiftUI
import UIKit

/// 매일 미사 본문보기의 노트 편집 대상
private struct MassNoteTarget: Identifiable {
    let ref: VerseRef
    let text: String
    var id: String { ref.id }
}

struct DailyMassView: View {
    @Environment(BibleStore.self) private var store
    @Environment(LiturgyStore.self) private var liturgy
    @Environment(ReaderSettings.self) private var settings
    @Environment(ReaderNavigation.self) private var navigation
    @Environment(ReadingState.self) private var readingState
    @Environment(AnnotationStore.self) private var annotations
    @Environment(KnbNotesStore.self) private var knbNotes
    @Environment(\.dismiss) private var dismiss

    @State private var viewedDate: Date = LDate.today()
    @State private var showCalendar = false
    @State private var noteTarget: MassNoteTarget?
    @State private var dictRequest: DictionaryRequest?
    /// 주석 성경 본문에서 각주 마커('N)')를 탭했을 때 뜨는 주석 팝업
    @State private var markerNote: MarkerNoteTarget?
    /// 모든 독서의 본문 미리보기를 한꺼번에 펼치거나 닫는다(날짜·재실행에도 유지).
    @AppStorage("mass.showAllText") private var showAllText = false
    /// 본문보기에 쓸 성경 판본(화답송 제외, 기본: 주석 성경, 날짜·재실행에도 유지).
    @AppStorage("mass.previewEditionID") private var previewEditionID = "knbnotes"
    /// 화답송 전용 판본(기본: 전례 시편, 따로 선택·유지).
    @AppStorage("mass.psalmEditionID") private var psalmEditionID = "pslitur"

    /// 이 독서가 화답송인가(화답송은 전례 시편 등 별도 판본으로 본다).
    private func isPsalm(_ reading: MassReading) -> Bool { reading.role.contains("화답송") }
    /// 독서별 본문보기 판본(화답송이면 psalmEditionID, 그 외 previewEditionID).
    private func editionID(for reading: MassReading) -> String {
        isPsalm(reading) ? psalmEditionID : previewEditionID
    }
    /// 화답송 판본 후보: 시편을 담은 판본만(신약 전용 b200 제외).
    private var psalmEditions: [Edition] {
        Editions.all.filter { $0.scope != .newTestament }
    }

    private var isToday: Bool { viewedDate == LDate.today() }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.timeZone = LDate.calendar.timeZone
        f.dateFormat = "yyyy년 M월 d일 (E)"
        return f
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    readingsSection
                }
                .padding(20)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
                // '본문 열기' 같은 버튼(링크)은 탭이 우선이라 선택되지 않고,
                // 그 밖의 본문·제목·성구·화답송 등은 눌러서 복사할 수 있다.
                .textSelection(.enabled)
            }
            .background(settings.theme.background.ignoresSafeArea())
            // 매일미사를 다시 열면 이전 강조는 지운다(다음 독서를 고를 때까지 유지되던 것).
            .onAppear { navigation.activeHighlight = nil }
            .navigationTitle("매일미사")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { showCalendar = true }) {
                        Label("전례력", systemImage: "calendar")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
            .sheet(isPresented: $showCalendar) {
                LiturgicalMonthView(selected: $viewedDate)
                    .environment(liturgy)
                    .environment(settings)
            }
            .sheet(item: $noteTarget) { target in
                NoteEditorView(verse: target.ref, verseText: target.text,
                               existing: annotations.noteOrNew(for: target.ref))
                    .environment(annotations)   // Mac Catalyst: 모달 환경 재주입
            }
            .sheet(item: $dictRequest) { req in
                DictionaryView(initialTerm: req.term)
            }
            // 주석 성경 본문의 각주 마커 'N)' 탭 → 해당 주석 팝업
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "catholicbible", url.host == "note" else { return .systemAction }
                let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                func q(_ k: String) -> String? { items.first { $0.name == k }?.value }
                if let b = q("b"), let cs = q("c"), let c = Int(cs), let n = q("n") {
                    let note = knbNotes.notes(edition: previewEditionID,
                                              bookID: b, chapter: c).first { $0.n == n }
                    markerNote = MarkerNoteTarget(n: n, text: note?.text ?? "이 주석을 찾지 못했습니다.", bookID: b, chapter: c)
                }
                return .handled
            })
            .fullScreenCover(item: $markerNote) { mn in
                MarkerNoteSheet(n: mn.n, text: mn.text, bookID: mn.bookID, chapter: mn.chapter).environment(settings)
            }
        }
    }

    // MARK: - 머리말 (날짜·전례일·전례색·주기)

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(Self.dateFormatter.string(from: viewedDate))
                    .font(.subheadline)
                    .foregroundStyle(settings.theme.secondary)
                Spacer(minLength: 0)
                navButton("chevron.left", "이전 날") { viewedDate = LDate.addDays(viewedDate, -1) }
                Button { viewedDate = LDate.today() } label: {
                    Text("오늘").font(.subheadline.weight(.semibold))
                        .foregroundStyle(isToday ? settings.theme.secondary.opacity(0.5) : Color.accentColor)
                }
                .buttonStyle(.plain).disabled(isToday)
                navButton("chevron.right", "다음 날") { viewedDate = LDate.addDays(viewedDate, 1) }
            }

            // 제목도 다른 본문과 같이 낱말 선택·복사가 되도록 UITextView로 렌더한다.
            SelectableAttributedText(attributed: titleAttributed(liturgy.title(viewedDate)))

            HStack(spacing: 8) {
                colorBadge(liturgy.color(viewedDate))
                Text(LiturgicalCalendar.liturgicalPosition(viewedDate).season.shortName)
                    .font(.caption).foregroundStyle(settings.theme.secondary)
                Text("·").foregroundStyle(settings.theme.secondary)
                Text(LiturgicalCalendar.cycleLabel(viewedDate))
                    .font(.caption.weight(.medium)).foregroundStyle(settings.theme.secondary)
            }
        }
        .padding(.bottom, 4)
    }

    /// 전례일 제목을 선택·복사 가능한 굵은 큰 글씨로.
    private func titleAttributed(_ title: String) -> NSAttributedString {
        let size = max(settings.fontSize * 1.35, 22)
        let font: UIFont
        switch settings.fontChoice {
        case .myeongjo: font = UIFont(name: "NanumMyeongjoBold", size: size) ?? .systemFont(ofSize: size, weight: .bold)
        case .gothic:   font = .systemFont(ofSize: size, weight: .bold)
        }
        let para = NSMutableParagraphStyle()
        para.lineSpacing = settings.lineSpacing * 0.5
        return NSAttributedString(string: title, attributes: [
            .font: font, .foregroundColor: UIColor(settings.theme.headingText), .paragraphStyle: para,
        ])
    }

    private func colorBadge(_ c: LiturgicalColor) -> some View {
        HStack(spacing: 5) {
            Circle().fill(c.color).frame(width: 12, height: 12)
                .overlay(Circle().stroke(settings.theme.secondary.opacity(0.35), lineWidth: 0.5))
            Text(c.label).font(.caption.weight(.medium)).foregroundStyle(settings.theme.text)
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(Capsule().fill(c.color.opacity(0.14)))
    }

    private func navButton(_ systemName: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName).font(.body.weight(.semibold))
                .foregroundStyle(settings.theme.secondary)
                .frame(width: 34, height: 30).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel(label)
    }

    // MARK: - 독서

    private var readingsSection: some View {
        let readings = liturgy.readings(viewedDate)
        return VStack(alignment: .leading, spacing: 14) {
            if readings.isEmpty {
                Text("이 날의 독서 자료가 없습니다.")
                    .font(.callout).foregroundStyle(settings.theme.secondary)
            } else {
                if !liturgy.hasFullReadings(viewedDate) {
                    Label("전체 독서는 준비 중입니다. 지금은 전례력으로 계산한 복음만 표시합니다.",
                          systemImage: "info.circle")
                        .font(.caption).foregroundStyle(settings.theme.secondary)
                        .padding(.bottom, 2)
                } else if liturgy.isReconstructed(viewedDate) {
                    Label("같은 전례 주기의 다른 해 독서로 표시합니다.",
                          systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption).foregroundStyle(settings.theme.secondary)
                        .padding(.bottom, 2)
                }
                // 본문 모두 펼치기/닫기 + 본문보기 판본 선택
                HStack(spacing: 12) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showAllText.toggle() }
                    } label: {
                        Label(showAllText ? "본문 모두 닫기" : "본문 모두 보기",
                              systemImage: showAllText ? "chevron.up" : "chevron.down")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                    Menu {
                        Picker("본문 판본 (화답송 제외)", selection: $previewEditionID) {
                            ForEach(Editions.all) { ed in Text(ed.name).tag(ed.id) }
                        }
                        Picker("화답송 판본", selection: $psalmEditionID) {
                            ForEach(psalmEditions) { ed in Text(ed.name).tag(ed.id) }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "book.closed")
                            Text(Editions.edition(previewEditionID)?.shortName ?? "성경")
                            Image(systemName: "chevron.down").font(.caption2)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(.bottom, 2)

                ForEach(readings) { reading in
                    ReadingCard(reading: reading, expanded: showAllText,
                                editionID: editionID(for: reading), openReading: open,
                                onOpenNote: { ref, text in noteTarget = MassNoteTarget(ref: ref, text: text) },
                                onLookUp: { dictRequest = DictionaryRequest() })
                        .environment(store)
                        .environment(settings)
                }
            }
        }
    }

    /// 성구를 리더로 연다(시트를 닫고 사이드바 선택을 옮긴다).
    private func open(_ reading: MassReading) {
        guard let c = reading.primaryCitation, Bible.book(c.bookID) != nil else { return }
        // 매일미사에서 고른 본문 판본으로 리더를 연다(사이드바 판본이 아니라).
        // 화답송은 화답송 전용 판본(전례 시편 등)으로 연다.
        readingState.selectedEditionID = editionID(for: reading)
        // 참조 문자열에서 불연속 구간까지 살린 강조를 만든다(빠진 절은 칠하지 않음).
        if let parsed = ScriptureReference.highlight(reading.reference), parsed.bookID == c.bookID {
            navigation.open(bookID: c.bookID, chapter: parsed.highlight.startChapter,
                            highlight: parsed.highlight)
        } else {
            let end = c.verseEnd > 0 ? c.verseEnd : c.verseStart
            navigation.open(bookID: c.bookID, chapter: c.chapter, verse: c.verseStart,
                            verseEnd: end, endChapter: c.endChapter)
        }
        dismiss()
    }
}

// MARK: - 독서 한 장 카드

private struct ReadingCard: View {
    let reading: MassReading
    /// 상위에서 내려주는 '본문 모두 보기' 상태
    let expanded: Bool
    /// 본문보기에 쓸 성경 판본
    let editionID: String
    let openReading: (MassReading) -> Void
    /// 절의 노트 추가·편집 요청
    let onOpenNote: (VerseRef, String) -> Void
    /// 사전 열기 요청(매일미사 화면이 직접 사전을 띄운다)
    let onLookUp: () -> Void

    @Environment(BibleStore.self) private var store
    @Environment(ReaderSettings.self) private var settings

    @State private var cachedItems: [(chapter: Int, verse: Verse)]?
    @State private var cacheKey: String?

    private var edition: Edition { Editions.edition(editionID) ?? Editions.edition("knb") ?? Editions.all[0] }

    private var previewItemsCached: [(chapter: Int, verse: Verse)] {
        let key = "\(reading.reference):\(editionID)"
        if cacheKey == key && cachedItems != nil { return cachedItems! }
        let items = previewItems(reading)
        cacheKey = key
        cachedItems = items
        return items
    }

    var body: some View {
        let book = previewBook(reading)
        let items = expanded ? previewItemsCached(reading) : []
        let multiChapter = Set(items.map { $0.chapter }).count > 1
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(reading.role)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                Spacer(minLength: 6)
                if reading.primaryCitation != nil {
                    Button {
                        openReading(reading)
                    } label: {
                        Label("본문 열기", systemImage: "book")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain).foregroundStyle(Color.accentColor)
                }
            }

            // 소제목·성구·화답송은 낱말 선택·복사 가능한 머리글로.
            SelectableAttributedText(attributed: headerAttributed(reading))

            // 본문: 절마다 번호를 눌러 책갈피·노트·복사할 수 있게 리더와 같은 절 행으로.
            if expanded, let book {
                VStack(alignment: .leading, spacing: settings.lineSpacing * 0.7) {
                    ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                        if multiChapter && (idx == 0 || items[idx - 1].chapter != item.chapter) {
                            Text(book.chapterLabel(item.chapter))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(settings.theme.secondary)
                                .padding(.top, idx == 0 ? 2 : 8)
                        }
                        VerseRowView(edition: edition, book: book, chapter: item.chapter,
                                     verse: item.verse, highlighted: false,
                                     onOpenNote: onOpenNote, onLookUp: onLookUp)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(settings.theme.text.opacity(0.04)))
    }

    /// 참조가 가리키는 책.
    private func previewBook(_ reading: MassReading) -> BibleBook? {
        if let p = ScriptureReference.segmentList(reading.reference) { return Bible.book(p.bookID) }
        return reading.primaryCitation.flatMap { Bible.book($0.bookID) }
    }

    /// 소제목·성구·화답송을 낱말 선택·복사 가능한 머리글로 묶는다.
    private func headerAttributed(_ reading: MassReading) -> NSAttributedString {
        let textColor = UIColor(settings.theme.headingText)
        let secondary = UIColor(settings.theme.secondary)
        let para = NSMutableParagraphStyle()
        para.lineSpacing = settings.lineSpacing
        para.paragraphSpacing = settings.lineSpacing * 0.6
        let result = NSMutableAttributedString()
        func append(_ s: String, font: UIFont, color: UIColor) {
            result.append(NSAttributedString(string: s, attributes: [
                .font: font, .foregroundColor: color, .paragraphStyle: para,
            ]))
        }
        if let sub = reading.subtitle, !sub.isEmpty {
            append("〈\(sub)〉\n", font: uiBodyFont(max(settings.fontSize * 0.82, 12)), color: secondary)
        }
        append(reading.reference, font: uiBodyFont(max(settings.fontSize, 17), bold: true), color: textColor)
        if let refrain = reading.refrain, !refrain.isEmpty {
            append("\n◎ \(refrain)", font: uiBodyFont(max(settings.fontSize * 0.92, 13)), color: secondary)
        }
        return result
    }

    private func uiBodyFont(_ size: CGFloat, bold: Bool = false) -> UIFont {
        switch settings.fontChoice {
        case .myeongjo:
            let name = bold ? "NanumMyeongjoBold" : "NanumMyeongjo"
            return UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: bold ? .bold : .regular)
        case .gothic:
            return .systemFont(ofSize: size, weight: bold ? .bold : .regular)
        }
    }

    /// 「성경」(knb)에서 참조에 해당하는 절만 골라 (장, 절) 목록으로 돌려준다.
    /// 참조 문자열을 구간으로 풀어(불연속·여러 장·여러 인용 지원) 그 구간의 절만 담는다.
    /// 성능 최적화: 절 숫자 파싱과 필터링을 한 번에 수행
    private func previewItems(_ reading: MassReading) -> [(chapter: Int, verse: Verse)] {
        guard let edition = Editions.edition(editionID) ?? Editions.edition("knb") else { return [] }
        // 참조 문자열 파싱 우선, 실패하면 citation의 단순 범위로 대체.
        let bookID: String
        var segs: [ScriptureReference.RefSegment] = []
        if let parsed = ScriptureReference.segmentList(reading.reference) {
            bookID = parsed.bookID; segs = parsed.segments
        } else if let c = reading.primaryCitation {
            bookID = c.bookID
            segs = [.init(chapter: c.chapter, low: c.verseStart, high: max(c.verseEnd, c.verseStart))]
        } else { return [] }
        guard let book = Bible.book(bookID) else { return [] }
        var out: [(Int, Verse)] = []
        var seen = Set<String>()
        for seg in segs {
            let versesInChapter = store.verses(edition: edition, book: book, chapter: seg.chapter)
            for v in versesInChapter {
                let verseNum: Int
                if let n = Int(v.number) {
                    verseNum = n
                } else if let first = v.number.split(separator: "(").first, let n = Int(first) {
                    verseNum = n
                } else {
                    continue
                }
                if verseNum >= seg.low && verseNum <= seg.high {
                    let key = "\(seg.chapter):\(v.number)"
                    if seen.insert(key).inserted { out.append((seg.chapter, v)) }
                }
            }
        }
        return out
    }
}

// MARK: - 전례력 달력 (한 달)

struct LiturgicalMonthView: View {
    @Binding var selected: Date
    @Environment(LiturgyStore.self) private var liturgy
    @Environment(ReaderSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var monthAnchor: Date = LDate.today()

    private let weekdaySymbols = ["일", "월", "화", "수", "목", "금", "토"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                monthHeader
                weekdayRow
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(Array(monthCells.enumerated()), id: \.offset) { _, cell in
                        if let date = cell {
                            dayCell(date)
                        } else {
                            Color.clear.frame(height: 44)
                        }
                    }
                }
                legend
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(settings.theme.background.ignoresSafeArea())
            .navigationTitle("전례력")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } } }
        }
    }

    private var monthHeader: some View {
        HStack {
            Button { monthAnchor = LDate.calendar.date(byAdding: .month, value: -1, to: monthAnchor) ?? monthAnchor } label: {
                Image(systemName: "chevron.left").font(.body.weight(.semibold))
            }
            Spacer()
            Text("\(LDate.year(monthAnchor))년 \(LDate.month(monthAnchor))월")
                .font(.headline).foregroundStyle(settings.theme.text)
            Spacer()
            Button { monthAnchor = LDate.calendar.date(byAdding: .month, value: 1, to: monthAnchor) ?? monthAnchor } label: {
                Image(systemName: "chevron.right").font(.body.weight(.semibold))
            }
        }
        .tint(Color.accentColor)
    }

    private var weekdayRow: some View {
        HStack(spacing: 4) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { i, s in
                Text(s).font(.caption2.weight(.semibold))
                    .foregroundStyle(i == 0 ? Color.red.opacity(0.8) : settings.theme.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let isSelected = date == selected
        let isToday = date == LDate.today()
        let color = liturgy.color(date)
        return Button {
            selected = date
            dismiss()
        } label: {
            VStack(spacing: 3) {
                Text("\(LDate.day(date))")
                    .font(.callout.weight(isToday ? .bold : .regular))
                    .foregroundStyle(settings.theme.text)
                Circle().fill(color.color).frame(width: 7, height: 7)
            }
            .frame(maxWidth: .infinity).frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isToday ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var legend: some View {
        let items: [LiturgicalColor] = [.green, .violet, .white, .red, .rose]
        return HStack(spacing: 10) {
            ForEach(items, id: \.rawValue) { c in
                HStack(spacing: 3) {
                    Circle().fill(c.color).frame(width: 8, height: 8)
                    Text(c.label).font(.caption2).foregroundStyle(settings.theme.secondary)
                }
            }
        }
        .padding(.top, 6)
    }

    /// 달력 셀(앞뒤 빈칸 포함). 일요일 시작.
    private var monthCells: [Date?] {
        let year = LDate.year(monthAnchor), month = LDate.month(monthAnchor)
        let first = LDate.make(year, month, 1)
        let leading = LDate.calendar.component(.weekday, from: first) - 1  // 일=0
        let range = LDate.calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for d in 1...range { cells.append(LDate.make(year, month, d)) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }
}

// MARK: - 선택·복사 가능한 본문 (UIKit)

/// 낱말을 눌러 선택하고 복사할 수 있는 본문 뷰(아이패드 기본 선택 방식).
/// 스크롤은 바깥 ScrollView가 맡으므로 자체 스크롤은 끈다.
struct SelectableAttributedText: UIViewRepresentable {
    let attributed: NSAttributedString

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.setContentCompressionResistancePriority(.required, for: .vertical)
        tv.setContentHuggingPriority(.required, for: .vertical)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        tv.attributedText = attributed
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0, width.isFinite else { return nil }
        let fit = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fit.height))
    }
}
