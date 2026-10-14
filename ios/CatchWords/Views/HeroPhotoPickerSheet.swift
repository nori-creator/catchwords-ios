import SwiftUI
import PhotosUI

/// 「この単語は、どの絵で見せるか」(web HeroPhotoPicker.tsx, 要望 #17).
///
/// Only pictures that exist are offered — a choice that does nothing is never shown. A cut-out
/// that is the same file as the original is not offered either (the web compares the two).
/// The choice is saved on the server (`hero_role`), so it follows the learner to the web app.
struct HeroPhotoPickerSheet: View {
    let sticker: Sticker
    let onPick: (String) async throws -> Void
    /// 写真を替える, at the bottom of this sheet (owner 2026-10-11, web HeroPhotoPicker `onReplaceFile`). The word page
    /// does the replacing (and the new cut-out); nil = not offered here.
    var onReplace: ((PhotosPickerItem) -> Void)? = nil
    /// 自撮りを撮る, under 写真を替える (owner 2026-10-14: moved here from the bottom of the word page). The word page
    /// saves it; nil = not offered (no front camera, or the word is still being saved).
    var onSelfie: ((UIImage) async -> Void)? = nil

    @State private var takingSelfie = false
    @State private var savingSelfie = false

    @Environment(DexStore.self) private var dex
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var saving: String?
    @State private var chosen: String?
    @State private var failure: String?
    @State private var newPhoto: PhotosPickerItem?

    private struct Option: Identifiable {
        let id: String
        let label: String
        let path: String
        let isCutout: Bool
    }

    private var options: [Option] {
        var out: [Option] = []
        if let p = sticker.objectImageUrl { out.append(Option(id: "object", label: L("元の写真"), path: p, isCutout: false)) }
        if let p = sticker.cutoutImageUrl, p != sticker.objectImageUrl {
            out.append(Option(id: "cutout", label: L("切り抜き"), path: p, isCutout: true))
        }
        if let p = sticker.selfieImageUrl { out.append(Option(id: "selfie", label: L("自撮り"), path: p, isCutout: false)) }
        return out
    }

    /// What the page shows now: the saved choice, else the default order (cut-out, then original).
    private var current: String {
        if let chosen { return chosen }
        if let r = sticker.heroRole, options.contains(where: { $0.id == r }) { return r }
        return options.first { $0.id == "cutout" }?.id ?? "object"
    }

    var body: some View {
        // Scrolls when it is taller than the sheet: at the half-height detent the tiles and buttons ran off the bottom
        // (owner 2026-10-14: 「表示する写真が見切れている」).
        ScrollView {
            content
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.background.ignoresSafeArea())
        .sensoryFeedback(.selection, trigger: chosen)
        .onChange(of: newPhoto) { _, item in
            guard let item else { return }
            newPhoto = nil
            dismiss()
            onReplace?(item)
        }
        .fullScreenCover(isPresented: $takingSelfie) {
            SelfieCamera { image in
                Task {
                    savingSelfie = true
                    await onSelfie?(image)
                    savingSelfie = false
                }
            }
            .ignoresSafeArea()
            .statusBarTone(.hidden)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("表示する写真"))
                    .scaledFont(size: 22, weight: .bold)
                    .foregroundStyle(Theme.foreground)
                Text(L("単語の詳細で、この写真を表紙にします。"))
                    .scaledFont(size: 13)
                    .foregroundStyle(Theme.muted)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(options) { option in
                    tile(option)
                }
            }
            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .scaledFont(size: 13, weight: .medium)
                    .foregroundStyle(Theme.primary)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if onReplace != nil {
                PhotosPicker(selection: $newPhoto, matching: .images) {
                    Label(L("写真を替える"), systemImage: "photo.badge.arrow.down")
                        .scaledFont(size: 16, weight: .semibold)
                        .foregroundStyle(Theme.foreground)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Theme.card, in: .rect(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.border, lineWidth: 1))
                }
                .buttonStyle(PressableStyle())
                .disabled(saving != nil)
                .accessibilityIdentifier("hero.replacePhoto")
                .padding(.top, 4)
            }
            if onSelfie != nil {
                Button { takingSelfie = true } label: {
                    Label(savingSelfie ? L("保存しています…")
                          : (sticker.selfieImageUrl == nil ? L("いま自撮りを撮る") : L("自撮りを撮り直す")),
                          systemImage: "camera")
                        .scaledFont(size: 16, weight: .semibold)
                        .foregroundStyle(Theme.primaryInk)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Theme.primary.opacity(0.12), in: .rect(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(PressableStyle())
                .disabled(saving != nil || savingSelfie)
                .accessibilityIdentifier("detail.addSelfie")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 26)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tile(_ option: Option) -> some View {
        let on = current == option.id
        return Button {
            pick(option.id)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // A square that never grows with the photo: a 3:4 photo drawn to fill used to make its tile 3:4, which
                // pushed the row (and the cut-out next to it) off the sheet. The photo fills the square and is
                // cropped by it; the cut-out fits inside with room for its shadow.
                (option.isCutout ? Color(hex: 0xEEF3F9) : Theme.secondary)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        StickerImage(path: option.path, url: dex.url(for: option.path, preferThumb: false),
                                     contentMode: option.isCutout ? .fit : .fill)
                            .padding(option.isCutout ? 18 : 0)
                            .shadow(color: .black.opacity(option.isCutout ? 0.22 : 0), radius: 6, y: 4)
                            .allowsHitTesting(false)
                    }
                    .overlay {
                        if saving == option.id {
                            Color.black.opacity(0.25)
                            ProgressView().tint(.white)
                        }
                    }
                    .clipShape(.rect(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(on ? Theme.primary : Color.black.opacity(0.06), lineWidth: on ? 3 : 1)
                }
                .overlay(alignment: .topTrailing) {
                    if on {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Theme.primary, in: Circle())
                            .shadow(color: Theme.primary.opacity(0.4), radius: 6, y: 2)
                            .padding(8)
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                }
                .scaleEffect(on ? 1 : 0.97)
                .shadow(color: .black.opacity(on ? 0.14 : 0.05), radius: on ? 14 : 4, y: on ? 8 : 2)
                Text(option.label)
                    .scaledFont(size: 14, weight: on ? .bold : .medium)
                    .foregroundStyle(on ? Theme.foreground : Theme.muted)
                    .padding(.leading, 4)
            }
        }
        .buttonStyle(PressableStyle())
        .disabled(saving != nil)
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func pick(_ role: String) {
        guard saving == nil, role != current || sticker.heroRole != role else { return }
        let before = chosen
        withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.72)) {
            chosen = role
            failure = nil
        }
        saving = role
        Task {
            do {
                try await onPick(role)
                saving = nil
                try? await Task.sleep(for: .milliseconds(280))
                dismiss()
            } catch {
                saving = nil
                Haptics.warning()
                withAnimation(.snappy) {
                    chosen = before
                    failure = (error as? LocalizedError)?.errorDescription ?? L("保存できませんでした。通信を確かめてください。")
                }
            }
        }
    }
}
