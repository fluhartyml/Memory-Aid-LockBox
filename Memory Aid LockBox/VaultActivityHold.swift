//
//  VaultActivityHold.swift
//  Memory Aid LockBox
//
//  A view modifier that holds the vault's idle auto-lock open for as long as an
//  editor is on screen. Applied to every create/edit sheet so the auto-lock —
//  which is an *idle* timeout — never fires mid-entry and discards unsaved work.
//  Backgrounding the app still locks immediately (see VaultLock.lockNow()).
//

import SwiftUI

private struct VaultActivityHold: ViewModifier {
    @Environment(VaultLock.self) private var vaultLock
    @AppStorage("autoLockMinutes") private var autoLockMinutes = 5

    func body(content: Content) -> some View {
        content
            .onAppear { vaultLock.beginActivityHold() }
            .onDisappear { vaultLock.endActivityHold(forMinutes: autoLockMinutes) }
    }
}

extension View {
    /// Suspend the vault's idle auto-lock while this editor is on screen.
    func holdsVaultActivity() -> some View {
        modifier(VaultActivityHold())
    }
}
