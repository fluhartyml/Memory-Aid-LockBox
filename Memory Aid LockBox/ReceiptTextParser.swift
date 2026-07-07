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
import CoreGraphics

enum ReceiptTextParser {
    struct Result {
        var items: [ReceiptLineItem] = []
        var subtotal: String?
        var tax: String?
        var total: String?
        var phone: String?
        var address: String?
    }

    /// Structured result of the geometric (position-aware) scan parse.
    struct ReceiptScan {
        var items: [ReceiptLineItem] = []
        var subtotal = ""
        var tax = ""
        var total = ""
        var phone = ""
        var address = ""
    }

    // MARK: - Geometric parse (uses fragment positions)

    /// Parse from OCR fragments with their bounding boxes. Reliable for standard
    /// retail receipts: real items begin with a long item/UPC CODE (headers like
    /// GROCERY/TOYS and "Regular Price" lines do not), and prices sit in a
    /// right-hand column. We take the code-prefixed item names top-to-bottom and
    /// pair each with the next right-column price (items always sit above the
    /// SUBTOTAL/TAX/TOTAL block). Totals are matched to their label's row.
    static func parseScan(_ frags: [(text: String, box: CGRect)]) -> ReceiptScan {
        var out = ReceiptScan()

        struct Named { let name: String; let midY: CGFloat; let inlinePrice: String? }
        var names: [Named] = []
        for f in frags {
            guard let r = f.text.range(of: "^[0-9]{5,}\\s+", options: .regularExpression) else { continue }
            var rest = String(f.text[r.upperBound...])
            var inline: String?
            if let tp = trailingPrice(in: rest) { inline = tp.price; rest = tp.rest }
            let name = cleanName(rest)
            guard name.count >= 2, name.rangeOfCharacter(from: .letters) != nil else { continue }
            names.append(Named(name: name, midY: f.box.midY, inlinePrice: inline))
        }
        names.sort { $0.midY > $1.midY }   // top to bottom

        // Bare prices in the right-hand column, top-to-bottom.
        var prices: [String] = frags
            .filter { $0.box.minX > 0.5 && priceOnly($0.text) != nil }
            .sorted { $0.box.midY > $1.box.midY }
            .compactMap { priceOnly($0.text) }

        var qi = 0
        for nm in names {
            let price: String
            if let ip = nm.inlinePrice { price = ip }
            else if qi < prices.count { price = prices[qi]; qi += 1 }
            else { continue }
            out.items.append(ReceiptLineItem(name: nm.name, price: price))
        }

        // Totals: nearest right-column price to each label's row.
        let allPrices: [(value: String, midY: CGFloat)] = frags
            .filter { $0.box.minX > 0.5 }
            .compactMap { f in priceOnly(f.text).map { (value: $0, midY: f.box.midY) } }
        if let y = frags.first(where: { $0.text.uppercased().contains("SUBTOTAL") })?.box.midY {
            out.subtotal = nearestPrice(y, allPrices)
        }
        if let y = frags.first(where: { $0.text.uppercased().contains("TAX") })?.box.midY {
            out.tax = nearestPrice(y, allPrices)
        }
        if let y = frags.first(where: {
            let u = $0.text.uppercased(); return u.contains("TOTAL") && !u.contains("SUBTOTAL")
        })?.box.midY {
            out.total = nearestPrice(y, allPrices)
        }

        // Address + phone from the top of the receipt.
        let top = frags.sorted { $0.box.midY > $1.box.midY }.prefix(8).map(\.text)
        out.phone = firstPhone(in: Array(top)) ?? ""
        out.address = detect(.address, in: top.joined(separator: ", ")) ?? ""
        return out
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

    /// A fragment that is JUST a price ("$7.49" → "7.49"), else nil.
    private static func priceOnly(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.range(of: "^\\$?[0-9]{1,4}\\.[0-9]{2}$", options: .regularExpression) != nil else { return nil }
        return t.replacingOccurrences(of: "$", with: "")
    }

    /// A trailing price on an item line ("KNG HAWAIIAN 7.49" → 7.49 + the rest),
    /// for receipts that keep the price on the same fragment as the name.
    private static func trailingPrice(in s: String) -> (price: String, rest: String)? {
        guard let r = s.range(of: "\\s+\\$?[0-9]{1,4}\\.[0-9]{2}\\s*[A-Za-z]{0,2}$",
                              options: .regularExpression) else { return nil }
        let tail = String(s[r])
        guard let pr = tail.range(of: "[0-9]{1,4}\\.[0-9]{2}", options: .regularExpression) else { return nil }
        return (String(tail[pr]), String(s[..<r.lowerBound]))
    }

    /// The right-column price whose row is vertically closest to `y`.
    private static func nearestPrice(_ y: CGFloat, _ prices: [(value: String, midY: CGFloat)]) -> String {
        prices.min(by: { abs($0.midY - y) < abs($1.midY - y) })?.value ?? ""
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
