import SwiftUI
import MapKit

/// Puts right where a photo was taken (owner 2026-10-31: 「ユーザーが場所を直す機能もつけて。地図上で指定できるまたは
/// 場所の名前を変更できるように」): the map is moved under a pin that stays in its middle, the places near the pin can be
/// picked, and the name can be written. Saved as a point and a name; a name written or picked is the learner's own
/// (`custom`: shown as it is, never looked up again).
struct PlaceEditSheet: View {
    /// What the photo has now: its point (nil = none saved) and the name shown for it.
    let start: CLLocationCoordinate2D?
    let startName: String
    /// The name shown now was written or picked by the learner.
    let startCustom: Bool
    let onSave: (_ at: CLLocationCoordinate2D, _ name: String?, _ custom: Bool) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var camera: MapCameraPosition
    @State private var center: CLLocationCoordinate2D
    /// The name in the field, and whether the learner wrote or picked it (else it follows the pin).
    @State private var name: String
    @State private var custom: Bool = false
    /// The pin's place as Apple names it, and the named places around it.
    @State private var looked: String?
    @State private var spots: [LocationService.Spot] = []
    @State private var looking: Bool = false
    @State private var saving: Bool = false
    @State private var failed: Bool = false

    /// Where the map opens when the photo has no point: 台北 (the app teaches 台湾華語).
    private static let taipei = CLLocationCoordinate2D(latitude: 25.0330, longitude: 121.5654)
    /// How far around the pin the places offered to pick are.
    private static let spotRadius: CLLocationDistance = 250

    init(start: CLLocationCoordinate2D?, startName: String, startCustom: Bool,
         onSave: @escaping (_ at: CLLocationCoordinate2D, _ name: String?, _ custom: Bool) async throws -> Void) {
        self.start = start
        self.startName = startName
        self.startCustom = startCustom
        self.onSave = onSave
        let at = start ?? Self.taipei
        _center = State(initialValue: at)
        _camera = State(initialValue: .region(MKCoordinateRegion(center: at, latitudinalMeters: 500, longitudinalMeters: 500)))
        _name = State(initialValue: startName)
        _custom = State(initialValue: startCustom)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                map
                List {
                    Section {
                        TextField(L("場所の名前"), text: Binding(get: { name }, set: { name = $0; custom = true }))
                            .submitLabel(.done)
                            .accessibilityIdentifier("place.name")
                    } header: {
                        Text(L("場所の名前"))
                    } footer: {
                        if custom, let looked, looked != name {
                            Button(L("地図の名前に戻す")) {
                                Haptics.selection()
                                name = looked
                                custom = false
                            }
                            .scaledFont(size: 13, weight: .semibold)
                        }
                    }
                    Section(L("近くの場所")) {
                        if spots.isEmpty {
                            Text(looking ? L("探しています…") : L("近くに名前のある場所はありません"))
                                .foregroundStyle(Theme.muted)
                        }
                        ForEach(spots) { spot in
                            Button { pick(spot) } label: {
                                HStack {
                                    Image(systemName: "mappin.circle.fill").foregroundStyle(Theme.primary)
                                    Text(spot.name).foregroundStyle(Theme.foreground).lineLimit(1)
                                    Spacer(minLength: 8)
                                    Text(verbatim: "\(Int(spot.metres.rounded())) m")
                                        .font(.footnote.monospacedDigit())
                                        .foregroundStyle(Theme.muted)
                                    if custom && name == spot.name {
                                        Image(systemName: "checkmark").foregroundStyle(Theme.primary)
                                    }
                                }
                            }
                            .accessibilityIdentifier("place.spot")
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle(L("場所を直す"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("キャンセル")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button(L("保存")) { save() }
                            .bold()
                            .accessibilityIdentifier("place.save")
                    }
                }
            }
            .alert(L("保存できませんでした。もう一度お試しください。"), isPresented: $failed) {
                Button("OK", role: .cancel) {}
            }
        }
        // Looked up once the map stops, a moment after (not on every frame of a drag).
        .task(id: "\(center.latitude),\(center.longitude)") { await lookUp() }
    }

    /// The map with its pin fixed in the middle: the learner moves the map under it.
    private var map: some View {
        Map(position: $camera)
            .onMapCameraChange(frequency: .onEnd) { ctx in center = ctx.region.center }
            .overlay {
                Image(systemName: "mappin")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                    .offset(y: -17)   // the pin's point on the middle
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .overlay(alignment: .bottom) {
                Text(L("地図を動かして、撮った場所にピンを合わせてください"))
                    .scaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(10)
                    .allowsHitTesting(false)
            }
            .frame(height: 300)
            .accessibilityIdentifier("place.map")
    }

    private func lookUp() async {
        looking = true
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        let at = center
        async let near = LocationService.spots(near: at, radius: Self.spotRadius)
        let found = await LocationService.shared.placeName(for: CLLocation(latitude: at.latitude, longitude: at.longitude))
        let list = await near
        guard !Task.isCancelled else { return }
        looked = found
        spots = Array(list.prefix(8))
        looking = false
        // The name follows the pin until the learner writes or picks one.
        if !custom, let found { name = found }
    }

    /// A place near the pin: its name, and the pin on it.
    private func pick(_ spot: LocationService.Spot) {
        Haptics.selection()
        name = spot.name
        custom = true
        let at = CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude)
        withAnimation(.easeInOut(duration: 0.35)) {
            camera = .region(MKCoordinateRegion(center: at, latitudinalMeters: 300, longitudinalMeters: 300))
        }
    }

    private func save() {
        let written = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // A name left as the map gave it is not the learner's own: it is looked up again in each display language.
        let own = custom && !written.isEmpty && written != looked
        let shown = own ? written : (looked ?? (written.isEmpty ? nil : written))
        saving = true
        Task {
            do {
                try await onSave(center, shown, own)
                Haptics.success()
                dismiss()
            } catch {
                saving = false
                Haptics.warning()
                failed = true
            }
        }
    }
}
