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

    /// The current image description (TIFF) and capture date (EXIF), for editing.
    static func editableFields(from data: Data) -> (description: String, date: Date?) {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any]
        else { return ("", nil) }
        let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any]
        let desc = (tiff?[kCGImagePropertyTIFFImageDescription as String] as? String) ?? ""
        var date: Date?
        if let s = exif?[kCGImagePropertyExifDateTimeOriginal as String] as? String {
            let f = DateFormatter(); f.dateFormat = "yyyy:MM:dd HH:mm:ss"
            date = f.date(from: s)
        }
        return (desc, date)
    }

    /// Write a new description / capture date into the image, preserving every
    /// other tag (deliberate user edit only — roadmap 014b). Returns new bytes,
    /// or nil if the data isn't an editable image.
    static func edit(data: Data, description: String?, date: Date?) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(src)
        else { return nil }

        var props = (CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any]) ?? [:]

        if let description {
            var tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
            tiff[kCGImagePropertyTIFFImageDescription as String] = description
            props[kCGImagePropertyTIFFDictionary as String] = tiff
        }
        if let date {
            let f = DateFormatter(); f.dateFormat = "yyyy:MM:dd HH:mm:ss"
            var exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
            exif[kCGImagePropertyExifDateTimeOriginal as String] = f.string(from: date)
            props[kCGImagePropertyExifDictionary as String] = exif
        }

        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, type, 1, nil) else { return nil }
        CGImageDestinationAddImageFromSource(dest, src, 0, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
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
