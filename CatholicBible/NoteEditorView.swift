//
//  NoteEditorView.swift
//  CatholicBible
//
//  한 절의 노트를 한 화면에서 읽고 작성한다.
//  텍스트 + 사진 + 손글씨 + 오디오 + 비디오를 모두 여기서 보고 듣고 추가한다.
//

import SwiftUI
import UIKit
import PhotosUI
import AVKit
import PencilKit
import UniformTypeIdentifiers

/// 전체 화면으로 띄우는 대상(하나의 fullScreenCover로 통합)
private enum NoteCover: Identifiable {
    case cameraPhoto
    case cameraVideo
    case drawNew
    case drawEdit(Attachment)
    case zoom(ZoomPhoto)

    var id: String {
        switch self {
        case .cameraPhoto: return "camPhoto"
        case .cameraVideo: return "camVideo"
        case .drawNew:     return "drawNew"
        case .drawEdit(let a): return "edit-\(a.id)"
        case .zoom(let z):     return "zoom-\(z.id)"
        }
    }
}

struct NoteEditorView: View {
    let verse: VerseRef
    /// 참고용으로 함께 보여줄 현재 판본의 절 본문(있으면)
    var verseText: String?

    @Environment(AnnotationStore.self) private var annotations
    @Environment(\.dismiss) private var dismiss

    @State private var note: Note
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var videoItem: PhotosPickerItem?
    @State private var cover: NoteCover?
    @State private var drawingRefresh = 0
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
                        ImageAttachmentGrid(
                            attachments: images,
                            image: displayImage,
                            onDelete: removeAttachment,
                            onTapPhoto: { _, img in cover = .zoom(ZoomPhoto(image: img)) },
                            onEditDrawing: { cover = .drawEdit($0) },
                            refresh: drawingRefresh
                        )
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
                    Button { cover = .drawNew } label: {
                        Label("손글씨", systemImage: "pencil.tip.crop.circle")
                    }
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 6, matching: .images) {
                        Label("사진 보관함", systemImage: "photo.on.rectangle")
                    }
                    Button { cover = .cameraPhoto } label: {
                        Label("사진 촬영", systemImage: "camera")
                    }
                    PhotosPicker(selection: $videoItem, matching: .videos) {
                        Label("비디오 보관함", systemImage: "film")
                    }
                    Button { cover = .cameraVideo } label: {
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
            // 카메라·손글씨·사진 확대를 하나의 전체 화면 커버로 통합
            .fullScreenCover(item: $cover) { which in
                switch which {
                case .cameraPhoto:
                    CameraPicker(mode: .photo) { url in add(kind: .photo, from: url) }
                        .ignoresSafeArea()
                case .cameraVideo:
                    CameraPicker(mode: .video) { url in add(kind: .video, from: url) }
                        .ignoresSafeArea()
                case .drawNew:
                    DrawingEditor { data in
                        let att = annotations.addAttachment(kind: .drawing, data: data, ext: "drawing")
                        note.attachments.append(att)
                        save()
                    }
                case .drawEdit(let att):
                    DrawingEditor(existingData: annotations.data(for: att)) { data in
                        annotations.overwrite(att, with: data)
                        drawingRefresh += 1   // 갱신된 손글씨 다시 그리기
                        save()
                    }
                case .zoom(let z):
                    ZoomImageView(image: z.image)
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

    /// 첨부를 표시용 이미지로: 사진은 파일에서, 손글씨는 벡터에서 렌더링.
    private func displayImage(_ att: Attachment) -> UIImage? {
        switch att.kind {
        case .drawing:
            guard let data = annotations.data(for: att) else { return nil }
            return drawingUIImage(from: data)
        default:
            return UIImage(contentsOfFile: annotations.url(for: att).path)
        }
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
    /// 첨부를 표시용 이미지로 변환(사진은 파일, 손글씨는 렌더링)
    let image: (Attachment) -> UIImage?
    let onDelete: (Attachment) -> Void
    let onTapPhoto: (Attachment, UIImage) -> Void
    let onEditDrawing: (Attachment) -> Void
    /// 손글씨를 덮어써 갱신됐을 때 다시 그리도록 하는 값
    var refresh: Int = 0

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(attachments) { att in
                let img = image(att)
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let img {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: att.kind.systemImage)
                                .font(.title)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(height: 104)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .bottomLeading) {
                        Label(att.kind.label, systemImage: att.kind.systemImage)
                            .labelStyle(.iconOnly)
                            .font(.caption2)
                            .padding(4)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(4)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                    .onTapGesture {
                        if att.kind == .drawing { onEditDrawing(att) }
                        else if let img { onTapPhoto(att, img) }
                    }

                    // 삭제 버튼 (노트 화면에서 바로 삭제)
                    Button { onDelete(att) } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.55))
                    }
                    .padding(4)
                    .accessibilityLabel("\(att.kind.label) 삭제")
                }
            }
        }
        .id(refresh)
        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
    }
}

// 사진 확대 보기용 (창 크기에 맞춰 표시 + 핀치 확대)
struct ZoomPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct ZoomImageView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()                     // 열린 창 크기에 맞춤
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(scale)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { v in scale = min(max(lastScale * v, 1), 5) }
                            .onEnded { _ in lastScale = scale }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation { scale = scale > 1 ? 1 : 2.5; lastScale = scale }
                    }
            }
            .background(Color.black.opacity(0.92).ignoresSafeArea())
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }.tint(.white)
                }
            }
        }
    }
}

// MARK: - 손글씨 편집기 (새로 쓰거나 기존 손글씨 이어 쓰기)

struct DrawingEditor: View {
    /// 편집할 기존 손글씨(PKDrawing) 데이터. nil이면 새로 그린다.
    var existingData: Data? = nil
    /// 저장 시 PKDrawing(벡터) 데이터를 돌려준다.
    let onSave: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var canvas = PKCanvasView()

    var body: some View {
        NavigationStack {
            DrawingCanvas(canvasView: $canvas)
                .background(Color.white)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(existingData == nil ? "손글씨" : "손글씨 이어 쓰기")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("취소") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("저장") {
                            onSave(canvas.drawing.dataRepresentation())
                            dismiss()
                        }.fontWeight(.semibold)
                    }
                }
                .onAppear {
                    if let existingData, let drawing = try? PKDrawing(data: existingData) {
                        canvas.drawing = drawing
                    }
                }
        }
    }
}
