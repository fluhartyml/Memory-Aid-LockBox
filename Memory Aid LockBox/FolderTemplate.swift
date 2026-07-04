//
//  FolderTemplate.swift
//  Memory Aid LockBox
//
//  The template system (roadmap 001/002): each folder has a template that
//  decides which specialized entry sheet + default fields it uses. A NEW folder
//  picks a template; the built-in starter folders each map to one. Folders
//  created before templates existed have no stored template and INFER one from
//  their name, so there is no data migration and the live vault is untouched.
//

import Foundation

enum FolderTemplate: String, CaseIterable, Identifiable {
    case customNotes    // catch-all: Title · Notes · optional PIN/Code · photos (002a/008)
    case cards
    case codesAccounts
    case journal
    case contacts
    case receipts
    case appointments
    case photos         // the media library (MediaLibraryView), not an item list

    var id: String { rawValue }

    /// Shown in the New Folder template picker.
    var displayName: String {
        switch self {
        case .customNotes:   return "Custom / Notes"
        case .cards:         return "Cards"
        case .codesAccounts: return "Codes / Accounts"
        case .journal:       return "Journal"
        case .contacts:      return "Contacts"
        case .receipts:      return "Receipts"
        case .appointments:  return "Appointments"
        case .photos:        return "Photos"
        }
    }

    /// SF Symbol suggested when this template is chosen.
    var defaultIcon: String {
        switch self {
        case .customNotes:   return "note.text"
        case .cards:         return "creditcard.fill"
        case .codesAccounts: return "lock.fill"
        case .journal:       return "book.closed.fill"
        case .contacts:      return "person.crop.circle.fill"
        case .receipts:      return "doc.text.fill"
        case .appointments:  return "calendar"
        case .photos:        return "photo.fill"
        }
    }

    /// Templates offered when creating a new folder (roadmap 002a). Photos is a
    /// built-in media library with its own viewer, so it isn't offered here (no
    /// second media folder without that viewer).
    static var pickerChoices: [FolderTemplate] {
        [.customNotes, .cards, .codesAccounts, .journal, .contacts, .receipts, .appointments]
    }

    /// Legacy folders (no stored template) infer one from their name, matching
    /// the seeded starter-folder names, so the app behaves exactly as before.
    static func inferred(fromFolderName name: String) -> FolderTemplate {
        switch name {
        case "Cards":            return .cards
        case "Codes / Accounts": return .codesAccounts
        case "Photos":           return .photos
        case "Notes":            return .customNotes
        case "Journal":          return .journal
        case "Contacts":         return .contacts
        case "Receipts":         return .receipts
        case "Appointments":     return .appointments
        default:                 return .customNotes
        }
    }
}
