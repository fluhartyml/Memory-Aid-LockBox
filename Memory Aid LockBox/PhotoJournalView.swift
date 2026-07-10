//
//  PhotoJournalView.swift
//  Memory Aid LockBox
//
//  A curated photo album (template .photoJournal). Unlike the master Photos
//  library (a grid it OWNS), a journal owns nothing — it holds an ordered list
//  of references (Folder.journalAssetIDs) to MediaAssets owned by the master
//  Photos folder, shown as a one-column list: thumbnail + title + caption per
//  row. Tap a row to open the photo full-screen and edit its title/caption
//  (the same MediaViewerView the master library uses). Removing a row or
//  deleting the journal never deletes the photo from master.
//
//  Add flows (Take Picture / Import / Add-from-master) and the master "Add to
//  Photo Journal" push flow land in later chunks.
//

import SwiftUI
import SwiftData

struct PhotoJournalView: View {
    let folder: Folder
    @Query private var allAssets: [MediaAsset]

    @State private var viewerAsset: MediaAsset?

    /// The journal's referenced photos, resolved from the master library and
    /// kept in the journal's stored order. References whose photo no longer
    /// exists in master (deleted there) are skipped gracefully.
    private var assets: [MediaAsset] {
        let byID = Dictionary(allAssets.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return folder.journalAssetIDs.compactMap { byID[$0] }
    }

    var body: some View {
        content
            .resizingNavigationTitle(folder.name)
            #if os(iOS)
            .fullScreenCover(item: $viewerAsset) { MediaViewerView(asset: $0) }
            #else
            .sheet(item: $viewerAsset) { MediaViewerView(asset: $0).frame(minWidth: 600, minHeight: 600) }
            #endif
    }

    @ViewBuilder
    private var content: some View {
        if assets.isEmpty {
            ContentUnavailableView {
                Label {
                    Text("No Photos Yet")
                } icon: {
                    Image(systemName: "photo.stack")
                }
            } description: {
                Text("This journal will hold a curated set of photos. Add some to get started.")
            }
        } else {
            List {
                ForEach(assets) { asset in
                    row(asset)
                        .contentShape(Rectangle())
                        .onTapGesture { viewerAsset = asset }
                }
            }
            #if os(macOS)
            .listStyle(.inset)
            #endif
        }
    }

    private func row(_ asset: MediaAsset) -> some View {
        HStack(spacing: 12) {
            MediaThumbnailImage(data: asset.thumbnailData ?? asset.data)
                .aspectRatio(1, contentMode: .fill)
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(asset.title.isEmpty ? "Untitled" : asset.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(asset.title.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                if !asset.caption.isEmpty {
                    Text(asset.caption)
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
