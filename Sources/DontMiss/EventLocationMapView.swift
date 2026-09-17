import SwiftUI
import MapKit
import DontMissCore

struct EventLocationMapView: View {
    let location: String
    @StateObject private var lookup = EventLocationLookup()
    @State private var attempt = 0
    @State private var openError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch lookup.state {
            case .idle:
                EmptyView()
            case .loading:
                ProgressView("Finding location in Apple Maps...")
                    .controlSize(.small)
            case .resolved(let place):
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: place.placemark.coordinate,
                    latitudinalMeters: 800, longitudinalMeters: 800)),
                    interactionModes: []) {
                    Marker(item: place)
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("Map of \(place.name ?? location)")
                .onTapGesture { open(place) }
                HStack {
                    Text(place.placemark.title ?? place.name ?? location)
                        .font(.caption).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Spacer()
                    Button { open(place) } label: {
                        Label("Open in Apple Maps", systemImage: "arrow.up.right.square")
                    }
                    .controlSize(.small)
                }
            case .unavailable(let message):
                HStack(alignment: .top) {
                    Label(message, systemImage: "map")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Retry") { attempt += 1 }.controlSize(.small)
                }
            }
            if let openError {
                Text(openError).font(.caption).foregroundStyle(.red)
            }
        }
        .task(id: attempt) { await lookup.load(location) }
    }

    private func open(_ place: MKMapItem) {
        openError = place.openInMaps()
            ? nil : "Could not open this location in Apple Maps."
    }
}
