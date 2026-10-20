import SwiftUI

/// The learner's numbers (web AppShell BrandMenu → UserPanel, `getMyStats`): capture and review
/// streaks, level, total words, today's reviews and what is due. Opened from the avatar on Home.
nonisolated struct UserStats: Decodable, Equatable, Sendable {
    let xp: Int
    let level: Int
    let captureStreak: Int
    let reviewStreak: Int
    let capturedTotal: Int
    let reviewsDue: Int
    let reviewsDoneToday: Int

    enum CodingKeys: String, CodingKey {
        case xp, level
        case captureStreak = "capture_streak"
        case reviewStreak = "review_streak"
        case capturedTotal = "captured_total"
        case reviewsDue = "reviews_due"
        case reviewsDoneToday = "reviews_done_today"
    }

    /// Same curve as the server: level = floor(sqrt(xp / 50)) + 1.
    var levelProgress: Double {
        let start = 50.0 * pow(Double(level - 1), 2)
        let next = 50.0 * pow(Double(level), 2)
        guard next > start else { return 0 }
        return min(1, max(0, (Double(xp) - start) / (next - start)))
    }
    var xpToNext: Int { max(0, Int(50.0 * pow(Double(level), 2)) - xp) }
}

struct UserStatsPanel: View {
    let onSettings: () -> Void
    let onReview: () -> Void

    @Environment(ProfileStore.self) private var profile
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var stats: UserStats?
    @State private var failed = false
    @State private var ringShown: Double = 0

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 14) {
                AvatarView(url: profile.avatarURL, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.displayName.isEmpty ? L("あなた") : profile.displayName)
                        .scaledFont(size: 20, weight: .bold)
                        .foregroundStyle(Theme.foreground)
                    Text(profile.targetLanguage == "en" ? L("英語を学習中") : profile.targetLanguage == "ja" ? L("日本語を学習中") : L("台湾華語を学習中"))
                        .scaledFont(size: 13)
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                levelRing
            }

            HStack(spacing: 10) {
                streakTile(value: stats?.captureStreak, label: L("キャッチ連続"), icon: "camera.fill", tint: Theme.primary)
                streakTile(value: stats?.reviewStreak, label: L("復習連続"), icon: "flame.fill", tint: Color(hex: 0xFF7A1A))
            }

            HStack(spacing: 0) {
                figure(stats?.capturedTotal, L("集めた単語"), unit: L10n.unit(L("語"), count: stats?.capturedTotal))
                Divider().frame(height: 34)
                figure(stats?.reviewsDoneToday, L("今日の復習"), unit: L10n.unit(L("回"), count: stats?.reviewsDoneToday))
                Divider().frame(height: 34)
                figure(stats?.reviewsDue, L("復習待ち"), unit: L10n.unit(L("語"), count: stats?.reviewsDue))
            }
            .padding(.vertical, 12)
            .background(Theme.card, in: .rect(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.border))

            if failed {
                Text(L("数字を読み込めませんでした。通信を確かめてください。"))
                    .scaledFont(size: 12).foregroundStyle(Theme.muted)
            }

            HStack(spacing: 10) {
                if let due = stats?.reviewsDue, due > 0 {
                    Button(action: onReview) {
                        Label(L("復習する"), systemImage: "arrow.triangle.2.circlepath")
                            .scaledFont(size: 15, weight: .semibold)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(Theme.brandGradient, in: Capsule())
                    }
                    .buttonStyle(PressableStyle())
                }
                Button(action: onSettings) {
                    Label(L("設定"), systemImage: "gearshape")
                        .scaledFont(size: 15, weight: .semibold)
                        .foregroundStyle(Theme.foreground)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Theme.card, in: Capsule())
                        .overlay(Capsule().stroke(Theme.border))
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(20)
        .padding(.top, 8)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.background.ignoresSafeArea())
        .task { await load() }
    }

    private func load() async {
        do {
            let s = try await NativeAPI.call("getMyStats", [:], as: UserStats.self)
            withAnimation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.85)) { stats = s }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 1.1).delay(0.15)) { ringShown = s.levelProgress }
            failed = false
        } catch {
            failed = true
        }
    }

    private var levelRing: some View {
        ZStack {
            Circle().stroke(Theme.border, lineWidth: 6)
            Circle()
                .trim(from: 0, to: ringShown)
                .stroke(Theme.brandGradient, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            // Fixed sizes: the two lines fill the 60 pt ring (not Dynamic Type; see ScaledFont.swift).
            VStack(spacing: -2) {
                Text(L("レベル")).font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.7)
                Text(stats.map { "\($0.level)" } ?? "–")
                    .font(.system(size: 20, weight: .heavy).monospacedDigit())
                    .foregroundStyle(Theme.foreground)
                    .contentTransition(.numericText())
            }
        }
        .frame(width: 60, height: 60)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stats.map { L("レベル\($0.level)、次のレベルまで\($0.xpToNext)") } ?? L("レベル"))
    }

    private func streakTile(value: Int?, label: String, icon: String, tint: Color) -> some View {
        let on = (value ?? 0) > 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .scaledFont(size: 14, weight: .bold)
                    .foregroundStyle(on ? tint : Theme.muted.opacity(0.5))
                    .symbolEffect(.bounce, value: value)
                Text(label).scaledFont(size: 12, weight: .semibold).foregroundStyle(Theme.muted)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value.map(String.init) ?? "–")
                    .scaledFont(size: 34, weight: .heavy, monospacedDigit: true)
                    .foregroundStyle(Theme.foreground)
                    .contentTransition(.numericText())
                Text(L10n.unit(L("日"), count: value)).scaledFont(size: 14, weight: .semibold).foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(on ? tint.opacity(0.08) : Theme.card)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(on ? tint.opacity(0.25) : Theme.border))
        }
        .accessibilityElement(children: .combine)
    }

    private func figure(_ value: Int?, _ label: String, unit: String) -> some View {
        VStack(spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value.map(String.init) ?? "–")
                    .scaledFont(size: 22, weight: .bold, monospacedDigit: true)
                    .foregroundStyle(Theme.foreground)
                    .contentTransition(.numericText())
                Text(unit).scaledFont(size: 11, weight: .semibold).foregroundStyle(Theme.muted)
            }
            Text(label).scaledFont(size: 11).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
