//
//  LocationMapCapture.swift
//  Memory Aid LockBox
//
//  One-shot current-location fetch used by the manual "Tag location" button on
//  Notes / Journal / Receipts. Returns a coordinate the record stores; the
//  coordinate is later shown as a tappable mini-map (see MiniMapCard). Works on
//  iOS, iPadOS, and macOS — nothing here is platform-specific.
//

import CoreLocation

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
        let location = await withCheckedContinuation { (cont: CheckedContinuation<CLLocation?, Never>) in
            locationContinuation = cont
            manager.requestLocation()
        }
        return location?.coordinate
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
