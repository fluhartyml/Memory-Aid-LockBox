//
//  ReceiptLogoCropper.swift
//  Memory Aid LockBox
//
//  Best-effort: pull a store logo out of a receipt image to use as the store
//  contact's photo (roadmap: receipt → Contacts handoff). Logos sit at the top
//  of a receipt, so we run Vision attention-saliency and take the most prominent
//  region whose center is in the upper part of the page; if saliency finds
//  nothing usable, we fall back to a square crop from the top-center. Returns
//  nil only when the image can't be decoded at all.
//

import Foundation
import Vision
import ImageIO
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum ReceiptLogoCropper {
    static func crop(from data: Data) async -> Data? {
        guard let cg = decode(data) else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)

        if let box = salientTopBox(cg) {
            let rect = CGRect(x: box.minX * w,
                              y: (1 - box.maxY) * h,   // Vision origin is bottom-left → flip
                              width: box.width * w,
                              height: box.height * h).integral
            if rect.width > 8, rect.height > 8, let cropped = cg.cropping(to: rect) {
                return encode(cropped)
            }
        }

        // Fallback: a square from the top-center, where a store logo usually sits.
        let side = min(w, h * 0.25)
        let rect = CGRect(x: (w - side) / 2, y: h * 0.02, width: side, height: side).integral
        if let cropped = cg.cropping(to: rect) { return encode(cropped) }
        return nil
    }

    /// The most confident salient region whose center is in the top ~45% of the
    /// receipt (that's where the logo lives), padded slightly. Normalized rect.
    private static func salientTopBox(_ cg: CGImage) -> CGRect? {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        try? handler.perform([request])
        guard let obs = request.results?.first as? VNSaliencyImageObservation,
              let objects = obs.salientObjects, !objects.isEmpty else { return nil }

        let top = objects.filter { $0.boundingBox.midY > 0.55 }   // upper part of the page
        guard let pick = (top.isEmpty ? objects : top).max(by: { $0.confidence < $1.confidence })
        else { return nil }

        let box = pick.boundingBox.insetBy(dx: -pick.boundingBox.width * 0.08,
                                           dy: -pick.boundingBox.height * 0.08)
        return box.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    // MARK: - Decode / encode

    #if canImport(UIKit)
    private static func decode(_ data: Data) -> CGImage? {
        guard let ui = UIImage(data: data) else { return nil }
        if ui.imageOrientation == .up { return ui.cgImage }
        let r = UIGraphicsImageRenderer(size: ui.size)
        return r.image { _ in ui.draw(in: CGRect(origin: .zero, size: ui.size)) }.cgImage
    }
    private static func encode(_ cg: CGImage) -> Data? {
        UIImage(cgImage: cg).jpegData(compressionQuality: 0.9)
    }
    #else
    private static func decode(_ data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
    private static func encode(_ cg: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: cg).representation(using: .jpeg, properties: [:])
    }
    #endif
}
