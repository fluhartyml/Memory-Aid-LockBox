//
//  LockedFolderView.swift
//  Memory Aid LockBox
//
//  Shown in place of a protected folder's contents while it's locked, so no
//  thumbnails or items render until Face ID succeeds. It auto-prompts on appear
//  and calls `onUnlock` when authentication passes.
//

import SwiftUI
import SwiftData

struct LockedFolderView: View {
    let folder: Folder
    let onUnlock: () -> Void

    @State private var failed = false

    var body: some View {
        VStack(spacing: 24) {
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .accessibilityHidden(true)

            Text("\(folder.name) is locked")
                .font(.system(size: 24, weight: .bold))

            Text("Unlock with Face ID to view its contents.")
                .font(.system(size: 17))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if failed {
                Text("Authentication failed. Tap to try again.")
                    .font(.system(size: 15))
                    .foregroundStyle(.red)
            }

            Button {
                Task { await attempt() }
            } label: {
                Label("Unlock with Face ID", systemImage: "faceid")
                    .font(.system(size: 18, weight: .semibold))
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .task(id: folder.persistentModelID) { await attempt() }
    }

    private func attempt() async {
        let success = await BiometricAuthenticator.authenticate(reason: "Unlock \(folder.name)")
        if success {
            failed = false
            onUnlock()
        } else {
            failed = true
        }
    }
}
