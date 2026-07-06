//
//  AppointmentTextParser.swift
//  Memory Aid LockBox
//
//  Parses a pasted/shared appointment-reminder text (e.g. a doctor's SMS) into
//  Appointment fields (roadmap 025a): practice · date+time · address · phone ·
//  prep, while stripping the reminder noise ("reply STOP", "reply C to confirm",
//  unsubscribe, repeated blocks). Uses on-device NSDataDetector for date/phone/
//  address — no network, no LLM required. The Share Extension (025) will reuse
//  this; it's also wired into the Appointment sheet now so it's usable today.
//

import Foundation

struct ParsedAppointment {
    var practice = ""
    var date: Date?
    var address = ""
    var phone = ""
    var prep = ""
}

enum AppointmentTextParser {
    /// Lines that are reminder-service noise, not appointment content.
    private static let noiseMarkers = [
        "reply stop", "reply c", "reply y", "text stop", "unsubscribe",
        "to confirm", "to cancel", "msg&data", "message and data",
        "std msg", "do not reply", "this is an automated", "opt out", "opt-out",
    ]

    private static let prepMarkers = [
        "fast", "bring", "arrive", "prior", "before your", "no food",
        "no eating", "prep", "instruction", "medication", "please",
    ]

    static func parse(_ raw: String) -> ParsedAppointment {
        var result = ParsedAppointment()

        // Keep only meaningful lines (drop the reminder-service noise + dupes).
        var seen = Set<String>()
        let lines = raw
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                guard !line.isEmpty else { return false }
                let lower = line.lowercased()
                if noiseMarkers.contains(where: { lower.contains($0) }) { return false }
                let key = lower
                if seen.contains(key) { return false }   // strip repeated blocks
                seen.insert(key)
                return true
            }
        let cleaned = lines.joined(separator: "\n")

        // Date / phone / address via on-device detectors.
        let types: NSTextCheckingResult.CheckingType = [.date, .phoneNumber, .address]
        if let detector = try? NSDataDetector(types: types.rawValue) {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            detector.enumerateMatches(in: cleaned, range: range) { match, _, _ in
                guard let match else { return }
                switch match.resultType {
                case .date where result.date == nil:
                    result.date = match.date
                case .phoneNumber where result.phone.isEmpty:
                    result.phone = match.phoneNumber ?? ""
                case .address where result.address.isEmpty:
                    result.address = (cleaned as NSString).substring(with: match.range)
                        .replacingOccurrences(of: "\n", with: ", ")
                default:
                    break
                }
            }
        }

        // Practice = the first content line that isn't purely a date/phone/address.
        result.practice = lines.first(where: { line in
            let lower = line.lowercased()
            let looksLikeContact = line.contains(where: \.isNumber) &&
                (lower.contains("call") || line.filter(\.isNumber).count >= 7)
            return !looksLikeContact
        }) ?? (lines.first ?? "")

        // Prep = any line mentioning a prep keyword.
        result.prep = lines
            .filter { line in prepMarkers.contains(where: { line.lowercased().contains($0) }) }
            .joined(separator: "\n")

        return result
    }
}
