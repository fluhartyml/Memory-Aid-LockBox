//
//  LocationMapCapture.swift
//  Memory Aid LockBox
//
//  Journal helper: capture the device's current location and render a square
//  map image (with a pin) that has the GPS coordinates embedded in its EXIF, so
//  a journal entry can be stamped with where it was written. iOS/iPadOS only —
//  the Mac's coarse Wi-Fi location isn't worth a separate entitlement here.
//

#if os(iOS)
import UIKit
import CoreLocation
import MapKit
import ImageIO
import UniformTypeIdentifiers

/// One-shot current-location fetch. Requests "While Using" permission the first
/// time; returns nil if permission is denied or no fix can be obtained.
@MainActor
final class LocationFetcher: NSObject, CLLocationManagerDelegate {
    static let shared = LocationFetcher()

    private let manager = CLLocationManager()
    private var authContinuation: CheckedContinuation<Void, Never>?
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func currentLocation() async -> CLLocation? {
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
        return await withCheckedContinuation { (cont: CheckedContinuation<CLLocation?, Never>) in
            locationContinuation = cont
            manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authContinuation?.resume()
            authContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            locationContinuation?.resume(returning: locations.last)
            locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            locationContinuation?.resume(returning: nil)
            locationContinuation = nil
        }
    }
}

enum LocationMapCapture {
    /// Grab the current location and render a square map image (with a pin) whose
    /// EXIF carries the GPS coordinates. Returns nil on permission denial or error.
    static func captureCurrentLocationMap() async -> Data? {
        guard let location = await LocationFetcher.shared.currentLocation() else { return nil }
        return await mapImage(for: location.coordinate)
    }

    static func mapImage(for coordinate: CLLocationCoordinate2D, points: CGFloat = 600) async -> Data? {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: coordinate,
                                            latitudinalMeters: 700,
                                            longitudinalMeters: 700)
        options.size = CGSize(width: points, height: points)
        options.traitCollection = UITraitCollection(userInterfaceStyle: .light)

        let snapshotter = MKMapSnapshotter(options: options)
        guard let snapshot = try? await snapshotter.start() else { return nil }

        // Composite a pin whose tip sits on the captured coordinate.
        let composited = UIGraphicsImageRenderer(size: snapshot.image.size).image { _ in
            snapshot.image.draw(at: .zero)
            let point = snapshot.point(for: coordinate)
            let markerSize: CGFloat = 40
            let marker = UIImage(systemName: "mappin.circle.fill")?
                .withTintColor(.systemRed, renderingMode: .alwaysOriginal)
            marker?.draw(in: CGRect(x: point.x - markerSize / 2,
                                    y: point.y - markerSize,
                                    width: markerSize,
                                    height: markerSize))
        }
        return jpegWithGPS(composited, coordinate: coordinate)
    }

    private static func jpegWithGPS(_ image: UIImage, coordinate: CLLocationCoordinate2D) -> Data? {
        guard let cgImage = image.cgImage else { return nil }
        let gps: [CFString: Any] = [
            kCGImagePropertyGPSLatitude: abs(coordinate.latitude),
            kCGImagePropertyGPSLatitudeRef: coordinate.latitude >= 0 ? "N" : "S",
            kCGImagePropertyGPSLongitude: abs(coordinate.longitude),
            kCGImagePropertyGPSLongitudeRef: coordinate.longitude >= 0 ? "E" : "W",
        ]
        let properties: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: gps,
            kCGImageDestinationLossyCompressionQuality: 0.9,
        ]
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
#endif
