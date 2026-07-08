//
//  AddressMapView.swift
//  Memory Aid LockBox
//
//  A small inline map snapshot for a typed address (contacts, receipts,
//  appointments). Geocodes the address, shows a pinned mini-map, and taps
//  through to the system Maps app for directions. Appears only when the address
//  resolves to a real location; renders nothing (and never blocks) otherwise —
//  fail-safe: a bad/empty address just means no map, no error.
//

import SwiftUI
import MapKit
import CoreLocation

struct AddressMapView: View {
    /// The free-text address to look up (e.g. "202 Highway 332 W, Texas 77566").
    let address: String
    /// Name shown on the pin and carried into Maps (e.g. the store/contact name).
    var placeName: String = ""

    /// The resolved place. We hold the whole MKMapItem (not just a coordinate) so
    /// "Directions" opens Maps on the exact geocoded result, name and all.
    @State private var resolved: MKMapItem?

    var body: some View {
        Group {
            if let resolved {
                MiniMapCard(coordinate: resolved.location.coordinate, placeName: placeName)
            }
        }
        // Re-geocode when the address settles. `.task(id:)` cancels & restarts on
        // every change; the debounce means we only hit the geocoder once typing
        // pauses (geocoding is rate-limited).
        .task(id: address) {
            await lookUp(address)
        }
    }

    private func lookUp(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // MKGeocodingRequest's initializer is failable (nil for an empty/invalid
        // address string).
        guard trimmed.count >= 5, let request = MKGeocodingRequest(addressString: trimmed) else {
            resolved = nil
            return
        }
        // Debounce: wait for typing to pause; cancellation (from a newer edit or
        // the view going away) drops out here cleanly.
        try? await Task.sleep(for: .milliseconds(600))
        if Task.isCancelled { return }

        // New MapKit geocoding (iOS/macOS 26): request.mapItems is an async getter.
        let items = try? await request.mapItems
        if Task.isCancelled { return }
        resolved = items?.first
    }
}

/// The tappable mini-map card: a static map preview centered on a coordinate
/// that opens Apple Maps for directions when tapped. Shared by AddressMapView
/// (a geocoded address) and the "Tag location" feature on Notes/Journal/Receipts
/// (a stored coordinate). Cross-platform (iOS + macOS).
struct MiniMapCard: View {
    let coordinate: CLLocationCoordinate2D
    var placeName: String = ""

    var body: some View {
        Button {
            openInMaps()
        } label: {
            Map(initialPosition: .region(region)) {
                Marker(placeName.isEmpty ? "Location" : placeName, coordinate: coordinate)
            }
            // The mini-map is a preview, not an interactive map — let the tap
            // fall through to the Button so it opens full Maps.
            .allowsHitTesting(false)
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .bottomTrailing) {
                Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(8)
            }
        }
        .buttonStyle(.plain)
    }

    private var region: MKCoordinateRegion {
        MKCoordinateRegion(center: coordinate,
                           span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
    }

    private func openInMaps() {
        let mapItem = MKMapItem(location: CLLocation(latitude: coordinate.latitude,
                                                     longitude: coordinate.longitude),
                                address: nil)
        if !placeName.isEmpty { mapItem.name = placeName }
        mapItem.openInMaps(launchOptions: nil)
    }
}
