//
//  CardFieldExtractor.swift
//  Memory Aid LockBox
//
//  Smart, on-device field extraction from a card's OCR text using Apple's
//  Foundation Models (the on-device LLM). Runs ONLY on Apple-Intelligence-capable
//  hardware (iPhone 15 Pro / A17 Pro and later, M-series); on everything else it
//  reports unavailable and the caller falls back to the plain OCR heuristics in
//  CardTextRecognizer. Nothing leaves the device — required for a vault.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Typed fields the on-device model pulls out of OCR text.
@Generable
struct ExtractedCardFields {
    @Guide(description: "The card, account, or membership name (e.g. 'Chase Visa', 'Public Library Card'). Empty if not clearly present.")
    var title: String

    @Guide(description: "The primary card, account, or member number as printed. Empty if none is present.")
    var number: String

    @Guide(description: "Any other useful details as a short readable summary — expiration date, name on the card, phone, address. Empty if none.")
    var notes: String
}
#endif

enum CardFieldExtractor {
    /// Plain result the UI uses, decoupled from FoundationModels types.
    struct Fields {
        var title: String
        var number: String
        var notes: String
    }

    /// True only on hardware where the on-device model is present and enabled.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        return SystemLanguageModel.default.isAvailable
        #else
        return false
        #endif
    }

    /// Extract structured fields from OCR text with the on-device model. Returns
    /// nil if the model is unavailable or extraction fails — the caller should
    /// then fall back to CardTextRecognizer's heuristics.
    static func extract(from text: String) async -> Fields? {
        #if canImport(FoundationModels)
        guard SystemLanguageModel.default.isAvailable else { return nil }
        let session = LanguageModelSession(instructions: instructions)
        let prompt = "Extract the fields from this scanned card/account text:\n\n\(text)"
        guard let response = try? await session.respond(to: prompt,
                                                        generating: ExtractedCardFields.self) else {
            return nil
        }
        let fields = response.content
        return Fields(title: fields.title, number: fields.number, notes: fields.notes)
        #else
        return nil
        #endif
    }

    #if canImport(FoundationModels)
    private static let instructions = """
    You extract fields from the OCR text of a card, account, or membership. \
    Use only information that is present in the text. If a field is not clearly \
    there, leave it empty. Never invent, guess, or reformat values beyond light \
    cleanup of obvious OCR spacing.
    """
    #endif
}
