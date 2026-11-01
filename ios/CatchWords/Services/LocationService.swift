import CoreLocation
import ImageIO
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
    /// The most accurate fix of the request in flight (a fix comes in a few times as the phone narrows it down).
    private var best: CLLocation?
    private var startedAt = Date()
    /// The camera is open: the phone keeps measuring, so a precise point is ready at the shutter (the first fixes after
    /// starting are rough — a cold start can take longer than the capture waits).
    private var warming = false
    /// The newest fix while the camera is open.
    private var latest: CLLocation?
    /// 「正確な位置情報」 off: asked once per launch to turn it on while photos are taken (`CapturePlace`).
    private var askedFullAccuracy = false

    /// A fix this close is taken at once; a less accurate one only when nothing better came in time.
    nonisolated static let goodAccuracy: CLLocationAccuracy = 20
    /// How old the phone's last fix may be to be taken without asking again, and how close it must have been.
    nonisolated static let cachedAge: TimeInterval = 15
    /// How long the capture waits for a good fix before taking the best it has.
    nonisolated static let fixTimeout: Double = 6

    override init() {
        super.init()
        manager.delegate = self
        // The best the phone can do: the place's name is only as right as the point (owner 2026-11-01: 「写真を撮った
        // 場所の地名が正確じゃない」 — a fix to within 100 m, up to five minutes old, was named).
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestPermissionIfNeeded() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
    }

    func current() async -> CLLocation? {
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return nil }
        if let fresh = latest, Self.isGood(fresh, maxAge: Self.cachedAge) { return fresh }
        if let cached = manager.location, Self.isGood(cached, maxAge: Self.cachedAge) { return cached }
        return await withCheckedContinuation { cont in
            waiters.append(cont)
            guard waiters.count == 1 else { return }  // a request is already on its way: share its answer
            generation += 1
            let mine = generation
            best = nil
            startedAt = Date()
            // Fixes keep coming as the phone narrows the point down: the first good one is taken, else the best one
            // when the time is up (one `requestLocation` answered with the first rough fix).
            manager.startUpdatingLocation()
            Task {
                try? await Task.sleep(for: .seconds(Self.fixTimeout))
                guard self.generation == mine else { return }
                // Nothing new in time: the phone's last fix when it is from the last minute.
                let recent = self.manager.location.flatMap { $0.timestamp.timeIntervalSinceNow > -60 ? $0 : nil }
                self.finish(self.best ?? self.latest ?? recent)
            }
        }
    }

    /// The camera opened: start measuring now (owner 2026-11-01: 「地名の精度も高めて」). With 「正確な位置情報」 off
    /// the point is only known to a few kilometres — the system asks once per launch to allow it while photos are taken.
    func warmUp() {
        // Wanted even before the permission is answered: measuring starts once it is given.
        warming = true
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
        if manager.accuracyAuthorization == .reducedAccuracy, !askedFullAccuracy {
            askedFullAccuracy = true
            manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "CapturePlace")
        }
        manager.startUpdatingLocation()
    }

    /// The camera closed: stop measuring (unless a capture is still waiting for its point).
    func coolDown() {
        warming = false
        latest = nil
        if waiters.isEmpty { manager.stopUpdatingLocation() }
    }

    /// A fix recent enough and as accurate as `goodAccuracy`.
    nonisolated static func isGood(_ l: CLLocation, maxAge: TimeInterval) -> Bool {
        l.horizontalAccuracy >= 0 && l.horizontalAccuracy <= goodAccuracy && l.timestamp.timeIntervalSinceNow > -maxAge
    }

    /// The location saved in a photo from the library (its EXIF GPS), so a photo taken elsewhere is not named after
    /// where the phone is now. nil = the photo has none.
    nonisolated static func photoLocation(_ data: Data) -> CLLocation? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any],
              let lat = (gps[kCGImagePropertyGPSLatitude] as? NSNumber)?.doubleValue,
              let lng = (gps[kCGImagePropertyGPSLongitude] as? NSNumber)?.doubleValue else { return nil }
        let signedLat = (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S" ? -lat : lat
        let signedLng = (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W" ? -lng : lng
        guard CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: signedLat, longitude: signedLng)),
              signedLat != 0 || signedLng != 0 else { return nil }
        let error = (gps[kCGImagePropertyGPSHPositioningError] as? NSNumber)?.doubleValue ?? 0
        return CLLocation(coordinate: CLLocationCoordinate2D(latitude: signedLat, longitude: signedLng), altitude: 0,
                          horizontalAccuracy: error, verticalAccuracy: -1, timestamp: Date())
    }

    /// The place name in the display language (a saved name stays in the language it was saved in, so
    /// screens re-ask with `localizedName` when the coordinates are known).
    ///
    /// A named place where there is one — the shop, café, park or station it was taken at, then the district
    /// (「星巴克 忠孝門市 · 大安區」) — so the learner can picture where it was (owner 2026-10-31: 「ただの住所になってるから
    /// …具体的な場所やお店の名前を表示して」). Without one, the city and district as before.
    ///
    /// How near a place must be follows how sure the point is (owner 2026-11-01: 「もっと正確に場所、具体的な名称を
    /// 表示して。もし特定の場所が、具体的なお店、場所がない場合は、その場所の地図の住所を表示して」):
    /// - a precise point: the nearest shop or place within `spotRadius`, else the park, station or campus it lies in,
    ///   else its address on the map (「台北市 大安區 和平東路一段162號」);
    /// - a point only known to within a block or so: no shop (the nearest one to a wrong point is a wrong name) —
    ///   the park, station or campus, else the street without its number;
    /// - a rough point (Precise Location off, or no better fix): the city and district.
    /// A point read back from saved coordinates has no accuracy (0) and is taken as precise.
    func placeName(for location: CLLocation) async -> String? {
        let accuracy = location.horizontalAccuracy
        let precise = accuracy >= 0 && accuracy <= Self.spotRadius + 15
        let rough = accuracy < 0 || accuracy > 150
        async let spot = Self.nearbySpot(location, look: precise)
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location, preferredLocale: L10n.locale)
        let p = placemarks?.first
        // A park, a station or a campus the point lies inside (Apple's own areas) when no shop is right there.
        let named = await spot ?? (rough ? nil : p?.areasOfInterest?.lazy.compactMap { Self.properName($0) }.first)
        // Apple answers in the display language where the place has a name in it, else in the place's own script (a
        // Taipei district in 中文 on a Spanish screen): shown as it comes — a place's name as it is written there
        // (owner 2026-10-31: 「その地名や具体的な名前はそのまま表記して。英語でも中国語でも」).
        let parts: [String]
        if let named {
            let area = [p?.subLocality, p?.locality].lazy.compactMap { Self.properName($0) }.first
            parts = [named] + (area.map { $0 == named ? [] : [$0] } ?? [])
        } else if let p {
            let area = [p.locality, p.subLocality].compactMap { Self.properName($0) }
            let street = rough ? nil : Self.street(p, withNumber: precise || accuracy <= 50)
            parts = area + (street.map { s in area.contains(s) ? [] : [s] } ?? [])
        } else {
            return nil
        }
        return parts.isEmpty ? nil : parts.joined(separator: L10n.current.placeSeparator)
    }

    /// The street and its number as the map writes them: 「和平東路一段162號」 where the street is written in Han
    /// characters, 「162 Heping East Road」 elsewhere. nil = the placemark has no street.
    nonisolated static func street(_ p: CLPlacemark, withNumber: Bool) -> String? {
        guard let road = properName(p.thoroughfare) else { return nil }
        guard withNumber, let number = properName(p.subThoroughfare) else { return road }
        // The number as part of the street's name: Han (台灣・日本) writes it after the street without a space.
        let han = road.unicodeScalars.contains { $0.properties.isIdeographic }
        return han ? road + number : number + " " + road
    }

    /// How near a shop or other place must be to be named: the phone's fix is within about this much in a city.
    nonisolated static let spotRadius: CLLocationDistance = 35

    /// The nearest named place (a shop, café, restaurant, park, station, museum…) within `spotRadius`; nil when none is
    /// that near.
    private static func nearbySpot(_ location: CLLocation, look: Bool) async -> String? {
        guard look else { return nil }
        return await spots(near: location.coordinate, radius: spotRadius).first?.name
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

    /// A shop's, a park's, a station's or a district's own name, as Apple has it — in whatever script it is written there,
    /// English, 中文 or any other, on every screen: a place's name is not a mixed-in language (owner 2026-10-31: 「お店は
    /// 現地の名前表記通りでいい。言語混ざるとかではなく、その地名や具体的な名前はそのまま表記して。英語でも中国語でも」).
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
        if !warming { manager.stopUpdatingLocation() }
        best = nil
        let done = waiters
        waiters = []
        generation += 1  // the finished request's timer is now stale
        done.forEach { $0.resume(returning: location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            if self.warming, let newest = locations.last(where: { $0.horizontalAccuracy >= 0 }) {
                // The newest unless it is much rougher than a fix from the last few seconds.
                let rougher = self.latest.map { kept in
                    kept.timestamp.timeIntervalSinceNow > -5 && newest.horizontalAccuracy > kept.horizontalAccuracy * 2
                } ?? false
                if !rougher { self.latest = newest }
            }
            guard !self.waiters.isEmpty else { return }
            // Only fixes made for this request (an old one the phone hands back first is not where the photo is).
            for l in locations where l.horizontalAccuracy >= 0 && l.timestamp >= self.startedAt.addingTimeInterval(-2) {
                if self.best == nil || l.horizontalAccuracy < self.best!.horizontalAccuracy { self.best = l }
            }
            if let best = self.best, best.horizontalAccuracy <= Self.goodAccuracy { self.finish(best) }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in if self.warming { self.warmUp() } }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 「not known yet」 while updating: the phone keeps trying (the timeout ends the wait).
        if (error as? CLError)?.code == .locationUnknown { return }
        Task { @MainActor in self.finish(self.best) }
    }
}
