//
//  DocumentScannerMac.swift
//  Memory Aid Lockbox
//
//  macOS-only USB / network scanner support via ImageCaptureCore (the same
//  framework Image Capture and the Printers & Scanners panel use). Browses for
//  connected scanners, scans the selected one, and returns per-page PNGs to
//  match VaultItem.imageData.
//
//  NOTE: the scan path is UNVERIFIED at runtime — it compiles against the real
//  ImageCaptureCore API but has not been exercised with a physical scanner.
//

#if os(macOS)
import SwiftUI
import Combine
import ImageCaptureCore
import AppKit
import UniformTypeIdentifiers

@MainActor
final class ScannerModel: NSObject, ObservableObject {
    @Published var scanners: [ICScannerDevice] = []
    @Published var status = "Looking for scanners…"
    @Published var isScanning = false

    private let browser = ICDeviceBrowser()
    private var active: ICScannerDevice?
    private var scannedURLs: [URL] = []
    var onScanned: (([Data]) -> Void)?

    override init() {
        super.init()
        browser.delegate = self
        let mask = ICDeviceTypeMask.scanner.rawValue
            | ICDeviceLocationTypeMask.local.rawValue
            | ICDeviceLocationTypeMask.shared.rawValue
            | ICDeviceLocationTypeMask.bonjour.rawValue
        browser.browsedDeviceTypeMask = ICDeviceTypeMask(rawValue: mask)!
        browser.start()
    }

    func stop() {
        active?.requestCloseSession()
        browser.stop()
    }

    func scan(_ device: ICScannerDevice) {
        status = "Connecting…"
        isScanning = true
        scannedURLs = []
        active = device
        device.delegate = self
        device.requestOpenSession()
    }

    private func selectUnit(_ scanner: ICScannerDevice) {
        let types = scanner.availableFunctionalUnitTypes.compactMap {
            ICScannerFunctionalUnitType(rawValue: $0.uintValue)
        }
        let wanted: ICScannerFunctionalUnitType
        if types.contains(.flatbed) { wanted = .flatbed }
        else if types.contains(.documentFeeder) { wanted = .documentFeeder }
        else { wanted = types.first ?? .flatbed }
        scanner.requestSelect(wanted)   // async -> scannerDevice(_:didSelect:error:)
    }

    private func startScan(_ scanner: ICScannerDevice) {
        let unit = scanner.selectedFunctionalUnit
        unit.measurementUnit = .inches
        if unit.supportedResolutions.contains(300) { unit.resolution = 300 }
        unit.pixelDataType = .RGB
        unit.bitDepth = .depth8Bits
        if let flatbed = unit as? ICScannerFunctionalUnitFlatbed {
            unit.scanArea = NSRect(origin: .zero, size: flatbed.physicalSize)
        } else if let feeder = unit as? ICScannerFunctionalUnitDocumentFeeder {
            unit.scanArea = NSRect(origin: .zero, size: feeder.physicalSize)
        }
        scanner.transferMode = .fileBased
        scanner.downloadsDirectory = FileManager.default.temporaryDirectory
        scanner.documentName = "MemoryAidScan"
        scanner.documentUTI = UTType.png.identifier
        status = "Scanning…"
        scanner.requestScan()
    }

    private func finish() {
        isScanning = false
        let pages: [Data] = scannedURLs.compactMap { url in
            guard let image = NSImage(contentsOf: url),
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff) else { return nil }
            return rep.representation(using: .png, properties: [:])
        }
        active?.requestCloseSession()
        if pages.isEmpty {
            status = "No pages scanned."
        } else {
            onScanned?(pages)
        }
    }
}

extension ScannerModel: ICDeviceBrowserDelegate {
    nonisolated func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        guard let scanner = device as? ICScannerDevice else { return }
        Task { @MainActor in
            if !scanners.contains(scanner) { scanners.append(scanner) }
            status = ""
        }
    }

    nonisolated func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        Task { @MainActor in scanners.removeAll { $0 == device } }
    }
}

extension ScannerModel: ICScannerDeviceDelegate {
    nonisolated func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
        Task { @MainActor in
            if error != nil {
                isScanning = false
                status = "Couldn't open the scanner."
            }
        }
    }

    nonisolated func deviceDidBecomeReady(_ device: ICDevice) {
        Task { @MainActor in
            if let scanner = device as? ICScannerDevice { selectUnit(scanner) }
        }
    }

    nonisolated func scannerDevice(_ scanner: ICScannerDevice,
                                   didSelect functionalUnit: ICScannerFunctionalUnit,
                                   error: Error?) {
        Task { @MainActor in
            if error == nil {
                startScan(scanner)
            } else {
                isScanning = false
                status = "Couldn't configure the scanner."
            }
        }
    }

    nonisolated func scannerDevice(_ scanner: ICScannerDevice, didScanTo url: URL) {
        Task { @MainActor in scannedURLs.append(url) }
    }

    nonisolated func scannerDevice(_ scanner: ICScannerDevice, didCompleteScanWithError error: Error?) {
        Task { @MainActor in finish() }
    }

    nonisolated func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {}

    nonisolated func didRemove(_ device: ICDevice) {}
}

/// Sheet that lists connected scanners and scans the chosen one.
struct ScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = ScannerModel()
    var onScanned: ([Data]) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Scan a Document")
                .font(.headline)

            if model.scanners.isEmpty {
                Text(model.status)
                    .foregroundStyle(.secondary)
            } else {
                List(model.scanners, id: \.self) { scanner in
                    Button {
                        model.scan(scanner)
                    } label: {
                        Label(scanner.name ?? "Scanner", systemImage: "scanner")
                    }
                    .disabled(model.isScanning)
                }
                .frame(minHeight: 120)
                if model.isScanning {
                    ProgressView(model.status)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
            }
        }
        .padding(20)
        .frame(minWidth: 360, minHeight: 240)
        .onAppear {
            model.onScanned = { pages in
                onScanned(pages)
                dismiss()
            }
        }
        .onDisappear { model.stop() }
    }
}
#endif
