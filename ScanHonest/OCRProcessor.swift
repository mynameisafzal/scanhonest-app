import Vision
import UIKit

class OCRProcessor {
    static let shared = OCRProcessor()

    func extractText(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                continuation.resume(returning: text)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func extractText(fromPDFPages images: [UIImage]) async throws -> String {
        var allText: [String] = []
        for (index, image) in images.enumerated() {
            let text = try await extractText(from: image)
            if !text.isEmpty {
                allText.append("--- Page \(index + 1) ---\n\(text)")
            }
        }
        return allText.joined(separator: "\n\n")
    }

    // Smart file naming from OCR text
    func suggestFileName(from text: String) -> String {
        let lines = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let firstLine = lines.first ?? "Scan"
        let cleaned = firstLine
            .components(separatedBy: .punctuationCharacters).joined(separator: "_")
            .components(separatedBy: .whitespaces).joined(separator: "_")
            .prefix(30)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM_yyyy"
        let dateStr = dateFormatter.string(from: Date())

        return "\(cleaned)_\(dateStr)"
    }
}

enum OCRError: Error {
    case invalidImage
    case processingFailed
}
