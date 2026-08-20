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

    // MARK: - Public Methods

    func downloadHeadings() {
        guard !isDownloading else { return }

        isDownloading = true
        downloadProgress = 0
        lastError = nil

        Task {
            do {
                try await downloadNABREHeadings()
                try await downloadNCBHeadings()

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

    // MARK: - Private Methods

    private func downloadNABREHeadings() async throws {
        let urlString = "https://bible.usccb.org/bible/genesis/1"
        guard let url = URL(string: urlString) else {
            throw DownloadError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw DownloadError.invalidResponse
        }

        // Parse HTML to extract headings
        let headingsData = try parseNABREHeadings(from: data)
        try saveHeadings(headingsData, forEdition: "nabre")

        await MainActor.run {
            self.downloadProgress = 0.5
        }
    }

    private func downloadNCBHeadings() async throws {
        // NCB headings from a web source or local file
        // For now, using a placeholder URL - replace with actual source
        let urlString = "https://example.com/ncb-headings.json"
        guard let url = URL(string: urlString) else {
            throw DownloadError.invalidURL
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw DownloadError.invalidResponse
            }

            try saveHeadings(data, forEdition: "ncb")
        } catch {
            print("Warning: NCB headings download failed: \(error)")
        }

        await MainActor.run {
            self.downloadProgress = 1.0
        }
    }

    private func parseNABREHeadings(from htmlData: Data) throws -> Data {
        guard let htmlString = String(data: htmlData, encoding: .utf8) else {
            throw DownloadError.invalidData
        }

        var headings: [String: [String: [String: String]]] = [:]

        // Simple HTML parsing for section headings
        // This is a basic implementation - enhance as needed
        let pattern = #"<h[2-3][^>]*>([^<]+)</h[2-3]>"#
        let regex = try NSRegularExpression(pattern: pattern)
        let nsString = htmlString as NSString
        let matches = regex.matches(in: htmlString, range: NSRange(location: 0, length: nsString.length))

        var headingsList: [[String: String]] = []
        for match in matches {
            if let range = Range(match.range(at: 1), in: htmlString) {
                let heading = String(htmlString[range])
                headingsList.append(["title": heading])
            }
        }

        // Convert to expected format
        headings["headings"] = [
            "gn": [
                "1": headingsList.count > 0 ? ["1": headingsList[0]["title"] ?? ""] : [:]
            ]
        ]

        return try JSONSerialization.data(withJSONObject: headings)
    }

    private func saveHeadings(_ data: Data, forEdition edition: String) throws {
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let headingsDir = documentsPath.appendingPathComponent("BibleHeadings")

        try fileManager.createDirectory(at: headingsDir, withIntermediateDirectories: true)

        let fileName = edition == "nabre" ? "NabreHeadings.json" : "NcbHeadings.json"
        let filePath = headingsDir.appendingPathComponent(fileName)

        try data.write(to: filePath)
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
        }
    }
}
