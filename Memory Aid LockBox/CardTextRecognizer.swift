//
//  CardTextRecognizer.swift
//  Memory Aid LockBox
//
//  On-device OCR for "scan a card, fill the fields." Uses the Vision framework
//  (fully on-device, no Apple Intelligence hardware required, works on every
//  supported device and on Mac) to read text off a scanned/photographed card,
//  then a light heuristic + NSDataDetector to suggest a title and a number.
//

import Foundation
import Vision

struct RecognizedCard {
    /// Every recognized line, top to bottom.
    var lines: [String]
    /// A likely title (a name-ish line), if one stands out.
    var suggestedTitle: String?
    /// A likely card/account/phone number, if one stands out.
    var suggestedNumber: String?

    var fullText: String { lines.joined(separator: "\n") }
}

enum CardTextRecognizer {
    /// Recognize text on the given image. Returns nil if nothing was read.
    static func recognize(from imageData: Data) async -> RecognizedCard? {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        guard let observations = try? await request.perform(on: imageData) else { return nil }

        let lines = observations
            .compactMap { $0.topCandidates(1).first?.string }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return nil }

        return RecognizedCard(lines: lines,
                              suggestedTitle: bestTitle(in: lines),
                              suggestedNumber: bestNumber(in: lines))
    }

    /// First mostly-letters line (usually the card/bank/member name).
    private static func bestTitle(in lines: [String]) -> String? {
        lines.first { line in
            let letters = line.filter(\.isLetter).count
            return letters >= 3 && Double(letters) / Double(max(line.count, 1)) > 0.5
        } ?? lines.first
    }

    /// A phone number (via NSDataDetector) or, failing that, the line with the
    /// most digits (a card/account number). Returns nil if nothing looks numeric.
    private static func bestNumber(in lines: [String]) -> String? {
        let joined = lines.joined(separator: " ")
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue) {
            let range = NSRange(joined.startIndex..., in: joined)
            if let match = detector.firstMatch(in: joined, options: [], range: range),
               let matched = Range(match.range, in: joined) {
                return String(joined[matched])
            }
        }
        let numericLines = lines.filter { $0.filter(\.isNumber).count >= 6 }
        return numericLines.max { $0.filter(\.isNumber).count < $1.filter(\.isNumber).count }
    }
}
