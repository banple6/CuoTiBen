import Foundation

#if canImport(PencilKit) && canImport(Vision) && canImport(UIKit)
import PencilKit
import Vision
import UIKit

struct InkRecognitionResult {
    let text: String
    let confidence: Double
}

final class InkRecognitionService {
    func recognizeText(from drawingData: Data) async -> InkRecognitionResult? {
        guard let drawing = try? PKDrawing(data: drawingData), !drawing.bounds.isEmpty else {
            return nil
        }

        let image = renderImage(from: drawing)
        guard let cgImage = image.cgImage else { return nil }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let candidates = observations.compactMap { observation -> (String, Float)? in
                    guard let best = observation.topCandidates(1).first else { return nil }
                    return (best.string, best.confidence)
                }

                let text = candidates
                    .map(\.0)
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let confidence = candidates.map(\.1).max().map(Double.init) ?? 0

                guard let normalized = self.normalizedRecognizedText(text), !normalized.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: InkRecognitionResult(text: normalized, confidence: confidence))
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US", "zh-Hans"]

            let handler = VNImageRequestHandler(cgImage: cgImage)
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    private func renderImage(from drawing: PKDrawing) -> UIImage {
        let bounds = drawing.bounds.insetBy(dx: -18, dy: -18)
        return drawing.image(from: bounds, scale: 2)
    }

    private func normalizedRecognizedText(_ value: String) -> String? {
        let trimmed = value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count >= 2, trimmed.count <= 32 else { return nil }
        return trimmed
    }
}

#else

struct InkRecognitionResult {
    let text: String
    let confidence: Double
}

final class InkRecognitionService {
    func recognizeText(from drawingData: Data) async -> InkRecognitionResult? {
        nil
    }
}

#endif
