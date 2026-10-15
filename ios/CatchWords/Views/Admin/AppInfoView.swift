import SwiftUI
import UIKit

/// 設定 › 開発者 › アプリの情報: this app and this phone as the developer needs them when something goes wrong — the
/// version and build, where it was installed from, the phone and iOS, the account and languages, which servers it
/// talks to and whether the AI answers, and what is kept on the phone (words, pictures and voices on disk, photos
/// waiting for analysis).
struct AppInfoView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DexStore.self) private var dex
    @Environment(ReviewStore.self) private var review
    @State private var ai: AdminAiStatus?
    @State private var aiFailed = false
    @State private var disk: (images: Int64, voices: Int64, snapshot: Int64)?
    @State private var copied = false
    @State private var logCopied = false
    @State private var log = DevLog.shared

    var body: some View {
        List {
            // First: what went wrong lately (a failed save's real reason), the thing to look at when something broke.
            logSection
            Section(L("アプリ")) {
                AdminRow(label: L("バージョン"), value: Self.info("CFBundleShortVersionString"))
                AdminRow(label: L("ビルド"), value: Self.info("CFBundleVersion"))
                AdminRow(label: L("バンドル ID"), value: Bundle.main.bundleIdentifier ?? "—")
                AdminRow(label: L("入れ方"), value: Self.installSource)
            }
            Section(L("端末")) {
                AdminRow(label: L("機種"), value: "\(UIDevice.current.model) (\(Self.machine))")
                AdminRow(label: "iOS", value: UIDevice.current.systemVersion)
                AdminRow(label: L("画面"), value: "\(Int(UIScreen.main.bounds.width)) × \(Int(UIScreen.main.bounds.height)) pt @\(Int(UIScreen.main.scale))x")
                AdminRow(label: L("端末の言語"), value: Locale.preferredLanguages.first ?? "—")
                AdminRow(label: L("タイムゾーン"), value: TimeZone.current.identifier)
            }
            Section(L("アカウント")) {
                HStack {
                    AdminRow(label: L("ユーザー ID"), value: String((SupabaseClient.shared.userId ?? "—").prefix(13)) + "…")
                    Button {
                        UIPasteboard.general.string = SupabaseClient.shared.userId
                        Haptics.success()
                        withAnimation(.snappy) { copied = true }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("コピー"))
                }
                AdminRow(label: L("表示言語"), value: L10n.lang)
                AdminRow(label: L("学習言語"), value: NativeAPI.targetLanguage)
                AdminRow(label: L("AIへのデータ送信"), value: AIConsent.shared.isGranted ? L("同意済み") : L("未同意"))
                AdminRow(label: L("管理者"), value: AdminAccess.shared.isAdmin ? L("はい") : L("いいえ"))
            }
            Section(L("サーバ")) {
                AdminRow(label: L("Web版"), value: AppConfig.webBaseURL.host() ?? AppConfig.webBaseURL.absoluteString)
                AdminRow(label: L("データベース"), value: URL(string: AppConfig.supabaseURL)?.host() ?? AppConfig.supabaseURL)
                AdminRow(label: L("AI の状態"), value: aiStatus)
            }
            Section {
                AdminRow(label: L("図鑑の語（この学習言語）"), value: AdminFormat.int(dex.stickers.count))
                AdminRow(label: L("再会の写真"), value: AdminFormat.int(dex.encounterPhotos.values.reduce(0) { $0 + $1.count }))
                AdminRow(label: L("切り抜きのない写真"), value: AdminFormat.int(dex.stickers.filter { CutoutBackfill.needsCutout($0) }.count))
                AdminRow(label: L("今日の復習（読み込み済み）"), value: review.hasLoaded ? L("\(review.queue.count)枚") : "—")
                AdminRow(label: L("解析待ちの写真"), value: AdminFormat.int(dex.pending.count))
                AdminRow(label: L("端末に保存した画像"), value: disk.map { Self.bytes($0.images) } ?? "…")
                AdminRow(label: L("端末に保存した発音"), value: disk.map { Self.bytes($0.voices) } ?? "…")
                AdminRow(label: L("図鑑の控え"), value: disk.map { Self.bytes($0.snapshot) } ?? "…")
            } header: {
                Text(L("この端末のデータ"))
            } footer: {
                Text(L("画像・発音・図鑑の控えは、すぐ表示するために端末に保存しています。サインアウトすると消えます。"))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L("アプリの情報"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button(L("閉じる")) { dismiss() } }
        }
        .task { await loadAI() }
        .task { disk = await Self.measureDisk() }
    }

    /// 最近の記録 (`DevLog`): the real error of a failed save, an answer that did not decode, an example shown without its
    /// scene label — newest first, with when it happened, to copy into a message.
    private var logSection: some View {
        Section {
            if log.entries.isEmpty {
                Text(L("記録はまだありません"))
                    .scaledFont(size: 14)
                    .foregroundStyle(Theme.muted)
            } else {
                ForEach(log.entries.prefix(40)) { e in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(e.area)
                                .scaledFont(size: 11, weight: .bold)
                                .foregroundStyle(Theme.primaryInk)
                            Text(e.at, format: .dateTime.month().day().hour().minute().second())
                                .scaledFont(size: 11)
                                .foregroundStyle(Theme.muted)
                        }
                        Text(e.text)
                            .scaledFont(size: 13)
                            .foregroundStyle(Theme.foreground)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                    .accessibilityIdentifier("devlog.entry")
                }
                Button {
                    UIPasteboard.general.string = log.text
                    Haptics.success()
                    withAnimation(.snappy) { logCopied = true }
                } label: {
                    Label(logCopied ? L("コピーしました") : L("記録をコピー"), systemImage: logCopied ? "checkmark" : "doc.on.doc")
                }
                Button(role: .destructive) { log.clear() } label: {
                    Label(L("記録を消す"), systemImage: "trash")
                }
            }
        } header: {
            Text(L("最近の記録"))
        } footer: {
            Text(L("保存の失敗などの本当の理由です。開発者だけが見られます。"))
        }
    }

    private var aiStatus: String {
        if aiFailed { return L("確かめられませんでした") }
        guard let ai else { return "…" }
        if ai.ok { return L("動いています（\(ai.provider ?? "—")）") }
        return ai.error.map { L10n.readerSafe($0, fallback: L("動いていません")) } ?? L("動いていません")
    }

    private func loadAI() async {
        if let s = try? await NativeAPI.call("adminGetAiSettings", [:], as: AdminAiSettings.self, timeout: 30), s.isAdmin {
            ai = s.status
        } else {
            aiFailed = true
        }
    }

    private static func info(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "—"
    }

    /// TestFlight builds carry a sandbox receipt; development builds none.
    private static var installSource: String {
        #if DEBUG
        return L("開発用ビルド")
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" ? "TestFlight" : "App Store"
        #endif
    }

    /// The model identifier (iPhone17,1 …).
    private static var machine: String {
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }

    private static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    /// The sizes of the folders kept in Caches (pictures, voices, the dex snapshot), counted off the main thread.
    private static func measureDisk() async -> (images: Int64, voices: Int64, snapshot: Int64) {
        await Task.detached(priority: .utility) { () -> (images: Int64, voices: Int64, snapshot: Int64) in
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            func size(_ name: String) -> Int64 {
                let dir = caches.appendingPathComponent(name, isDirectory: true)
                guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
                return files.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
            }
            return (size("images"), size("tts"), size("dex-snapshot"))
        }.value
    }
}
