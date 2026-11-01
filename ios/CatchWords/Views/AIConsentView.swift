import SwiftUI

/// The AI consent (App Store Review Guideline 5.1.2(i), privacy policy chapter 4): what is sent, to whom,
/// why, and what happens without it, then 「同意して始める」 / 「同意しない」.
///
/// Shown over the app once per account (RootView, after sign-in and onboarding, before the camera or any
/// AI feature), and as a sheet wherever a blocked AI feature is opened again (the camera tab, 設定, the
/// word page). The answer is kept by `AIConsent`; `NativeAPI.call` enforces it.
struct AIConsentView: View {
    /// Called after a choice (true = agreed). The overlay leaves it nil: it closes when the answer is saved.
    var onDecided: ((Bool) -> Void)? = nil

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        point(icon: "photo.on.rectangle", title: L("送るもの"),
                              text: L("撮った写真、写真アプリから選んだ画像、「違う単語を入力」で入力した単語、誤りを報告するときに書いたメモ、学ぶ言語やレベルなどの設定。メールアドレスや名前は送りません。"))
                        point(icon: "network", title: L("送り先"),
                              text: L("当社のサーバを通して、外部のAIサービス（Google など）に送ります。送り先の会社と国は、プライバシーポリシーに書いてあります。"))
                        point(icon: "lightbulb", title: L("使い道"),
                              text: L("写っている物や入力した単語の判定、単語の解説と例文の作成、報告された誤りの修正のためだけに使います。当社が写真や入力した文章を AI の学習に使うことはありません。"))
                        point(icon: "hand.raised", title: L("同意しない場合"),
                              text: L("カメラ、写真アプリの画像、「違う単語を入力」、単語の解説と例文の作成など、AI を使う機能は使えません（何も送りません）。集めた単語を見ることや復習は、そのまま使えます。あとから「設定」で同意することも、取り消すこともできます。"))
                        Text(LegalLinks.aiConsentDetails())
                            .scaledFont(size: 13)
                            .foregroundStyle(Theme.muted)
                            .tint(Theme.primaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 28)
                    .padding(.bottom, 16)
                    .readableColumn()
                }
                .scrollBounceBehavior(.basedOnSize)
                buttons
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Theme.brandGradient, in: .rect(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)
            Text(L("AIへのデータ送信について"))
                .scaledFont(size: 26, weight: .heavy)
                .foregroundStyle(Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(L("CatchWords は、写真から単語を見つけたり、単語の解説や例文を作ったりするために、外部のAIサービスを使います。使い始める前に、送る内容を確かめて、同意するかを選んでください。"))
                .scaledFont(size: 15)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 4)
    }

    private func point(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.primary)
                .frame(width: 40, height: 40)
                .background(Theme.accent, in: .rect(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).scaledFont(size: 16, weight: .bold).foregroundStyle(Theme.foreground)
                Text(text)
                    .scaledFont(size: 14)
                    .foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Theme.card, in: .rect(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.border, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var buttons: some View {
        VStack(spacing: 6) {
            PrimaryButton(title: L("同意して始める"), icon: "checkmark") { decide(true) }
                .accessibilityIdentifier("aiConsent.accept")
            Button { decide(false) } label: {
                Text(L("同意しない"))
                    .scaledFont(size: 16, weight: .semibold)
                    .foregroundStyle(Theme.primaryInk)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("aiConsent.decline")
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .readableColumn()
        .background(Theme.background.opacity(0.95).ignoresSafeArea(edges: .bottom))
    }

    private func decide(_ agreed: Bool) {
        if agreed {
            Haptics.success()
            AIConsent.shared.grant()
        } else {
            Haptics.selection()
            AIConsent.shared.decline()
        }
        onDecided?(agreed)
    }
}

/// The camera tab without the AI consent: the camera stays off (its photos would go to AI), with the way
/// to read the consent again and agree.
struct AIConsentGateView: View {
    @Environment(AppRouter.self) private var router
    @State private var showConsent = false

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 16) {
                Image(systemName: "camera.badge.ellipsis")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .accessibilityHidden(true)
                Text(L("AIの機能は止まっています"))
                    .scaledFont(size: 22, weight: .heavy)
                    .foregroundStyle(Theme.foreground)
                    .multilineTextAlignment(.center)
                Text(L("カメラで撮った写真や写真アプリから選んだ画像は、単語を見つけるために外部のAIサービスに送られます。AIへのデータ送信に同意すると、カメラ、写真アプリの画像、「違う単語を入力」、単語の解説と例文の作成が使えます。"))
                    .scaledFont(size: 15)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                PrimaryButton(title: L("内容を確認して同意する"), icon: "doc.text.magnifyingglass") { showConsent = true }
                    .accessibilityIdentifier("aiConsent.review")
                    .padding(.top, 6)
                Text(L("集めた単語を見ることや復習は、同意しなくても使えます。"))
                    .scaledFont(size: 13)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: 440)
            .padding(.bottom, router.barRoom(90, rail: 0))   // above the tab bar (none with the side rail)
        }
        .onAppear {
            // The light screen keeps the ordinary tab bar (not the camera machine's).
            router.cameraImmersive = false
            router.tabBarHidden = false
        }
        .onDisappear { router.cameraImmersive = true }
        .aiConsentSheet(isPresented: $showConsent)
    }
}

extension View {
    /// The AI consent as a sheet (a blocked AI feature opened again). `onGranted` runs after agreeing.
    func aiConsentSheet(isPresented: Binding<Bool>, onGranted: @escaping () -> Void = {}) -> some View {
        sheet(isPresented: isPresented) {
            AIConsentView { granted in
                isPresented.wrappedValue = false
                if granted { onGranted() }
            }
            .presentationDragIndicator(.visible)
        }
    }
}
