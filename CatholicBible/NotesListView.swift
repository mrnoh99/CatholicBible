//
//  NotesListView.swift
//  CatholicBible
//
//  저장된 노트 목록. 한 개를 선택하면 편집 화면(NoteEditorView)이 열린다.
//  노트는 판본 공통이라, 미리보기 본문은 현재 선택된 판본(없으면 성경)에서 가져온다.
//

import SwiftUI
import UniformTypeIdentifiers

/// 노트·책갈피·미디어를 한 파일로 담는 백업 문서(JSON)
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct NotesListView: View {
    @Environment(AnnotationStore.self) private var annotations
    @Environment(BibleStore.self) private var store
    @Environment(ReadingState.self) private var readingState
    @Environment(ReaderNavigation.self) private var navigation
    @Environment(\.dismiss) private var dismiss

    @State private var editing: Note?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var backupDoc = BackupDocument(data: Data())
    @State private var resultMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if annotations.notes.isEmpty {
                    ContentUnavailableView(
                        "노트 없음",
                        systemImage: "note.text",
                        description: Text("리더에서 절을 길게 눌러 ‘노트’를 선택하면 이 절에 대한 메모·사진·손글씨·오디오·비디오를 남길 수 있습니다.")
                    )
                } else {
                    List {
                        ForEach(annotations.notesByRecency) { note in
                            Button { editing = note } label: { row(note) }
                                .buttonStyle(.plain)
                        }
                        .onDelete(perform: delete)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("노트")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("파일로 내보내기(백업)", systemImage: "square.and.arrow.up") {
                            backupDoc = BackupDocument(data: annotations.exportBackup() ?? Data())
                            showExporter = true
                        }
                        Button("파일에서 가져오기(복원)", systemImage: "square.and.arrow.down") {
                            showImporter = true
                        }
                    } label: {
                        Label("백업", systemImage: "externaldrive")
                    }
                }
            }
            .sheet(item: $editing) { note in
                NoteEditorView(verse: note.verse,
                               verseText: previewText(note.verse),
                               existing: note)
                    .environment(annotations)   // Mac Catalyst: 모달 환경 전파 대비
            }
            .fileExporter(isPresented: $showExporter, document: backupDoc,
                          contentType: .json,
                          defaultFilename: "가톨릭성경-노트백업") { result in
                if case .failure(let err) = result {
                    resultMessage = "내보내기 실패: \(err.localizedDescription)"
                } else {
                    resultMessage = "백업 파일을 저장했습니다."
                }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.json]) { result in
                handleImport(result)
            }
            .alert("백업", isPresented: Binding(get: { resultMessage != nil },
                                              set: { if !$0 { resultMessage = nil } })) {
                Button("확인", role: .cancel) { resultMessage = nil }
            } message: {
                Text(resultMessage ?? "")
            }
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let err):
            resultMessage = "가져오기 실패: \(err.localizedDescription)"
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                resultMessage = "파일을 읽지 못했습니다."; return
            }
            if let (n, b) = annotations.importBackup(data) {
                resultMessage = "복원 완료: 노트 \(n)개, 책갈피 \(b)개 추가."
            } else {
                resultMessage = "백업 파일 형식이 아닙니다."
            }
        }
    }

    private func row(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(note.verse.reference)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Text(note.modified, style: .date)
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            if !note.text.isEmpty {
                Text(note.text).font(.callout).foregroundStyle(.primary).lineLimit(2)
            }
            // 첨부 종류 배지
            let kinds: [AttachmentKind] = [.photo, .drawing, .audio, .video]
            let present = kinds.filter { !note.attachments(of: $0).isEmpty }
            if !present.isEmpty {
                HStack(spacing: 12) {
                    ForEach(present, id: \.self) { kind in
                        Label("\(note.attachments(of: kind).count)", systemImage: kind.systemImage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func previewText(_ ref: VerseRef) -> String? {
        guard let book = Bible.book(ref.bookID) else { return nil }
        let edition = readingState.selectedEdition
        let verses = store.verses(edition: edition, book: book, chapter: ref.chapter)
        if let v = verses.first(where: { $0.number == ref.verse }) { return v.text }
        // 현재 판본에 없으면 성경(knb)에서
        if let knb = Editions.edition("knb") {
            return store.verses(edition: knb, book: book, chapter: ref.chapter)
                .first { $0.number == ref.verse }?.text
        }
        return nil
    }

    private func delete(at offsets: IndexSet) {
        let list = annotations.notesByRecency
        for i in offsets { annotations.delete(list[i]) }
    }
}
