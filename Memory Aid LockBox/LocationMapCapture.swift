//
//  LocationMapCapture.swift
//  Memory Aid LockBox
//
//  Manual "Tag location" support for Notes / Journal / Receipts:
//   • LocationFetcher — one-shot current-coordinate fetch (iOS + macOS).
//   • LocationMapImage — renders a map snapshot with a centered pin, added to the
//     record's attachments so the location is also viewable as a plain picture
//     (alongside the stored coordinate / tappable mini-map).
//

import CoreLocation
import MapKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// One-shot current-location fetch. Requests "While Using" permission the first
/// time; returns nil if permission is denied or no fix can be obtained.
@MainActor
final class LocationFetcher: NSObject, CLLocationManagerDelegate {
    static let shared = LocationFetcher()

    private let manager = CLLocationManager()
    private var authContinuation: CheckedContinuation<Void, Never>?
    private var locationContinuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    /// Returns the device's current coordinate, or nil on denial / no fix.
    func currentCoordinate() async -> CLLocationCoordinate2D? {
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                authContinuation = cont
                manager.requestWhenInUseAuthorization()
            }
        }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            break
        default:
            return nil
        }

        // Fast path: a recent cached fix.
        if let loc = manager.location, loc.horizontalAccuracy >= 0,
           abs(loc.timestamp.timeIntervalSinceNow) < 60 {
            return loc.coordinate
        }

        // Otherwise stream updates and take the first good fix. One-shot
        // requestLocation() routinely fails right after the permission grant
        // (no fix yet); streaming + a timeout backstop is reliable.
        return await withCheckedContinuation { (cont: CheckedContinuation<CLLocationCoordinate2D?, Never>) in
            locationContinuation = cont
            manager.startUpdatingLocation()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(10))
                finish(nil)
            }
        }
    }

    /// Resume the pending location wait exactly once and stop the stream.
    private func finish(_ coordinate: CLLocationCoordinate2D?) {
        guard let cont = locationContinuation else { return }
        locationContinuation = nil
        manager.stopUpdatingLocation()
        cont.resume(returning: coordinate)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            // This fires once immediately when the delegate is set (still
            // .notDetermined) — ignore that, or we'd resume the permission wait
            // before the user has actually responded and then read the stale
            // undetermined status. Only resume once they've decided.
            guard manager.authorizationStatus != .notDetermined else { return }
            authContinuation?.resume()
            authContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            if let loc = locations.last, loc.horizontalAccuracy >= 0 {
                finish(loc.coordinate)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            // Only give up on a hard denial; transient "location unknown" errors are
            // expected while acquiring a fix — keep waiting (up to the timeout).
            if let clError = error as? CLError, clError.code == .denied {
                finish(nil)
            }
        }
    }
}

enum LocationMapImage {
    /// Render a square map snapshot centered on `coordinate` with a red pin at the
    /// center, returned as JPEG data for use as a record attachment. Because the
    /// snapshot is centered on the coordinate, the pin is drawn at the image
    /// center — no coordinate→point mapping (and no AppKit/UIKit y-flip pitfall).
    /// Returns nil on snapshot failure.
    static func snapshotData(for coordinate: CLLocationCoordinate2D, points: CGFloat = 600) async -> Data? {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: coordinate,
                                            latitudinalMeters: 700,
                                            longitudinalMeters: 700)
        options.size = CGSize(width: points, height: points)

        let snapshotter = MKMapSnapshotter(options: options)
        guard let snapshot = try? await snapshotter.start() else { return nil }
        return composite(snapshot)
    }

    #if canImport(UIKit)
    private static func composite(_ snapshot: MKMapSnapshotter.Snapshot) -> Data? {
        let image = snapshot.image
        let composited = UIGraphicsImageRenderer(size: image.size).image { _ in
            image.draw(at: .zero)
            let markerSize: CGFloat = 44
            let center = CGPoint(x: image.size.width / 2, y: image.size.height / 2)
            UIImage(systemName: "mappin.circle.fill")?
                .withTintColor(.systemRed, renderingMode: .alwaysOriginal)
                .draw(in: CGRect(x: center.x - markerSize / 2, y: center.y - markerSize / 2,
                                 width: markerSize, height: markerSize))
        }
        return composited.jpegData(compressionQuality: 0.9)
    }
    #elseif canImport(AppKit)
    private static func composite(_ snapshot: MKMapSnapshotter.Snapshot) -> Data? {
        let image = snapshot.image
        let size = image.size
        let composed = NSImage(size: size)
        composed.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size))
        let markerSize: CGFloat = 44
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let config = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
        NSImage(systemSymbolName: "mappin.circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(config)?
            .draw(in: NSRect(x: center.x - markerSize / 2, y: center.y - markerSize / 2,
                             width: markerSize, height: markerSize))
        composed.unlockFocus()

        guard let tiff = composed.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
    }
    #endif
}
