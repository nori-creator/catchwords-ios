import SwiftUI
import UIKit

/// Which ways the screen may turn: upright only on the iPhone and on iPhone Duo's outer screen (folded); also sideways
/// on the Duo's inner screen, opened like a book (owner 2026-10-29: 「見開き（横長）で開いたとき…」 — 折りたたみ・見開き
/// （横長）・見開き（縦長）). Decided by the window's shorter side, so this iPhone app shown on an iPad (an iPhone-sized
/// window) stays upright as before.
enum ScreenOrientation {
    /// The shorter side of a window that may turn: the Duo's inner screen is 669 pt; the outer one 466, iPhones ≤ 440.
    static let turningSide: CGFloat = 600
    /// The widest a column of reading and forms is drawn (`readableColumn()`): wider than the Duo's inner screen held
    /// upright (669 pt), so only the screen held sideways (951 pt) narrows it.
    static let readableWidth: CGFloat = 680

    static func mask(for window: UIWindow?) -> UIInterfaceOrientationMask {
        guard let size = window?.bounds.size, min(size.width, size.height) >= turningSide else { return .portrait }
        return .allButUpsideDown
    }

    /// Asks the system again after the window changed size (the Duo folded or opened), so a sideways screen turns
    /// upright when the Duo is folded while held sideways.
    @MainActor
    static func refresh() {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows where window.isKeyWindow {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        }
    }
}

extension View {
    /// A column of reading and forms at most `ScreenOrientation.readableWidth` wide, in the middle: across iPhone Duo's
    /// inner screen held sideways the lines and buttons ran the whole 951 pt. Nothing changes on the iPhone or the Duo
    /// held upright.
    func readableColumn() -> some View {
        frame(maxWidth: ScreenOrientation.readableWidth).frame(maxWidth: .infinity)
    }
}

final class OrientationDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        ScreenOrientation.mask(for: window)
    }
}
