//
//  FeedbackView.swift
//  Memory Aid LockBox
//
//  Created by Michael Fluharty on 4/16/26.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
import MessageUI
#endif

struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var feedbackType = "Bug Report"
    @State private var feedbackText = ""
    @State private var showMailError = false

    let feedbackTypes = ["Bug Report", "Feature Request", "General Feedback"]

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    var deviceInfo: String {
        #if os(iOS)
        let device = UIDevice.current
        return """
        Device: \(device.model)
        System: \(device.systemName) \(device.systemVersion)
        App: Memory Aid Lockbox \(appVersion)
        """
        #else
        return "App: Memory Aid Lockbox \(appVersion) (macOS)"
        #endif
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $feedbackType) {
                        ForEach(feedbackTypes, id: \.self) { type in
                            Text(type)
                                .font(.system(size: 18))
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Feedback Type")
                        .font(.system(size: 16))
                }

                Section {
                    TextEditor(text: $feedbackText)
                        .font(.system(size: 18))
                        .frame(minHeight: 150)
                } header: {
                    Text("Details")
                        .font(.system(size: 16))
                }

                Section {
                    Text(deviceInfo)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Device Info (included automatically)")
                        .font(.system(size: 16))
                }
            }
            .resizingNavigationTitle("Send Feedback")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 18))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        sendFeedback()
                    }
                    .font(.system(size: 18, weight: .semibold))
                    .disabled(feedbackText.isEmpty)
                }
            }
            .alert("Cannot Send Email", isPresented: $showMailError) {
                Button("OK") {}
            } message: {
                Text("This device is not configured to send email. Please email michael.fluharty@mac.com directly.")
            }
        }
    }

    private func sendFeedback() {
        let subject = "Memory Aid Lockbox - \(feedbackType)"
        let body = """
        \(feedbackText)

        ---
        \(deviceInfo)
        """

        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let mailto = "mailto:michael.fluharty@mac.com?subject=\(encodedSubject)&body=\(encodedBody)"

        #if os(iOS)
        if let url = URL(string: mailto), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
            dismiss()
        } else {
            showMailError = true
        }
        #endif
    }
}
