import SwiftUI
import StoreKit

enum AppTab: Int, CaseIterable, Identifiable {
    case home, dex, camera, review, settings

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .home: L("ホーム")
        case .dex: L("図鑑")
        case .camera: L("カメラ")
        case .review: L("復習")
        case .settings: L("設定")
        }
    }

    var icon: String {
        switch self {
        case .home: "house"
        case .dex: "book"
        case .camera: "camera"
        case .review: "sparkles"
        case .settings: "gearshape"
        }
    }
}

/// Shared navigation state so the reward flight can open the dex and target the new cell.
@Observable
final class AppRouter {
    var tab: AppTab = .home
    var landingStickerId: String?
    /// The catch's star waiting for the save: it leaves from the celebration's sticker (CaptureView → CatchLanding).
    var catchStar: CatchStar?
    /// A catch landing in progress: the dex opens in ギャラリー and the star flies into the slot.
    var landing: CatchLandingController?
    var detailSticker: Sticker?
    var showPaywall: Bool = false
    /// Today's free catches (`CatchLimitSheet`): opened when they run out, or from the camera's counter.
    var showCatchLimit: Bool = false

    /// No catch left today: the paywall once Pro is sold, until then the limit sheet (come back tomorrow).
    func showLimitReached() {
        if PlanStore.paywallEnabled { showPaywall = true } else { showCatchLimit = true }
    }
    /// Home's 「解析待ち」 banner: open the camera with its waiting list showing.
    var openPending: Bool = false
    /// True while the camera "machine" (live preview / selfie / analyzing) fills the screen.
    var cameraImmersive: Bool = true
    /// Analyzing and the reward stage take the whole screen (no tab bar). Set by the camera screen, and read only while
    /// the camera tab shows (`cameraFullScreen`): what it last set never hides the tab bar of another tab.
    var tabBarHidden: Bool = false
    /// The camera tab shows a catch full screen (analyzing, the words, the GET moment).
    var cameraFullScreen: Bool { tabBarHidden && tab == .camera }
    /// No tab bar while the camera shows a catch full screen or a catch lands in the dex (the page rises over everything;
    /// the bar slides back in once the word has landed). Shown, it is always on top (MainTabView). 2026-10-15 (UI tour,
    /// ja/en): after a typed word landed, the review and settings tabs could not be reached — the tab bar was still in
    /// the screen's tree but out of sight, and taps on it went to the dex page under it.
    var hidesTabBar: Bool { cameraFullScreen || landing != nil || praise != nil }
    /// A new word was saved (`CaptureView.finishSave`, not a re-encounter): the praise flow looks at it (`PraiseFlow`).
    var caughtNew: CaughtWord?
    /// The praise on screen (`PraiseCelebrationView`), over every tab (owner 2026-10-25).
    var praise: PraiseMoment?
    /// First-run tour over the real screens (FirstCatchFlow's experience steps).
    var tour: TourStep = .off
    /// The word caught during the tour (used by the Dex / word / review steps).
    var tourStickerId: String?
    /// The word sheet zooms out of the tile it was opened from (iOS 18 zoom transition). Set by MainTabView.
    var detailZoom: Namespace.ID?
    /// The open word came from a tile marked with `detailZoomSource` (Dex grid / list), so the sheet zooms.
    var detailZoomed: Bool = false
    /// The camera screen's shutter, drawn by the tab bar's camera disc (owner 2026-10-26: the disc turns into the shutter
    /// where it stands — no second blue disc above the bar). Set by CaptureView while its camera can shoot; nil otherwise.
    var cameraShutter: CameraShutter?
    /// A word page's 「いま復習する」: the review tab brings this sticker in as the next card, due or not.
    var reviewNow: String?
    /// A one-line notice over every tab (a catch's background save reports a failure here: the camera
    /// screen, which has its own toast, is gone by then).
    var notice: String?
    @ObservationIgnored private var noticeToken = 0

    /// `seconds`: how long it stays (a notice of several lines needs longer to read).
    func showNotice(_ text: String, seconds: Double = 3.5) {
        noticeToken += 1
        let token = noticeToken
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { notice = text }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard noticeToken == token else { return }
            withAnimation(.easeOut(duration: 0.25)) { notice = nil }
        }
    }

    /// Open a word's sheet; `zoom` only when the tapped tile carries `detailZoomSource(_:)`. A catch still being
    /// saved opens at once too (owner 2026-10-11: 「キャッチしたてのときその単語の詳細に進めない」): its page waits
    /// for the save by itself and turns into the saved word in place (WordDetailView, `DexStore.current`).
    func openDetail(_ sticker: Sticker, zoom: Bool) {
        detailZoomed = zoom && detailZoom != nil
        detailSticker = sticker
    }

    func advanceTour(from step: TourStep, to next: TourStep) {
        guard tour == step else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) { tour = next }
    }
}

/// The tab bar, in a view of its own that watches the router itself (`AppRouter.hidesTabBar`). UI tour 2026-10-16
/// (zh-TW/en, after a typed word landed): the trace has "landing end … current=true" and then nothing — not the
/// "tabbar hidden=false" line the bar's owner wrote the moment the bar came back after every other landing — and the
/// bar never came back (the review and settings tabs were missing from the screen for the rest of the run). By all signs
/// the tab screen (MainTabView), which owned the bar, did not draw again when the landing ended. The bar no longer
/// depends on that screen redrawing: this view watches the router and redraws on its own, and a landing is ended after
/// at most `CatchLanding.longest` even if its animation never finishes.
struct TabBarSlot: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        ZStack(alignment: .bottom) {
            if !router.hidesTabBar {
                CapsuleTabBar(selection: $router.tab, onCamera: router.tab == .camera && router.cameraImmersive,
                              shutter: router.tab == .camera ? router.cameraShutter : nil)
                    .padding(.bottom, 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear { UITestTrace.log("tabbar view in tab=\(router.tab)") }
                    .onDisappear { UITestTrace.log("tabbar view out tab=\(router.tab)") }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.9), value: router.hidesTabBar)
        .onChange(of: router.hidesTabBar) { _, hidden in UITestTrace.log("tabbar hidden=\(hidden) tab=\(router.tab)") }
    }
}

struct MainTabView: View {
    @State private var router = AppRouter()
    @Environment(DexStore.self) private var dex
    /// This account's "first tour still to run" (`TourStep.pendingStorageKey`, kept per account).
    @AppStorage private var tourPending: Bool
    @Namespace private var detailZoom
    @Environment(ProfileStore.self) private var profile
    /// The system's App Store rating sheet (App Review Guideline 5.6.1: no custom review prompts).
    @Environment(\.requestReview) private var requestReview

    init() {
        _tourPending = AppStorage(wrappedValue: false, TourStep.pendingStorageKey(for: SupabaseClient.shared.userId))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch router.tab {
                case .home: HomeView().environment(\.colorScheme, .light).statusBarTone(.dark)  // the paper album stays paper
                case .dex:
                    // A catch landing: the dex page rises over the camera screen (film v6: 140 px with a fade, .4 s).
                    DexView(startInGallery: router.landing != nil || router.landingStickerId != nil)
                        .transition(router.landing != nil
                                    ? AnyTransition.asymmetric(insertion: AnyTransition.offset(y: 52).combined(with: .opacity),
                                                               removal: .opacity)
                                    : AnyTransition.opacity)
                        .zIndex(router.landing != nil ? 1 : 0)
                case .camera:
                    // Without the AI consent the camera stays off: its photos would go to AI (AIConsentGateView).
                    Group {
                        if AIConsent.shared.isGranted { CaptureView() } else { AIConsentGateView() }
                    }
                        .transition(router.landing != nil
                                    ? AnyTransition.asymmetric(insertion: .opacity,
                                                               removal: AnyTransition.opacity.animation(.linear(duration: 0.01).delay(0.6)))
                                    : AnyTransition.opacity)
                case .review: ReviewView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Above every tab's page, the dex rising for a landing too (it takes zIndex 1 for that).
            TabBarSlot()
                .zIndex(2)
        }
        .overlay {
            if let landing = router.landing { CatchLandingOverlay(controller: landing) }
        }
        .overlay {
            if let moment = router.praise {
                PraiseCelebrationView(moment: moment) {
                    withAnimation(.easeOut(duration: 0.3)) { router.praise = nil }
                }
                .transition(.opacity)
            }
        }
        .onChange(of: router.caughtNew) { _, caught in
            guard let caught else { return }
            let start = profile.createdAt
            Task { await PraiseFlow.afterCatch(caught, router: router, dex: dex, start: start, requestReview: requestReview) }
        }
        .overlay(alignment: .top) {
            if let notice = router.notice {
                // The camera's toast, over every tab.
                Text(notice)
                    .scaledFont(size: 14, weight: .medium)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    // Several lines (a failed save says what happened and that the word was kept): a rounded card.
                    .background(Theme.toastInk.opacity(0.88),
                                in: RoundedRectangle(cornerRadius: notice.contains("\n") ? 18 : 30, style: .continuous))
                    .padding(.top, 60)
                    .padding(.horizontal, 24)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
            }
        }
        .overlayPreferenceValue(TourAnchorKey.self) { anchors in
            // The catch hides the tab bar for its whole flow; its capture steps still need the guide.
            if router.tour != .off, router.tour != .word, router.tour != .complete,
               !router.cameraFullScreen || (router.tab == .camera && router.tour.isCapture) {
                TourLayer(step: router.tour, anchors: anchors, onNext: tourNext, onSkip: endTour)
                    .transition(.opacity)
            }
        }
        .overlay {
            if router.tour == .complete {
                TourCompleteView(sticker: router.tourStickerId.flatMap { dex.sticker(id: $0) }) { endTour() }
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
                    .zIndex(3)
            }
        }
        .environment(router)
        .sheet(item: $router.detailSticker, onDismiss: {
            router.detailZoomed = false
            // 「ことば」を見終えたら復習へ（Web: StickerSheet の onClose → review）。
            if router.tour == .word { startTourReview() }
        }) { sticker in
            WordDetailView(sticker: sticker)
                .environment(router)
                .modifier(DetailZoomTransition(id: sticker.id, namespace: router.detailZoomed ? router.detailZoom : nil))
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.background)
                .overlay(alignment: .bottom) {
                    if router.tour == .word {
                        TourCoachCard(step: .word, onNext: { router.detailSticker = nil }, onSkip: endTour)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    }
                }
        }
        .onAppear {
            router.detailZoom = detailZoom
            beginTourIfPending()
            openNotification(NotificationRouter.shared.pending)
        }
        .onChange(of: NotificationRouter.shared.pending) { _, route in openNotification(route) }
        // A word's reminder or widget tapped at launch waits for the dex to know that word.
        .onChange(of: dex.hasLoaded) { _, loaded in if loaded { openNotification(NotificationRouter.shared.pending) } }
        .onChange(of: tourPending) { _, _ in beginTourIfPending() }
        .onChange(of: router.tab) { _, tab in
            if tab == .camera { router.advanceTour(from: .tapCamera, to: .shoot) }
            // The camera screen's full-screen catch is over once another tab shows: coming back to the camera starts
            // from its own setting (`CaptureView.syncChrome` on appear), never from one it left behind.
            if tab != .camera { router.tabBarHidden = false }
        }
        .onChange(of: router.detailSticker) { old, s in
            if s != nil { router.advanceTour(from: .dexOpen, to: .word) }
            // Every way into a word (dex, home, review, a reminder) pons open; closing it pons back.
            if old == nil, s != nil { SoundService.shared.pon(open: true) }
            if old != nil, s == nil { SoundService.shared.pon(open: false) }
        }
        .fullScreenCover(isPresented: $router.showPaywall) {
            PaywallView()
                .statusBarTone(.automatic)
        }
        .sheet(isPresented: $router.showCatchLimit) {
            CatchLimitSheet()
                .presentationDetents([.medium])
        }
    }

    /// A tapped reminder: the review tab, or the word a place reminder was about.
    private func openNotification(_ route: NotificationRoute?) {
        guard let route else { return }
        // Cold launch: the dex isn't read yet, so the word can't be found — keep the route until it is.
        if case .sticker(_) = route, !dex.hasLoaded { return }
        NotificationRouter.shared.pending = nil
        switch route {
        case .review:
            router.detailSticker = nil
            router.tab = .review
        case .home:
            router.detailSticker = nil
            router.tab = .home
        case .sticker(let id):
            if let s = dex.sticker(id: id) {
                router.tab = .dex
                router.detailSticker = s
            } else {
                router.tab = .review
            }
        case .pendingPhotos:
            // Like the home banner: the camera opens its 「解析待ち」 list.
            router.detailSticker = nil
            router.openPending = true
            router.tab = .camera
        }
    }

    private func beginTourIfPending() {
        guard tourPending, router.tour == .off else { return }
        router.tab = .home
        withAnimation(.easeOut(duration: 0.3)) { router.tour = .home }
    }

    private func tourNext() {
        switch router.tour {
        case .home: router.advanceTour(from: .home, to: .tapCamera)
        case .detail: router.advanceTour(from: .detail, to: .peel)
        case .added: router.advanceTour(from: .added, to: .dexTypes)
        case .dexOpen:
            if let id = router.tourStickerId, let s = dex.sticker(id: id) { router.detailSticker = s } else { startTourReview() }
        case .review: router.advanceTour(from: .review, to: .reviewPick)
        default: break
        }
    }

    private func startTourReview() {
        // Nothing to quiz on (no word in the dex): skip the practice instead of stopping on an empty review.
        guard dex.stickers.contains(where: { $0.word != nil }) else {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) { router.tour = .complete }
            return
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) {
            router.tour = .review
            router.tab = .review
        }
    }

    private func endTour() {
        tourPending = false
        router.detailSticker = nil
        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
            router.tour = .off
            router.tab = .home
        }
    }
}

/// TabBar.tsx: floating capsule (87.6% width, ~55pt, full-capsule corners), a bubble exactly one
/// cell wide that slides between cells.
/// It stays the same white strip on the camera too (owner request 2026-10-02: no dark glass there),
/// only fully opaque so the dark machine behind it does not grey it.
///
/// The camera is the raised blue disc (B) for everyone (owner 2026-10-25: 「開発者の試しの下のバーのカメラを浮いた丸に
/// 変更して」). It was a developer's trial from 2026-10-16 (docs/backlog.md); the flat blue icon in the row is gone.
struct CapsuleTabBar: View {
    @Binding var selection: AppTab
    var onCamera: Bool
    /// The camera screen's shutter while the camera tab shows a camera that can shoot: the camera disc becomes it.
    var shutter: CameraShutter? = nil

    @Namespace private var bubble
    /// Taps per tab: drives each icon's bounce, so only the tab just chosen bounces.
    @State private var bounces: [AppTab: Int] = [:]
    /// The disc takes a shot only a moment after it became the shutter: a second tap on the camera tab must not shoot.
    @State private var shutterArmed = false
    @State private var shutterPressed = false
    @Environment(\.appReduceMotion) private var reduceMotion

    /// The bar's height; the camera disc rises `raise` points above its top edge.
    static let height: CGFloat = 58
    static let raise: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let width = min(geo.size.width * 0.92, 400)
            HStack(spacing: 0) {
                ForEach(AppTab.allCases) { tab in
                    if tab == .camera {
                        raisedCameraDisc
                            .tourAnchor(.cameraTab)
                            .tourAnchor(.shutter, if: isShutter)
                    } else {
                        cell(tab)
                    }
                }
            }
            .frame(width: width, height: Self.height)
            .background {
                Capsule().fill(Theme.card.opacity(onCamera ? 1 : 0.9)).background(.regularMaterial, in: Capsule())
                    // The edge goes under the items, so the raised disc is never crossed by it.
                    .overlay { Capsule().stroke(Theme.border, lineWidth: 1) }
            }
            .shadow(color: .black.opacity(onCamera ? 0.3 : 0.1), radius: 16, y: 6)
            .frame(maxWidth: .infinity)
        }
        .frame(height: Self.height)
        .animation(.easeInOut(duration: 0.25), value: onCamera)
    }

    private func cell(_ tab: AppTab) -> some View {
        let isOn = selection == tab
        let tint = isOn ? Theme.primary : Theme.foreground.opacity(0.75)
        return Button { select(tab) } label: {
            VStack(spacing: 5) {
                Image(systemName: tab.icon)
                    .font(.system(size: 19, weight: .regular))
                    .frame(height: 21)
                    .foregroundStyle(tint)
                    .symbolEffect(.bounce, value: bounces[tab, default: 0])
                Text(tab.title).font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if isOn {
                    Capsule()
                        .fill(Theme.primary.opacity(0.14))
                        .matchedGeometryEffect(id: "bubble", in: bubble)
                        .padding(4)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .accessibilityLabel(tab.title)
        .accessibilityIdentifier("tab.\(String(describing: tab))")
    }

    /// The camera disc is the shutter now: the camera tab shows a camera that can shoot.
    private var isShutter: Bool { selection == .camera && shutter != nil }

    /// The camera: a filled blue disc with the white camera, standing up over the bar's top edge with a soft shadow. It is
    /// drawn above the bar and still takes the tap there (nothing clips it); the bar's own height does not change, so the
    /// landing's hide / show and the safe area are as before.
    ///
    /// On the camera tab it turns into the shutter where it stands (owner 2026-10-26: 「その場で変身する案で作って」): the
    /// camera glyph shrinks away and a white disc grows inside the white ring — the shutter of the phone's own camera. The
    /// camera screen draws no shutter of its own then (CaptureView).
    private var raisedCameraDisc: some View {
        let isOn = selection == .camera
        let asShutter = isShutter
        let enabled = shutter?.enabled ?? true
        let size: CGFloat = asShutter ? 64 : 56
        return Button {
            if asShutter {
                guard shutterArmed, let shutter, shutter.enabled else { return }
                shutter.shoot()
            } else {
                select(.camera)
            }
        } label: {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Theme.primaryBright, Theme.primaryDeep], startPoint: .top, endPoint: .bottom))
                    .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 3))
                    .shadow(color: Theme.primary.opacity(asShutter ? 0.6 : 0.45), radius: asShutter ? 16 : 12, y: 6)
                Image(systemName: "camera.fill")
                    .font(.system(size: 56 * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: bounces[.camera, default: 0])
                    .scaleEffect(asShutter ? 0.3 : 1)
                    .opacity(asShutter ? 0 : 1)
                Circle()
                    .fill(.white)
                    .padding(asShutter ? 9 : 22)
                    .scaleEffect(shutterPressed ? 0.86 : 1)
                    .opacity(asShutter ? 1 : 0)
            }
            .frame(width: size, height: size)
            .offset(y: -Self.raise)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The whole cell takes the tap; the tap area moves up with the disc so its top is reachable.
            .contentShape(Rectangle().offset(y: -Self.raise))
        }
        .buttonStyle(DiscPressStyle(pressed: $shutterPressed, scale: asShutter ? 1 : 0.92))
        .disabled(asShutter && !enabled)
        .opacity(asShutter && !enabled ? 0.45 : 1)
        .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.72), value: asShutter)
        .accessibilityLabel(asShutter ? L("撮影") : AppTab.camera.title)
        .accessibilityAddTraits(isOn && !asShutter ? .isSelected : [])
        // The UI tests find the shutter once it takes shots.
        .accessibilityIdentifier(asShutter && shutterArmed ? "camera.shutter" : "tab.camera")
        .onAppear { shutterArmed = asShutter }
        .onChange(of: asShutter) { _, now in
            shutterArmed = false
            guard now else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                if isShutter { shutterArmed = true }
            }
        }
    }

    private func select(_ tab: AppTab) {
        guard selection != tab else { return }
        SoundService.shared.pon(open: true)   // a tab switch is a page opening: bubble pon + soft tap
        bounces[tab, default: 0] += 1
        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { selection = tab }
    }
}

/// The word sheet zooming out of its tile and back into it on close (iOS 18). Without a source
/// (opened from review, home, a reminder…) the sheet keeps the ordinary slide-up.
private struct DetailZoomTransition: ViewModifier {
    let id: String
    let namespace: Namespace.ID?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let namespace {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
    }
}

/// The tile a word sheet zooms out of (`AppRouter.openDetail(_:zoom: true)`). Harmless without a router.
struct DetailZoomSource: ViewModifier {
    @Environment(AppRouter.self) private var router: AppRouter?
    let id: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if let namespace = router?.detailZoom {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

extension View {
    /// Marks a word tile as the place its detail sheet zooms out of and back into.
    func detailZoomSource(_ id: String) -> some View {
        modifier(DetailZoomSource(id: id))
    }
}

/// What the camera screen hands the tab bar so its camera disc can be the shutter (`AppRouter.cameraShutter`).
struct CameraShutter {
    var enabled: Bool
    let shoot: () -> Void
}

/// The disc's press: scales the disc (as the other tabs do), and as the shutter shrinks its white centre instead.
private struct DiscPressStyle: ButtonStyle {
    @Binding var pressed: Bool
    var scale: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(.spring(response: 0.28, dampingFraction: 0.62), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, p in
                if p { Haptics.impact(.light, intensity: 0.6) }
                withAnimation(.spring(response: 0.22, dampingFraction: 0.6)) { pressed = p }
            }
    }
}
