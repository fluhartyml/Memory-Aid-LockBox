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
    /// True while a geocode is in flight — drives a visible "Locating…" placeholder
    /// so the map's arrival is obvious instead of the view sitting blank (the map
    /// used to render nothing until it resolved, which read as "no map").
    @State private var isLocating = false

    var body: some View {
        Group {
            if let resolved {
                MiniMapCard(coordinate: resolved.location.coordinate, placeName: placeName)
            } else if isLocating {
                locatingPlaceholder
            }
        }
        // Re-geocode when the address settles. `.task(id:)` cancels & restarts on
        // every change; the short debounce coalesces keystrokes while still
        // resolving a stored address almost immediately on open.
        .task(id: address) {
            await lookUp(address)
        }
    }

    /// Same footprint as the resolved map, so there's no layout jump when it swaps in.
    private var locatingPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.quaternary)
            .frame(height: 150)
            .overlay {
                Label("Locating on map…", systemImage: "mappin.and.ellipse")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
    }

    private func lookUp(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // MKGeocodingRequest's initializer is failable (nil for an empty/invalid
        // address string).
        guard trimmed.count >= 5, let request = MKGeocodingRequest(addressString: trimmed) else {
            resolved = nil
            isLocating = false
            return
        }
        isLocating = true
        // Short debounce: coalesce keystrokes while editing; cancellation (from a
        // newer edit or the view going away) drops out cleanly.
        try? await Task.sleep(for: .milliseconds(300))
        if Task.isCancelled { return }

        // New MapKit geocoding (iOS/macOS 26): request.mapItems is an async getter.
        let items = try? await request.mapItems
        if Task.isCancelled { return }
        resolved = items?.first
        isLocating = false
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

/// The manual "Tag current location" control for a compose sheet (Notes /
/// Journal / Receipts). Tapping grabs the device's current coordinate into the
/// bindings; once tagged it shows the mini-map + a Remove option. For Journal,
/// pass `appendImageTo` so a rendered map-pin picture is also added to the
/// entry's attachments. Cross-platform.
struct TagLocationControl: View {
    @Binding var latitude: Double?
    @Binding var longitude: Double?
    var placeName: String = ""
    /// If provided, tagging also appends a rendered map-pin image here (Journal).
    var appendImageTo: Binding<[Data]>? = nil

    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let lat = latitude, let lon = longitude {
                MiniMapCard(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                            placeName: placeName)
                Button {
                    latitude = nil
                    longitude = nil
                } label: {
                    Label("Remove location", systemImage: "trash").font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            } else {
                Button {
                    tag()
                } label: {
                    HStack(spacing: 8) {
                        if busy {
                            ProgressView()
                        } else {
                            Image(systemName: "mappin.and.ellipse").font(.system(size: 16))
                        }
                        Text(busy ? "Tagging…" : "Tag current location")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .disabled(busy)
            }
        }
    }

    private func tag() {
        Task {
            busy = true
            if let coord = await LocationFetcher.shared.currentCoordinate() {
                latitude = coord.latitude
                longitude = coord.longitude
                if let bind = appendImageTo,
                   let img = await LocationMapImage.snapshotData(for: coord) {
                    bind.wrappedValue.append(img)
                }
            }
            busy = false
        }
    }
}
