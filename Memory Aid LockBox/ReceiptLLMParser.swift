//
//  ReceiptLLMParser.swift
//  Memory Aid LockBox
//
//  On-device receipt understanding via Apple's Foundation Models (Apple
//  Intelligence). Vision OCR reads a receipt column-by-column, so item names
//  and their prices come out orphaned; the on-device model re-associates them
//  by understanding, not geometry — the fix for skewed/messy real receipts.
//  Returns nil when Apple Intelligence isn't available (older device), so the
//  caller falls back to the positional heuristic (ReceiptTextParser).
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Platform-neutral result so callers don't depend on FoundationModels.
struct LLMReceipt {
    var items: [(name: String, price: String)] = []
    var store = ""
    var address = ""
    var phone = ""
    var subtotal = ""
    var tax = ""
    var total = ""
}

enum ReceiptLLMParser {
    /// Structured extraction from raw receipt OCR text. nil if the on-device
    /// model isn't available or the request fails.
    static func parse(ocrText: String) async -> LLMReceipt? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return await parseWithModel(ocrText)
        }
        #endif
        return nil
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private static func parseWithModel(_ ocrText: String) async -> LLMReceipt? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        let session = LanguageModelSession(instructions: instructions)
        guard let response = try? await session.respond(
            to: "Receipt OCR text:\n\(ocrText)", generating: GenReceipt.self)
        else { return nil }
        let p = response.content
        return LLMReceipt(
            items: p.items.map { (name: $0.name, price: $0.price) },
            store: p.store, address: p.address, phone: p.phone,
            subtotal: p.subtotal, tax: p.tax, total: p.total)
    }

    private static let instructions = """
    You extract structured data from the raw OCR text of a store receipt. The OCR \
    often lists all item names first and then all prices in the same order — \
    re-associate each item with its correct price. Include ONLY real purchased line \
    items. Ignore "Regular Price" lines, discounts and coupons, subtotal/tax/total, \
    payment/card/AUTH lines, survey codes, and store-policy text. Give prices as \
    plain numbers like 7.49. If a field is not present in the text, leave it empty — \
    never invent values. Infer the store name only if the text clearly names it \
    (e.g. a website or slogan).
    """
    #endif
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
@Generable
private struct GenReceipt {
    @Guide(description: "Every purchased line item with its price")
    var items: [GenItem]
    @Guide(description: "Store or merchant name if the text names it, else empty")
    var store: String
    @Guide(description: "Street address if present, else empty")
    var address: String
    @Guide(description: "Phone number if present, else empty")
    var phone: String
    @Guide(description: "Subtotal as a number like 56.15, else empty")
    var subtotal: String
    @Guide(description: "Tax as a number, else empty")
    var tax: String
    @Guide(description: "Total as a number, else empty")
    var total: String
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
private struct GenItem {
    @Guide(description: "Item name")
    var name: String
    @Guide(description: "Item price as a number like 7.49")
    var price: String
}
#endif
