//
//  VaultLock.swift
//  Memory Aid LockBox
//
//  Shared lock state for folders marked `requiresAuth`. A successful Face ID
//  unlocks every protected folder for the timeout window (one scan, not folder
//  by folder). When the window elapses it re-locks, which the UI uses to eject
//  the user back to the folder list. Backgrounding the app re-locks immediately.
//

import Foundation
import Observation

@MainActor
@Observable
final class VaultLock {
    /// True while protected folders are unlocked (inside the timeout window).
    private(set) var isUnlocked = false

    @ObservationIgnored private var relockTask: Task<Void, Never>?

    /// Unlock every protected folder. `minutes == 0` means "Never auto-lock":
    /// stays unlocked until the app backgrounds or is closed. Otherwise it
    /// re-locks after `minutes`.
    func unlock(forMinutes minutes: Int) {
        isUnlocked = true
        relockTask?.cancel()
        relockTask = nil

        guard minutes > 0 else { return }

        let nanoseconds = UInt64(minutes) * 60 * 1_000_000_000
        relockTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            self?.isUnlocked = false
        }
    }

    /// Re-arm the auto-lock window with a new timeout — e.g. the user changed
    /// the setting mid-session. Restarts the countdown from now with the new
    /// duration. No-op while the vault is locked (the next unlock uses it).
    func reschedule(forMinutes minutes: Int) {
        guard isUnlocked else { return }
        unlock(forMinutes: minutes)
    }

    /// Re-lock right now (app backgrounded, or any manual lock).
    func lockNow() {
        relockTask?.cancel()
        relockTask = nil
        isUnlocked = false
    }
}
