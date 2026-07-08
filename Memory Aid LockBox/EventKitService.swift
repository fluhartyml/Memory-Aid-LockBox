//
//  EventKitService.swift
//  Memory Aid LockBox
//
//  One shared EventKit surface for every "push to Apple Calendar / Reminders"
//  action in the app (roadmap 019 appointments · 010b significant dates · 012/013
//  receipt grocery lists). Uses the iOS 17+/macOS 14+ full-access requests. All
//  writes are explicit, one-shot exports the user taps — the app never syncs or
//  reads back.
//

import Foundation
import EventKit
import CoreLocation

enum EventKitService {
    static let store = EKEventStore()

    // MARK: - Access

    static func requestCalendar() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    static func requestReminders() async -> Bool {
        (try? await store.requestFullAccessToReminders()) ?? false
    }

    // MARK: - Calendar events

    /// Add a calendar event. A non-empty `prep` note adds a day-before alarm and
    /// is written into the event notes. Returns false if access is denied or the
    /// save fails.
    @discardableResult
    static func addEvent(title: String,
                         date: Date,
                         durationMinutes: Int = 60,
                         notes: String = "",
                         location: String = "",
                         prep: String = "",
                         annualRecurring: Bool = false) async -> Bool {
        guard await requestCalendar() else { return false }
        let event = EKEvent(eventStore: store)
        event.title = title.isEmpty ? "Appointment" : title
        event.startDate = date
        event.endDate = date.addingTimeInterval(TimeInterval(durationMinutes * 60))
        event.calendar = store.defaultCalendarForNewEvents

        var noteParts: [String] = []
        if !prep.isEmpty { noteParts.append("Prep: \(prep)") }
        if !notes.isEmpty { noteParts.append(notes) }
        if !noteParts.isEmpty { event.notes = noteParts.joined(separator: "\n\n") }
        if !location.isEmpty { event.location = location }

        if !prep.isEmpty { event.addAlarm(EKAlarm(relativeOffset: -86_400)) } // 1 day before
        event.addAlarm(EKAlarm(relativeOffset: -3_600))                        // 1 hour before

        if annualRecurring {
            event.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil))
        }

        do { try store.save(event, span: .thisEvent, commit: true); return true }
        catch { return false }
    }

    // MARK: - Reminders

    /// Add a single reminder, optionally due at a date and/or with an arrive-here
    /// location alarm (used by the receipt grocery list, roadmap 013a).
    @discardableResult
    static func addReminder(title: String,
                            due: Date? = nil,
                            notes: String = "",
                            listName: String? = nil,
                            location: CLLocationCoordinate2D? = nil,
                            locationTitle: String = "") async -> Bool {
        guard await requestReminders() else { return false }
        guard let calendar = reminderList(named: listName) else { return false }
        let reminder = makeReminder(title: title, due: due, notes: notes,
                                    calendar: calendar, location: location, locationTitle: locationTitle)
        do { try store.save(reminder, commit: true); return true }
        catch { return false }
    }

    /// Create a NEW reminders list and add every item to it (roadmap 013 — one
    /// list per receipt). An optional arrive-here location alarm fires the whole
    /// list when you reach the store (roadmap 013a).
    @discardableResult
    static func addReminderList(named name: String,
                                items: [String],
                                location: CLLocationCoordinate2D? = nil,
                                locationTitle: String = "") async -> Bool {
        guard await requestReminders() else { return false }
        let source = store.defaultCalendarForNewReminders()?.source
            ?? store.sources.first(where: { $0.sourceType == .local })
            ?? store.sources.first
        guard let source else { return false }

        let list = EKCalendar(for: .reminder, eventStore: store)
        list.title = name
        list.source = source
        do { try store.saveCalendar(list, commit: true) } catch { return false }

        for item in items where !item.trimmingCharacters(in: .whitespaces).isEmpty {
            let reminder = makeReminder(title: item, due: nil, notes: "",
                                        calendar: list, location: location, locationTitle: locationTitle)
            try? store.save(reminder, commit: false)
        }
        do { try store.commit(); return true } catch { return false }
    }

    // MARK: - Private

    private static func reminderList(named name: String?) -> EKCalendar? {
        if let name, !name.isEmpty {
            let list = EKCalendar(for: .reminder, eventStore: store)
            list.title = name
            list.source = store.defaultCalendarForNewReminders()?.source
                ?? store.sources.first(where: { $0.sourceType == .local })
                ?? store.sources.first
            if list.source != nil, (try? store.saveCalendar(list, commit: true)) != nil {
                return list
            }
        }
        return store.defaultCalendarForNewReminders()
    }

    private static func makeReminder(title: String,
                                     due: Date?,
                                     notes: String,
                                     calendar: EKCalendar,
                                     location: CLLocationCoordinate2D?,
                                     locationTitle: String) -> EKReminder {
        let reminder = EKReminder(eventStore: store)
        reminder.title = title.isEmpty ? "Reminder" : title
        reminder.calendar = calendar
        if !notes.isEmpty { reminder.notes = notes }
        if let due {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: due)
        }
        if let location {
            let structured = EKStructuredLocation(title: locationTitle.isEmpty ? "Store" : locationTitle)
            structured.geoLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
            structured.radius = 100   // meters — explicit geofence so "arriving" actually fires (default 0 is unreliable)
            let alarm = EKAlarm()
            alarm.structuredLocation = structured
            alarm.proximity = .enter
            reminder.addAlarm(alarm)

            // A reminder that carries an alarm but no date makes EventKit warn
            // that the trigger is an undefined "duration" alarm. Anchor it with a
            // START date (not a due date) so the trigger is well-defined — a start
            // date shows no notification on its own, so the location alarm stays
            // the only thing that fires.
            if reminder.dueDateComponents == nil {
                reminder.startDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day], from: due ?? Date())
            }
        }
        return reminder
    }
}
