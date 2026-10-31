import CoreLocation
import MapKit

/// Grabs the capture location and turns it into a readable place name in the display language.
final class LocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    private let manager = CLLocationManager()
    /// Everyone waiting for the fix in flight: callers within the same few seconds share one request
    /// (a second call used to answer the first with nil, and the first call's timer cut the second short).
    private var waiters: [CheckedContinuation<CLLocation?, Never>] = []
    /// Which request the timeout belongs to (a stale timer must not end a newer request).
    private var generation = 0

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestPermissionIfNeeded() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
    }

    func current() async -> CLLocation? {
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return nil }
        if let cached = manager.location, cached.timestamp.timeIntervalSinceNow > -300 { return cached }
        return await withCheckedContinuation { cont in
            waiters.append(cont)
            guard waiters.count == 1 else { return }  // a request is already on its way: share its answer
            generation += 1
            let mine = generation
            manager.requestLocation()
            Task {
                try? await Task.sleep(for: .seconds(6))
                if self.generation == mine { self.finish(nil) }
            }
        }
    }

    /// The place name in the display language (a saved name stays in the language it was saved in, so
    /// screens re-ask with `localizedName` when the coordinates are known).
    ///
    /// A named place where there is one — the shop, café, park or station it was taken at, then the district
    /// (「星巴克 忠孝門市 · 大安區」) — so the learner can picture where it was (owner 2026-10-31: 「ただの住所になってるから
    /// …具体的な場所やお店の名前を表示して」). Without one, the city and district as before.
    func placeName(for location: CLLocation) async -> String? {
        async let spot = Self.nearbySpot(location)
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location, preferredLocale: L10n.locale)
        let p = placemarks?.first
        // A park, a station or a campus the point lies inside (Apple's own areas) when no shop is right there.
        let named = await spot ?? p?.areasOfInterest?.lazy.compactMap { Self.properName($0) }.first
        // Apple answers in the place's own script when it has no name in the requested language (a Taipei district in
        // 中文 on a Spanish screen): each part is kept only when it reads as the display language.
        let parts: [String]
        if let named {
            let area = [p?.subLocality, p?.locality].lazy.compactMap { Self.shownPlace($0) }.first
            parts = [named] + (area.map { $0 == named ? [] : [$0] } ?? [])
        } else if let p {
            parts = [p.locality, p.subLocality ?? p.name].compactMap { Self.shownPlace($0) }
        } else {
            return nil
        }
        return parts.isEmpty ? nil : parts.joined(separator: L10n.current.placeSeparator)
    }

    /// How near a shop or other place must be to be named: the phone's fix is within about this much in a city.
    nonisolated static let spotRadius: CLLocationDistance = 35

    /// The nearest named place (a shop, café, restaurant, park, station, museum…) within `spotRadius`; nil when none is
    /// that near.
    private static func nearbySpot(_ location: CLLocation) async -> String? {
        await spots(near: location.coordinate, radius: spotRadius).first?.name
    }

    /// A named place near a point, for the learner to pick (`PlaceEditSheet`).
    struct Spot: Identifiable, Hashable {
        let name: String
        let latitude: Double
        let longitude: Double
        let metres: CLLocationDistance
        var id: String { "\(name)|\(latitude)|\(longitude)" }
    }

    /// The named places within `radius` of a point, nearest first (their names as Apple has them). Not the kinds
    /// no one would say they were at (an ATM, a car park, a toilet).
    static func spots(near point: CLLocationCoordinate2D, radius: CLLocationDistance) async -> [Spot] {
        let request = MKLocalPointsOfInterestRequest(center: point, radius: max(radius * 2, 100))
        request.pointOfInterestFilter = MKPointOfInterestFilter(excluding: [.atm, .evCharger, .parking, .restroom, .fireStation, .police])
        guard let items = try? await MKLocalSearch(request: request).start().mapItems else { return [] }
        let here = CLLocation(latitude: point.latitude, longitude: point.longitude)
        var seen = Set<String>()
        return items.compactMap { item -> Spot? in
            guard let name = properName(item.name), let at = item.placemark.location else { return nil }
            let metres = at.distance(from: here)
            guard metres <= radius, seen.insert(name).inserted else { return nil }
            return Spot(name: name, latitude: at.coordinate.latitude, longitude: at.coordinate.longitude, metres: metres)
        }
        .sorted { $0.metres < $1.metres }
    }

    /// A shop's, a park's or a station's own name, as Apple has it — in 中文 on any screen when it has no other: a proper
    /// name is not a mixed-in language (owner 2026-10-31: 「これは中国語の固有名詞だから表示していい」). The city and
    /// district around it still follow `shownPlace`.
    nonisolated static func properName(_ name: String?) -> String? {
        let v = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    private var nameCache: [String: String] = [:]

    /// A saved place name shown as it was saved — only when it reads as the display language (a name saved on a
    /// Japanese screen, 「渋谷区」, is not shown on a Spanish one; Han-only names stay for 日本語 and 繁體中文). The
    /// screens without coordinates to look the name up again use this; nil = show no place.
    nonisolated static func shownPlace(_ saved: String?) -> String? {
        let v = ReaderLanguage.shown(saved, hanOnlyOk: true)
        return v.isEmpty ? nil : v
    }

    /// A saved place shown in the current display language: the coordinates are looked up again
    /// (once per place and language); without coordinates, or when the lookup fails, the saved name when it reads
    /// as the display language (`shownPlace`), else none.
    /// A name the learner wrote or picked (`custom`) is theirs: shown as it is, in whatever language they wrote it.
    func localizedName(lat: Double?, lng: Double?, saved: String?, custom: Bool = false) async -> String? {
        if custom, let saved, !saved.isEmpty { return saved }
        guard let lat, let lng else { return Self.shownPlace(saved) }
        let key = String(format: "%.4f,%.4f,", lat, lng) + L10n.lang
        if let hit = nameCache[key] { return hit }
        guard let name = await placeName(for: CLLocation(latitude: lat, longitude: lng)) else { return Self.shownPlace(saved) }
        nameCache[key] = name
        return name
    }

    private func finish(_ location: CLLocation?) {
        guard !waiters.isEmpty else { return }
        let done = waiters
        waiters = []
        generation += 1  // the finished request's timer is now stale
        done.forEach { $0.resume(returning: location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in self.finish(last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }
}
