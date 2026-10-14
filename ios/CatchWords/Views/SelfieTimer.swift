import SwiftUI

/// The self-timer for selfies (owner 2026-10-14: 「毎回ものを持ちながらシャッターボタン押すのむずい。タイマーの時間も
/// 選べるように」). One choice for both selfie cameras (the catch's 「ものと一緒に、もう一枚」 and the word page's),
/// remembered on the phone; 0 = off.
enum SelfieTimer {
    static let storageKey = "selfie.timer"
    static let choices = [0, 3, 5, 10]

    static func label(_ seconds: Int) -> String { seconds == 0 ? L("オフ") : L("\(seconds)秒") }
}

/// Counts down a second at a time (a tick and a tap each second), then takes the shot. The shutter or 「スキップ」
/// during the count stops it.
@Observable
final class SelfieCountdown {
    /// Seconds left while counting; nil when not counting.
    private(set) var remaining: Int?
    private var task: Task<Void, Never>?

    var isRunning: Bool { remaining != nil }

    /// Starts the count; with 0 seconds `fire` runs at once.
    func start(_ seconds: Int, fire: @escaping () -> Void) {
        cancel()
        guard seconds > 0 else { fire(); return }
        remaining = seconds
        task = Task {
            for left in stride(from: seconds, through: 1, by: -1) {
                if Task.isCancelled { return }
                remaining = left
                SoundService.shared.play(.ccTick)
                Haptics.impact(.light, intensity: left <= 3 ? 0.9 : 0.5)
                try? await Task.sleep(for: .seconds(1))
            }
            if Task.isCancelled { return }
            remaining = nil
            task = nil
            fire()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        remaining = nil
    }
}

/// The timer button beside the selfie shutter: a menu of off / 3 / 5 / 10 seconds. Lit gold while a timer is set.
struct SelfieTimerMenu: View {
    @Binding var seconds: Int

    var body: some View {
        Menu {
            Picker(L("タイマー"), selection: $seconds) {
                ForEach(SelfieTimer.choices, id: \.self) { s in
                    Text(SelfieTimer.label(s)).tag(s)
                }
            }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: seconds == 0 ? "timer" : "timer.circle.fill")
                    .font(.system(size: 19, weight: .regular))
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(seconds == 0 ? 0.1 : 0.2), in: .rect(cornerRadius: 13, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(seconds == 0 ? .white.opacity(0.18) : Theme.gold.opacity(0.7), lineWidth: 1))
                Text(seconds == 0 ? L("タイマー") : SelfieTimer.label(seconds))
                    .scaledFont(size: 11, weight: .medium)
                    .monospacedDigit()
            }
            .foregroundStyle(seconds == 0 ? .white : Theme.gold)
            .frame(minWidth: 56)
        }
        .onChange(of: seconds) { _, _ in Haptics.selection() }
        .accessibilityLabel(L("タイマー"))
        .accessibilityValue(SelfieTimer.label(seconds))
        .accessibilityIdentifier("selfie.timer")
    }
}

/// The big number in the middle of the viewfinder while the timer counts.
struct SelfieCountdownNumber: View {
    let remaining: Int

    var body: some View {
        Text("\(remaining)")
            .font(.system(size: 132, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.45), radius: 16, y: 2)
            .contentTransition(.numericText(countsDown: true))
            .animation(.snappy, value: remaining)
            .allowsHitTesting(false)
            .accessibilityLabel(L("あと\(remaining)秒"))
    }
}
