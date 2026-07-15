//
//  MediaCapture.swift
//  CatholicBible
//
//  노트에 쓰는 미디어 캡처/재생 도구:
//  - CameraPicker: 카메라로 사진 또는 비디오 촬영 (UIImagePickerController)
//  - AudioRecorder / AudioPlayerBox: 오디오 녹음·재생 (AVFoundation)
//  - DrawingCanvas: PencilKit 손글씨 캔버스
//

import SwiftUI
import UIKit
import AVFoundation
import PencilKit

// MARK: - 카메라 (사진/비디오 촬영)

struct CameraPicker: UIViewControllerRepresentable {
    enum Mode { case photo, video }
    let mode: Mode
    /// 촬영 결과 임시 파일 URL (사진은 jpg로 써서 전달)
    let onCapture: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = mode == .video ? ["public.movie"] : ["public.image"]
        picker.cameraCaptureMode = mode == .video ? .video : .photo
        picker.videoQuality = .typeHigh
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let movieURL = info[.mediaURL] as? URL {
                parent.onCapture(movieURL)
            } else if let image = info[.originalImage] as? UIImage,
                      let data = image.jpegData(compressionQuality: 0.9) {
                let tmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(UUID().uuidString).jpg")
                try? data.write(to: tmp)
                parent.onCapture(tmp)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - 오디오 녹음

@Observable
final class AudioRecorder: NSObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    private var timer: Timer?
    /// 녹음이 끝나면 임시 파일 URL을 돌려준다.
    var onFinish: ((URL) -> Void)?

    func requestPermissionAndStart() {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            guard granted else { return }
            DispatchQueue.main.async { self?.start() }
        }
    }

    private func start() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
            let rec = try AVAudioRecorder(url: url, settings: settings)
            rec.delegate = self
            rec.record()
            recorder = rec
            isRecording = true
            elapsed = 0
            timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                self?.elapsed = self?.recorder?.currentTime ?? 0
            }
        } catch {
            isRecording = false
        }
    }

    func stop() {
        guard let recorder else { return }
        let url = recorder.url
        recorder.stop()
        timer?.invalidate(); timer = nil
        isRecording = false
        self.recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        onFinish?(url)
    }
}

// MARK: - 오디오 재생

@Observable
final class AudioPlayerBox: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private(set) var isPlaying = false
    private(set) var progress: Double = 0
    private var timer: Timer?

    func toggle(url: URL) {
        if isPlaying { pause() } else { play(url: url) }
    }

    func play(url: URL) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            if player?.url != url {
                player = try AVAudioPlayer(contentsOf: url)
                player?.delegate = self
            }
            player?.play()
            isPlaying = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let p = self?.player else { return }
                self?.progress = p.duration > 0 ? p.currentTime / p.duration : 0
            }
        } catch {
            isPlaying = false
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        timer?.invalidate(); timer = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        progress = 0
        timer?.invalidate(); timer = nil
    }
}

// MARK: - PencilKit 손글씨 캔버스

struct DrawingCanvas: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    /// 기존 손글씨 이미지를 배경으로 깔 때 사용(편집 재개용) — 여기선 새 그림 기준
    var toolPickerShows: Bool = true

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.drawingPolicy = .anyInput   // 손가락·펜슬 모두
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        if toolPickerShows {
            let picker = context.coordinator.toolPicker
            picker.setVisible(true, forFirstResponder: canvasView)
            picker.addObserver(canvasView)
            DispatchQueue.main.async { canvasView.becomeFirstResponder() }
        }
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        let toolPicker = PKToolPicker()
    }
}

extension PKCanvasView {
    /// 현재 손글씨를 흰 배경 PNG 데이터로 렌더링한다.
    func exportPNG(scale: CGFloat = 3.0) -> Data? {
        let bounds = drawing.bounds.isEmpty
            ? CGRect(x: 0, y: 0, width: 600, height: 400)
            : drawing.bounds.insetBy(dx: -16, dy: -16)
        let image = drawing.image(from: bounds, scale: scale)
        let renderer = UIGraphicsImageRenderer(size: image.size)
        let composed = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: image.size))
            image.draw(at: .zero)
        }
        return composed.pngData()
    }
}
