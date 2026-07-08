//
//  JournalExporter.swift
//  Memory Aid LockBox
//
//  Exports a Journal folder in two portable formats (roadmap 009 + Michael 7/6):
//   • Markdown — one .md per entry with YAML front-matter + an attachments/
//     subfolder for header images (relative-linked). This is an Obsidian vault
//     and imports cleanly into Ghost/WordPress/Jekyll/Hugo/Pages. Delivered as a
//     .zip so the whole folder travels through the share sheet.
//   • PDF — a rendered, non-editable copy that opens and prints anywhere (the
//     "at minimum" format).
//
//  Both hand back a file URL for the system share sheet (iOS) / Finder (macOS).
//

import Foundation
import SwiftUI

enum JournalExporter {
    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let title: String
        let body: String
        let images: [Data]   // hero first, then the rest of the entry's attachments
    }

    private static var posix: Locale { Locale(identifier: "en_US_POSIX") }

    /// "YYYY MMM DD HH:MM:SS {Title}" — mirrors Michael's archive convention.
    static func label(for date: Date, title: String) -> String {
        let f = DateFormatter()
        f.locale = posix
        f.dateFormat = "yyyy MMM dd HH:mm:ss"
        let stamp = f.string(from: date)
        return title.isEmpty ? stamp : "\(stamp) \(title)"
    }

    // MARK: - Markdown archive (.zip)

    static func markdownArchive(folderName: String, entries: [Entry]) -> URL? {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("JournalMD-\(UUID().uuidString)", isDirectory: true)
        let vault = root.appendingPathComponent(safe(folderName), isDirectory: true)
        let attachments = vault.appendingPathComponent("attachments", isDirectory: true)

        let iso = DateFormatter(); iso.locale = posix; iso.dateFormat = "yyyy-MM-dd HH:mm:ss"

        do {
            try fm.createDirectory(at: vault, withIntermediateDirectories: true)
            var madeAttachments = false

            for (i, e) in entries.enumerated() {
                let base = safe(label(for: e.date, title: e.title))
                let fileBase = base.isEmpty ? "entry-\(i)" : base

                var md = "---\ntitle: \(yaml(e.title))\ndate: \(iso.string(from: e.date))\n---\n\n\(e.body)\n"
                // Every image for this entry: hero as "{base}.jpg", the rest as
                // "{base}-2.jpg", "{base}-3.jpg"… all linked inline, hero first.
                for (j, img) in e.images.enumerated() {
                    if !madeAttachments {
                        try fm.createDirectory(at: attachments, withIntermediateDirectories: true)
                        madeAttachments = true
                    }
                    let imgName = j == 0 ? "\(fileBase).jpg" : "\(fileBase)-\(j + 1).jpg"
                    try img.write(to: attachments.appendingPathComponent(imgName))
                    md += "\n![](attachments/\(imgName))\n"
                }
                try md.data(using: .utf8)?.write(to: vault.appendingPathComponent("\(fileBase).md"))
            }
            return zip(folder: vault, named: safe(folderName))
        } catch {
            return nil
        }
    }

    /// Zip a folder with NSFileCoordinator's `.forUploading` — built in, no libs.
    private static func zip(folder: URL, named name: String) -> URL? {
        var result: URL?
        var err: NSError?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: [.forUploading], error: &err) { tempZip in
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).zip")
            try? FileManager.default.removeItem(at: dest)
            if (try? FileManager.default.copyItem(at: tempZip, to: dest)) != nil {
                result = dest
            }
        }
        return result
    }

    // MARK: - PDF

    @MainActor
    static func pdf(folderName: String, entries: [Entry]) -> URL? {
        let doc = JournalPDFDocument(folderName: folderName, entries: entries).frame(width: 612)
        let renderer = ImageRenderer(content: doc)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe(folderName)).pdf")
        try? FileManager.default.removeItem(at: url)

        var produced = false
        renderer.render { size, renderInContext in
            var box = CGRect(origin: .zero, size: size)
            guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            ctx.beginPDFPage(nil)
            renderInContext(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
            produced = true
        }
        return produced ? url : nil
    }

    // MARK: - Helpers

    private static func safe(_ s: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r\t")
        let cleaned = s.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        return cleaned
    }

    private static func yaml(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

/// The printed journal — white page, black text, one entry after another.
private struct JournalPDFDocument: View {
    let folderName: String
    let entries: [JournalExporter.Entry]

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text(folderName)
                .font(.system(size: 28, weight: .bold))
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 8) {
                    Text(JournalExporter.label(for: entry.date, title: ""))
                        .font(.system(size: 12))
                        .foregroundStyle(.gray)
                    Text(entry.title.isEmpty ? "Untitled Entry" : entry.title)
                        .font(.system(size: 20, weight: .semibold))
                    ForEach(Array(entry.images.enumerated()), id: \.offset) { _, data in
                        entryImage(data)
                    }
                    Text(entry.body)
                        .font(.system(size: 13))
                    Divider()
                }
            }
        }
        .padding(36)
        .frame(width: 612, alignment: .leading)
        .background(Color.white)
        .foregroundStyle(Color.black)
    }

    @ViewBuilder
    private func entryImage(_ data: Data) -> some View {
        #if canImport(UIKit)
        if let ui = UIImage(data: data) {
            Image(uiImage: ui).resizable().scaledToFit().frame(maxWidth: 400, maxHeight: 300, alignment: .leading)
        }
        #else
        if let ns = NSImage(data: data) {
            Image(nsImage: ns).resizable().scaledToFit().frame(maxWidth: 400, maxHeight: 300, alignment: .leading)
        }
        #endif
    }
}

#if os(iOS)
import UIKit

/// Shares exported file URLs (the Markdown .zip or the PDF) via the system sheet.
struct FileShareSheet: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
#endif
