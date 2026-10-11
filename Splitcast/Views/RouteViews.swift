import MapKit
import SwiftUI

/// A small map image of a workout's route, for telling runs apart in lists. Rendered once with
/// MKMapSnapshotter (cheaper than live maps in every row), then kept in memory and in Caches.
struct RouteThumbnail: View {
    let workoutID: UUID?
    var size: CGFloat = 52

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var scale
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(.quaternary)
            if let image {
                Image(uiImage: image).resizable()
            } else {
                Image(systemName: "figure.run").foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: workoutID) {
            guard let workoutID else { return }
            image = await RouteSnapshots.image(for: workoutID, size: size, scale: scale, dark: colorScheme == .dark)
        }
        .accessibilityHidden(true)
    }
}

private enum RouteSnapshots {
    static var cache: [String: UIImage] = [:]
    static let directory = URL.cachesDirectory.appending(path: "route-thumbnails")

    static func image(for workoutID: UUID, size: CGFloat, scale: CGFloat, dark: Bool) async -> UIImage? {
        let key = "\(workoutID)-\(Int(size))-\(dark ? "dark" : "light")@\(Int(scale))x"
        if let cached = cache[key] { return cached }
        let file = directory.appending(path: "\(key).png")
        if let data = try? Data(contentsOf: file), let saved = UIImage(data: data, scale: scale) {
            cache[key] = saved
            return saved
        }
        let route = await RouteLoader.shared.route(for: workoutID, maxPoints: 150)
        guard route.count > 1 else { return nil }

        let options = MKMapSnapshotter.Options()
        options.region = region(around: route)
        options.size = CGSize(width: size, height: size)
        options.pointOfInterestFilter = .excludingAll
        options.traitCollection = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let image = UIGraphicsImageRenderer(size: options.size, format: format).image { _ in
            snapshot.image.draw(at: .zero)
            let path = UIBezierPath()
            for (i, c) in route.enumerated() {
                let p = snapshot.point(for: c.clCoordinate)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.lineWidth = 2.5
            path.lineJoinStyle = .round
            UIColor.systemOrange.setStroke()
            path.stroke()
        }
        cache[key] = image
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? image.pngData()?.write(to: file, options: .atomic)
        return image
    }
}

/// The region that fits a route, with a margin.
func region(around route: [Coordinate]) -> MKCoordinateRegion {
    let lats = route.map(\.latitude), lons = route.map(\.longitude)
    let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lons.min()! + lons.max()!) / 2)
    let span = MKCoordinateSpan(latitudeDelta: max((lats.max()! - lats.min()!) * 1.3, 0.003),
                                longitudeDelta: max((lons.max()! - lons.min()!) * 1.3, 0.003))
    return MKCoordinateRegion(center: center, span: span)
}

/// A full-width, interactive map of a route, for the result editor.
struct RouteMap: View {
    let workoutID: UUID

    @State private var route: [Coordinate] = []

    var body: some View {
        Group {
            if route.count > 1 {
                Map(initialPosition: .region(region(around: route))) {
                    MapPolyline(coordinates: route.map(\.clCoordinate)).stroke(.orange, lineWidth: 4)
                }
            } else {
                Color.clear
            }
        }
        .task(id: workoutID) { route = await RouteLoader.shared.route(for: workoutID) }
    }
}

/// One past result: route, name, date and distance, time and pace.
struct ResultRow: View {
    let result: Benchmark
    let data: FitnessData
    let units: Units
    var detail: String? = nil
    /// Marks the fastest result at its distance.
    var isPB = false

    var body: some View {
        HStack(spacing: 12) {
            RouteThumbnail(workoutID: data.matchingRun(for: result)?.id)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(result.name)
                    if isPB { PBBadge() }
                }
                Text("\(result.date.formatted(date: .abbreviated, time: .omitted)) · \(Format.distance(result.km, units, digits: 2))")
                    .font(.caption).foregroundStyle(.secondary)
                if let detail { Text(detail).font(.caption).foregroundStyle(.orange) }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.clock(result.minutes)).bold().monospacedDigit()
                Text(Format.pace(result.minutes / result.km, units)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Chooses the result to compare with: a row showing the current choice that opens a list with
/// routes, times and paces, so runs can be told apart.
struct BenchmarkPicker: View {
    let title: String
    let benchmarks: [Benchmark]
    let selected: Benchmark
    let data: FitnessData
    /// Results that are personal bests, marked with a badge.
    var pbIDs: Set<UUID> = []
    let select: (Benchmark) -> Void

    @AppStorage(Setting.units) private var units = Units.miles

    var body: some View {
        NavigationLink {
            BenchmarkList(benchmarks: benchmarks, selected: selected, data: data, units: units, pbIDs: pbIDs, select: select)
                .navigationTitle(title)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                ResultRow(result: selected, data: data, units: units, isPB: pbIDs.contains(selected.id))
            }
        }
    }
}

struct BenchmarkList: View {
    let benchmarks: [Benchmark]
    let selected: Benchmark
    let data: FitnessData
    let units: Units
    var pbIDs: Set<UUID> = []
    let select: (Benchmark) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(benchmarks) { b in
            Button {
                select(b)
                dismiss()
            } label: {
                HStack {
                    ResultRow(result: b, data: data, units: units, isPB: pbIDs.contains(b.id))
                    Image(systemName: "checkmark").foregroundStyle(.tint).opacity(b.id == selected.id ? 1 : 0)
                }
            }
            .tint(.primary)
        }
    }
}

/// Marks a personal best.
struct PBBadge: View {
    var body: some View {
        Text("PB").font(.caption2.weight(.bold)).foregroundStyle(Color.then)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Color.then.opacity(0.15), in: Capsule())
            .accessibilityLabel("Personal best")
    }
}
