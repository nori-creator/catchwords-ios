import SwiftUI
import PhotosUI
import AVFoundation
import CoreLocation

/// The camera tab: shoot → AI analyses → the words on their objects → tap one → celebration → 図鑑に追加.
/// (owner 2026-10-09: the camera only takes photos — no 検索 / スキャン modes, no card catch.)
struct CaptureView: View {
    @Environment(DexStore.self) private var dex
    @Environment(PlanStore.self) private var plan
    @Environment(AppRouter.self) private var router

    @State private var camera = CameraService()
    @State private var vm = CaptureViewModel()
    @State private var focusPoint: CGPoint?
    @State private var shutterFlash: Bool = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var showPending: Bool = false
    @State private var baseZoom: CGFloat = 1
    @State private var positionBeforeSelfie: AVCaptureDevice.Position = .back
    @AppStorage("selfie.mode") private var selfieMode: Bool = false
    /// The selfie's self-timer (0 = off), shared with the word page's selfie camera.
    @AppStorage(SelfieTimer.storageKey) private var selfieTimer: Int = 0
    @State private var selfieCountdown = SelfieCountdown()
    /// The selfie step's words have gone and スキップ sits small in the corner (`selfieChrome`).
    @State private var selfieCompact: Bool = false
    @Environment(\.appReduceMotion) private var reduceMotion
    /// The shutter flash (`#flash` 0 → 1 at 12% → 0, 480 ms ease-out), above every screen.
    @State private var shotFlash: Double?
    /// shoot(): the shutter and the viewfinder hide the moment the photo is taken.
    @State private var shooting: Bool = false
    /// A save started from the celebration is running: no second save, no going back meanwhile.
    @State private var saveInFlight: Bool = false
    /// The celebration's sticker on screen (global): the star flies into the dex from there.
    @State private var stickerFrame: CGRect?

    private var isMachine: Bool {
        switch vm.step {
        case .camera, .selfie, .processing, .failed: true
        default: false
        }
    }

    /// The words on the photo and the celebration are dark full-screen views too (no tab bar).
    private var isFullScreen: Bool { vm.step == .select || vm.step == .celebrate }

    /// `-uiDemo` (DEBUG, the UI tests on CI): the simulator has no camera, so the viewfinder shows a sample
    /// photo and the shutter takes it (the demo backend then answers the analysis offline).
    private var demoCamera: Bool {
        #if DEBUG
        return DemoBackend.isOn
        #else
        return false
        #endif
    }

    private var demoPhoto: UIImage? {
        #if DEBUG
        return UIImage(data: DemoImages.png(seed: "camera-sample", emoji: "🛵", text: "", transparent: false, size: 1024))
        #else
        return nil
        #endif
    }

    var body: some View {
        ZStack {
            stepView
            if let toast = vm.toast {
                VStack {
                    Text(toast)
                        .scaledFont(size: 14, weight: .medium)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Theme.toastInk.opacity(0.88), in: Capsule())
                        .padding(.top, 60)
                        .padding(.horizontal, 24)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(false)
                .zIndex(20)
            }
            if shutterFlash {
                Color.white.ignoresSafeArea().allowsHitTesting(false)
            }
            CCShutterFlash(start: shotFlash, calm: reduceMotion).zIndex(30)
        }
        .denseTypeSizeCap()  // the camera chrome is laid out around the viewfinder and the shutter
        // The camera machine and the words on the photo are dark full-screen views; the choose screen and the GET
        // moment (film v6) are the light page.
        .statusBarTone(vm.step == .celebrate || (vm.step == .select && vm.lightStage) ? .dark
                       : (isMachine || isFullScreen ? .light : .automatic))
        .task { await startCamera() }
        .onAppear {
            LocationService.shared.requestPermissionIfNeeded()
            syncChrome()
            SoundService.shared.warmTicks()   // the shutter plays from the tick engine
            SoundService.shared.prepareCatchSounds()
        }
        .onDisappear {
            UITestTrace.log("capture.disappear step=\(vm.step)")
            selfieCountdown.cancel()
            camera.stop()
            router.cameraImmersive = true
            router.tabBarHidden = false
        }
        .task(id: vm.step == .selfie) {
            // Each selfie step starts with its words, which give way after a few seconds.
            guard vm.step == .selfie else { return }
            selfieCompact = false
            try? await Task.sleep(for: .seconds(Self.selfieChromeSeconds))
            guard !Task.isCancelled else { return }
            compactSelfieChrome()
        }
        .onChange(of: selfieTimer) { _, _ in compactSelfieChrome() }
        .onChange(of: vm.step) { old, step in
            UITestTrace.log("step \(old) -> \(step)")
            if step != .selfie { selfieCountdown.cancel() }
            syncChrome()
            if step == .select { router.advanceTour(from: .shoot, to: .pick) }
            if step == .celebrate {
                router.advanceTour(from: .pick, to: .detail)
                // The dex page the word lands on next: its squares are read into memory now, while the word is
                // celebrated, so the page never rises blank (owner 2026-10-15).
                if let w = vm.picked { dex.warmLanding(headword: w.headword, categoryKey: w.categoryKey) }
                // The photos go up while the word is celebrated: 図鑑に追加 then only saves the row.
                // A cut-out still being made is waited for, so the upload carries the sticker that is saved.
                // A re-encounter uploads its photos with its record (`DexStore.recordEncounter`).
                Task {
                    await vm.awaitCutout()
                    if vm.step == .celebrate, vm.owned == nil { vm.startUploads(using: dex) }
                }
            }
            shooting = false
            if step == .camera, router.tour.isCapture, router.tour != .shoot {
                withAnimation { router.tour = .shoot }
            }
            switch step {
            case .camera:
                if old == .selfie || camera.position != positionBeforeSelfie { camera.switchTo(positionBeforeSelfie) }
                // After a catch the dex is already open while this screen fades out (vm.reset 700 ms later):
                // never turn the camera back on behind another tab.
                if router.tab == .camera { Task { await startCamera() } }
            case .selfie:
                positionBeforeSelfie = camera.position
                camera.switchTo(.front)
                Task { await startCamera() }
            default:
                camera.stop()
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = await ImageTools.downsampledInBackground(data) {
                    // A photo that loads after another catch has started is dropped (never replaces it).
                    if vm.step == .camera { beginAnalyze(img, askSelfie: false) }
                } else {
                    vm.showToast(L("写真を読み込めませんでした。"))
                }
                pickerItem = nil
            }
        }
        .onAppear { takePendingRequest() }
        // The rewarded ad is loaded ahead once the day's last free catch is near (`CatchLimitSheet`).
        .task(id: plan.remainingToday) {
            if PlanStore.catchLimitEnabled, !plan.isPro, plan.remainingToday <= 1, plan.canEarnBonus {
                RewardedAds.shared.prepare()
            }
        }
        .onChange(of: router.openPending) { _, _ in takePendingRequest() }
        .sheet(isPresented: $showPending) {
            PendingListView { item in
                showPending = false
                if item.isUnsaved {
                    // A word whose save failed (「保存待ち」): saved again as it is — never analyzed or chosen again.
                    retryUnsaved(item)
                    return
                }
                guard plan.canCatch else { router.showLimitReached(); return }
                vm.restore(item)
            }
            .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private var stepView: some View {
        let _ = UITestTrace.log("capture.stepView \(vm.step)")
        switch vm.step {
        case .camera, .selfie:
            cameraMachine.transition(.opacity)
        case .processing, .select:
            // One view from the shutter to the tap (the scan runs over the same photo the tags land on).
            CandidatePickerView(vm: vm, scanning: vm.step == .processing).transition(.opacity)
        case .celebrate:
            CatchCelebrationView(vm: vm, saving: saveInFlight, onAdd: addToDex,
                                 onStickerFrame: { stickerFrame = $0 })
                // From the choose screen the GET moment goes on in the very same frame (CatchStageScene): no fade.
                .transition(vm.stageHandoff != nil ? AnyTransition.identity : AnyTransition.opacity)
        case .failed(let reason, let retryable):
            ZStack {
                MachineBackground()
                FailedView(reason: reason, retryable: retryable, offline: vm.failedOffline,
                           onRetry: { vm.retry() },
                           onHome: {
                               vm.keepPendingAndReset()
                               withAnimation { router.tab = .home }
                           },
                           onAgain: { vm.keepPendingAndReset() })
            }
        }
    }

    private func takePendingRequest() {
        guard router.openPending else { return }
        router.openPending = false
        dex.refreshPending()
        if !dex.pending.isEmpty { showPending = true }
    }

    private func syncChrome() {
        router.cameraImmersive = isMachine
        // No tab bar through the whole catch (analyze, the words, the celebration).
        router.tabBarHidden = vm.step == .processing || isFullScreen
    }

    /// The real camera; never under `-uiDemo` (its sample photo stands in, `demoCamera`).
    private func startCamera() async {
        guard !demoCamera else { return }
        // The connection for the photo's request is opened while the learner frames the shot.
        NativeAPI.warmUp()
        await camera.start()
    }

    // MARK: Camera machine

    private var cameraMachine: some View {
        ZStack {
            MachineBackground()
            VStack(spacing: 0) {
                topBar
                ZStack(alignment: .bottom) {
                    previewLayer
                    // Zoom only means something on a live camera: not over 「許可されていません」/「起動できませんでした」.
                    if cameraLive { zoomPills.padding(.bottom, 12).transition(.opacity) }
                }
                .clipShape(.rect(cornerRadius: 24, style: .continuous))
                .padding(.horizontal, 10)
                .padding(.top, 8)

                controls
                    .padding(.top, 22)
                    .padding(.bottom, 86)
            }
        }
    }

    private var topBar: some View {
        ZStack {
            Text("CatchWords")
                .scaledFont(size: 17, weight: .semibold)
                .foregroundStyle(.white)
            HStack {
                if plan.isPro || PlanStore.catchLimitEnabled { usagePill }
                Spacer()
                if !dex.pending.isEmpty {
                    Button { showPending = true } label: {
                        Label("\(dex.pending.count)", systemImage: "tray.and.arrow.up.fill")
                            .scaledFont(size: 12, weight: .semibold)
                            .foregroundStyle(Theme.gold)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 30)
                            .background(.white.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel(L("解析待ち \(dex.pending.count)件"))
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(minHeight: 36)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var previewLayer: some View {
        if demoCamera {
            demoPreview
        } else {
            switch camera.state {
            case .running, .idle:
                livePreview
            case .denied:
                CameraMessageView(icon: "camera.fill", title: L("カメラの使用が許可されていません"),
                                  message: L("1. 下の「設定を開く」を押す\n2. 「カメラ」をオンにして、この画面に戻る"),
                                  buttonTitle: L("設定を開く")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            case .unavailable:
                CameraMessageView(icon: "camera.metering.unknown", title: L("カメラを起動できませんでした"),
                                  message: L("ほかのアプリがカメラを使っていたら閉じてから、もう一度試してください。写真アプリの画像からも集められます。"),
                                  buttonTitle: L("もう一度試す")) {
                    Task { await startCamera() }
                }
            }
        }
    }

    private var livePreview: some View {
        CameraPreview(session: camera.session) { point, device in
            camera.focus(at: device)
            Haptics.impact(.light, intensity: 0.5)
            focusPoint = point
            Task {
                try? await Task.sleep(for: .seconds(1.1))
                withAnimation(.easeOut(duration: 0.25)) { focusPoint = nil }
            }
        }
        .scaleEffect(x: camera.position == .front ? -1 : 1, y: 1)
        .gesture(MagnifyGesture()
            .onChanged { v in camera.setZoom(baseZoom * v.magnification) }
            .onEnded { _ in baseZoom = camera.zoom })
        .overlay {
            if vm.step == .camera, !shooting { ViewfinderBrackets().padding(36).allowsHitTesting(false) }
        }
        .overlay {
            if let focusPoint {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Theme.gold, lineWidth: 1.5)
                    .frame(width: 74, height: 74)
                    .position(focusPoint)
                    .transition(.scale(scale: 1.4).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .overlay { selfieChrome }
        .overlay {
            if vm.step == .selfie, let left = selfieCountdown.remaining { SelfieCountdownNumber(remaining: left) }
        }
        .background(Color.black)
    }

    /// `-uiDemo`: the sample photo the shutter takes, in place of the live camera.
    private var demoPreview: some View {
        Color.black
            .overlay {
                if let img = demoPhoto {
                    Image(uiImage: img).resizable().scaledToFill().allowsHitTesting(false)
                }
            }
            .clipped()
            .overlay {
                if vm.step == .camera, !shooting { ViewfinderBrackets().padding(36).allowsHitTesting(false) }
            }
            .overlay { selfieChrome }
            .overlay {
                if vm.step == .selfie, let left = selfieCountdown.remaining { SelfieCountdownNumber(remaining: left) }
            }
    }

    /// The selfie step's words over the viewfinder (owner 2026-10-22: 「数秒したらスキップ以外の文字は消えて、スキップも小さく
    /// 右上に移動して。タイマーモードを押したらすぐ…」): 「ものと一緒に、もう一枚」 and a large スキップ at first; after
    /// `selfieChromeSeconds`, or at once when the timer is chosen or starts counting, only a small スキップ in the top-right
    /// corner, so the words never cover the selfie.
    @ViewBuilder
    private var selfieChrome: some View {
        if vm.step == .selfie {
            if selfieCompact {
                skipButton(small: true)
                    .padding(.top, 10)
                    .padding(.trailing, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .topTrailing)))
            } else {
                selfiePrompt
                    .padding(.top, 48)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }

    /// How long 「ものと一緒に、もう一枚」 stays before only the small スキップ is left.
    private static let selfieChromeSeconds: Double = 3

    private var selfiePrompt: some View {
        VStack(spacing: 18) {
            Text(L("ものと一緒に、もう一枚"))
                .scaledFont(size: 20, weight: .bold)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 6, y: 1)
            skipButton(small: false)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func skipButton(small: Bool) -> some View {
        Button {
            selfieCountdown.cancel()
            vm.finishSelfie(nil)
        } label: {
            Text(L("スキップ"))
                .scaledFont(size: small ? 13 : 16, weight: .medium)
                .foregroundStyle(.white)
                .padding(.horizontal, small ? 12 : 26)
                .frame(minHeight: small ? 30 : 44)
                .background(.black.opacity(0.35), in: Capsule())
                .background(.ultraThinMaterial, in: Capsule())
                // The small one keeps a finger-sized place to tap.
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("selfie.skip")
    }

    private func compactSelfieChrome() {
        guard vm.step == .selfie, !selfieCompact else { return }
        withAnimation(.snappy(duration: 0.3)) { selfieCompact = true }
    }

    /// The camera is on (zoom and 切替 work).
    private var cameraLive: Bool { !demoCamera && camera.state == .running }
    /// The camera was refused or could not start (its message and button fill the viewfinder).
    private var cameraFailed: Bool { !demoCamera && (camera.state == .denied || camera.state == .unavailable) }
    /// Something to shoot: the live camera, or the demo's sample photo.
    private var canShoot: Bool { cameraLive || demoCamera }

    /// 1× 2× 3× 5× (CameraZoomMeter): the lit stop follows pinch zoom too.
    private var zoomPills: some View {
        let stops: [CGFloat] = [1, 2, 3, 5]
        let nearest = stops.min { abs($0 - camera.zoom) < abs($1 - camera.zoom) } ?? 1
        return HStack(spacing: 4) {
            ForEach(stops, id: \.self) { z in
                let isOn = z == nearest
                Button {
                    Haptics.selection()
                    withAnimation(.snappy) { camera.setZoom(z) }
                    baseZoom = camera.zoom
                } label: {
                    // The display language's decimal mark (1.5× · 1,5×).
                    Text(isOn && abs(camera.zoom - z) > 0.05
                         ? "\(Double(camera.zoom).formatted(.number.precision(.fractionLength(1)).locale(L10n.locale)))×"
                         : "\(Int(z))×")
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(isOn ? Theme.gold : .white.opacity(0.85))
                        .frame(width: 42, height: 32)
                        .background(isOn ? .white.opacity(0.16) : .clear, in: Capsule())
                }
                .buttonStyle(PressableStyle(scale: 0.9))
            }
        }
        .padding(4)
        .background(Theme.navyDeep.opacity(0.7), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.1), lineWidth: 1))
    }

    private var controls: some View {
        HStack(alignment: .top) {
            if vm.step == .selfie {
                // Where 写真 was: the self-timer (no photo library for selfies).
                SelfieTimerMenu(seconds: $selfieTimer, onOpen: compactSelfieChrome)
                    .disabled(selfieCountdown.isRunning)
            } else {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    sideButton(icon: "photo.badge.plus", label: L("写真"))
                }
                .buttonStyle(PressableStyle(scale: 0.9))
            }
            Spacer()
            ShutterButton(enabled: canShoot, arriving: router.shutterFlying) { shoot() }
                .opacity(shooting ? 0 : 1)
                .allowsHitTesting(!shooting)
                // The first tour's 撮る step lights the shutter and dims the rest. With the camera denied or
                // broken there is nothing to shoot, and the dim would cover 「設定を開く」/「もう一度試す」:
                // no spotlight then (TourLayer leaves the screen undimmed without its anchor). Outside the
                // tour the anchor stays: the camera tab's icon still flies into the shutter.
                .tourAnchor(.shutter, if: !(cameraFailed && router.tour == .shoot))
                .accessibilityIdentifier("camera.shutter")
            Spacer()
            Button { camera.toggle() } label: {
                sideButton(icon: "arrow.triangle.2.circlepath.camera", label: L("切替"))
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            // Like the shutter: switching needs a running camera.
            .disabled(!cameraLive)
            .opacity(cameraLive ? 1 : 0.4)
        }
        .padding(.horizontal, 44)
    }

    private var usagePill: some View {
        Group {
            if plan.isPro {
                Label("PRO", systemImage: "infinity").foregroundStyle(Theme.gold)
            } else if plan.dailyLimit + plan.bonusToday <= 5 {
                HStack(spacing: 4) {
                    ForEach(0..<(plan.dailyLimit + plan.bonusToday), id: \.self) { i in
                        Circle()
                            .fill(i < plan.remainingToday ? Theme.primaryBright : .white.opacity(0.22))
                            .frame(width: 6, height: 6)
                    }
                }
            } else {
                // The welcome week (10 a day): a number reads better than ten dots.
                Text(L("今日あと\(plan.remainingToday)回")).foregroundStyle(.white)
            }
        }
        .scaledFont(size: 11, weight: .bold)
        .padding(.horizontal, 10)
        .frame(minHeight: 30)
        .background(.white.opacity(0.1), in: Capsule())
        .contentShape(Capsule())
        .onTapGesture { if PlanStore.paywallEnabled, !plan.isPro { router.showPaywall = true } else if !plan.isPro { router.showCatchLimit = true } }
        .accessibilityLabel(plan.isPro ? "Pro" : L("今日あと\(plan.remainingToday)回"))
    }

    private func sideButton(icon: String, label: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .regular))
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.1), in: .rect(cornerRadius: 13, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(.white.opacity(0.18), lineWidth: 1))
            Text(label).scaledFont(size: 11, weight: .medium)
        }
        .foregroundStyle(.white)
        .frame(minWidth: 56)
    }

    // MARK: Actions

    /// The live camera's photo, or `-uiDemo`'s sample.
    private func capturePhoto() async -> UIImage? {
        if demoCamera { return demoPhoto }
        return await camera.capture()
    }

    /// The app's shutter, unless the system's own click plays (and may not be silenced) on this device.
    private func shutterSound() {
        if demoCamera || !camera.systemShutterSound { SoundService.shared.shutter() }
    }

    private func shoot() {
        if vm.step == .selfie {
            // With the timer on, the shutter starts the count; a second press stops it.
            if selfieCountdown.isRunning {
                Haptics.selection()
                selfieCountdown.cancel()
                return
            }
            compactSelfieChrome()
            selfieCountdown.start(selfieTimer) {
                guard vm.step == .selfie else { return }
                shutterSound()
                flash()
                Task { vm.finishSelfie(await capturePhoto()) }
            }
            return
        }
        guard plan.canCatch else { router.showLimitReached(); return }
        // The shutter sound, the white flash, the shutter and viewfinder hide.
        shutterSound()
        let shotAt = CCClock.now
        shotFlash = shotAt
        shooting = true
        Task {
            // The flash is over after 480 ms: drop it so its TimelineView stops redrawing.
            try? await Task.sleep(for: .milliseconds(600))
            if shotFlash == shotAt { shotFlash = nil }
        }
        Task {
            if let img = await capturePhoto() {
                beginAnalyze(img, askSelfie: selfieMode)
            } else {
                shooting = false
            }
        }
    }

    private func flash() {
        Haptics.impact(.rigid)
        withAnimation(.easeOut(duration: 0.05)) { shutterFlash = true }
        Task {
            try? await Task.sleep(for: .milliseconds(90))
            withAnimation(.easeOut(duration: 0.3)) { shutterFlash = false }
        }
    }

    /// 「保存待ち」 tapped in the list: the same save again (`DexStore.retryUnsaved`); the result is told over every tab.
    private func retryUnsaved(_ item: PendingCatch) {
        let store = dex, nav = router
        Task {
            do {
                try await store.retryUnsaved(pendingId: item.id)
                Haptics.success()
                nav.showNotice(L("図鑑に保存しました"))
            } catch is CancellationError {
                // Already being saved (the automatic retry): nothing to tell.
            } catch {
                Haptics.warning()
                nav.showNotice(L("まだ保存できていません：\(SaveFailure.message(for: error))"), seconds: 5)
            }
            store.refreshPending()
        }
    }

    private func beginAnalyze(_ img: UIImage, askSelfie: Bool) {
        guard plan.canCatch else { router.showLimitReached(); return }
        vm.analyze(img, askSelfie: askSelfie)
        dex.refreshPending()
    }

    /// 「図鑑に追加」. The dex opens at once (`CatchLanding`) on a provisional entry while the catch is saved behind
    /// it through the app's own path (photo and cut-out uploads, saveSticker): the learner never waits on the
    /// network after the tap (owner report 2026-10-04). Only the cut-out is awaited here (started at the tap on the
    /// word, so usually ready). The card's details are no longer waited for (owner 2026-10-10: 「ただ待たされる
    /// 時間は苦痛」 — the card took several seconds and sometimes failed, which stopped the catch): a card not here
    /// yet is saved from the word's own fields and filled in behind the dex when it arrives (`DexStore.fillCard`).
    /// Safety kept: the photo stays in 「解析待ち」 (hidden) until the save is done; a failed save removes the
    /// provisional entry, gives the catch back to the plan, shows the photo in 「解析待ち」 again and says why.
    private func addToDex() async -> Bool {
        guard !saveInFlight, vm.step == .celebrate, let want = vm.picked else { return false }
        saveInFlight = true
        defer { saveInFlight = false }
        // Cut-out mode: the sticker is cut before it goes into the dex (never a half-done cut).
        await vm.awaitCutout()
        // Another word was chosen (or the screen left) meanwhile: this tap belongs to the old one.
        guard vm.picked == want, vm.step == .celebrate else { return false }
        // A word already in the dex: its new photo goes to that word (the same finale, on its own square).
        if let owned = vm.owned { return recordReencounter(owned) }
        let cardLater = vm.cardStillComing
        guard let d = vm.details ?? vm.provisionalDetails(), let draft = vm.draft(details: d) else {
            vm.showToast(L("保存に失敗しました"))
            return false
        }
        guard let local = dex.addProvisional(draft) else {
            vm.showToast(L("保存に失敗しました"))
            return false
        }
        // The squares around the word's place are read into memory while the dex page rises.
        dex.warmLanding(headword: want.headword, categoryKey: d.categoryKey)
        plan.recordCatch()
        let pendingId = vm.detachPendingForSave()
        // Photos uploaded while the celebration was on screen now belong to this save (`reset` must not delete them).
        vm.handOffUploads(to: draft)
        if router.tour == .peel || router.tour == .detail {
            router.tourStickerId = local.sticker.id
            router.tour = .added
        }
        // The sticker itself leaves the stage and flies into the word's slot in the dex (film v6).
        if let f = stickerFrame {
            router.catchStar = CatchStar(center: CGPoint(x: f.midX, y: f.midY), size: 52, k: 1,
                                         image: vm.cutout ?? vm.stickerFallback(), box: f.size)
        }
        // The dex page rises over this screen, then the camera is put back.
        CatchLanding.land(stickerId: local.sticker.id, router: router, calm: reduceMotion,
                          goal: CatchGoal.make(headword: want.headword, stickers: dex.stickers, lang: NativeAPI.targetLanguage))
        // This screen goes away with the tab: the background save holds what it needs itself.
        let model = vm, store = dex, planStore = plan, nav = router
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            model.reset()
        }
        Task {
            await Self.finishSave(draft, provisional: local.sticker.id, ts: local.ts, pendingId: pendingId,
                                  cardLater: cardLater, dex: store, plan: planStore, router: nav)
        }
        return true
    }

    /// A re-encounter (web `ReencounterPanel`, its save moved here from the re-encounter card it had): no quiz — the new
    /// photo, its cut-out (waited for, like a new catch's) and where it was met are added to the word already in the
    /// dex (encounter count + 1), and the review date is not moved. The sticker flies into the word's own square with
    /// the same finale as a new word, without NEW, counters or goal toast (`alreadyCaught`).
    ///
    /// Owner 2026-10-11 (「同じ単語の画像を撮ったときに、追加するまでに時間が無駄にかかる」): nothing waits for the network.
    /// The dex shows the photo at once (`DexStore.recordEncounter`), and the upload and the record finish behind the
    /// screens — owned by this task, not by the screen, so leaving it never stops them. As for a new word
    /// (`finishSave`): the photo is handed from the camera to the save (hidden in 「解析待ち」 meanwhile), goes when it is
    /// recorded, and only a failure is told (a notice over every tab; the photo is back in 「解析待ち」 to try again).
    private func recordReencounter(_ owned: OwnedWord) -> Bool {
        guard vm.reencCount == nil else { return false }
        vm.reencCount = owned.encounterCount + 1
        let pendingId = vm.detachPendingForSave()
        let photo = vm.photo, cutout = vm.cutout, location = vm.location, placeName = vm.placeName
        let store = dex, nav = router
        Task {
            await Self.finishRecord(owned: owned, photo: photo, cutout: cutout, location: location, placeName: placeName,
                                    pendingId: pendingId, dex: store, router: nav)
        }
        if router.tour == .peel || router.tour == .detail {
            router.tourStickerId = owned.stickerId
            router.tour = .added
        }
        // The sticker itself leaves the stage and flies into the word's square in the dex (film v6).
        if let f = stickerFrame {
            router.catchStar = CatchStar(center: CGPoint(x: f.midX, y: f.midY), size: 52, k: 1,
                                         image: vm.cutout ?? vm.stickerFallback(), box: f.size)
        }
        CatchLanding.land(stickerId: owned.stickerId, router: router, calm: reduceMotion, alreadyCaught: true)
        let model = vm
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            model.reset()
        }
        return true
    }

    private static func finishRecord(owned: OwnedWord, photo: UIImage?, cutout: UIImage?, location: CLLocation?,
                                     placeName: String?, pendingId: String?, dex: DexStore, router: AppRouter) async {
        do {
            _ = try await dex.recordEncounter(owned: owned, photo: photo, cutout: cutout,
                                              location: location, placeName: placeName)
            if let pid = pendingId {
                PendingQueue.shared.remove(id: pid)
                PendingRetry.shared.forget(pid)
            }
            dex.refreshPending()
        } catch let error where DexStore.isAccountChanged(error) {
            // Signed out (or into another account) meanwhile: the photo stays with the account that took it.
            if let pid = pendingId { PendingQueue.shared.setSaving(pid, false) }
        } catch {
            DevLog.shared.add("encounter", "\(owned.headword): \(APIError.describe(error))")
            let failed = L("記録に失敗しました")
            let reason = (error as? LocalizedError)?.errorDescription ?? ""
            if let pid = pendingId {
                PendingQueue.shared.updateReason(id: pid, reason: failed)
                PendingQueue.shared.setSaving(pid, false)
            }
            dex.refreshPending()
            Haptics.warning()
            router.showNotice(reason.isEmpty || reason == failed ? failed : L("記録に失敗しました\n\(reason)"))
        }
    }

    /// The save, behind the dex. Success: the provisional entry becomes the saved sticker (the landing and the
    /// tour follow it; a word page opened on it meanwhile turns into it in place, `DexStore.current`) and the
    /// queued photo goes. Failure: the word stays in the dex as 「保存待ち」 (owner 2026-10-15: after 「保存に失敗しました。
    /// ネットワークに接続できませんでした」 花束 and 草莓蛋糕 were gone from the dex) — its word, card, photos and the photos
    /// already in storage are kept with the photo in 「解析待ち」 — and it is saved again on its own (`PendingRetry`: when
    /// the connection comes back, when the app comes to the front, after a while) or from its page, with the same
    /// `client_catch_id` so it is never saved twice. The learner reads what really happened; the real error goes to the
    /// developer log (`DevLog`).
    /// `cardLater`: the card still being generated when it was saved from the word's own fields; its notes are
    /// filled into the saved word when it arrives (a card that fails leaves the word as saved — the detail page
    /// writes the notes when it is opened, as for any word without them).
    private static func finishSave(_ draft: CatchDraft, provisional: String, ts: Int, pendingId: String?,
                                   cardLater: Task<CardDetails?, Never>? = nil,
                                   dex: DexStore, plan: PlanStore, router: AppRouter) async {
        do {
            let outcome = try await dex.save(draft, ts: ts, replacing: provisional, holdCategory: true) { saved in
                if let l = router.landing, l.stickerId == provisional { l.stickerId = saved.id }
                if router.tourStickerId == provisional { router.tourStickerId = saved.id }
            }
            // Its square stays in the category it landed in while the landing plays, then goes where the server filed it.
            let savedId = outcome.sticker.id
            Task {
                var waited = 0
                while router.landing?.stickerId == savedId, waited < 40 {
                    try? await Task.sleep(for: .milliseconds(200))
                    waited += 1
                }
                dex.settleLanding(savedId)
            }
            if let cardLater, case .created(let saved) = outcome, !saved.wordId.isEmpty {
                Task { if let card = await cardLater.value { await dex.fillCard(wordId: saved.wordId, card: card) } }
            }
            if let pid = pendingId {
                PendingQueue.shared.remove(id: pid)
                PendingRetry.shared.forget(pid)
            }
            dex.refreshPending()
        } catch let error where DexStore.isAccountChanged(error) {
            // Signed out (or into another account) during the save: the provisional entry and the plan count
            // were cleared with the old account; the new one is told nothing about it.
            dex.discardProvisional(provisional)
            if router.detailSticker?.id == provisional { router.detailSticker = nil }
            if let pid = pendingId { PendingQueue.shared.setSaving(pid, false) }
        } catch {
            DevLog.shared.add("save", SaveFailure.log(error, headword: draft.candidate.headword))
            if let pid = dex.keepUnsaved(draft, provisional: provisional, ts: ts, pendingId: pendingId, error: error) {
                PendingRetry.shared.noteFailedSave(pid, error: error)
                // The card still being generated: kept for the next try when it comes (the word is then saved with it).
                if let cardLater {
                    Task {
                        guard let card = await cardLater.value, let raw = card.raw else { return }
                        PendingQueue.shared.updateSave(id: pid) { s in
                            s.card = raw
                            s.categoryKey = card.categoryKey
                            s.exampleSentence = card.exampleSentence
                            s.exampleTranslation = card.exampleTranslation
                        }
                    }
                }
                dex.refreshPending()
                Haptics.warning()
                router.showNotice(L("まだ保存できていません：\(SaveFailure.message(for: error))\n図鑑に「保存待ち」で残してあります。あとで自動でもう一度保存します。"),
                                  seconds: 6)
            } else {
                // Nothing could be kept for a retry (no card at all): the entry goes and the catch is not counted.
                dex.discardProvisional(provisional)
                plan.undoCatch()
                if router.tourStickerId == provisional { router.tourStickerId = nil }
                if router.detailSticker?.id == provisional { router.detailSticker = nil }
                if let pid = pendingId {
                    PendingQueue.shared.updateReason(id: pid, reason: SaveFailure.message(for: error))
                    PendingQueue.shared.setSaving(pid, false)
                }
                dex.refreshPending()
                router.showNotice(L("保存に失敗しました\n\(SaveFailure.message(for: error))"))
            }
        }
    }
}

/// The camera "machine": deep navy with a faint dot grid (never a flat fill).
struct MachineBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x0C2346), Theme.navyDeep], startPoint: .top, endPoint: .bottom)
            Canvas { ctx, size in
                let step: CGFloat = 7
                var y: CGFloat = 0
                while y < size.height {
                    var x: CGFloat = 0
                    while x < size.width {
                        ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)), with: .color(.white.opacity(0.05)))
                        x += step
                    }
                    y += step
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// Four white corner brackets framing the subject.
struct ViewfinderBrackets: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height, l: CGFloat = 26, r: CGFloat = 10
            Path { p in
                p.move(to: CGPoint(x: 0, y: l)); p.addLine(to: CGPoint(x: 0, y: r))
                p.addQuadCurve(to: CGPoint(x: r, y: 0), control: .zero); p.addLine(to: CGPoint(x: l, y: 0))
                p.move(to: CGPoint(x: w - l, y: 0)); p.addLine(to: CGPoint(x: w - r, y: 0))
                p.addQuadCurve(to: CGPoint(x: w, y: r), control: CGPoint(x: w, y: 0)); p.addLine(to: CGPoint(x: w, y: l))
                p.move(to: CGPoint(x: w, y: h - l)); p.addLine(to: CGPoint(x: w, y: h - r))
                p.addQuadCurve(to: CGPoint(x: w - r, y: h), control: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: w - l, y: h))
                p.move(to: CGPoint(x: l, y: h)); p.addLine(to: CGPoint(x: r, y: h))
                p.addQuadCurve(to: CGPoint(x: 0, y: h - r), control: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: 0, y: h - l))
            }
            .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }
}

/// Deep-blue disc (the brand primary) with a white ring and a white camera glyph. While the camera tab's
/// icon is flying in (`arriving`) the disc waits hidden, then pops in with a small bounce while its white
/// ring draws round.
struct ShutterButton: View {
    var enabled: Bool
    /// The tab bar's camera icon is still on its way here (MainTabView's shutter flight).
    var arriving: Bool = false
    let action: () -> Void
    @State private var pressed: Bool = false
    @State private var ring: CGFloat = 1
    @State private var pop: CGFloat = 1

    /// Shared with the flight so the flying disc lands as exactly this one.
    static let discSize: CGFloat = 66
    static let discFill = LinearGradient(colors: [Theme.primary, Theme.primaryDeep], startPoint: .top, endPoint: .bottom)

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Theme.primary.opacity(0.35)).frame(width: 84, height: 84).blur(radius: 10)
                Circle()
                    .trim(from: 0, to: ring)
                    .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 74, height: 74)
                Circle()
                    .fill(Self.discFill)
                    .frame(width: Self.discSize, height: Self.discSize)
                    .overlay(Image(systemName: "camera").font(.system(size: 22, weight: .semibold)).foregroundStyle(.white))
                    .scaleEffect(pressed ? 0.88 : 1)
            }
            .frame(width: 88, height: 88)
            .scaleEffect(pop)
            .opacity(arriving ? 0 : 1)
            .contentShape(Circle())
        }
        .buttonStyle(ShutterStyle(pressed: $pressed))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityLabel(L("撮影"))
        .onAppear { if arriving { ring = 0 } }
        .onChange(of: arriving) { _, isArriving in
            guard !isArriving else { ring = 0; return }
            // Landed: a small overshoot bounce while the ring draws in clockwise from the top.
            withAnimation(.easeOut(duration: 0.12)) { pop = 1.1 } completion: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { pop = 1 }
            }
            withAnimation(.easeOut(duration: 0.38)) { ring = 1 }
        }
    }
}

private struct ShutterStyle: ButtonStyle {
    @Binding var pressed: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, p in
                withAnimation(.spring(response: 0.22, dampingFraction: 0.6)) { pressed = p }
            }
    }
}

struct CameraMessageView: View {
    let icon: String
    let title: String
    let message: String
    let buttonTitle: String?
    let action: () -> Void

    var body: some View {
        ZStack {
            Theme.navyCard
            VStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 42)).foregroundStyle(Theme.primaryBright)
                Text(title).scaledFont(size: 20, weight: .bold).foregroundStyle(.white)
                Text(message).scaledFont(size: 14).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
                if let buttonTitle {
                    PrimaryButton(title: buttonTitle, action: action).frame(maxWidth: 240).padding(.top, 8)
                }
            }
            .padding(32)
        }
    }
}

/// Web `OfflineSavedPanel` (capture.tsx): the photo was kept in "解析待ち" when analysis failed.
/// The reason is always shown — a 401 or a broken image must not look like "just try later".
struct FailedView: View {
    let reason: String
    let retryable: Bool
    let offline: Bool
    let onRetry: () -> Void
    let onHome: () -> Void
    let onAgain: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: offline ? "wifi.slash" : "sparkles")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Theme.gold)
            Text(L("解析できなかったので写真を預かりました"))
                .scaledFont(size: 20, weight: .bold)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(L("あとでホームの「解析待ち」から続きができます。撮った瞬間は逃していません。"))
                .scaledFont(size: 14)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            Text(L("理由: \(reason)"))
                .scaledFont(size: 12)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            VStack(spacing: 10) {
                if retryable { PrimaryButton(title: L("いますぐもう一度試す"), icon: "arrow.clockwise", action: onRetry) }
                secondary(L("ホームへ"), action: onHome)
                secondary(L("もう一枚撮る"), action: onAgain)
            }
            .padding(.top, 8)
            Spacer()
        }
        .padding(28)
        .padding(.bottom, 80)
    }

    private func secondary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .scaledFont(size: 15, weight: .semibold)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(.white.opacity(0.1), in: .rect(cornerRadius: 16))
            .buttonStyle(PressableStyle())
    }
}

struct PendingListView: View {
    @Environment(DexStore.self) private var dex
    @Environment(PlanStore.self) private var plan
    let onRestore: (PendingCatch) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(dex.pending) { item in
                    Button { onRestore(item) } label: {
                        HStack(spacing: 12) {
                            if let img = PendingQueue.shared.thumbnail(for: item) {
                                Color.clear.frame(width: 56, height: 56)
                                    .overlay { Image(uiImage: img).resizable().scaledToFill().allowsHitTesting(false) }
                                    .clipShape(.rect(cornerRadius: 10))
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                if let word = item.save?.candidate.headword {
                                    // A word whose save failed: it is in the dex already, waiting to be saved.
                                    Text(L("保存待ち：\(word)"))
                                        .scaledFont(size: 15, weight: .semibold)
                                        .foregroundStyle(Theme.primaryInk)
                                }
                                Text(item.createdAt, format: .dateTime.month().day().hour().minute().locale(L10n.locale))
                                    .scaledFont(size: item.isUnsaved ? 12 : 15, weight: item.isUnsaved ? .regular : .semibold)
                                    .foregroundStyle(item.isUnsaved ? Theme.muted : Theme.foreground)
                                Text(L10n.readerSafe(item.reason, fallback: L("解析待ちの写真"))).scaledFont(size: 12).foregroundStyle(Theme.muted).lineLimit(2)
                            }
                            Spacer()
                            Image(systemName: item.isUnsaved ? "icloud.and.arrow.up.fill" : "arrow.clockwise.circle.fill")
                                .font(.title2).foregroundStyle(Theme.primary)
                        }
                    }
                    .accessibilityIdentifier(item.isUnsaved ? "pending.unsaved" : "pending.photo")
                    .swipeActions {
                        Button(L("削除"), role: .destructive) {
                            if item.isUnsaved {
                                // Its word leaves the dex too (it was never saved), and the catch is not counted.
                                dex.discardUnsaved(pendingId: item.id)
                                plan.undoCatch()
                            } else {
                                PendingQueue.shared.remove(id: item.id)
                            }
                            dex.refreshPending()
                        }
                    }
                }
            }
            .navigationTitle(L("解析待ちの写真"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
