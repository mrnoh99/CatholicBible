import Foundation
import Combine

class DataDownloadManager: NSObject, ObservableObject {
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var lastError: String?
    @Published var lastUpdateTime: Date? {
        didSet {
            UserDefaults.standard.set(lastUpdateTime, forKey: "lastHeadingsUpdateTime")
        }
    }

    static let shared = DataDownloadManager()

    override init() {
        super.init()
        if let savedDate = UserDefaults.standard.object(forKey: "lastHeadingsUpdateTime") as? Date {
            self.lastUpdateTime = savedDate
        }
    }

    func downloadHeadings() {
        guard !isDownloading else { return }

        isDownloading = true
        downloadProgress = 0
        lastError = nil

        Task {
            do {
                try await copyBundleHeadingsToDocuments()

                await MainActor.run {
                    self.lastUpdateTime = Date()
                    self.isDownloading = false
                    self.downloadProgress = 1.0
                }
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                    self.isDownloading = false
                    self.downloadProgress = 0
                }
            }
        }
    }

    private func copyBundleHeadingsToDocuments() async throws {
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let headingsDir = documentsPath.appendingPathComponent("BibleHeadings")

        try fileManager.createDirectory(at: headingsDir, withIntermediateDirectories: true)

        // NABRE 헤딩 복사
        if let nabreURL = Bundle.main.url(forResource: "BibleText_nabre", withExtension: "json"),
           let nabreData = try? Data(contentsOf: nabreURL) {
            let nabreDestination = headingsDir.appendingPathComponent("NabreHeadings.json")
            try nabreData.write(to: nabreDestination)
            await MainActor.run {
                self.downloadProgress = 0.5
            }
        }

        // NCB 헤딩 복사
        if let ncbURL = Bundle.main.url(forResource: "NcbHeadings", withExtension: "json"),
           let ncbData = try? Data(contentsOf: ncbURL) {
            let ncbDestination = headingsDir.appendingPathComponent("NcbHeadings.json")
            try ncbData.write(to: ncbDestination)
        }

        await MainActor.run {
            self.downloadProgress = 1.0
        }
    }

    static func getHeadingsPath(forEdition edition: String) -> URL? {
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let headingsDir = documentsPath.appendingPathComponent("BibleHeadings")

        let fileName = edition == "nabre" ? "NabreHeadings.json" : "NcbHeadings.json"
        let filePath = headingsDir.appendingPathComponent(fileName)

        return fileManager.fileExists(atPath: filePath.path) ? filePath : nil
    }
}

enum DownloadError: LocalizedError {
    case invalidURL
    case invalidResponse
    case invalidData
    case networkError(String)
    case copyFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "유효하지 않은 URL입니다."
        case .invalidResponse:
            return "서버 응답이 유효하지 않습니다."
        case .invalidData:
            return "데이터를 처리할 수 없습니다."
        case .networkError(let message):
            return "네트워크 오류: \(message)"
        case .copyFailed:
            return "파일 복사 실패"
        }
    }
}
