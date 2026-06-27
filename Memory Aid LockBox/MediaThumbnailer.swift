//
//  MediaThumbnailer.swift
//  Memory Aid LockBox
//
//  Generates small grid thumbnails and reads video metadata. Keeping this in
//  one place means the grid never has to decode full-resolution media.
//

import Foundation
import AVFoundation
import CoreGraphics
#if canImport(UIKit)
import UIKit
#endif

enum MediaThumbnailer {
    /// Longest-edge size for grid thumbnails.
    static let maxThumbDimension: CGFloat = 400

    // MARK: - Photos

    #if canImport(UIKit)
    static func photoThumbnail(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return image.downscaled(maxDimension: maxThumbDimension)
            .jpegData(compressionQuality: 0.7)
    }
    #else
    static func photoThumbnail(from data: Data) -> Data? {
        guard let image = NSImage(data: data) else { return nil }
        return image.jpegThumbnail(maxDimension: maxThumbDimension)
    }
    #endif

    // MARK: - Videos

    /// A poster frame near the start of the video.
    static func videoThumbnail(fileURL: URL) async -> Data? {
        let asset = AVURLAsset(url: fileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxThumbDimension, height: maxThumbDimension)
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        guard let result = try? await generator.image(at: time) else { return nil }
        return jpegData(from: result.image)
    }

    static func videoDuration(fileURL: URL) async -> Double {
        let asset = AVURLAsset(url: fileURL)
        guard let duration = try? await asset.load(.duration) else { return 0 }
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite ? seconds : 0
    }

    // MARK: - CGImage → JPEG

    private static func jpegData(from cgImage: CGImage) -> Data? {
        #if canImport(UIKit)
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.7)
        #else
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
        #endif
    }
}

// MARK: - Platform image downscaling

#if canImport(UIKit)
private extension UIImage {
    func downscaled(maxDimension: CGFloat) -> UIImage {
        let longestSide = max(size.width, size.height)
        guard longestSide > maxDimension else { return self }
        let scale = maxDimension / longestSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
#else
import AppKit
private extension NSImage {
    func jpegThumbnail(maxDimension: CGFloat) -> Data? {
        guard let tiff = tiffRepresentation,
              let source = NSBitmapImageRep(data: tiff) else { return nil }
        return source.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
    }
}
#endif
