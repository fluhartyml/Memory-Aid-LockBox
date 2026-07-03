//
//  View+ResizingTitle.swift
//  Memory Aid LockBox
//
//  Created by Michael Fluharty on 7/3/26.
//

import SwiftUI

extension View {
    /// A navigation title that **shrinks to fit** instead of truncating with an
    /// ellipsis. A UIKit navigation title only truncates — it never scales — so a
    /// long name like "Memory Aid Lockbox" or "Codes / Accounts" clips to
    /// "Memory Aid Loc…". This draws the title as a `Text` we control in the
    /// toolbar's principal (center) slot with `.minimumScaleFactor`, so it scales
    /// down to fit the available width. `.navigationTitle` is still set for the
    /// back-button label and VoiceOver.
    ///
    /// iOS only needs this — the Mac window is wide and doesn't truncate, and a
    /// principal item there would double the window title — so macOS keeps the
    /// standard `.navigationTitle`.
    @ViewBuilder
    func resizingNavigationTitle(_ title: String) -> some View {
        #if os(iOS)
        self
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
        #else
        self.navigationTitle(title)
        #endif
    }
}
