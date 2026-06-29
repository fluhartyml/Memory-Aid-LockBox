//
//  BiometricAuthenticator.swift
//  Memory Aid LockBox
//
//  One place for Face ID / Touch ID challenges, so the app-entry lock, the
//  per-folder locks, and the Settings gate all behave the same way.
//

import LocalAuthentication

enum BiometricAuthenticator {
    /// Prompts for Face ID / Touch ID (falling back to the device passcode).
    /// Returns true on success. If the device has no biometrics or passcode at
    /// all (e.g. a bare simulator), returns true rather than hard-blocking — the
    /// app-entry lock is the backstop in that case.
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            return await evaluate(context, policy: .deviceOwnerAuthenticationWithBiometrics, reason: reason)
        }
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            return await evaluate(context, policy: .deviceOwnerAuthentication, reason: reason)
        }
        return true
    }

    private static func evaluate(_ context: LAContext, policy: LAPolicy, reason: String) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            context.evaluatePolicy(policy, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}
