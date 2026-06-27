//
//  LockScreenView.swift
//  Memory Aid LockBox
//
//  Created by Michael Fluharty on 4/16/26.
//

import SwiftUI
import LocalAuthentication

struct LockScreenView: View {
    @State private var isUnlocked = false
    @State private var authError: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        if isUnlocked {
            ContentView()
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .background {
                        isUnlocked = false
                    }
                }
        } else {
            VStack(spacing: 30) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue)

                Text("Memory Aid Lockbox")
                    .font(.system(size: 28, weight: .bold))

                Text("Tap to unlock")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)

                if let authError {
                    Text(authError)
                        .font(.system(size: 18))
                        .foregroundStyle(.red)
                }

                Button {
                    authenticate()
                } label: {
                    Label("Unlock with Face ID", systemImage: "faceid")
                        .font(.system(size: 20, weight: .semibold))
                        .padding(.horizontal, 30)
                        .padding(.vertical, 14)
                        .background(.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #if os(iOS)
            .background(Color(.systemBackground))
            #else
            .background(Color(NSColor.windowBackgroundColor))
            #endif
            .ignoresSafeArea()
            .onAppear {
                authenticate()
            }
        }
    }

    private func authenticate() {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Unlock your vault"
            ) { success, authenticationError in
                if success {
                    isUnlocked = true
                    authError = nil
                } else {
                    authError = "Authentication failed"
                }
            }
        } else {
            // No biometrics — fall back to device passcode
            if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
                context.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: "Unlock your vault"
                ) { success, _ in
                    if success {
                        isUnlocked = true
                        authError = nil
                    } else {
                        authError = "Authentication failed"
                    }
                }
            } else {
                // No auth available (simulator) — unlock directly
                isUnlocked = true
            }
        }
    }
}
