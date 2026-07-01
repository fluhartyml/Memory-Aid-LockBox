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

    // MARK: - Contact heuristics (fallback when the on-device model is absent)

    /// Contact details pulled from a scanned card/sign with plain heuristics.
    struct RecognizedContact {
        var name: String?
        var phone: String?
        var email: String?
        var address: String?
    }

    /// OCR the image, then pull name/phone/email/address with NSDataDetector +
    /// a light email regex. Used when Foundation Models isn't available.
    static func contactFields(from imageData: Data) async -> RecognizedContact? {
        guard let card = await recognize(from: imageData) else { return nil }
        return heuristicContact(in: card.lines)
    }

    private static func heuristicContact(in lines: [String]) -> RecognizedContact {
        let joined = lines.joined(separator: " ")
        return RecognizedContact(
            name: bestTitle(in: lines),
            phone: bestNumber(in: lines),
            email: firstEmail(in: lines),
            address: firstAddress(in: joined)
        )
    }

    /// First token matching a simple email pattern.
    private static func firstEmail(in lines: [String]) -> String? {
        let pattern = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            if let match = regex.firstMatch(in: line, options: [], range: range),
               let r = Range(match.range, in: line) {
                return String(line[r])
            }
        }
        return nil
    }

    /// A postal address detected anywhere in the joined text.
    private static func firstAddress(in text: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        if let match = detector.firstMatch(in: text, options: [], range: range),
           let r = Range(match.range, in: text) {
            return String(text[r])
        }
        return nil
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
