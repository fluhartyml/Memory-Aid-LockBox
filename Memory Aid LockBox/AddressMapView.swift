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

    @State private var coordinate: CLLocationCoordinate2D?
    @State private var isLooking = false

    var body: some View {
        Group {
            if let coordinate {
                Button {
                    openInMaps(coordinate)
                } label: {
                    Map(initialPosition: .region(region(for: coordinate))) {
                        Marker(placeName.isEmpty ? "Location" : placeName,
                               coordinate: coordinate)
                    }
                    // The mini-map is a preview, not an interactive map — let the
                    // tap fall through to the Button so it opens full Maps.
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
        }
        // Re-geocode when the address settles. `.task(id:)` cancels & restarts on
        // every change; the debounce means we only hit the geocoder once typing
        // pauses (CLGeocoder is rate-limited).
        .task(id: address) {
            await lookUp(address)
        }
    }

    private func region(for coord: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(center: coord,
                           span: MKCoordinateSpan(latitudeDelta: 0.01,
                                                  longitudeDelta: 0.01))
    }

    private func lookUp(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 5 else {
            coordinate = nil
            return
        }
        // Debounce: wait for typing to pause; cancellation (from a newer edit or
        // the view going away) drops out here cleanly.
        try? await Task.sleep(for: .milliseconds(600))
        if Task.isCancelled { return }

        let placemarks = try? await CLGeocoder().geocodeAddressString(trimmed)
        if Task.isCancelled { return }
        coordinate = placemarks?.first?.location?.coordinate
    }

    private func openInMaps(_ coord: CLLocationCoordinate2D) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coord))
        item.name = placeName.isEmpty ? address : placeName
        item.openInMaps(launchOptions: [
            MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: coord)
        ])
    }
}
