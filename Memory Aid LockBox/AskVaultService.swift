//
//  AskVaultService.swift
//  Memory Aid LockBox
//
//  "Ask your vault" — natural-language recall over the vault's items. The user
//  asks a plain question ("what's mom's Netflix password?") and gets a direct
//  answer drawn ONLY from their own entries.
//
//  Everything runs on-device. Relevant entries are found with a local keyword
//  rank (so only a few are ever handed to the model — the on-device model has a
//  small context window), then Apple's Foundation Models answers from just those.
//  On hardware without the on-device model, it falls back to listing the matches.
//  Nothing ever leaves the device — required for a vault of real passwords.
//

import Foundation
import SwiftData

#if canImport(FoundationModels)
import FoundationModels
#endif

enum AskVaultService {
    struct Result {
        var answer: String
        /// The entries the answer was drawn from (tappable in the UI).
        var sources: [VaultItem]
        /// True when the on-device model synthesized the answer; false when the
        /// keyword-match fallback was used (no Apple-Intelligence hardware).
        var usedModel: Bool
    }

    /// True only where the on-device model is present and enabled.
    static var modelAvailable: Bool {
        #if canImport(FoundationModels)
        return SystemLanguageModel.default.isAvailable
        #else
        return false
        #endif
    }

    /// Answer a question from the vault. Ranks entries locally, then either asks
    /// the on-device model or (fallback) lists the best matches.
    static func answer(question: String, items: [VaultItem]) async -> Result {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Result(answer: "Type a question about something in your vault.",
                          sources: [], usedModel: false)
        }

        let ranked = rankItems(items, for: trimmed)
        guard !ranked.isEmpty else {
            return Result(answer: "I couldn't find anything in your vault about that. Try different words, or the name you saved it under.",
                          sources: [], usedModel: false)
        }

        #if canImport(FoundationModels)
        if SystemLanguageModel.default.isAvailable {
            let context = ranked.map(entryText).joined(separator: "\n\n")
            let session = LanguageModelSession(instructions: instructions)
            let prompt = """
            Vault entries:
            \(context)

            Question: \(trimmed)
            """
            if let response = try? await session.respond(to: prompt) {
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    return Result(answer: text, sources: ranked, usedModel: true)
                }
            }
        }
        #endif

        return Result(answer: fallbackText(ranked), sources: ranked, usedModel: false)
    }

    // MARK: - Local keyword ranking

    /// Words too common to help match an entry.
    private static let stopWords: Set<String> = [
        "the", "a", "an", "and", "or", "of", "for", "to", "in", "on", "at",
        "is", "are", "was", "my", "me", "i", "do", "does", "did", "what",
        "whats", "where", "when", "who", "how", "which", "please", "tell",
        "give", "show", "find", "get", "you", "your"
    ]

    /// Rank entries by keyword overlap with the question; keep the best few.
    static func rankItems(_ items: [VaultItem], for question: String, limit: Int = 5) -> [VaultItem] {
        let keywords = question.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 && !stopWords.contains($0) }
        guard !keywords.isEmpty else { return [] }

        let scored: [(item: VaultItem, score: Int)] = items.map { item in
            let title = item.title.lowercased()
            let body = [item.notes, item.contactPhone, item.contactEmail, item.contactAddress]
                .joined(separator: " ")
                .lowercased()
            var score = 0
            for keyword in keywords {
                if title.contains(keyword) { score += 3 }   // a title hit matters most
                if body.contains(keyword) { score += 1 }
            }
            return (item, score)
        }

        return scored
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map(\.item)
    }

    // MARK: - Context + fallback text

    /// One entry rendered for the model. Notes are capped so several entries fit
    /// the on-device model's small context window.
    private static func entryText(_ item: VaultItem) -> String {
        var parts = ["Title: \(item.title)"]
        if !item.pin.isEmpty { parts.append("PIN/Code/Password: \(item.pin)") }
        if !item.notes.isEmpty { parts.append("Notes: \(String(item.notes.prefix(500)))") }
        if !item.contactPhone.isEmpty { parts.append("Phone: \(item.contactPhone)") }
        if !item.contactEmail.isEmpty { parts.append("Email: \(item.contactEmail)") }
        if !item.contactAddress.isEmpty { parts.append("Address: \(item.contactAddress)") }
        return parts.joined(separator: "\n")
    }

    /// Plain answer when there's no on-device model: name the matches and, where
    /// present, surface the code so a card/password question is still answered.
    private static func fallbackText(_ items: [VaultItem]) -> String {
        var lines = ["Here's what matches in your vault:"]
        for item in items {
            if item.pin.isEmpty {
                lines.append("• \(item.title)")
            } else {
                lines.append("• \(item.title): \(item.pin)")
            }
        }
        return lines.joined(separator: "\n")
    }

    #if canImport(FoundationModels)
    private static let instructions = """
    You are a private memory aid. Answer the user's question using ONLY the vault \
    entries provided in the prompt — these are the user's own records (passwords, \
    codes, notes, contacts). Answer directly and briefly. If a password, PIN, or \
    code is asked for and present, state it plainly. If the answer is not in the \
    entries, say you don't have it saved. Never invent or guess details that are \
    not in the entries.
    """
    #endif
}
