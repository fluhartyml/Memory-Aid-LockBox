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

/// Typed fields the on-device model pulls out of OCR text. General enough for a
/// card, an account, or a storefront/sign (name + hours + address).
@Generable
struct ExtractedCardFields {
    @Guide(description: "The name — of the card, account, business, or place (e.g. 'Chase Visa', 'Ace Hardware'). Empty if not clearly present.")
    var title: String

    @Guide(description: "The primary card, account, or member number as printed (NOT a phone number). Empty if none is present.")
    var number: String

    @Guide(description: "Opening / store hours if shown (e.g. on a storefront door), formatted readably like 'Mon–Fri 9–5, Sat 10–2'. Empty if none.")
    var hours: String

    @Guide(description: "Any other useful details as a short summary — telephone number, street address, expiration date, name on the card. Empty if none.")
    var details: String
}

/// Typed contact fields the on-device model pulls from a business card, sign, or
/// storefront — feeds a secure contact card.
@Generable
struct ExtractedContactFields {
    @Guide(description: "The person's or business's full name. Empty if not clearly present.")
    var name: String

    @Guide(description: "The primary telephone number as printed. Empty if none.")
    var phone: String

    @Guide(description: "The email address. Empty if none.")
    var email: String

    @Guide(description: "The full mailing/street address on one line. Empty if none.")
    var address: String
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
        let prompt = "Extract the fields from this scanned text (a card, account, or a storefront/sign):\n\n\(text)"
        guard let response = try? await session.respond(to: prompt,
                                                        generating: ExtractedCardFields.self) else {
            return nil
        }
        let fields = response.content
        // Fold hours + details into the note body.
        let noteParts = [fields.hours, fields.details].filter { !$0.isEmpty }
        return Fields(title: fields.title,
                      number: fields.number,
                      notes: noteParts.joined(separator: "\n"))
        #else
        return nil
        #endif
    }

    /// Plain contact result the UI uses, decoupled from FoundationModels types.
    struct ContactFields {
        var name: String
        var phone: String
        var email: String
        var address: String
    }

    /// Extract contact details (name/phone/email/address) from OCR text with the
    /// on-device model. Returns nil if the model is unavailable or extraction
    /// fails — the caller should then fall back to CardTextRecognizer heuristics.
    static func extractContact(from text: String) async -> ContactFields? {
        #if canImport(FoundationModels)
        guard SystemLanguageModel.default.isAvailable else { return nil }
        let session = LanguageModelSession(instructions: contactInstructions)
        let prompt = "Extract the contact details from this scanned text (a business card, sign, or storefront):\n\n\(text)"
        guard let response = try? await session.respond(to: prompt,
                                                        generating: ExtractedContactFields.self) else {
            return nil
        }
        let f = response.content
        return ContactFields(name: f.name, phone: f.phone, email: f.email, address: f.address)
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

    private static let contactInstructions = """
    You extract contact details from the OCR text of a business card, sign, or \
    storefront. Use only information present in the text. If a field is not \
    clearly there, leave it empty. Never invent or guess values beyond light \
    cleanup of obvious OCR spacing.
    """
    #endif
}
