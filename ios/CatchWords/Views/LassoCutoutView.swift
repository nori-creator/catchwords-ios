import SwiftUI

/// 囲んで切り抜き直す (owner 2026-11-04: 「切り抜いたあとの画像を、指でその物体をサークルで囲うと切り抜きをその部分やり直す
/// 機能をつけて」). The original photo, full screen: the learner draws a loop round the thing with a finger, the cut-out is
/// made again from what lies in it (`LassoCutout`), shown on a checkerboard, and kept with 「この切り抜きにする」
/// (`onSave`) or drawn again. Opened from the long-press photo sheet (`HeroPhotoPickerSheet`).
struct LassoCutoutView: View {
    /// The original photo's path (`Sticker.objectImageUrl`, or a later photo's own).
    let photoPath: String
    /// Saves the new cut-out (the word page uploads it and shows it); throws when it could not be saved.
    let onSave: (UIImage) async throws -> Void

    @Environment(DexStore.self) private var dex
    @Environment(\.dismiss) private var dismiss
    @State private var photo: UIImage?
    @State private var loadFailed = false
    /// The loop being drawn / drawn, 0–1 of the photo.
    @State private var loop: [CGPoint] = []
    @State private var drawing = false
    @State private var working = false
    @State private var result: UIImage?
    @State private var saving = false
    @State private var note: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                GeometryReader { geo in
                    stage(in: geo.size)
                }
                bottomBar
            }
        }
        .statusBarTone(.light)
        .task { await loadPhoto() }
        .sensoryFeedback(.success, trigger: result != nil)
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.14), in: Circle())
            }
            .accessibilityLabel(L("閉じる"))
            .accessibilityIdentifier("lasso.close")
            Spacer()
        }
        .overlay {
            Text(L("囲んで切り抜き直す"))
                .scaledFont(size: 17, weight: .bold)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func stage(in size: CGSize) -> some View {
        if let photo {
            let frame = fitted(photo.size, in: size)
            ZStack(alignment: .topLeading) {
                if let result {
                    // The new cut-out on a checkerboard, so its edge shows.
                    Checkerboard()
                        .frame(width: frame.width, height: frame.height)
                        .clipShape(.rect(cornerRadius: 12))
                        .offset(x: frame.minX, y: frame.minY)
                    Image(uiImage: result)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(18)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        .accessibilityIdentifier("lasso.result")
                } else {
                    Image(uiImage: photo)
                        .resizable()
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                    loopShape(in: frame)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(draw(in: frame), including: result == nil && !working ? .all : .none)
            .overlay {
                if working {
                    ProgressView(L("切り抜いています…"))
                        .tint(.white)
                        .foregroundStyle(.white)
                        .padding(18)
                        .background(.black.opacity(0.6), in: .rect(cornerRadius: 16))
                }
            }
            .accessibilityIdentifier("lasso.stage")
        } else if loadFailed {
            Text(L("元の写真を読み込めませんでした"))
                .scaledFont(size: 15, weight: .semibold)
                .foregroundStyle(.white)
                .frame(width: size.width, height: size.height)
        } else {
            ProgressView().tint(.white).frame(width: size.width, height: size.height)
        }
    }

    private func loopShape(in frame: CGRect) -> some View {
        Path { p in
            let pts = loop.map { CGPoint(x: frame.minX + $0.x * frame.width, y: frame.minY + $0.y * frame.height) }
            guard let first = pts.first else { return }
            p.move(to: first)
            p.addLines(pts)
            if !drawing { p.closeSubpath() }
        }
        .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: drawing ? [] : [8, 6]))
        .shadow(color: .black.opacity(0.5), radius: 2)
        .allowsHitTesting(false)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if let note {
                Text(note)
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("lasso.note")
            } else if result == nil {
                Text(L("切り抜きたい物を指で囲んでください"))
                    .scaledFont(size: 14, weight: .medium)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
            if result != nil {
                HStack(spacing: 12) {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { result = nil; loop = []; note = nil }
                    } label: {
                        Text(L("もう一度囲む"))
                            .scaledFont(size: 16, weight: .semibold)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(.white.opacity(0.14), in: .rect(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(saving)
                    .accessibilityIdentifier("lasso.again")
                    Button { Task { await save() } } label: {
                        Text(saving ? L("保存しています…") : L("この切り抜きにする"))
                            .scaledFont(size: 16, weight: .bold)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Theme.primary, in: .rect(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(saving)
                    .accessibilityIdentifier("lasso.use")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(minHeight: 96)
    }

    /// The photo's rectangle when it is fitted into `size`, centred.
    private func fitted(_ image: CGSize, in size: CGSize) -> CGRect {
        guard image.width > 0, image.height > 0 else { return .zero }
        let s = min(size.width / image.width, size.height / image.height)
        let w = image.width * s, h = image.height * s
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    private func draw(in frame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in
                if !drawing { drawing = true; loop = []; note = nil }
                let p = CGPoint(x: min(1, max(0, (v.location.x - frame.minX) / max(1, frame.width))),
                                y: min(1, max(0, (v.location.y - frame.minY) / max(1, frame.height))))
                // Every few points is enough for the outline, and keeps the loop light.
                if let last = loop.last, hypot((p.x - last.x) * frame.width, (p.y - last.y) * frame.height) < 3 { return }
                loop.append(p)
            }
            .onEnded { _ in
                drawing = false
                guard LassoCut.isLoop(loop) else {
                    note = L("もう少し大きく囲んでください")
                    loop = []
                    Haptics.warning()
                    return
                }
                Task { await recut() }
            }
    }

    private func recut() async {
        guard let photo else { return }
        working = true
        let drawn = loop
        let made = await Task.detached(priority: .userInitiated) { LassoCutout.cut(photo, loop: drawn) }.value
        working = false
        if let made {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { result = made }
        } else {
            note = L("もう少し大きく囲んでください")
            loop = []
            Haptics.warning()
        }
    }

    private func save() async {
        guard let result else { return }
        saving = true
        defer { saving = false }
        do {
            try await onSave(result)
            Haptics.success()
            dismiss()
        } catch {
            Haptics.warning()
            note = L("保存できませんでした。もう一度お試しください。")
        }
    }

    private func loadPhoto() async {
        guard photo == nil else { return }
        var image = await ImageCache.shared.cached(for: photoPath)
        if image == nil {
            await dex.prefetchPictures([photoPath])
            if let url = dex.url(for: photoPath, preferThumb: false) {
                image = await ImageCache.shared.load(url: url, key: photoPath)
            }
        }
        if let image { photo = image } else { loadFailed = true }
    }
}

/// Grey and white squares behind a cut-out, so its transparent edge shows.
private struct Checkerboard: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.92)))
            let s: CGFloat = 14
            var y: CGFloat = 0, row = 0
            while y < size.height {
                var x: CGFloat = row.isMultiple(of: 2) ? 0 : s
                while x < size.width {
                    ctx.fill(Path(CGRect(x: x, y: y, width: s, height: s)), with: .color(Color(white: 0.8)))
                    x += s * 2
                }
                y += s
                row += 1
            }
        }
    }
}
