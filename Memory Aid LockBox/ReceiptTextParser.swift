//
//  ReceiptTextParser.swift
//  Memory Aid LockBox
//
//  Turns Vision OCR lines (CardTextRecognizer.recognize → .lines) from a
//  scanned/photographed receipt into discrete line items + subtotal/tax/total.
//  Fully on-device, no Apple Intelligence needed — a "dumb" but reliable
//  heuristic: a line ending in a $#.## price is an item (name = the text before
//  the price); total/tax rows are captured separately; store header/address,
//  coupons (negative), and payment/meta rows are skipped. Users edit the rows
//  after, so over-capturing a stray row is cheaper than dropping a real item.
//

import Foundation

enum ReceiptTextParser {
    struct Result {
        var items: [ReceiptLineItem] = []
        var subtotal: String?
        var tax: String?
        var total: String?
        var phone: String?
        var address: String?
    }

    static func parse(_ lines: [String]) -> Result {
        var result = Result()
        result.phone = firstPhone(in: lines)   // per-row so it doesn't grab trailing address digits
        result.address = detect(.address, in: lines.joined(separator: ", "))

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let split = priceSplit(line) else { continue }
            let upper = line.uppercased()

            // Money-bearing meta rows: capture the amount, don't list as an item.
            if upper.contains("SUBTOTAL") || upper.contains("SUB TOTAL") {
                if result.subtotal == nil { result.subtotal = split.price }
                continue
            }
            if upper.contains("TAX") {
                if result.tax == nil { result.tax = split.price }
                continue
            }
            if upper.contains("TOTAL") || upper.contains("BALANCE DUE") || upper.contains("AMOUNT DUE") {
                if result.total == nil { result.total = split.price }
                continue
            }
            if split.negative { continue }        // coupons / discounts
            if isMeta(upper) { continue }          // payment, change, savings, etc.

            let name = cleanName(split.name)
            guard name.count >= 2, name.contains(where: \.isLetter) else { continue }
            result.items.append(ReceiptLineItem(name: name, price: split.price))
        }
        return result
    }

    // MARK: - Heuristics

    private struct PriceSplit { let name: String; let price: String; let negative: Bool }

    /// Split "MILK 2 GAL 5.99 F" → (name: "MILK 2 GAL", price: "5.99"). Greedy
    /// name so the LAST money value on the line wins (unit price then line
    /// total). Allows a leading $, an optional minus, and a trailing 0–2 letter
    /// tax/unit flag (Target's N/T/F, or "EA"/"LB").
    private static func priceSplit(_ line: String) -> PriceSplit? {
        let pattern = "^(.+)\\s+\\$?(-?)(\\d{1,4}\\.\\d{2})\\s*[A-Za-z]{0,2}$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        guard let m = regex.firstMatch(in: line, options: [], range: range),
              let nameR = Range(m.range(at: 1), in: line),
              let priceR = Range(m.range(at: 3), in: line) else { return nil }
        let negative = Range(m.range(at: 2), in: line).map { line[$0] == "-" } ?? false
        return PriceSplit(name: String(line[nameR]), price: String(line[priceR]), negative: negative)
    }

    /// Strip a leading UPC/DPCI code and stray symbols off an item name.
    private static func cleanName(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        t = t.replacingOccurrences(of: "^[0-9]{5,}\\s+", with: "", options: .regularExpression)
        // drop a trailing tax/unit flag left after the price was removed (NF, T, N, F, H, X)
        t = t.replacingOccurrences(of: "\\s+(NF|N|T|F|H|X)$", with: "",
                                    options: [.regularExpression, .caseInsensitive])
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: "$*#•- "))
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// First phone found in any single row (avoids a whole-text match gluing on
    /// the address's leading digits, e.g. "979-299-0009 202").
    private static func firstPhone(in lines: [String]) -> String? {
        for line in lines { if let p = detect(.phoneNumber, in: line) { return p } }
        return nil
    }

    /// First NSDataDetector match of the given type (phone, address).
    private static func detect(_ type: NSTextCheckingResult.CheckingType, in text: String) -> String? {
        guard let d = try? NSDataDetector(types: type.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = d.firstMatch(in: text, options: [], range: range),
              let r = Range(m.range, in: text) else { return nil }
        return String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let metaKeywords = [
        "REGULAR PRICE", "REG PRICE", "SALE PRICE", "PRICE YOU PAY",
        "CHANGE", "TENDER", "CASH", "CREDIT", "DEBIT", "VISA", "MASTERCARD",
        "AMEX", "DISCOVER", "AUTH", "APPROV", "ACCOUNT", "CARD #", "PAYMENT",
        "SAVINGS", "SAVED", "LOYALTY", "MEMBER", "REWARD", "COUPON", "RETURN",
        "REF ", "TRANSACTION", "CASHIER", "REGISTER", "REG#", "STORE", "ORDER #",
        "ITEMS SOLD", "NUMBER OF ITEMS", "PURCHASE", "GST", "PST", "HST",
    ]

    private static func isMeta(_ upper: String) -> Bool {
        metaKeywords.contains { upper.contains($0) }
    }
}
