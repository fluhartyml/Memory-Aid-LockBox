//
//  NotificationService.swift
//  Memory Aid LockBox
//
//  Local notifications for a contact's significant dates (roadmap 010b, added
//  2026-07-11). Each significant date can carry a per-date lead time (minutes
//  before); this schedules a UNCalendarNotificationTrigger for it. Recurring
//  (yearly) dates repeat annually. The notification identifier is the significant
//  date's UUID, so rescheduling replaces cleanly and deleting cancels by id.
//
//  Cross-platform: UserNotifications is available on iOS and macOS. No Info.plist
//  key is needed — requesting authorization surfaces the system prompt itself.
//

import Foundation
import UserNotifications

enum NotificationService {
    /// Outcome of a schedule attempt, so the UI can give honest feedback.
    enum ScheduleResult {
        case scheduled   // a reminder is now pending
        case cleared     // reminder turned off (any existing one cancelled)
        case denied      // the user hasn't granted notification permission
        case past        // a one-off whose fire time already passed — nothing to schedule
    }

    /// Ask once for permission. After the first call this returns the standing
    /// decision without re-prompting.
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// (Re)schedule the reminder for a significant date. Always cancels any existing
    /// notification for this id first, so this is safe to call on every add/edit.
    /// Fail-safe: denial or a past one-off just means no notification, never an error.
    @discardableResult
    static func schedule(for d: SignificantDate, contactName: String) async -> ScheduleResult {
        let center = UNUserNotificationCenter.current()
        let id = d.id.uuidString
        center.removePendingNotificationRequests(withIdentifiers: [id])

        guard let lead = d.reminderLeadMinutes else { return .cleared }
        guard await requestAuthorization() else { return .denied }

        let fireDate = d.date.addingTimeInterval(TimeInterval(-lead * 60))
        let cal = Calendar.current
        let trigger: UNCalendarNotificationTrigger

        if d.recurring {
            // Annual: match month/day/hour/minute and repeat every year. iOS fires
            // the next matching occurrence, so a past-this-year date is fine.
            let comps = cal.dateComponents([.month, .day, .hour, .minute], from: fireDate)
            trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        } else {
            // One-off: don't schedule something already in the past.
            guard fireDate > Date() else { return .past }
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        }

        let content = UNMutableNotificationContent()
        let name = contactName.trimmingCharacters(in: .whitespaces).isEmpty ? "Contact" : contactName
        let label = d.label.isEmpty ? "Significant date" : d.label
        content.title = "\(label) — \(name)"
        content.body = body(label: label, name: name, lead: lead)
        content.sound = .default

        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        do { try await center.add(request); return .scheduled }
        catch { return .denied }
    }

    /// Cancel a significant date's pending notification (on delete).
    static func cancel(id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }

    private static func body(label: String, name: String, lead: Int) -> String {
        let when: String
        switch lead {
        case 0:      when = "is now"
        case 60:     when = "is in 1 hour"
        case 1_440:  when = "is tomorrow"
        case 10_080: when = "is in 1 week"
        default:
            if lead % 1_440 == 0 { when = "is in \(lead / 1_440) days" }
            else if lead % 60 == 0 { when = "is in \(lead / 60) hours" }
            else { when = "is in \(lead) minutes" }
        }
        return "\(label) for \(name) \(when)."
    }
}
