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

    /// Number of editors currently on screen. While > 0 the idle auto-lock is
    /// suspended — filling out a card is activity, not idleness, and a re-lock
    /// mid-edit would eject the user and discard their unsaved entry.
    @ObservationIgnored private var activityHolds = 0

    /// Unlock every protected folder. `minutes == 0` means "Never auto-lock":
    /// stays unlocked until the app backgrounds or is closed. Otherwise it
    /// re-locks after `minutes`.
    func unlock(forMinutes minutes: Int) {
        isUnlocked = true
        relockTask?.cancel()
        relockTask = nil

        // An open editor suspends the countdown; it re-arms when the last one closes.
        guard minutes > 0, activityHolds == 0 else { return }

        let nanoseconds = UInt64(minutes) * 60 * 1_000_000_000
        relockTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            self?.isUnlocked = false
        }
    }

    /// Register an on-screen editor. Suspends the pending idle re-lock so the
    /// user is never kicked out (losing unsaved input) while actively entering data.
    func beginActivityHold() {
        activityHolds += 1
        relockTask?.cancel()
        relockTask = nil
    }

    /// Balance a `beginActivityHold`. When the last editor closes, restart the
    /// idle countdown from now with the current timeout.
    func endActivityHold(forMinutes minutes: Int) {
        activityHolds = max(0, activityHolds - 1)
        guard activityHolds == 0, isUnlocked else { return }
        unlock(forMinutes: minutes)
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
        activityHolds = 0
        isUnlocked = false
    }
}
