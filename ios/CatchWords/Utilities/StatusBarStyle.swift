import SwiftUI
import UIKit
import ObjectiveC

/// Status-bar text colour per screen. SwiftUI has no status-bar-style modifier, so screens ask for a tone
/// (`statusBarTone`) and the app window's SwiftUI controllers report it (`StatusBarHook`).
enum StatusBarTone: Equatable {
    /// White text: dark full-screen views (camera, scan, analysing, reward, the memorial reveal).
    case light
    /// Dark text: screens that stay paper-coloured even in the dark theme (home, onboarding).
    case dark
    /// Follows the app's colour scheme.
    case automatic
    /// No status bar (the system camera, which draws its own controls there).
    case hidden
}

@MainActor
final class StatusBarController {
    static let shared = StatusBarController()

    /// The app's window (the one SwiftUI made), whose view controllers decide the status bar.
    private weak var window: UIWindow?
    /// Screens on screen now, in the order they appeared: the last one is on top and wins, except that a covering
    /// view (one drawn over everything, like the opening `LaunchIntro`) wins over screens that appear under it.
    private var requests: [(id: UUID, tone: StatusBarTone, covering: Bool)] = []

    /// The style and visibility the app's view controllers report (`StatusBarHook`).
    private(set) var style: UIStatusBarStyle = .darkContent
    private(set) var hidden: Bool = false

    /// The app's effective colour scheme (theme setting), reported by RootView.
    var baseScheme: ColorScheme = .light {
        didSet { if oldValue != baseScheme { update() } }
    }

    private init() {}

    /// Owner 2026-10-29 (「時計の色最適化して」): the status bar is decided by the app window's own view controllers. An
    /// overlay window with its own controller used to hold the style, but iOS never asked it (the CI pictures showed
    /// black text over the opening's blue, the night sky and the camera); the app's SwiftUI controllers are now made to
    /// report this controller's style (`StatusBarHook`).
    func install(in window: UIWindow) {
        guard self.window !== window else { return }
        self.window = window
        update(force: true)
    }

    func set(_ id: UUID, _ tone: StatusBarTone, covering: Bool = false) {
        if let i = requests.firstIndex(where: { $0.id == id }) {
            guard requests[i].tone != tone else { return }
            requests[i].tone = tone
        } else {
            requests.append((id: id, tone: tone, covering: covering))
        }
        update()
    }

    func remove(_ id: UUID) {
        guard let i = requests.firstIndex(where: { $0.id == id }) else { return }
        requests.remove(at: i)
        update()
    }

    private func update(force: Bool = false) {
        let tone = (requests.last(where: { $0.covering }) ?? requests.last)?.tone ?? .automatic
        let newStyle: UIStatusBarStyle
        switch tone {
        case .light: newStyle = .lightContent
        case .dark: newStyle = .darkContent
        case .automatic, .hidden: newStyle = baseScheme == .dark ? .lightContent : .darkContent
        }
        let newHidden = tone == .hidden
        guard force || style != newStyle || hidden != newHidden else { return }
        style = newStyle
        hidden = newHidden
        apply()
    }

    /// Every controller from the window's root up the presented ones reports the style; the one iOS asks redraws.
    func apply() {
        guard let root = window?.rootViewController else { return }
        var vc: UIViewController? = root
        var chain: [UIViewController] = []
        while let c = vc {
            chain.append(c)
            StatusBarHook.patch(c)
            vc = c.presentedViewController
        }
        UIView.animate(withDuration: 0.25) {
            for c in chain { c.setNeedsStatusBarAppearanceUpdate() }
        }
    }
}

/// Makes a view controller's class report `StatusBarController`'s style (SwiftUI's hosting controllers report the
/// colour scheme's, and there is no SwiftUI modifier for it). Each class is patched once; only the app's own
/// SwiftUI hosting controllers are patched (a system controller presented over them, like the photo picker, keeps
/// its own status bar).
@MainActor
enum StatusBarHook {
    private static var patched: Set<ObjectIdentifier> = []

    static func patch(_ vc: UIViewController) {
        guard let cls = object_getClass(vc) else { return }
        let id = ObjectIdentifier(cls)
        guard !patched.contains(id) else { return }
        // SwiftUI's own controllers only (UIHostingController and its presentation controllers).
        guard NSStringFromClass(cls).contains("SwiftUI") || NSStringFromClass(cls).contains("Hosting") else { return }
        patched.insert(id)
        let (style, hidden, noChild) = blocks()
        class_replaceMethod(cls, #selector(getter: UIViewController.preferredStatusBarStyle), imp_implementationWithBlock(style), "q@:")
        class_replaceMethod(cls, #selector(getter: UIViewController.prefersStatusBarHidden), imp_implementationWithBlock(hidden), "B@:")
        class_replaceMethod(cls, #selector(getter: UIViewController.childForStatusBarStyle), imp_implementationWithBlock(noChild), "@@:")
        class_replaceMethod(cls, #selector(getter: UIViewController.childForStatusBarHidden), imp_implementationWithBlock(noChild), "@@:")
    }

    /// The replacement getters, made outside the main actor (Objective-C blocks carry no actor); iOS asks them on the
    /// main thread.
    nonisolated private static func blocks() -> (style: Any, hidden: Any, noChild: Any) {
        let style: @convention(block) (UIViewController) -> Int = { _ in
            MainActor.assumeIsolated { StatusBarController.shared.style.rawValue }
        }
        let hidden: @convention(block) (UIViewController) -> Bool = { _ in
            MainActor.assumeIsolated { StatusBarController.shared.hidden }
        }
        // The controller decides itself instead of handing it to a child.
        let noChild: @convention(block) (UIViewController) -> UIViewController? = { _ in nil }
        return (style, hidden, noChild)
    }
}

/// Finds the app's window and hands it to `StatusBarController`.
private struct StatusBarInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> InstallerView { InstallerView() }
    func updateUIView(_ uiView: InstallerView, context: Context) {}

    final class InstallerView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window else { return }
            StatusBarController.shared.install(in: window)
        }
    }
}

private struct StatusBarRoot: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(StatusBarInstaller().frame(width: 0, height: 0).allowsHitTesting(false).accessibilityHidden(true))
            .onAppear { StatusBarController.shared.baseScheme = colorScheme }
            .onChange(of: colorScheme) { _, s in StatusBarController.shared.baseScheme = s }
    }
}

private struct StatusBarToneModifier: ViewModifier {
    let tone: StatusBarTone
    var covering = false
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear {
                StatusBarController.shared.set(id, tone, covering: covering)
                // A screen shown in a full-screen cover sits on a new controller: patch it too.
                Task { @MainActor in StatusBarController.shared.apply() }
            }
            .onDisappear { StatusBarController.shared.remove(id) }
            .onChange(of: tone) { _, t in StatusBarController.shared.set(id, t) }
    }
}

extension View {
    /// The status bar's text colour while this view is on screen (the most recently shown view wins; a `covering`
    /// view, drawn over everything, also wins over the screens that appear under it).
    func statusBarTone(_ tone: StatusBarTone, covering: Bool = false) -> some View {
        modifier(StatusBarToneModifier(tone: tone, covering: covering))
    }

    /// Hands the app's window to `StatusBarController`; put once at the app's root, inside `.preferredColorScheme`.
    func statusBarRoot() -> some View {
        modifier(StatusBarRoot())
    }
}
