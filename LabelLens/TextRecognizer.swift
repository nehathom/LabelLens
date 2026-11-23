import UIKit
import Vision

enum TextRecognizerError: LocalizedError {
    case invalidImage
    var errorDescription: String? { "Could not read that image." }
}

/// On-device OCR using Apple's Vision framework. No network calls.
struct TextRecognizer {
    func recognize(in image: UIImage) throws -> [String] {
        guard let cgImage = image.cgImage else { throw TextRecognizerError.invalidImage }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage,
                                            orientation: CGImagePropertyOrientation(image.imageOrientation),
                                            options: [:])
        try handler.perform([request])

        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
