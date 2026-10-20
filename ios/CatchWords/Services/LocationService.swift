import CoreLocation

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
    func placeName(for location: CLLocation) async -> String? {
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location, preferredLocale: L10n.locale)
        guard let p = placemarks?.first else { return nil }
        let parts = [p.locality, p.subLocality ?? p.name].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: L10n.current.placeSeparator)
    }

    private var nameCache: [String: String] = [:]

    /// A saved place shown in the current display language: the coordinates are looked up again
    /// (once per place and language); without coordinates, or when the lookup fails, the saved name.
    func localizedName(lat: Double?, lng: Double?, saved: String?) async -> String? {
        guard let lat, let lng else { return saved }
        let key = String(format: "%.3f,%.3f,", lat, lng) + L10n.lang
        if let hit = nameCache[key] { return hit }
        guard let name = await placeName(for: CLLocation(latitude: lat, longitude: lng)) else { return saved }
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
