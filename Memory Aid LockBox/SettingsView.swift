//
//  SettingsView.swift
//  Memory Aid LockBox
//
//  App preferences. First control is the global auto-lock timeout for protected
//  folders. Reaching this screen is itself gated behind a Face ID challenge
//  (handled by the caller), since it governs the vault's security.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("autoLockMinutes") private var autoLockMinutes = 5
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Auto-lock after", selection: $autoLockMinutes) {
                        Text("Never").tag(0)
                        Text("1 minute").tag(1)
                        Text("5 minutes").tag(5)
                        Text("15 minutes").tag(15)
                        Text("30 minutes").tag(30)
                        Text("1 hour").tag(60)
                    }

                    Stepper(value: $autoLockMinutes, in: 0...240) {
                        Text(autoLockMinutes == 0
                             ? "Custom: Never"
                             : "Custom: \(autoLockMinutes) min")
                    }
                } header: {
                    Text("Security")
                } footer: {
                    Text("Protected folders re-lock this long after you unlock them, and you'll be returned to the folder list. \"Never\" keeps them unlocked until the app is closed or sent to the background.")
                }

                Section {
                    NavigationLink {
                        QuickTagsEditorView()
                    } label: {
                        Label("Quick interaction tags", systemImage: "bolt.badge.clock")
                    }
                } header: {
                    Text("Contacts")
                } footer: {
                    Text("Customize the one-tap buttons (Called, Texted, Emailed, Met…) in a contact's Interactions log — add your own, change icons, or reorder.")
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
