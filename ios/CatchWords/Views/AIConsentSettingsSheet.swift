import SwiftUI

/// 設定 › 規約と表記 › 「AIへのデータ送信」 (web `AiConsentRowView`, owner 2026-10-11: 「プライバシーのAIの同意は
/// WEB版と同じように、利用規約とか同じ欄に同じように統合して」). What the setting is, whether (and since when) this
/// account agreed, where the details are, and the one thing to do next: agree (through the full consent screen) or
/// withdraw (asked once more, here).
struct AIConsentSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showConsent = false
    @State private var confirmWithdraw = false
    @State private var notice: String?

    var body: some View {
        let consent = AIConsent.shared
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Text(L("AIへのデータ送信"))
                    .scaledFont(size: 22, weight: .bold)
                    .foregroundStyle(Theme.foreground)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                        .frame(width: 44, height: 44)
                        .background(Theme.card, in: Circle())
                        .overlay(Circle().stroke(Theme.border, lineWidth: 1))
                }
                .buttonStyle(PressableStyle(scale: 0.9))
                .accessibilityLabel(L("閉じる"))
            }
            Text(L("写真・調べた単語・入力した文章を、外部のAIサービス（Google など）に送ってよいかの設定です。"))
                .scaledFont(size: 15)
                .foregroundStyle(Theme.foreground.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            Label {
                Text(status(consent.status))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: consent.isGranted ? "checkmark.circle.fill" : "pause.circle")
                    .foregroundStyle(consent.isGranted ? Theme.ok : Theme.muted)
            }
            .scaledFont(size: 15, weight: .semibold)
            .foregroundStyle(Theme.foreground)
            .accessibilityIdentifier("settings.aiConsent.status")
            Text(LegalLinks.aiConsentDetails())
                .scaledFont(size: 14)
                .foregroundStyle(Theme.muted)
                .tint(Theme.primaryInk)

            if consent.isGranted {
                if confirmWithdraw {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L("取り消すと、カメラ、写真アプリの画像、「リストにない言葉を探す」、単語の解説と例文の作成など、AI を使う機能は使えなくなります。集めた単語と復習はそのまま使えます。"))
                            .scaledFont(size: 14)
                            .foregroundStyle(Theme.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 10) {
                            Button {
                                withAnimation(.snappy) { confirmWithdraw = false }
                            } label: {
                                Text(L("キャンセル"))
                                    .scaledFont(size: 16, weight: .semibold)
                                    .foregroundStyle(Theme.foreground)
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .background(Theme.card, in: Capsule())
                                    .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                            }
                            .buttonStyle(PressableStyle())
                            Button {
                                AIConsent.shared.decline()
                                Haptics.warning()
                                withAnimation(.snappy) {
                                    confirmWithdraw = false
                                    notice = L("同意を取り消しました")
                                }
                            } label: {
                                Text(L("取り消す"))
                                    .scaledFont(size: 16, weight: .semibold)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .background(Theme.destructive, in: Capsule())
                            }
                            .buttonStyle(PressableStyle())
                            .accessibilityIdentifier("settings.aiConsent.withdraw.confirm")
                        }
                    }
                    .padding(14)
                    .background(Theme.destructive.opacity(0.06), in: .rect(cornerRadius: 18, style: .continuous))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    Button {
                        Haptics.selection()
                        withAnimation(.snappy) { confirmWithdraw = true }
                    } label: {
                        Text(L("同意を取り消す"))
                            .scaledFont(size: 16, weight: .semibold)
                            .foregroundStyle(Theme.destructive)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Theme.card, in: Capsule())
                            .overlay(Capsule().stroke(Theme.destructive.opacity(0.4), lineWidth: 1))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityIdentifier("settings.aiConsent.withdraw")
                }
            } else {
                Button {
                    showConsent = true
                } label: {
                    Text(L("内容を確認して同意する"))
                        .scaledFont(size: 16, weight: .semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Theme.brandGradient, in: Capsule())
                        .shadow(color: Theme.primary.opacity(0.3), radius: 10, y: 5)
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("settings.aiConsent.review")
            }
            if let notice {
                Label(notice, systemImage: "checkmark")
                    .scaledFont(size: 13, weight: .medium)
                    .foregroundStyle(Theme.muted)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background.ignoresSafeArea())
        .aiConsentSheet(isPresented: $showConsent) {
            withAnimation(.snappy) { notice = L("AIへのデータ送信に同意しました") }
        }
    }

    private func status(_ s: AIConsent.Status) -> String {
        switch s {
        case .granted(let date):
            return L("同意しています（\(date.formatted(.dateTime.year().month().day().locale(L10n.locale)))）")
        case .declined:
            return L("同意していません。AI を使う機能は止まっています。")
        case .undecided:
            return L("まだ選んでいません。AI を使う機能を使う前に確認します。")
        }
    }
}
