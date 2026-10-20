import SwiftUI
import UIKit
import AVFoundation

/// The front camera for one selfie (the word page's 「いま自撮りを撮る」). Camera only: callers hide the entry when
/// `isAvailable` is false, so the photo library is never used for selfies (its permission text does not cover that
/// purpose). Its own screen (not the system picker) so it has the self-timer: holding the thing in one hand while
/// reaching for the shutter was hard (owner 2026-10-14). The shot is shown once to keep or retake, as the system
/// picker did.
struct SelfieCamera: View {
    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    let onPicked: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var camera = CameraService(preferred: .front)
    @State private var countdown = SelfieCountdown()
    @AppStorage(SelfieTimer.storageKey) private var timerSeconds: Int = 0
    /// The photo just taken, shown to keep or retake.
    @State private var shot: UIImage?
    @State private var capturing = false
    @State private var flash = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let shot {
                review(shot)
            } else {
                live
            }
            if flash {
                Color.white.ignoresSafeArea().allowsHitTesting(false)
            }
        }
        .task { await camera.start() }
        .onDisappear {
            countdown.cancel()
            camera.stop()
        }
    }

    // MARK: Live camera

    private var live: some View {
        VStack(spacing: 0) {
            HStack {
                Button { close() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .accessibilityLabel(L("閉じる"))
                Spacer()
                Text(L("自撮り")).scaledFont(size: 17, weight: .semibold).foregroundStyle(.white)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            preview
                .clipShape(.rect(cornerRadius: 24, style: .continuous))
                .padding(.horizontal, 10)
                .padding(.top, 8)

            HStack(alignment: .top) {
                SelfieTimerMenu(seconds: $timerSeconds)
                    .disabled(countdown.isRunning)
                Spacer()
                ShutterButton(enabled: camera.state == .running && !capturing) { shoot() }
                    .accessibilityIdentifier("selfie.shutter")
                Spacer()
                Button { camera.toggle() } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.system(size: 19, weight: .regular))
                            .frame(width: 44, height: 44)
                            .background(.white.opacity(0.1), in: .rect(cornerRadius: 13, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(.white.opacity(0.18), lineWidth: 1))
                        Text(L("切替")).scaledFont(size: 11, weight: .medium)
                    }
                    .foregroundStyle(.white)
                    .frame(minWidth: 56)
                }
                .buttonStyle(PressableStyle(scale: 0.9))
                .disabled(camera.state != .running || countdown.isRunning)
                .opacity(camera.state == .running ? 1 : 0.4)
            }
            .padding(.horizontal, 44)
            .padding(.top, 22)
            .padding(.bottom, 30)
        }
        .denseTypeSizeCap()
    }

    @ViewBuilder
    private var preview: some View {
        switch camera.state {
        case .running, .idle:
            CameraPreview(session: camera.session) { _, device in camera.focus(at: device) }
                .scaleEffect(x: camera.position == .front ? -1 : 1, y: 1)
                .background(Color.black)
                .overlay {
                    if let left = countdown.remaining { SelfieCountdownNumber(remaining: left) }
                }
                .overlay(alignment: .top) {
                    if countdown.isRunning {
                        Text(L("シャッターを押すと止まります"))
                            .scaledFont(size: 13, weight: .medium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(.black.opacity(0.4), in: Capsule())
                            .padding(.top, 14)
                            .transition(.opacity)
                    }
                }
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
                Task { await camera.start() }
            }
        }
    }

    // MARK: Keep or retake

    private func review(_ image: UIImage) -> some View {
        VStack(spacing: 0) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 10)
                .padding(.top, 16)
            HStack(spacing: 12) {
                Button {
                    Haptics.selection()
                    shot = nil
                } label: {
                    Text(L("撮り直す"))
                        .scaledFont(size: 17, weight: .semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(.white.opacity(0.14), in: Capsule())
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("selfie.retake")
                Button {
                    Haptics.success()
                    onPicked(image)
                    close()
                } label: {
                    Text(L("この写真を使う"))
                        .scaledFont(size: 17, weight: .bold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Theme.primary, in: Capsule())
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("selfie.use")
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 30)
        }
    }

    // MARK: Actions

    private func shoot() {
        // A second press during the count stops it.
        if countdown.isRunning {
            Haptics.selection()
            withAnimation(.easeOut(duration: 0.2)) { countdown.cancel() }
            return
        }
        countdown.start(timerSeconds) { take() }
    }

    private func take() {
        guard !capturing else { return }
        capturing = true
        // One shutter sound: the app's only where the system's own click is off (`CameraService.systemShutterSound`).
        if !camera.systemShutterSound { SoundService.shared.shutter() }
        Haptics.impact(.rigid)
        withAnimation(.easeOut(duration: 0.05)) { flash = true }
        Task {
            try? await Task.sleep(for: .milliseconds(90))
            withAnimation(.easeOut(duration: 0.3)) { flash = false }
        }
        Task {
            let image = await camera.capture()
            capturing = false
            if let image {
                withAnimation(.easeOut(duration: 0.2)) { shot = image }
            } else {
                Haptics.warning()
            }
        }
    }

    private func close() {
        countdown.cancel()
        camera.stop()
        dismiss()
    }
}
