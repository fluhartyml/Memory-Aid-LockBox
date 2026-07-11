//
//  MediaViewerView.swift
//  Memory Aid LockBox
//
//  Full-screen viewer for a single vault item: zoomable photo or playable video.
//

import SwiftUI
import AVKit
#if canImport(UIKit)
import UIKit
#endif

struct MediaViewerView: View {
    @Bindable var asset: MediaAsset
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var hSize
    #endif

    /// Wide when there's room for a side panel — iPad, or an unfolded iPhone
    /// Fold. Narrow (folded iPhone / compact) stacks. Drives the fold-adaptive
    /// layout; see [[reference_iphone_fold_adaptive_layout]].
    private var isWide: Bool {
        #if os(iOS)
        return hSize == .regular
        #else
        return true
        #endif
    }

    // Page content for one asset. The enclosing MediaPagerView supplies the
    // NavigationStack, the Done button, and (on iOS) the swipe-between-photos paging.
    var body: some View {
        Group {
            if isWide {
                HStack(spacing: 0) {
                    // Left: photo, then Title/Caption/Body beneath it. The photo
                    // keeps the bulk of the height; the text block is bounded and
                    // scrolls when the body is long.
                    VStack(spacing: 0) {
                        mediaArea
                        Divider()
                        prominentTitleNotes
                            .frame(maxHeight: 360)
                    }
                    Divider()
                    // Right: capture date + read-only image/EXIF metadata.
                    MediaDetailsForm(asset: asset, mode: .metadataOnly)
                        .frame(width: 360)
                }
            } else {
                // Narrow: photo on top, everything inline below.
                VStack(spacing: 0) {
                    mediaArea
                        .frame(maxHeight: .infinity)
                    Divider()
                    MediaDetailsForm(asset: asset, mode: .all)
                        .frame(maxHeight: .infinity)
                }
            }
        }
    }

    /// Title, Caption, then Body — the full blog-style stack, shown directly under
    /// the photo in the wide layout. Scrolls when the body is long. Binds to asset.
    private var prominentTitleNotes: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Title", text: $asset.title)
                    .font(.system(size: 24, weight: .bold))
                    .textFieldStyle(.plain)
                TextField("Caption", text: $asset.caption, axis: .vertical)
                    .font(.system(size: 17))
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                Divider()
                TextField("Body", text: $asset.notes, axis: .vertical)
                    .font(.system(size: 16))
                    .textFieldStyle(.plain)
                    .lineLimit(4...)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        #if os(iOS)
        .background(Color(.secondarySystemBackground))
        #endif
    }

    /// The photo/video on black — details live in the adjacent panel now, so the
    /// info button is gone.
    private var mediaArea: some View {
        ZStack {
            Color.black
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: isWide ? [] : .bottom)
    }

    @ViewBuilder
    private var content: some View {
        if asset.mediaType == .video, let data = asset.data {
            VideoPlaybackView(data: data)
        } else if let data = asset.data {
            ZoomablePhotoView(data: data)
        } else {
            ContentUnavailableView("Media Unavailable", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Pager (swipe between photos)

/// Full-screen viewer that pages through a collection — swipe left/right on iOS,
/// prev/next arrows on macOS — starting at the tapped asset. Wraps MediaViewerView
/// pages in one NavigationStack + Done (Michael, 2026-07-11).
struct MediaPagerView: View {
    let assets: [MediaAsset]
    @State private var selection: UUID
    @Environment(\.dismiss) private var dismiss

    init(assets: [MediaAsset], current: MediaAsset) {
        self.assets = assets
        _selection = State(initialValue: current.id)
    }

    var body: some View {
        NavigationStack {
            pages
                .toolbar {
                    #if os(macOS)
                    ToolbarItemGroup(placement: .navigation) {
                        Button { step(-1) } label: { Image(systemName: "chevron.left") }
                            .disabled(!canStep(-1))
                        Button { step(1) } label: { Image(systemName: "chevron.right") }
                            .disabled(!canStep(1))
                    }
                    #endif
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }.font(.system(size: 18))
                    }
                }
        }
    }

    @ViewBuilder
    private var pages: some View {
        #if os(iOS)
        TabView(selection: $selection) {
            ForEach(assets) { asset in
                MediaViewerView(asset: asset).tag(asset.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        #else
        if let asset = assets.first(where: { $0.id == selection }) {
            MediaViewerView(asset: asset)
        } else {
            ContentUnavailableView("Media Unavailable", systemImage: "exclamationmark.triangle")
        }
        #endif
    }

    #if os(macOS)
    private var currentIndex: Int? { assets.firstIndex { $0.id == selection } }
    private func canStep(_ d: Int) -> Bool {
        guard let i = currentIndex else { return false }
        return assets.indices.contains(i + d)
    }
    private func step(_ d: Int) {
        guard let i = currentIndex, assets.indices.contains(i + d) else { return }
        selection = assets[i + d].id
    }
    #endif
}

// MARK: - Video

private struct VideoPlaybackView: View {
    let data: Data
    @State private var player: AVPlayer?
    @State private var tempURL: URL?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .onAppear { loadPlayer() }
        .onDisappear {
            player?.pause()
            if let tempURL { try? FileManager.default.removeItem(at: tempURL) }
        }
    }

    private func loadPlayer() {
        guard player == nil else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        do {
            try data.write(to: url)
            tempURL = url
            player = AVPlayer(url: url)
            player?.play()
        } catch {
            // Leave player nil; the spinner stays rather than crashing.
        }
    }
}

// MARK: - Photo (pinch / double-tap zoom)

private struct ZoomablePhotoView: View {
    let data: Data
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        #if canImport(UIKit)
        if let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .gesture(magnification)
                .simultaneousGesture(drag)
                .onTapGesture(count: 2) { toggleZoom() }
        } else {
            unavailable
        }
        #else
        if let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
        } else {
            unavailable
        }
        #endif
    }

    private var unavailable: some View {
        ContentUnavailableView("Image Unavailable", systemImage: "photo")
            .foregroundStyle(.white)
    }

    #if canImport(UIKit)
    private var magnification: some Gesture {
        MagnificationGesture()
            .onChanged { value in scale = lastScale * value }
            .onEnded { _ in
                lastScale = scale
                if scale < 1.0 { resetZoom() }
            }
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { value in
                if scale > 1.0 {
                    offset = CGSize(width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height)
                }
            }
            .onEnded { _ in lastOffset = offset }
    }

    private func toggleZoom() {
        withAnimation {
            if scale > 1.0 { resetZoom() }
            else { scale = 3.0; lastScale = 3.0 }
        }
    }

    private func resetZoom() {
        withAnimation {
            scale = 1.0; lastScale = 1.0; offset = .zero; lastOffset = .zero
        }
    }
    #endif
}
