//
//  NoteEditorView.swift
//  CatholicBible
//
//  한 절의 노트를 한 화면에서 읽고 작성한다.
//  텍스트 + 사진 + 손글씨 + 오디오 + 비디오를 모두 여기서 보고 듣고 추가한다.
//

import SwiftUI
import PhotosUI
import AVKit
import PencilKit
import UniformTypeIdentifiers

struct NoteEditorView: View {
    let verse: VerseRef
    /// 참고용으로 함께 보여줄 현재 판본의 절 본문(있으면)
    var verseText: String?

    @Environment(AnnotationStore.self) private var annotations
    @Environment(\.dismiss) private var dismiss

    @State private var note: Note
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var videoItem: PhotosPickerItem?
    @State private var showCameraPhoto = false
    @State private var showCameraVideo = false
    @State private var showDrawing = false
    @State private var recorder = AudioRecorder()
    @State private var showDeleteConfirm = false

    init(verse: VerseRef, verseText: String? = nil, existing: Note) {
        self.verse = verse
        self.verseText = verseText
        _note = State(initialValue: existing)
    }

    var body: some View {
        NavigationStack {
            Form {
                // 절 정보 + 참고 본문
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verse.longReference)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                        if let verseText {
                            Text(verseText)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // 텍스트 노트
                Section("메모") {
                    TextField("이 절에 대한 메모…", text: $note.text, axis: .vertical)
                        .lineLimit(3...12)
                }

                // 오디오
                if !note.attachments(of: .audio).isEmpty || recorder.isRecording {
                    Section("오디오") {
                        ForEach(note.attachments(of: .audio)) { att in
                            AudioAttachmentRow(url: annotations.url(for: att)) {
                                removeAttachment(att)
                            }
                        }
                    }
                }

                // 손글씨 · 사진
                let images = note.attachments.filter { $0.kind == .photo || $0.kind == .drawing }
                if !images.isEmpty {
                    Section("사진 · 손글씨") {
                        ImageAttachmentGrid(attachments: images,
                                            url: { annotations.url(for: $0) },
                                            onDelete: removeAttachment)
                    }
                }

                // 비디오
                if !note.attachments(of: .video).isEmpty {
                    Section("비디오") {
                        ForEach(note.attachments(of: .video)) { att in
                            VideoAttachmentRow(url: annotations.url(for: att)) {
                                removeAttachment(att)
                            }
                        }
                    }
                }

                // 추가 도구
                Section("추가") {
                    recordButton
                    Button { showDrawing = true } label: {
                        Label("손글씨", systemImage: "pencil.tip.crop.circle")
                    }
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 6, matching: .images) {
                        Label("사진 보관함", systemImage: "photo.on.rectangle")
                    }
                    Button { showCameraPhoto = true } label: {
                        Label("사진 촬영", systemImage: "camera")
                    }
                    PhotosPicker(selection: $videoItem, matching: .videos) {
                        Label("비디오 보관함", systemImage: "film")
                    }
                    Button { showCameraVideo = true } label: {
                        Label("비디오 촬영", systemImage: "video.badge.plus")
                    }
                }

                if !note.isEmpty {
                    Section {
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Label("노트 삭제", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("노트")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { save(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { save(); dismiss() }.fontWeight(.semibold)
                }
            }
            // 사진 보관함 선택 처리
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await importPhotos(items); photoItems = [] }
            }
            .onChange(of: videoItem) { _, item in
                guard let item else { return }
                Task { await importVideo(item); videoItem = nil }
            }
            .fullScreenCover(isPresented: $showCameraPhoto) {
                CameraPicker(mode: .photo) { url in add(kind: .photo, from: url) }
                    .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $showCameraVideo) {
                CameraPicker(mode: .video) { url in add(kind: .video, from: url) }
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showDrawing) {
                DrawingEditor { data in
                    let att = annotations.addAttachment(kind: .drawing, data: data, ext: "png")
                    note.attachments.append(att)
                    save()
                }
            }
            .confirmationDialog("이 노트를 삭제할까요?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("삭제", role: .destructive) {
                    annotations.delete(note)
                    dismiss()
                }
            }
            .onDisappear { save() }
        }
    }

    @ViewBuilder
    private var recordButton: some View {
        if recorder.isRecording {
            Button(role: .destructive) { recorder.stop() } label: {
                Label("녹음 중지 (\(timeString(recorder.elapsed)))", systemImage: "stop.circle.fill")
            }
        } else {
            Button {
                recorder.onFinish = { url in add(kind: .audio, from: url) }
                recorder.requestPermissionAndStart()
            } label: {
                Label("오디오 녹음", systemImage: "mic.circle")
            }
        }
    }

    // MARK: - 첨부 추가/삭제

    private func add(kind: AttachmentKind, from url: URL) {
        if let att = annotations.addAttachment(kind: kind, copyingFrom: url) {
            note.attachments.append(att)
            save()
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                let att = annotations.addAttachment(kind: .photo, data: data, ext: "jpg")
                note.attachments.append(att)
            }
        }
        save()
    }

    private func importVideo(_ item: PhotosPickerItem) async {
        if let movie = try? await item.loadTransferable(type: VideoTransfer.self) {
            add(kind: .video, from: movie.url)
        }
    }

    private func removeAttachment(_ att: Attachment) {
        note = annotations.removingAttachment(att, from: note)
        save()
    }

    private func save() {
        note.verse = verse
        annotations.save(note)
    }

    private func timeString(_ t: TimeInterval) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

// MARK: - PhotosPicker 비디오 전송용

struct VideoTransfer: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            // 임시 폴더로 복사해 안전한 URL 확보
            let dst = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).mov")
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.copyItem(at: received.file, to: dst)
            return VideoTransfer(url: dst)
        }
    }
}

// MARK: - 첨부 표시 행들

struct AudioAttachmentRow: View {
    let url: URL
    let onDelete: () -> Void
    @State private var player = AudioPlayerBox()

    var body: some View {
        HStack(spacing: 12) {
            Button { player.toggle(url: url) } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            ProgressView(value: player.progress)
            Image(systemName: "waveform").foregroundStyle(.secondary)
        }
        .swipeActions {
            Button("삭제", role: .destructive, action: onDelete)
        }
    }
}

struct VideoAttachmentRow: View {
    let url: URL
    let onDelete: () -> Void

    var body: some View {
        VideoPlayer(player: AVPlayer(url: url))
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .listRowInsets(EdgeInsets())
            .swipeActions {
                Button("삭제", role: .destructive, action: onDelete)
            }
    }
}

struct ImageAttachmentGrid: View {
    let attachments: [Attachment]
    let url: (Attachment) -> URL
    let onDelete: (Attachment) -> Void

    @State private var zoomed: Attachment?
    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(attachments) { att in
                if let img = UIImage(contentsOfFile: url(att).path) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(alignment: .topLeading) {
                            Image(systemName: att.kind.systemImage)
                                .font(.caption2)
                                .padding(4)
                                .background(.ultraThinMaterial, in: Circle())
                                .padding(3)
                        }
                        .onTapGesture { zoomed = att }
                        .contextMenu {
                            Button("삭제", systemImage: "trash", role: .destructive) { onDelete(att) }
                        }
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
        .sheet(item: $zoomed) { att in
            ZoomImageView(url: url(att))
        }
    }
}

struct ZoomImageView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                if let img = UIImage(contentsOfFile: url.path) {
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: img).resizable().scaledToFit()
                    }
                } else {
                    ContentUnavailableView("이미지를 열 수 없음", systemImage: "photo")
                }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
        }
    }
}

// MARK: - 손글씨 편집기

struct DrawingEditor: View {
    let onSave: (Data) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var canvas = PKCanvasView()

    var body: some View {
        NavigationStack {
            DrawingCanvas(canvasView: $canvas)
                .background(Color.white)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("손글씨")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("취소") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("저장") {
                            if let data = canvas.exportPNG() { onSave(data) }
                            dismiss()
                        }.fontWeight(.semibold)
                    }
                }
        }
    }
}
