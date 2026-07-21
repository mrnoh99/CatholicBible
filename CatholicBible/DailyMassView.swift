//
//  DailyMassView.swift
//  CatholicBible
//
//  '오늘의 미사': 전례일 이름·전례색·독서 주기(가/나/다해)와 그 날 독서
//  (제1독서·화답송·제2독서·복음)를 보여 준다. 표시법은 형제 앱 GospelForIpad의
//  '오늘의 말씀'을 따른다(날짜 이동 + 전례일 이름 + 성구). 각 독서의 성구를
//  누르면 리더가 해당 본문을 연다. 본문 미리보기는 번들된 「성경」에서 가져온다.
//
//  '전례력' 달력은 한 달을 전례색으로 물들여 보여 주고, 날짜를 누르면 그 날
//  미사로 이동한다.
//

import SwiftUI
import UIKit

struct DailyMassView: View {
    @Environment(BibleStore.self) private var store
    @Environment(LiturgyStore.self) private var liturgy
    @Environment(ReaderSettings.self) private var settings
    @Environment(ReaderNavigation.self) private var navigation
    @Environment(\.dismiss) private var dismiss

    @State private var viewedDate: Date = LDate.today()
    @State private var showCalendar = false

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
            // 오늘의 미사를 다시 열면 이전 강조는 지운다(다음 독서를 고를 때까지 유지되던 것).
            .onAppear { navigation.activeHighlight = nil }
            .navigationTitle("오늘의 미사")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("전례력", systemImage: "calendar") { showCalendar = true }
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

            Text(liturgy.title(viewedDate))
                .font(settings.fontChoice.font(size: 24, relativeTo: .title2, bold: true))
                .foregroundStyle(settings.theme.text)
                .fixedSize(horizontal: false, vertical: true)

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
                ForEach(readings) { reading in
                    ReadingCard(reading: reading, openReading: open)
                        .environment(store)
                        .environment(settings)
                }
            }
        }
    }

    /// 성구를 리더로 연다(시트를 닫고 사이드바 선택을 옮긴다).
    private func open(_ reading: MassReading) {
        guard let c = reading.primaryCitation, Bible.book(c.bookID) != nil else { return }
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
    let openReading: (MassReading) -> Void

    @Environment(BibleStore.self) private var store
    @Environment(ReaderSettings.self) private var settings
    @State private var expanded = false

    var body: some View {
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

            // 소제목·성구·화답송·(펼치면) 본문을 한 덩어리로 묶어, 성구와 본문을
            // 함께 낱말 단위로 선택·복사할 수 있게 한다(아이패드 기본 선택 방식).
            let verses = reading.primaryCitation.map { previewVerses($0) } ?? []
            SelectableAttributedText(attributed:
                readingAttributed(reading, verses: verses, expanded: expanded))

            if !verses.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    Label(expanded ? "본문 접기" : "본문 보기",
                          systemImage: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.medium)).foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(settings.theme.text.opacity(0.04)))
    }

    /// 소제목·성구·화답송·(펼치면) 본문을 한 덩어리로 묶는다. 성구와 본문을 함께 선택·복사 가능.
    private func readingAttributed(_ reading: MassReading, verses: [Verse], expanded: Bool) -> NSAttributedString {
        let textColor = UIColor(settings.theme.text)
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
        if expanded && !verses.isEmpty {
            result.append(NSAttributedString(string: "\n\n"))
            let numFont = uiBodyFont(max(settings.fontSize * 0.7, 10))
            let bodyFont = uiBodyFont(settings.fontSize)
            for (i, v) in verses.enumerated() {
                if i > 0 { result.append(NSAttributedString(string: "\n")) }
                result.append(NSAttributedString(string: "\(v.number) ", attributes: [
                    .font: numFont, .foregroundColor: secondary, .paragraphStyle: para,
                ]))
                result.append(NSAttributedString(string: v.text, attributes: [
                    .font: bodyFont, .foregroundColor: textColor, .paragraphStyle: para,
                ]))
            }
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

    /// 「성경」(knb) 판본에서 인용 범위의 절을 가져온다(같은 장 안에서).
    private func previewVerses(_ c: ScriptureCitation) -> [Verse] {
        guard let edition = Editions.edition("knb"), let book = Bible.book(c.bookID) else { return [] }
        let verses = store.verses(edition: edition, book: book, chapter: c.chapter)
        guard !verses.isEmpty else { return [] }
        let endVerse = (c.endChapter != nil && c.endChapter != c.chapter)
            ? (verses.last?.number ?? c.verseEnd)   // 여러 장에 걸치면 이 장 끝까지
            : c.verseEnd
        return verses.filter { $0.number >= c.verseStart && $0.number <= max(endVerse, c.verseStart) }
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
