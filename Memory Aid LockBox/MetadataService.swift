//
//  MetadataService.swift
//  Memory Aid LockBox
//
//  Read + edit image metadata (roadmap 014a/b). The app PRESERVES all metadata:
//  imported media keeps its original bytes as-is (see PhotoLibraryService — no
//  re-encode), and it never auto-strips or auto-injects. This surface only acts
//  on DELIBERATE user edits, and an edit copies the source with every other tag
//  intact (only the changed keys differ).
//

import Foundation
import ImageIO

enum MetadataService {
    struct Section: Identifiable {
        let id = UUID()
        let title: String
        let rows: [Row]
    }
    struct Row: Identifiable {
        let id = UUID()
        let key: String
        let value: String
    }

    /// All readable metadata, grouped (top-level, EXIF, TIFF, GPS, …) for display.
    static func sections(from data: Data) -> [Section] {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any]
        else { return [] }

        var sections: [Section] = []

        let topRows = props.filter { !($0.value is [String: Any]) }
            .sorted { $0.key < $1.key }
            .map { Row(key: prettify($0.key), value: describe($0.value)) }
        if !topRows.isEmpty { sections.append(Section(title: "Image", rows: topRows)) }

        let subDicts: [(String, String)] = [
            (kCGImagePropertyExifDictionary as String, "EXIF"),
            (kCGImagePropertyTIFFDictionary as String, "TIFF"),
            (kCGImagePropertyGPSDictionary as String, "GPS"),
            (kCGImagePropertyIPTCDictionary as String, "IPTC"),
        ]
        for (dictKey, title) in subDicts {
            if let dict = props[dictKey] as? [String: Any], !dict.isEmpty {
                let rows = dict.sorted { $0.key < $1.key }
                    .map { Row(key: prettify($0.key), value: describe($0.value)) }
                sections.append(Section(title: title, rows: rows))
            }
        }
        return sections
    }

    // XMP homes for the three photo text tiers. dc:* is what Apple Photos reads
    // for Title/Caption; the full body lives in a private namespace so it's
    // unlimited and never collides with a standard field.
    private static let dcNamespace = "http://purl.org/dc/elements/1.1/" as CFString
    private static let dcPrefix = "dc" as CFString
    private static let bodyNamespace = "http://memoryaidlockbox.app/xmp/1.0/" as CFString
    private static let bodyPrefix = "malb" as CFString

    /// The title (XMP dc:title), caption (XMP dc:description), full body
    /// (XMP malb:body) and capture date (EXIF) embedded in the image. Falls back
    /// to IPTC/TIFF for title/caption so a photo tagged by another app still
    /// surfaces them.
    static func editableFields(from data: Data) -> (title: String, caption: String, body: String, date: Date?) {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return ("", "", "", nil) }

        var title = "", caption = "", body = ""
        if let meta = CGImageSourceCopyMetadataAtIndex(src, 0, nil) {
            if let t = CGImageMetadataCopyStringValueWithPath(meta, nil, "dc:title" as CFString) as String? { title = t }
            else if let t = CGImageMetadataCopyStringValueWithPath(meta, nil, "dc:title[1]" as CFString) as String? { title = t }
            if let c = CGImageMetadataCopyStringValueWithPath(meta, nil, "dc:description" as CFString) as String? { caption = c }
            else if let c = CGImageMetadataCopyStringValueWithPath(meta, nil, "dc:description[1]" as CFString) as String? { caption = c }
            if let b = CGImageMetadataCopyStringValueWithPath(meta, nil, "malb:body" as CFString) as String? { body = b }
        }

        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any]
        if title.isEmpty || caption.isEmpty {
            let iptc = props?[kCGImagePropertyIPTCDictionary as String] as? [String: Any]
            let tiff = props?[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
            if title.isEmpty { title = (iptc?[kCGImagePropertyIPTCObjectName as String] as? String) ?? "" }
            if caption.isEmpty {
                caption = (iptc?[kCGImagePropertyIPTCCaptionAbstract as String] as? String)
                    ?? (tiff?[kCGImagePropertyTIFFImageDescription as String] as? String) ?? ""
            }
        }

        var date: Date?
        if let exif = props?[kCGImagePropertyExifDictionary as String] as? [String: Any],
           let s = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String {
            let f = DateFormatter(); f.dateFormat = "yyyy:MM:dd HH:mm:ss"
            date = f.date(from: s)
        }
        return (title, caption, body, date)
    }

    /// Embed the three photo text tiers + capture date into the image, preserving
    /// every other tag (deliberate user edit only). Title → XMP dc:title, caption
    /// → XMP dc:description (both read by Apple Photos as Title/Caption), full body
    /// → XMP malb:body (private, unlimited). Written via CopyImageSource so the
    /// pixels are copied, not re-compressed. Returns new bytes, or nil if the data
    /// isn't an editable image.
    static func edit(data: Data, title: String?, caption: String?, body: String?, date: Date?) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(src)
        else { return nil }

        // Start from the existing metadata so nothing else is dropped.
        let meta = (CGImageSourceCopyMetadataAtIndex(src, 0, nil)).flatMap { CGImageMetadataCreateMutableCopy($0) }
            ?? CGImageMetadataCreateMutable()
        CGImageMetadataRegisterNamespaceForPrefix(meta, dcNamespace, dcPrefix, nil)
        CGImageMetadataRegisterNamespaceForPrefix(meta, bodyNamespace, bodyPrefix, nil)

        if let title {
            CGImageMetadataSetValueWithPath(meta, nil, "dc:title" as CFString, title as CFString)
        }
        if let caption {
            CGImageMetadataSetValueWithPath(meta, nil, "dc:description" as CFString, caption as CFString)
        }
        if let body {
            CGImageMetadataSetValueWithPath(meta, nil, "malb:body" as CFString, body as CFString)
        }
        if let date {
            let f = DateFormatter(); f.dateFormat = "yyyy:MM:dd HH:mm:ss"
            CGImageMetadataSetValueWithPath(meta, nil, "exif:DateTimeOriginal" as CFString, f.string(from: date) as CFString)
        }

        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, type, 1, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageDestinationMetadata: meta,
            kCGImageDestinationMergeMetadata: true,
        ]
        var err: Unmanaged<CFError>?
        guard CGImageDestinationCopyImageSource(dest, src, options as CFDictionary, &err) else { return nil }
        return out as Data
    }

    // MARK: - Formatting

    private static func prettify(_ key: String) -> String {
        key.replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
    }

    private static func describe(_ value: Any) -> String {
        if let array = value as? [Any] {
            return array.map { "\($0)" }.joined(separator: ", ")
        }
        return "\(value)"
    }
}
