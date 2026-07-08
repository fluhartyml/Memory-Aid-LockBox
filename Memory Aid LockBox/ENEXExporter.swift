//
//  ENEXExporter.swift
//  Memory Aid LockBox
//
//  Evernote .enex export — the ONE format Apple Notes imports with inline images
//  (Notes → File → Import to Notes…). Kept as a fully self-contained, parallel
//  module ON PURPOSE: nothing else in the app depends on it, it only reads
//  JournalExporter.Entry and returns a file URL. If Evernote ever restricts the
//  format, drop this file plus its one button + one call in ItemListView and the
//  Markdown/PDF exports are entirely unaffected.
//
//  .enex is plain XML: each note's body is XHTML (ENML); images are base64
//  <resource> blocks, linked from the body by an <en-media> tag whose `hash` is
//  the MD5 of the raw image bytes. That MD5 link is what makes photos survive the
//  Apple Notes import.
//

import Foundation
import CryptoKit

enum ENEXExporter {
    /// Build a .enex file for the given journal entries. Returns its URL, or nil
    /// on write failure.
    static func export(folderName: String, entries: [JournalExporter.Entry]) -> URL? {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        df.dateFormat = "yyyyMMdd'T'HHmmss'Z'"

        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE en-export SYSTEM "http://xml.evernote.com/pub/evernote-export4.dtd">
        <en-export application="Memory Aid LockBox" version="1.0">

        """

        for e in entries {
            let stamp = df.string(from: e.date)

            // ENML note body: escaped text (newlines → <br/>) then each image as
            // an <en-media> tag keyed to its resource by MD5.
            var note = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
            note += "<!DOCTYPE en-note SYSTEM \"http://xml.evernote.com/pub/enml2.dtd\">\n"
            note += "<en-note><div>\(escape(e.body).replacingOccurrences(of: "\n", with: "<br/>"))</div>"

            var resources = ""
            for img in e.images {
                let hash = md5Hex(img)
                note += "<div><en-media type=\"image/jpeg\" hash=\"\(hash)\"/></div>"
                let b64 = img.base64EncodedString(options: [.lineLength76Characters, .endLineWithLineFeed])
                resources += "<resource><data encoding=\"base64\">\(b64)</data>"
                resources += "<mime>image/jpeg</mime></resource>"
            }
            note += "</en-note>"

            xml += "<note>"
            xml += "<title>\(escape(e.title.isEmpty ? "Untitled Entry" : e.title))</title>"
            xml += "<content><![CDATA[\(note)]]></content>"
            xml += "<created>\(stamp)</created><updated>\(stamp)</updated>"
            xml += resources
            xml += "</note>\n"
        }
        xml += "</en-export>\n"

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safe(folderName)).enex")
        try? FileManager.default.removeItem(at: url)
        guard let data = xml.data(using: .utf8), (try? data.write(to: url)) != nil else { return nil }
        return url
    }

    private static func md5Hex(_ data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func safe(_ s: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r\t")
        return s.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
    }
}
