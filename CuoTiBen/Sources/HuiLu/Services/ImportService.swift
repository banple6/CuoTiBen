import Foundation
import PDFKit

// MARK: - Import Service Protocol
public protocol ImportServiceProtocol {
    func importPDF(at url: URL) async throws -> SourceDocument
    func importImages(from urls: [URL]) async throws -> [SourceDocument]
    func importText(at url: URL) async throws -> SourceDocument
    func captureAndImportScan() async throws -> SourceDocument
}

// MARK: - Import Service Implementation
/// Handles initial material ingestion and creates source-document records.
public final class ImportService: ImportServiceProtocol {
    private let fileManager = FileManager.default
    private let documentsDirectory: URL

    public init(documentsDirectory: URL? = nil) {
        self.documentsDirectory = documentsDirectory ??
            fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    public func importPDF(at url: URL) async throws -> SourceDocument {
        guard url.isFileURL else {
            throw ImportError.invalidURL("不是本地文件链接")
        }

        guard url.pathExtension.lowercased() == "pdf" else {
            throw ImportError.unsupportedFormat("当前文件不是 PDF")
        }

        let destinationURL = try copyImportedFile(from: url)
        let pageCount = countPDFPages(at: destinationURL)

        return SourceDocument(
            title: destinationURL.deletingPathExtension().lastPathComponent,
            documentType: .pdf,
            importDate: Date(),
            pageCount: max(pageCount, 1),
            filePath: destinationURL.path,
            processingStatus: .imported
        )
    }

    public func importImages(from urls: [URL]) async throws -> [SourceDocument] {
        var documents: [SourceDocument] = []

        for url in urls {
            guard url.isFileURL else {
                continue
            }

            let destinationURL = try copyImportedFile(from: url)
            let document = SourceDocument(
                title: destinationURL.deletingPathExtension().lastPathComponent,
                documentType: .image,
                importDate: Date(),
                pageCount: 1,
                filePath: destinationURL.path,
                processingStatus: .imported
            )
            documents.append(document)
        }

        return documents
    }

    public func importText(at url: URL) async throws -> SourceDocument {
        guard url.isFileURL else {
            throw ImportError.invalidURL("不是本地文件链接")
        }

        let destinationURL = try copyImportedFile(from: url)

        return SourceDocument(
            title: destinationURL.deletingPathExtension().lastPathComponent,
            documentType: .text,
            importDate: Date(),
            pageCount: 1,
            filePath: destinationURL.path,
            processingStatus: .imported
        )
    }

    public func captureAndImportScan() async throws -> SourceDocument {
        throw ImportError.notImplemented("第一版先支持 PDF、图片和文本导入")
    }

    private func copyImportedFile(from url: URL) throws -> URL {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let destinationURL = uniqueDestinationURL(for: url.lastPathComponent)

        do {
            try fileManager.copyItem(at: url, to: destinationURL)
            return destinationURL
        } catch {
            throw ImportError.copyFailed(error.localizedDescription)
        }
    }

    private func uniqueDestinationURL(for fileName: String) -> URL {
        let ext = (fileName as NSString).pathExtension
        let baseName = (fileName as NSString).deletingPathExtension
        var candidate = documentsDirectory.appendingPathComponent(fileName)
        var suffix = 1

        while fileManager.fileExists(atPath: candidate.path) {
            let newName = ext.isEmpty ? "\(baseName)-\(suffix)" : "\(baseName)-\(suffix).\(ext)"
            candidate = documentsDirectory.appendingPathComponent(newName)
            suffix += 1
        }

        return candidate
    }

    private func countPDFPages(at url: URL) -> Int {
        PDFDocument(url: url)?.pageCount ?? 0
    }
}

// MARK: - Import Errors
public enum ImportError: LocalizedError {
    case invalidURL(String)
    case unsupportedFormat(String)
    case copyFailed(String)
    case permissionDenied
    case notImplemented(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let message):
            return "无效的链接：\(message)"
        case .unsupportedFormat(let message):
            return "不支持的格式：\(message)"
        case .copyFailed(let message):
            return "复制失败：\(message)"
        case .permissionDenied:
            return "无访问权限，请在设置中允许访问文件"
        case .notImplemented(let message):
            return message
        }
    }
}
