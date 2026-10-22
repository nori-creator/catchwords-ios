import SwiftUI
import UIKit

/// One day of the home album, laid out exactly like the web (`AlbumLayout.layoutDayAlbum`, a port of
/// album-day-layout.ts): photos placed by hand stay where they were put; the rest settle around them.
/// Positions are shared with the web through the same columns, so the page looks the same on both.
///
/// Each photo is the picture chosen in 設定 › ホームに表示する写真 (`AlbumPhoto`): the cut-out alone by default, with
/// the word on a beige paper tag stuck across its lower edge (owner 2026-10-11, the welcome mock's tags).
///
/// Rearranging (web DayCollage, owner 2026-10-11: 「ホームの画像を長押ししたら、WEB版のように画像が揺れ出して、大きさや
/// 配置を自由自在に変更できるように。並べ替えボタンはけして」): a long press (0.5 s) on any photo starts it — every
/// photo wiggles, the one under the finger is lifted and follows it at once. Then any photo can be dragged, pinched
/// to any size and twisted (two fingers anywhere on it), its ✕ takes it off the album, and 「完了」 (HomeView) saves.
/// Near level a photo snaps straight with a tick; the one you touch comes to the front.
///
/// A finger that moves before the long press is recognised scrolls the page (the press is UIKit's, which gives way
/// to the scroll view; 2026-10-11: 「単語のうえで上下にスクロールすると反応しない」). While a photo moves, only that
/// photo is redrawn (`CollagePiece` keeps the finger's change to itself); the page is laid out again when it is let go
/// (「長押ししたときの単語の動きがカクカク」).
struct CollageBoard: View {
    let items: [Sticker]
    let editable: Bool
    let onOpen: (Sticker) -> Void
    /// Lay every photo out automatically, ignoring positions placed by hand (the memorial album).
    var autoOnly: Bool = false
    /// Tells the screen to stop scrolling (and show 「完了」) while photos are being moved.
    var onEditingChange: ((Bool) -> Void)? = nil
    /// Goes up when 「完了」 is pressed: an editing board saves and stops.
    var finishRequest: Int = 0

    @Environment(DexStore.self) private var dex
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var boardW: CGFloat = 0
    @State private var editing = false
    @State private var saving = false
    /// Something moved since editing began (「完了」 without a change saves nothing).
    @State private var changed = false
    /// While editing: placements set by the fingers (not saved yet) and the front-to-back order.
    @State private var live: [String: AlbumPlacement] = [:]
    @State private var front: [String] = []
    @State private var grabbed: String?

    var body: some View {
        let layout = computeLayout()
        ZStack(alignment: .topLeading) {
            ForEach(layout.items.sorted { z($0) < z($1) }, id: \.id) { item in
                if let s = items.first(where: { $0.id == item.id }) {
                    CollagePiece(
                        sticker: s,
                        item: item,
                        boardW: boardW,
                        editing: editing,
                        canEdit: editable && !autoOnly,
                        isGrabbed: grabbed == s.id,
                        reduceMotion: reduceMotion,
                        onOpen: { onOpen(s) },
                        onGrab: { grab(s.id) },
                        onRelease: { place in release(s.id, at: place) },
                        onRemove: { remove(s.id) }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: max(1, layout.boardH * boardW))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { boardW = $0 }
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.82), value: editing)
        .onChange(of: editing) { _, on in onEditingChange?(on) }
        .onChange(of: finishRequest) { _, _ in if editing { finish() } }
        // Never leave the screen frozen if this board goes away mid-edit; what was moved is kept.
        .onDisappear {
            if editing {
                if changed { persist() }
                onEditingChange?(false)
            }
        }
    }

    // MARK: Layout

    private func computeLayout() -> (items: [DayLayoutItem], boardH: Double) {
        guard boardW > 0 else { return ([], 1.25) }
        let stickers: [DayLayoutSticker] = items.map { s in
            var d = (autoOnly ? nil : dex.albumPlacements[s.id]) ?? DayLayoutSticker(id: s.id)
            d.id = s.id
            d.caption = s.caption
            if let p = live[s.id] {
                d.albumX = p.x
                d.albumY = p.y
                d.albumScale = p.scale
                d.albumRot = p.rot
            }
            if let i = front.firstIndex(of: s.id) { d.albumOrder = i }
            return d
        }
        var ratios: [String: Double] = [:]
        for s in items {
            if let path = AlbumPhoto.path(for: s), let img = ImageCache.shared.image(for: path), img.size.width > 0 {
                ratios[s.id] = img.size.height / img.size.width
            }
        }
        let input = DayLayoutInput(
            stickers: stickers,
            hasHero: { id in items.first { $0.id == id }.flatMap { AlbumPhoto.path(for: $0) } != nil },
            photoRatio: ratios,
            boardW: Double(boardW)
        )
        return AlbumLayout.layoutDayAlbum(input)
    }

    private func z(_ item: DayLayoutItem) -> Int {
        if let i = front.firstIndex(of: item.id) { return 1000 + i }
        return item.z
    }

    // MARK: Rearranging

    /// Freezes the day's positions (automatic ones included) so moving one photo never shuffles the others.
    private func startEditing() {
        guard !editing else { return }
        Haptics.impact(.medium)
        let layout = computeLayout()
        var frozen: [String: AlbumPlacement] = [:]
        for i in layout.items { frozen[i.id] = i.place }
        live = frozen
        front = layout.items.sorted { $0.z < $1.z }.map(\.id)
        changed = false
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { editing = true }
    }

    /// A finger took this photo (a long press, or a touch while rearranging): it is lifted and comes to the front.
    private func grab(_ id: String) {
        if !editing { startEditing() }
        guard grabbed != id else { return }
        grabbed = id
        Haptics.impact(.soft)
        guard front.last != id else { return }
        changed = true
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            front.removeAll { $0 == id }
            front.append(id)
        }
    }

    /// The finger let go where `place` says: kept (straightened when near level) until 「完了」 saves the page.
    private func release(_ id: String, at place: AlbumPlacement) {
        let settled = AlbumLayout.settle(place)
        if live[id] != settled { changed = true }
        // Damped (no overshoot): the photo stays where the finger left it and only straightens.
        withAnimation(.spring(response: 0.26, dampingFraction: 0.9)) {
            live[id] = settled
            grabbed = nil
        }
    }

    /// The red ✕ while rearranging: the photo leaves the album (it stays in the dex; 「アルバムから外した写真」 has it).
    private func remove(_ id: String) {
        Haptics.impact(.light)
        withAnimation(.snappy) { dex.albumUndo = id }
        Task {
            let ok = await dex.setAlbumHidden(id, hidden: true)
            if !ok { Haptics.warning() }
        }
    }

    /// 「完了」: saves what moved and stops rearranging.
    private func finish() {
        guard editing, !saving else { return }
        if changed { persist() }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            editing = false
            grabbed = nil
        }
        if !changed {
            live = [:]
            front = []
        }
    }

    /// Saves every photo of the day (web `persistLayout`): its order, size, place, scale and tilt.
    private func persist() {
        let layout = computeLayout()
        let byId = Dictionary(uniqueKeysWithValues: layout.items.map { ($0.id, $0) })
        let entries: [(id: String, order: Int, size: AlbumSize, place: AlbumPlacement)] = front.enumerated().compactMap { i, id in
            guard let item = byId[id] else { return nil }
            let size = dex.albumPlacements[id]?.albumSize ?? AlbumLayout.AUTO_ALBUM_SIZE[i % AlbumLayout.AUTO_ALBUM_SIZE.count]
            return (id, i, size, live[id] ?? item.place)
        }
        saving = true
        Task {
            let ok = await dex.saveAlbumLayout(entries)
            saving = false
            if ok { Haptics.success() } else { Haptics.warning() }
            // The saved places are the dex's now: the fingers' copies can go (unless editing started again).
            if !editing {
                live = [:]
                front = []
            }
            changed = false
        }
    }
}

/// One photo on the album page. While a finger moves it, the change lives here (`press` from the long press,
/// `pinch` from the fingers while rearranging) and only this view is redrawn; the board takes the final place when
/// the finger lets go.
private struct CollagePiece: View {
    let sticker: Sticker
    let item: DayLayoutItem
    let boardW: CGFloat
    let editing: Bool
    /// This board can be rearranged (not the memorial album).
    let canEdit: Bool
    let isGrabbed: Bool
    let reduceMotion: Bool
    let onOpen: () -> Void
    let onGrab: () -> Void
    let onRelease: (AlbumPlacement) -> Void
    let onRemove: () -> Void

    /// The long press's finger since it was recognised (it keeps carrying the photo until it lifts).
    @State private var press: AlbumDelta?
    /// Drag, pinch and twist while rearranging. Let go, it hands over to the board's new place in the same animation,
    /// so the photo never jumps back to where it was for a frame.
    @GestureState(resetTransaction: Transaction(animation: .spring(response: 0.26, dampingFraction: 0.9)))
    private var pinch: AlbumDelta? = nil
    /// Near level right now (a tick when it snaps straight).
    @State private var snapped = false
    /// Scrolls the home page while this photo is carried to the screen's edge (absent on the memorial album).
    @Environment(AlbumAutoScroll.self) private var autoScroll: AlbumAutoScroll?

    /// The finger's movement plus how far the page scrolled under it since the photo was taken: the photo stays
    /// under the finger while the page runs (owner 2026-10-14).
    private var delta: AlbumDelta? {
        guard var d = pinch ?? press else { return nil }
        d.dy += Double(autoScroll?.scrolled ?? 0)
        return d
    }

    /// Where the photo is drawn now: its place on the page, moved by the finger.
    private var shown: AlbumPlacement {
        guard let delta else { return item.place }
        return AlbumLayout.applyDelta(item.place, delta, boardW: Double(boardW), maxY: 8)
    }

    var body: some View {
        let p = shown
        let size = AlbumLayout.sizePx(p, boardW: Double(boardW), ratio: item.ratio)
        let hasHero = AlbumPhoto.path(for: sticker) != nil
        let captionH = hasHero ? AlbumLayout.dayExtra(DayLayoutSticker(id: sticker.id, caption: sticker.caption), hasHero: true, boardW: Double(boardW)) * Double(boardW) : 0
        let lifted = isGrabbed || delta != nil
        let wiggles = editing && !reduceMotion && !lifted
        // 30 frames a second is plenty for the shiver (every photo of the day redrew at up to 120 with its shadows,
        // which made the photo under the finger stutter, owner 2026-10-14: 「なめらかに動かない。残像が残る」).
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !wiggles)) { ctx in
            let w = wiggles ? Self.wiggle(sticker.id, at: ctx.date) : (rot: 0.0, lift: 0.0)
            card(hasHero: hasHero, size: size, captionH: captionH, lifted: lifted)
                // While rearranging, drawn once into one layer (shadows included, with room for them): the shiver and
                // the drag then only move that layer instead of drawing every shadow again each frame. Only then: the
                // layer is drawn with Metal, and its first draw compiles Metal pipelines on the main thread — done for
                // every photo of the album, it held the main thread as the home album first showed its photos (13 s on
                // the UI tour's simulator, 2026-10-16).
                .modifier(FlattenedWhileEditing(on: editing && canEdit, room: Self.shadowRoom))
                .overlay(alignment: .topLeading) {
                    if editing && canEdit { removeButton }
                }
                .scaleEffect(lifted ? 1.06 : 1)
                .rotationEffect(.degrees(p.rot + w.rot))
                .offset(y: w.lift)
        }
        // The photo's own area takes the touches — set before it is positioned, so a tap on 地瓜 can never open the
        // photo drawn above it (`.position` makes a view as big as the whole page; 2026-10-11).
        .contentShape(.rect)
        .onTapGesture { if !editing { onOpen() } }
        // Stays on while rearranging (turning it off would cancel the very press that started it); presses then
        // are left to the fingers' own gestures (`began`).
        .gesture(LongPressGrab(enabled: canEdit, onBegan: began, onMoved: moved, onEnded: ended))
        .simultaneousGesture(manipulate, including: editing && canEdit ? .all : .subviews)
        .position(x: p.x * Double(boardW), y: p.y * Double(boardW) + captionH / 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(sticker.word?.headword ?? "")
        .accessibilityHint(editing ? L("ドラッグで移動、2本指で大きさと傾き") : L("単語をひらく"))
        .accessibilityAction(named: L("配置を変える")) { if canEdit && !editing { onGrab() } }
        .accessibilityAction(named: L("アルバムから外す")) { if canEdit && editing { onRemove() } }
    }

    // MARK: The long press (starts rearranging, then carries the photo)

    private func began() {
        // While rearranging, a finger on a photo is the drag below, not a new press.
        guard !editing else { return }
        onGrab()
        autoScroll?.begin()
        press = AlbumDelta(dx: 0, dy: 0, scale: 1, rot: 0)
    }

    private func moved(_ t: CGSize, _ windowY: CGFloat) {
        guard press != nil else { return }
        press = AlbumDelta(dx: t.width, dy: t.height, scale: 1, rot: 0)
        autoScroll?.finger(atWindowY: windowY)
    }

    private func ended(_ t: CGSize?) {
        guard press != nil else { return }
        let scrolled = Double(autoScroll?.end() ?? 0)
        let final = t.map { AlbumLayout.applyDelta(item.place,
                                                   AlbumDelta(dx: $0.width, dy: $0.height + scrolled, scale: 1, rot: 0),
                                                   boardW: Double(boardW), maxY: 8) } ?? item.place
        // The finger's offset and the board's new place change together, in one animation: the photo used to snap
        // back to its old place for a frame and spring over again (an afterimage).
        withAnimation(.spring(response: 0.26, dampingFraction: 0.9)) { press = nil }
        onRelease(final)
    }

    // MARK: Drag + pinch + twist while rearranging (web album-place.ts gestureDelta / applyDelta / settle)

    private var manipulate: some Gesture {
        // Measured on the screen, not in the photo's own frame: that frame moves with the photo, so the distance fed
        // back into itself and the photo flickered between two places while dragged.
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .simultaneously(with: MagnifyGesture())
            .simultaneously(with: RotateGesture())
            .updating($pinch) { v, state, _ in
                state = Self.delta(of: v)
            }
            .onChanged { v in
                if !isGrabbed {
                    onGrab()
                    autoScroll?.begin()
                }
                if let y = v.first?.first?.location.y { autoScroll?.finger(atWindowY: y) }
                let rot = v.second?.rotation.degrees ?? 0
                let near = abs(AlbumLayout.normalizeDeg(item.place.rot + rot)) <= AlbumLayout.ROT_SNAP_DEG
                if near != snapped {
                    snapped = near
                    if near && rot != 0 { Haptics.selection() }
                }
            }
            .onEnded { v in
                snapped = false
                var d = Self.delta(of: v)
                d.dy += Double(autoScroll?.end() ?? 0)
                onRelease(AlbumLayout.applyDelta(item.place, d, boardW: Double(boardW), maxY: 8))
            }
    }

    private static func delta(of v: SimultaneousGesture<SimultaneousGesture<DragGesture, MagnifyGesture>, RotateGesture>.Value) -> AlbumDelta {
        let t = v.first?.first?.translation ?? .zero
        return AlbumDelta(dx: t.width, dy: t.height,
                          scale: Double(v.first?.second?.magnification ?? 1),
                          rot: v.second?.rotation.degrees ?? 0)
    }

    // MARK: Drawing

    @ViewBuilder
    private func card(hasHero: Bool, size: (w: Double, h: Double), captionH: Double, lifted: Bool) -> some View {
        let word = sticker.word?.headword ?? ""
        if hasHero {
            VStack(spacing: 0) {
                AlbumPhoto(sticker: sticker, width: size.w, height: size.h, lifted: lifted)
                    .overlay(alignment: .bottom) {
                        // The tag hangs across the photo's lower edge, into the strip kept under it (CAP_ROW_PX).
                        if !word.isEmpty {
                            WordTag(text: word, zhuyin: sticker.word?.readingZhuyin, pinyin: sticker.word?.pinyin,
                                    tilt: Self.tagTilt(sticker.id))
                                .offset(x: Self.tagShift(sticker.id) * size.w, y: WordTag.height / 2)
                        }
                    }
                // The strip under the photo: the tag's lower half, then the one-liner when there is one.
                Group {
                    if let c = sticker.caption, !c.isEmpty {
                        Text(c)
                            .font(.system(size: 15))
                            .foregroundStyle(Color(hex: 0x33291F).opacity(0.85))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .padding(.top, WordTag.height / 2 + 6)
                    }
                }
                .frame(width: max(size.w, Double(boardW) * 0.3), height: max(0, captionH), alignment: .top)
            }
        } else {
            // A word looked up from text (no photo): its tag alone.
            WordTag(text: word, zhuyin: sticker.word?.readingZhuyin, pinyin: sticker.word?.pinyin,
                    tilt: Self.tagTilt(sticker.id), size: 26)
                .frame(width: size.w, height: max(size.h, 44))
        }
    }

    /// The red ✕ while rearranging: takes the photo off the album.
    private var removeButton: some View {
        Button(action: onRemove) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color(hex: 0xE5484D), in: Circle())
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        // Inside the photo's own touch area (it ended at the photo's edge, so half of the ✕ could not be pressed).
        .offset(x: -6, y: -6)
        .accessibilityLabel(L("アルバムから外す"))
        .transition(.scale.combined(with: .opacity))
    }

    /// The web's jiggle (album-drag.ts JIGGLE): ±1.1° and ±0.9 pt, a 240–300 ms cycle that differs per photo and
    /// starts at a different point, so the page shivers instead of swaying in step.
    private static func wiggle(_ id: String, at date: Date) -> (rot: Double, lift: Double) {
        let h = AlbumLayout.idHash(id)
        let period = 0.24 + Double((h >> 8) % 60) / 1000
        let delay = Double(h % 240) / 1000
        let phase = (date.timeIntervalSinceReferenceDate + delay) / period * 2 * Double.pi
        let v = sin(phase)
        return (v * 1.1, v * 0.9)
    }

    /// Room around the drawn photo for its shadow (deepest while lifted: radius 11, 11 pt down) and the tag's tilt.
    private static let shadowRoom: CGFloat = 26

    /// Each tag leans its own way (−6°…6°, from the id, so it never changes between draws).
    private static func tagTilt(_ id: String) -> Double {
        Double(Int(AlbumLayout.idHash(id) % 121) - 60) / 10
    }

    /// …and sits a little left or right of the middle (−18 %…18 % of the photo's width).
    private static func tagShift(_ id: String) -> Double {
        Double(Int((AlbumLayout.idHash(id) >> 7) % 37) - 18) / 100
    }
}

/// The word on a beige paper tag (the welcome mock's label: 咖啡 / 植物 under the stickers).
struct WordTag: View {
    let text: String
    /// The word's reading, drawn the way the rest of the app draws it (`ZhuyinWordView`: zhuyin beside each character,
    /// or pinyin above it per 設定 › 発音表記; kana for Japanese; none for English) — owner 2026-10-20.
    var zhuyin: String? = nil
    var pinyin: String? = nil
    var tilt: Double = 0
    /// The characters' size. The reading keeps the word page's proportion (pinyin 0.36, zhuyin 0.3 of it) at any size
    /// (owner 2026-10-20: 「単語の詳細の見出しの大きさのバランスにして」 — at 15 pt the reading's 9 pt minimum made it as
    /// big as the characters). 20 pt keeps the reading legible; an English word, with no reading, stays at 15 pt.
    var size: CGFloat? = nil
    /// The word's language (nil = the learner's learning language): the first-run guide's stickers are Mandarin
    /// before the account's learning language is saved.
    var language: String? = nil
    private var textSize: CGFloat { size ?? ((language ?? NativeAPI.targetLanguage) == "en" ? 15 : 20) }

    /// The tag's height without a reading at 15 pt (the album keeps half of it under the photo).
    static let height: CGFloat = 28

    private static let ink = Color(hex: 0x4A3A28)

    var body: some View {
        ZhuyinWordView(headword: text, zhuyin: zhuyin, size: textSize, weight: .bold, color: Self.ink,
                       readingColor: Self.ink.opacity(0.75), pinyin: pinyin, language: language,
                       proportionalReading: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
            .frame(minHeight: Self.height * min(textSize, 15) / 15)
            .background(Color(hex: 0xF6E4C8), in: .rect(cornerRadius: 3, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).stroke(Color(hex: 0xE6CFA8), lineWidth: 0.5))
            .shadow(color: Color(hex: 0x5A4630).opacity(0.22), radius: 2.5, y: 1.5)
            .rotationEffect(.degrees(tilt))
            .allowsHitTesting(false)
    }
}

/// A long press that keeps following the finger once recognised (UIKit). Until it is recognised it leaves the
/// scroll view alone — a finger that moves first scrolls the page — and once it is, the page stays still and the
/// finger carries the photo. Translations are in points, measured in the window.
private struct LongPressGrab: UIGestureRecognizerRepresentable {
    var enabled: Bool
    let onBegan: () -> Void
    /// The finger's translation, and its height in the window (for the page's auto-scroll).
    let onMoved: (CGSize, CGFloat) -> Void
    /// The finger's last translation, or nil when the press was cancelled.
    let onEnded: (CGSize?) -> Void

    final class Recognizer: UILongPressGestureRecognizer {
        var start: CGPoint = .zero
    }

    func makeUIGestureRecognizer(context: Context) -> Recognizer {
        let r = Recognizer()
        r.minimumPressDuration = 0.5
        r.allowableMovement = 10
        r.isEnabled = enabled
        return r
    }

    func updateUIGestureRecognizer(_ recognizer: Recognizer, context: Context) {
        recognizer.isEnabled = enabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: Recognizer, context: Context) {
        let point = recognizer.location(in: recognizer.view?.window)
        let t = CGSize(width: point.x - recognizer.start.x, height: point.y - recognizer.start.y)
        switch recognizer.state {
        case .began:
            recognizer.start = point
            onBegan()
        case .changed:
            onMoved(t, point.y)
        case .ended:
            onEnded(t)
        case .cancelled, .failed:
            onEnded(nil)
        default:
            break
        }
    }
}

/// The album photo drawn into one layer while the page is being rearranged (`CollagePiece`), plainly otherwise.
private struct FlattenedWhileEditing: ViewModifier {
    let on: Bool
    let room: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if on {
            content.padding(room).drawingGroup().padding(-room)
        } else {
            content
        }
    }
}

/// A selfie on the album page cut down to its people and what they hold (`SelfieCutouts`): a soft blank while it is
/// made, then the cut-out with the stickers' shadow.
private struct SelfieAlbumCutout: View {
    let path: String
    let width: CGFloat
    let height: CGFloat
    let lifted: Bool

    @Environment(DexStore.self) private var dex
    @State private var image: UIImage?

    var body: some View {
        let ready = SelfieCutouts.shared.state(for: path) == .ready
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .transition(.opacity)
                    .shadow(color: Color(hex: 0x5A4630).opacity(lifted ? 0.34 : 0.25), radius: lifted ? 11 : 3, y: lifted ? 11 : 2)
            } else {
                RoundedRectangle(cornerRadius: min(width, height) * 0.18, style: .continuous)
                    .fill(Color(hex: 0x33291F, opacity: 0.05))
            }
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
        .task(id: "\(path)|\(ready)") {
            guard ready else {
                SelfieCutouts.shared.request(path, dex: dex)
                return
            }
            if let kept = await ImageCache.shared.cached(for: SelfieCutouts.key(for: path)) {
                withAnimation(.easeOut(duration: 0.25)) { image = kept }
            } else {
                // The system emptied the cache: made again.
                SelfieCutouts.shared.forget(path)
            }
        }
    }
}

/// One photo in the album: the picture chosen in 設定 › ホームに表示する写真 (`Sticker.homePath`). A cut-out
/// (`stickers.cutout_image_url`, a transparent PNG) stands alone like a sticker, with only a soft shadow that follows
/// its outline — no white print, paper or frame behind it; a photo or a selfie is clipped round.
struct AlbumPhoto: View {
    let sticker: Sticker
    let width: CGFloat
    let height: CGFloat
    /// Picked up while rearranging: a deeper shadow.
    var lifted: Bool = false

    @Environment(DexStore.self) private var dex

    /// The picture the album shows for a catch (設定 › ホームに表示する写真).
    nonisolated static func path(for s: Sticker) -> String? { s.homePath }

    var body: some View {
        picture
            // A cut-out made on this phone (`CutoutBackfill`) fades in over the photo shown until then, rather than
            // swapping in at once (owner 2026-10-14: 「元の画像が一瞬表示されて、すぐ切り抜きになる」).
            .animation(.easeInOut(duration: 0.45), value: sticker.cutoutImageUrl)
    }

    @ViewBuilder private var picture: some View {
        let path = sticker.homePath
        if let path, path == sticker.selfieImageUrl, SelfieCutouts.shared.state(for: path) != .noPerson {
            // A selfie: its people and what they hold, cut out like the other stickers (made on this phone).
            SelfieAlbumCutout(path: path, width: width, height: height, lifted: lifted)
        } else if let path, path == sticker.cutoutImageUrl {
            // Decoded at the size it is drawn (a copy for the album, not the whole cut-out).
            StickerImage(path: path, url: dex.url(for: path, preferThumb: false), contentMode: .fit, maxPoints: max(width, height))
                .allowsHitTesting(false)
                .frame(width: width, height: height)
                .shadow(color: Color(hex: 0x5A4630).opacity(lifted ? 0.34 : 0.25), radius: lifted ? 11 : 3, y: lifted ? 11 : 2)
        } else if let path {
            StickerImage(path: path, url: dex.url(for: path, preferThumb: false), contentMode: .fill, maxPoints: max(width, height))
                .allowsHitTesting(false)
                .frame(width: width, height: height)
                .clipShape(.rect(cornerRadius: min(width, height) * 0.18, style: .continuous))
                .shadow(color: Color(hex: 0x5A4630).opacity(lifted ? 0.34 : 0.18), radius: lifted ? 11 : 4, y: lifted ? 11 : 2)
        } else {
            Color.clear.frame(width: width, height: height)
        }
    }
}
