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
    let asset: MediaAsset
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                content
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 18))
                }
            }
            #if os(iOS)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            #endif
        }
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
