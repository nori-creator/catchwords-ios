import AVFoundation
import UIKit

nonisolated enum CameraState: Equatable, Sendable {
    case idle
    case running
    case denied
    case unavailable
}

/// Real AVFoundation pipeline (also finds the cloud simulator's injected `.external` camera).
@Observable
final class CameraService: NSObject {
    var state: CameraState = .idle
    /// Displayed zoom (1× = the main wide lens, like the Camera app).
    var zoom: CGFloat = 1
    var position: AVCaptureDevice.Position = .back

    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var device: AVCaptureDevice?
    private var input: AVCaptureDeviceInput?
    private var isConfigured = false
    private let queue = DispatchQueue(label: "catchwords.camera")
    private var photoContinuation: CheckedContinuation<UIImage?, Never>?
    /// The lens the camera opens on (the selfie camera opens on the front one).
    private let preferred: AVCaptureDevice.Position

    init(preferred: AVCaptureDevice.Position = .back) {
        self.preferred = preferred
        super.init()
    }

    func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            let ok = await AVCaptureDevice.requestAccess(for: .video)
            if !ok { state = .denied; return }
        default:
            state = .denied
            return
        }
        if !isConfigured {
            guard configure() else { state = .unavailable; return }
        }
        let session = self.session
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            queue.async {
                if !session.isRunning { session.startRunning() }
                cont.resume()
            }
        }
        state = .running
    }

    func stop() {
        let session = self.session
        queue.async { if session.isRunning { session.stopRunning() } }
        if state == .running { state = .idle }
    }

    private static func find(_ pos: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = pos == .front
            ? [.builtInTrueDepthCamera, .builtInWideAngleCamera, .external]
            : [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera, .external]
        let devices = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .unspecified).devices
        return devices.first { $0.position == pos } ?? (pos == .back ? devices.first : nil)
    }

    private func configure() -> Bool {
        guard let camera = Self.find(preferred) ?? Self.find(preferred == .front ? .back : .front),
              let newInput = try? AVCaptureDeviceInput(device: camera) else { return false }
        session.beginConfiguration()
        session.sessionPreset = .photo
        guard session.canAddInput(newInput), session.canAddOutput(output) else {
            session.commitConfiguration()
            return false
        }
        session.addInput(newInput)
        session.addOutput(output)
        output.maxPhotoQualityPrioritization = .balanced
        session.commitConfiguration()
        device = camera
        input = newInput
        position = camera.position == .front ? .front : .back
        isConfigured = true
        setZoom(1)
        return true
    }

    /// Switches lens. When the device has no front camera (e.g. the simulator's external one) this is a no-op.
    func switchTo(_ pos: AVCaptureDevice.Position) {
        guard isConfigured, pos != position, let cam = Self.find(pos), cam != device,
              let newInput = try? AVCaptureDeviceInput(device: cam), let old = input else { return }
        session.beginConfiguration()
        session.removeInput(old)
        if session.canAddInput(newInput) {
            session.addInput(newInput)
            input = newInput
            device = cam
            position = pos
        } else {
            session.addInput(old)
        }
        session.commitConfiguration()
        setZoom(1)
    }

    func toggle() {
        Haptics.impact(.light)
        switchTo(position == .back ? .front : .back)
    }

    /// Real optical/digital zoom in displayed units (the web version could only CSS-scale).
    func setZoom(_ display: CGFloat) {
        guard let device else { return }
        let m = max(0.1, device.displayVideoZoomFactorMultiplier)
        let factor = max(device.minAvailableVideoZoomFactor, min(display / m, min(device.maxAvailableVideoZoomFactor, 12)))
        zoom = factor * m
        queue.async {
            guard (try? device.lockForConfiguration()) != nil else { return }
            device.videoZoomFactor = factor
            device.unlockForConfiguration()
        }
    }

    func focus(at devicePoint: CGPoint) {
        guard let device else { return }
        queue.async {
            guard (try? device.lockForConfiguration()) != nil else { return }
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = devicePoint
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = devicePoint
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
        }
    }

    func capture() async -> UIImage? {
        // A second tap while a shot is still being processed would replace the first continuation,
        // which then never resumes (that caller waits forever).
        guard state == .running, photoContinuation == nil else { return nil }
        return await withCheckedContinuation { cont in
            photoContinuation = cont
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .balanced
            output.capturePhoto(with: settings, delegate: self)
        }
    }

    fileprivate func finish(_ image: UIImage?) {
        photoContinuation?.resume(returning: image)
        photoContinuation = nil
    }
}

extension CameraService: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = photo.fileDataRepresentation().flatMap { UIImage(data: $0) }?.normalizedOrientation()
        Task { @MainActor in self.finish(image) }
    }
}
