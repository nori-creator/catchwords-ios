import SwiftUI

/// One photo of a word: the first catch or a re-encounter (server `listStickerPhotos`).
struct StickerPhoto: Decodable, Identifiable, Equatable {
    let url: String
    let takenAt: String
    let place: String?
    let first: Bool
    var id: String { url }
    enum CodingKeys: String, CodingKey { case url, place, first, takenAt = "taken_at" }

    private struct Res: Decodable { let photos: [StickerPhoto] }
    /// Kept for the session so the word page and its history section share one request.
    private static var cache: [String: [StickerPhoto]] = [:]

    static func load(stickerId: String) async -> [StickerPhoto] {
        if let hit = cache[stickerId] { return hit }
        guard let res = try? await NativeAPI.call("listStickerPhotos", ["sticker_id": stickerId], as: Res.self) else { return [] }
        cache[stickerId] = res.photos
        return res.photos
    }

    /// A new or replaced photo: the next look asks the server again instead of showing the old list.
    static func invalidate(_ stickerId: String) { cache[stickerId] = nil }

    /// Signing out: forget every list (they hold that account's signed photo links).
    static func invalidateAll() { cache = [:] }
}

/// Web `StickerPhotoHistory`: every photo of this word — the first catch and each re-encounter —
/// in the order you met it, with where. Hidden when there is only the first photo.
struct EncounterHistoryView: View {
    let stickerId: String

    private typealias Photo = StickerPhoto

    @State private var photos: [Photo] = []
    @State private var appeared = false

    var body: some View {
        Group {
            if photos.count > 1 {
                SectionCard(title: L("この言葉に出会った記録"), icon: "photo.stack") {
                    HStack {
                        Text(L("\(photos.count)枚")).scaledFont(size: 13).foregroundStyle(Theme.muted)
                        Spacer()
                    }
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(Array(photos.enumerated()), id: \.element.id) { i, p in
                                card(p, index: i)
                                    .opacity(appeared ? 1 : 0)
                                    .offset(y: appeared ? 0 : 14)
                                    .animation(.spring(response: 0.5, dampingFraction: 0.82).delay(Double(i) * 0.06), value: appeared)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .scrollIndicators(.hidden)
                    .scrollTargetBehavior(.viewAligned)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .task(id: stickerId) {
            let list = await StickerPhoto.load(stickerId: stickerId)
            guard !list.isEmpty else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { photos = list }
            appeared = true
        }
    }

    private func card(_ p: Photo, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: URL(string: p.url)) { phase in
                if let img = phase.image {
                    img.resizable().scaledToFill()
                } else {
                    Theme.secondary
                }
            }
            .frame(width: 118, height: 118)
            .clipShape(.rect(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .topLeading) {
                Text(p.first ? L("はじめて") : L("\(index + 1)回目"))
                    .scaledFont(size: 11, weight: .semibold)
                    .foregroundStyle(p.first ? .white : Theme.primaryInk)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(p.first ? AnyShapeStyle(Theme.primary) : AnyShapeStyle(.white.opacity(0.92)), in: Capsule())
                    .padding(6)
            }
            .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
            if let d = SupabaseDate.parse(p.takenAt) {
                Text(JPDate.full(d)).scaledFont(size: 11, monospacedDigit: true).foregroundStyle(Theme.muted)
            }
            if let place = LocationService.shownPlace(p.place) {
                Label(place, systemImage: "mappin").scaledFont(size: 11).foregroundStyle(Theme.muted).lineLimit(1)
            }
        }
        .frame(width: 118, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(p.first ? L("はじめて撮った写真") : L("\(index + 1)回目に撮った写真"))
    }
}
