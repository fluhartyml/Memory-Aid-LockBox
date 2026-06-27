//
//  ContinuityCameraScanner.swift
//  Memory Aid Lockbox
//
//  macOS-only Continuity Camera support. On the Mac, the scanner is surfaced
//  through the File menu (ImportFromDevicesCommands in the App scene) — the same
//  place Apple's own apps put "Import from iPhone or iPad → Scan Documents /
//  Take Photo". A view declares it accepts the result with .importsItemProviders,
//  and the captured data arrives here as NSItemProviders.
//
//  A "Scan Documents" capture is a multi-page PDF; we render each page to a PNG
//  so the result matches how VaultItem stores images (imageData: [Data]).
//

#if os(macOS)
import AppKit
import PDFKit
import UniformTypeIdentifiers

enum ContinuityScanImport {
    /// Convert Continuity Camera item providers (PDF scans or photos) to per-page PNGs.
    static func pngPages(from providers: [NSItemProvider]) async -> [Data] {
        var pages: [Data] = []
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier),
               let data = await loadData(provider, type: UTType.pdf.identifier),
               let pdf = PDFDocument(data: data) {
                for index in 0..<pdf.pageCount {
                    if let page = pdf.page(at: index), let png = png(from: page) {
                        pages.append(png)
                    }
                }
            } else if let data = await loadImageData(provider),
                      let image = NSImage(data: data),
                      let png = png(from: image) {
                pages.append(png)
            }
        }
        return pages
    }

    private static func loadData(_ provider: NSItemProvider, type: String) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private static func loadImageData(_ provider: NSItemProvider) async -> Data? {
        for type in [UTType.png.identifier, UTType.tiff.identifier,
                     UTType.jpeg.identifier, UTType.image.identifier] {
            if provider.hasItemConformingToTypeIdentifier(type),
               let data = await loadData(provider, type: type) {
                return data
            }
        }
        return nil
    }

    private static func png(from page: PDFPage) -> Data? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let image = NSImage(size: bounds.size)
        image.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(CGRect(origin: .zero, size: bounds.size))
            page.draw(with: .mediaBox, to: ctx)
        }
        image.unlockFocus()
        return png(from: image)
    }

    private static func png(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
#endif
