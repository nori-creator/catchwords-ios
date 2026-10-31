import SwiftUI

/// Sinks on touch-DOWN (not release) and springs back — apple-design §14 as used across the web app.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(.spring(response: 0.28, dampingFraction: 0.62), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptics.impact(.light, intensity: 0.6) }
            }
    }
}

/// Primary CTA with the slow sheen every 3.4s (catch-cta-sheen).
struct PrimaryButton: View {
    let title: String
    var icon: String?
    var isLoading: Bool = false
    var sheen: Bool = false
    let action: () -> Void

    @State private var sheenPhase: CGFloat = -1
    @Environment(\.appReduceMotion) private var reduceMotion
    /// `.disabled(...)` from the caller (an empty search, nothing to import): the button greys out.
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().tint(.white)
                } else if let icon {
                    Image(systemName: icon).scaledFont(size: 17, weight: .semibold)
                }
                Text(title).scaledFont(size: 17, weight: .semibold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Theme.brandGradient)
            .overlay {
                if sheen && !reduceMotion {
                    GeometryReader { geo in
                        LinearGradient(colors: [.clear, .white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.35)
                            .rotationEffect(.degrees(18))
                            .offset(x: sheenPhase * geo.size.width * 1.4)
                    }
                    .allowsHitTesting(false)
                }
            }
            .clipShape(.rect(cornerRadius: 16))
            .shadow(color: Theme.primary.opacity(isEnabled ? 0.45 : 0), radius: 16, y: 8)
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(PressableStyle())
        .disabled(isLoading)
        .task(id: sheen) {
            guard sheen, !reduceMotion else { return }
            while !Task.isCancelled {
                sheenPhase = -1
                withAnimation(.easeInOut(duration: 1.1)) { sheenPhase = 1 }
                try? await Task.sleep(for: .seconds(3.4))
            }
        }
    }
}

/// Atmosphere: near-white paper with a faint blue light pool (never a flat fill).
struct AppBackground: View {
    var body: some View {
        ZStack {
            Theme.background
            RadialGradient(colors: [Theme.primary.opacity(0.07), .clear], center: .topTrailing, startRadius: 10, endRadius: 460)
            RadialGradient(colors: [Theme.accent.opacity(0.5), .clear], center: .bottomLeading, startRadius: 10, endRadius: 420)
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Scrolled content must not run under the clock and battery: a strip of material over the status bar
    /// (a zero-height inset whose background reaches up into the safe area). Nothing moves at rest.
    func statusBarScrim() -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            Color.clear
                .frame(height: 0)
                .background(.regularMaterial)
                .allowsHitTesting(false)
        }
    }
}

/// memory-badge.ts: colour + number only (the level name lives in the accessibility label).
struct MemoryBadge: View {
    let percent: Int

    static func level(_ p: Int) -> Int {
        if p < 30 { return 0 }
        if p < 50 { return 1 }
        if p < 70 { return 2 }
        if p < 85 { return 3 }
        if p < 95 { return 4 }
        return 5
    }

    static var labels: [String] { [L("忘れかけ"), L("あやうい"), L("うろ覚え"), L("薄れぎみ"), L("覚えている"), L("はっきり")] }

    var body: some View {
        let lv = Self.level(percent)
        let c = Theme.memoryLevels[lv]
        HStack(spacing: 4) {
            Circle().fill(c).frame(width: 6, height: 6)
            Text("\(percent)%")
                .scaledFont(size: 11, weight: .semibold, monospacedDigit: true)
                .foregroundStyle(c.mix(with: Theme.foreground, by: 0.4))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Theme.card.opacity(0.94), in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Self.labels[lv]) \(percent)%")
    }
}

/// Pure memory math from srs.ts (retentionNow / stabilityOf).
nonisolated enum MemoryMath {
    private static let k: Double = 1 / (2.5 * log(1 / 0.9))

    static func stability(intervalDays: Int, ease: Double) -> Double {
        max(0.5, Double(max(1, intervalDays)) * max(1, ease) * k)
    }

    static func percent(intervalDays: Int, ease: Double, last: Date?, now: Date = Date()) -> Int {
        Int(exactPercent(intervalDays: intervalDays, ease: ease, last: last, now: now).rounded())
    }

    /// The same, not rounded: a curve drawn from whole percents climbs down in 1 % steps and looks jagged
    /// (owner 2026-10-27: 「グラフがぎざぎざ、波うってる」).
    static func exactPercent(intervalDays: Int, ease: Double, last: Date?, now: Date = Date()) -> Double {
        guard let last else { return 100 }
        let dt = now.timeIntervalSince(last) / 86_400
        guard dt > 0 else { return 100 }
        let stability = max(0.5, Double(max(1, intervalDays)) * max(1, ease) * k)
        return max(0, min(100, 100 * exp(-dt / stability)))
    }
}

/// Loads a sticker photo by storage path: memory, then the copy kept on this phone (`ImageCache` disk), then the
/// signed link. A picture whose link is missing (a catch just saved, a signing that failed) or no longer works
/// (links last 6 hours) asks the dex for a new one, and the new link draws it — it never stays blank for the
/// rest of the session (the home album's 馬桶 that showed no picture, 2026-10-11).
struct StickerImage: View {
    let path: String?
    let url: URL?
    var contentMode: ContentMode = .fit
    /// The largest side the picture is drawn at, in points, when it is small (a square of the dex, a sticker on the
    /// album): a copy decoded at that size is used instead of the whole picture (`ImageCache.kept(for:maxPixel:)`).
    /// nil: the picture itself (the word page).
    var maxPoints: CGFloat? = nil
    /// Told the picture's size once it is drawn (the word page shapes its hero after the cut-out).
    var onLoad: ((CGSize) -> Void)? = nil

    /// Optional: screens outside the signed-in app (previews) have no dex; they only use the cache.
    @Environment(DexStore.self) private var dex: DexStore?
    @State private var image: UIImage?

    /// A picture already in memory is drawn in the very first frame. It used to come one frame later (the `.task`), so
    /// a dex page drawn anew — the catch's landing opens it fresh — showed every square empty for a moment, and longer
    /// for the ones read from disk (owner 2026-10-15: the dex went blank during the add animation).
    init(path: String?, url: URL?, contentMode: ContentMode = .fit, maxPoints: CGFloat? = nil, onLoad: ((CGSize) -> Void)? = nil) {
        self.path = path
        self.url = url
        self.contentMode = contentMode
        self.maxPoints = maxPoints
        self.onLoad = onLoad
        _image = State(initialValue: Self.inMemory(path: path, url: url, maxPixel: Self.step(maxPoints, contentMode)))
    }

    /// The size step the picture is decoded at (nil: whole).
    private var maxPixel: Int? { Self.step(maxPoints, contentMode) }

    /// Filling a frame, the picture's longer side runs past it (a 4:3 photo in a square): half again as much.
    private static func step(_ points: CGFloat?, _ mode: ContentMode) -> Int? {
        guard let points else { return nil }
        return ImageCache.pixelStep(forPoints: mode == .fill ? points * 1.5 : points)
    }

    /// The picture (or its stand-in size) already in memory, read without waiting.
    private static func inMemory(path: String?, url: URL?, maxPixel: Int?) -> UIImage? {
        guard let path else { return nil }
        let thumb = url.map { $0.path.hasSuffix(DexStore.thumbSuffix) } ?? false
        let key = thumb ? path + DexStore.thumbSuffix : path
        return ImageCache.shared.image(for: key, maxPixel: maxPixel)
            ?? ImageCache.shared.image(for: thumb ? path : path + DexStore.thumbSuffix, maxPixel: maxPixel)
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                Color.clear
            }
        }
        // Keyed on the URL too: the signed URL usually arrives after the first draw, and a task keyed on the
        // path alone never ran again, leaving the picture blank. And on the size step: a sticker made bigger on the
        // album gets a sharper copy.
        .task(id: "\(path ?? "")|\(url?.absoluteString ?? "")|\(maxPixel ?? 0)") { await fill() }
        .onChange(of: image) { _, img in
            guard let img else { return }
            loaded(img)
        }
    }

    private func loaded(_ img: UIImage) {
        UITestTrace.once("first photo on screen")
        onLoad?(img.size)
        // A cut-out that came out (almost) empty: the dex shows the word's photo instead. Looked at off the main thread
        // (it draws the whole picture once), once per cut-out found not empty.
        if let path, path.contains("-cutout"), !Self.notBlank.contains(path) {
            let dex = self.dex
            Task {
                let blank = await Task.detached(priority: .utility) { ImageTools.isNearlyBlank(img) }.value
                if blank { dex?.markBlankCutout(path) } else { Self.notBlank.insert(path) }
            }
        }
    }

    /// Cut-outs already looked at and found not empty (a storage path never changes content).
    private static var notBlank: Set<String> = []

    private func fill() async {
        guard let path else { return }
        let cache = ImageCache.shared
        let px = maxPixel
        // The link says which size this is: a thumbnail is kept under its own key, never as the full picture.
        let thumb = url.map { $0.path.hasSuffix(DexStore.thumbSuffix) } ?? false
        let key = thumb ? path + DexStore.thumbSuffix : path
        // Already here: the very picture, or the full one where a thumbnail was asked for (only better).
        if let hit = cache.image(for: key, maxPixel: px) ?? (thumb ? cache.image(for: path, maxPixel: px) : nil) {
            // Drawn from the first frame already (`init`): told now, since no change of `image` will tell it.
            if image === hit { loaded(hit) } else { image = hit }
            return
        }
        // While the full picture comes, its thumbnail stands in.
        if image == nil, !thumb, let small = cache.image(for: path + DexStore.thumbSuffix, maxPixel: px) { image = small }
        var kept = await cache.kept(for: key, maxPixel: px)
        if kept == nil, thumb { kept = await cache.kept(for: path, maxPixel: px) }
        if kept == nil, !thumb, image == nil { kept = await cache.kept(for: path + DexStore.thumbSuffix, maxPixel: px) }
        guard !Task.isCancelled else { return }
        if let kept {
            image = kept
            // A thumbnail kept on disk stood in for a full picture: go on and fetch the full one.
            if thumb || cache.image(for: path, maxPixel: px) != nil { return }
        }
        guard let url else {
            dex?.requestSigning(path)
            return
        }
        if let loaded = await cache.load(url: url, key: key, maxPixel: px) {
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { image = loaded }
            return
        }
        // A thumbnail that does not load (a broken or unreadable companion file): the full picture instead, rather
        // than an empty square (owner 2026-10-14: 「図鑑に表示されてない単語がある」).
        if thumb, let full = dex?.url(for: path, preferThumb: false), full != url,
           let loaded = await cache.load(url: full, key: path, maxPixel: px) {
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { image = loaded }
            return
        }
        // The link has expired or the request failed: one new link (the dex limits how often), which redraws this.
        guard !Task.isCancelled else { return }
        dex?.requestSigning(path, force: true)
    }
}



/// Glass fallback for iOS < 26.
struct GlassBackground: ViewModifier {
    var cornerRadius: CGFloat
    var tint: Color = .clear

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(tint), in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(.white.opacity(0.12), lineWidth: 1))
        }
    }
}

extension View {
    func glassCard(_ radius: CGFloat, tint: Color = .clear) -> some View {
        modifier(GlassBackground(cornerRadius: radius, tint: tint))
    }
}

/// A saved place in the current display language (the name saved at capture time can be in another one).
struct LocalizedPlaceText: View {
    let lat: Double?
    let lng: Double?
    let saved: String?
    var fallback: String = ""
    /// The learner wrote or picked the saved name (`Sticker.locationCustom`): it is shown as it is.
    var custom: Bool = false
    @State private var name: String?

    private var savedName: String? { LocationService.shownPlace(saved) }
    private var ownName: String? { custom ? saved.flatMap { $0.isEmpty ? nil : $0 } : nil }

    var body: some View {
        // With coordinates the saved name (maybe another language) is never shown; the lookup replaces it — unless the
        // learner wrote it.
        Text(ownName ?? name ?? (lat == nil ? savedName : nil) ?? fallback)
            // A place's own name, as written there (not counted as a mixed-in language by the UI tests' check).
            .accessibilityIdentifier("place.name")
            .task(id: "\(lat ?? 0),\(lng ?? 0),\(L10n.lang)") {
                guard ownName == nil else { return }
                name = await LocationService.shared.localizedName(lat: lat, lng: lng, saved: savedName)
            }
    }
}

/// 「見本」 on the bundled sample word (`SampleSticker`): a small pale-blue pill on its album photo and its dex square, so
/// the learner knows it is not something they caught (owner 2026-10-28: 「残す。長押しで消せる」, with a mark).
struct SampleMark: View {
    var body: some View {
        Text(L("見本"))
            .font(.system(size: 9.5, weight: .heavy))
            .tracking(0.3)
            .foregroundStyle(Theme.primaryInk)
            .padding(.horizontal, 7)
            .frame(height: 18)
            .background(Theme.accent, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.9), lineWidth: 1))
            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel(L("見本"))
            .accessibilityIdentifier("sample.mark")
    }
}

/// Three short blue strokes, as if something had just popped up: by the welcome latte, beside the place the first tour
/// lights and on its cards (owner 2026-10-28: the reference pictures' mark, in place of the hand). Design pixels, box
/// 50…135 × 215…300; stroke it in 0x5AA4F8 with round caps.
struct WelcomeBurst: Shape {
    private static let lines: [(CGPoint, CGPoint)] = [
        (CGPoint(x: 126, y: 223), CGPoint(x: 125, y: 253)),
        (CGPoint(x: 80, y: 243), CGPoint(x: 102, y: 270)),
        (CGPoint(x: 57, y: 285), CGPoint(x: 87, y: 292)),
    ]

    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 85
        let sy = rect.height / 85
        var p = Path()
        for (a, b) in Self.lines {
            p.move(to: CGPoint(x: rect.minX + (a.x - 50) * sx, y: rect.minY + (a.y - 215) * sy))
            p.addLine(to: CGPoint(x: rect.minX + (b.x - 50) * sx, y: rect.minY + (b.y - 215) * sy))
        }
        return p
    }
}

/// A small blue pill for a short label (「STEP 1」 on the first tour's cards, 「はじめに」 on the onboarding's last screen).
struct StepPill: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .scaledFont(size: 12, weight: .bold)
            .tracking(0.8)
            .foregroundStyle(Theme.primaryInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Theme.primary.opacity(0.1), in: Capsule())
    }
}
