//
//  MediaAsset.swift
//  Memory Aid LockBox
//
//  A single photo or video that lives INSIDE the vault — independent of
//  Apple Photos. The raw bytes are kept in external file storage (not inline
//  in the database) so the library scales to videos. Every stored property is
//  defaulted/optional and there are no unique constraints, so this model is
//  ready to mirror to CloudKit once the iCloud container is provisioned.
//

import Foundation
import SwiftData

enum MediaType: String, Codable {
    case photo
    case video
}

@Model
final class MediaAsset {
    var id: UUID = UUID()
    var typeRaw: String = MediaType.photo.rawValue
    var dateImported: Date = Date()
    var dateCaptured: Date = Date()
    var originalFileName: String = ""
    /// Video length in seconds; 0 for photos.
    var durationSeconds: Double = 0

    /// The full-resolution media bytes, stored as an external file by SwiftData.
    @Attribute(.externalStorage)
    var data: Data?

    /// A small JPEG used in the grid so we never decode full media for tiles.
    @Attribute(.externalStorage)
    var thumbnailData: Data?

    var folder: Folder?

    var mediaType: MediaType {
        get { MediaType(rawValue: typeRaw) ?? .photo }
        set { typeRaw = newValue.rawValue }
    }

    init(type: MediaType,
         data: Data?,
         thumbnailData: Data?,
         originalFileName: String = "",
         dateCaptured: Date = Date(),
         durationSeconds: Double = 0,
         folder: Folder? = nil) {
        self.id = UUID()
        self.typeRaw = type.rawValue
        self.data = data
        self.thumbnailData = thumbnailData
        self.originalFileName = originalFileName
        self.dateImported = Date()
        self.dateCaptured = dateCaptured
        self.durationSeconds = durationSeconds
        self.folder = folder
    }
}
