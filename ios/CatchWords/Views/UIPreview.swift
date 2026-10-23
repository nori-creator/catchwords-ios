import SwiftUI

/// Screens the GitHub "iOS check" opens directly (launch argument `-uiPreview <name>`), so changes to
/// animation and design can be photographed on the simulator without an iPhone, a login, or the network.
/// Development (DEBUG) builds only — App Store builds never read the argument.
enum UIPreview {
    static var requested: String? {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "uiPreview")
        #else
        return nil
        #endif
    }

    /// The requested scene, parsed once (it sets the display language, so never during a redraw).
    static let parsed: (scene: String, dark: Bool)? = requested.map(parse)

    /// "settings-en-dark" → scene "settings", English, dark. Sets the display language as a side effect, and puts the
    /// per-device choices a scene may set (発音表記, the developer's trials) back to their defaults first, so one scene's
    /// choice never leaks into the next launch on the same simulator.
    static func parse(_ raw: String) -> (scene: String, dark: Bool) {
        var parts = raw.split(separator: "-").map(String.init)
        var dark = false
        var lang = "ja"
        // Any display language's code ("ko", "vi" …; "zh" for zh-TW) picks the language.
        let codes = Set(L10n.supported.filter { !$0.contains("-") } + ["zh"])
        while let last = parts.last, parts.count > 1, last == "dark" || codes.contains(last) {
            if last == "dark" { dark = true } else { lang = last == "zh" ? "zh-TW" : last }
            parts.removeLast()
        }
        L10n.lang = lang
        for key in ["reading.pref", DevChoices.tabBarKey] + DevChoices.retiredKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        return (parts.joined(separator: "-"), dark)
    }
}

/// CI photographs screens from outside the app (`xcrun simctl io screenshot`, .github/workflows/ios-check.yml),
/// where XCUITest's `waitForExistence` is not available. Instead the app leaves a file in
/// Caches/ui-ready/<name> once a known element of the screen is on screen, and the workflow waits for that
/// file before the first picture — so a slow launch or an entrance transition is never captured as a blank
/// frame. DEBUG builds launched with `-uiPreview` / `-uiDemo` only; nothing is written otherwise.
enum UIReady {
    static func mark(_ name: String) {
        #if DEBUG
        guard UIPreview.requested != nil || DemoBackend.isOn else { return }
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ui-ready", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? Data().write(to: dir.appendingPathComponent(name))
        #endif
    }
}

extension View {
    /// Marks the screen ready for CI's screenshots once this element has appeared (plus a short settle, so
    /// the first frame has been drawn). No effect in App Store builds.
    func uiReady(_ name: String) -> some View {
        #if DEBUG
        onAppear {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                UIReady.mark(name)
            }
        }
        #else
        self
        #endif
    }
}

#if DEBUG
struct UIPreviewRoot: View {
    let name: String
    @State private var router = AppRouter()

    var body: some View {
        Group {
            switch name {
            case "cutout": CelebrationPreview(withCutout: false)
            case "picker": PickerPreview()
            case "japicker": PickerPreview(learning: "ja")
            case "enpicker": PickerPreview(learning: "en")
            // The owner's desk (2026-10-15): tablet, cup, stylus, tissue — each tag on its own thing; and the same
            // answer without any position, the tags spread instead of piled in the middle.
            case "picker4": PickerPreview(desk: .placed)
            case "picker4-nopos": PickerPreview(desk: .unplaced)
            case "tabbar": TabBarPreview()
            // The raised camera disc kept for a later release (developer's trial only, docs/backlog.md).
            case "tabbar-b": TabBarPreview(variant: DevChoices.tabBarRaised)
            case "readings": ChunkReadingsPreview(pref: "zhuyin")
            case "readings-pinyin": ChunkReadingsPreview(pref: "pinyin")
            // A narrow card: the chunks shrink to stay on one line, down to 80% (owner 2026-10-16), and only then wrap.
            case "chunks-narrow": ChunkReadingsPreview(pref: "zhuyin", width: 290)
            case "reports": AdminReportsPreview()
            case "map": MapPreview()
            case "reward": CelebrationPreview()
            case "variants": PickerPreview(autoOpen: true)
            case "choose": PickerPreview(autoOpen: true, holdOpen: true)
            case "typed": PickerPreview(typed: true)
            case "get": CelebrationPreview(replay: 4.6)
            case "get-again": CelebrationPreview(replay: 4.6, again: true)
            case "landing": LandingPreview()
            case "landing-again": LandingPreview(again: true)
            case "analyzing": ScanPreview(namesAfter: 2.4).uiReady("preview")
            case "scanslow": ScanPreview(namesAfter: 6.0).uiReady("preview")
            case "hero": HeroPickerPreview()
            case "memorial": MemorialPreview()
            case "carousel": CarouselPreview()
            case "detail": DetailPreview()
            case "milktea": MilkTeaDetailPreview()
            case "tips": TipsPreview()
            // 「作り直す」: the section breaks into dust and the new text gathers back (owner 2026-10-16), on a loop.
            case "regen": RegenPreview()
            case "examples": ExamplesPreview()
            case "sunscreen": SunscreenExamplesPreview()
            case "unsaved": UnsavedWordPreview()
            case "devlog": DevLogPreview()
            case "selfie": SelfieDetailPreview(original: false)
            case "selfie-original": SelfieDetailPreview(original: true)
            case "slides": SlidesPreview()
            case "chunks": ChunkWheelPreview()
            case "jadetail": LanguageCardPreview(kind: .ja)
            case "quiz": ReviewPreview(learning: "zh-TW", answered: false)
            case "answer": ReviewPreview(learning: "zh-TW", answered: true)
            case "jaquiz": ReviewPreview(learning: "ja", answered: false)
            case "enanswer": ReviewPreview(learning: "en", answered: true)
            case "endetail": LanguageCardPreview(kind: .en)
            case "settings": SettingsView()
            case "aisettings": AdminAiSettingsPreview()
            case "aistats": AdminAiStatsPreview()
            case "aicosts": AdminAiCostsPreview()
            case "auth": AuthView()
            case "signin": AuthView(startOnOptions: true)
            case "onboarding": OnboardingView {}
            case "aiconsent": AIConsentView()
            case "paywall": PaywallView()
            case "dex": DexView()
            case "done": DonePreview()
            case "home": HomePreview()
            case "home-again": HomePreview(metAgain: true)
            case "camblocked": CameraBlockedPreview()
            case "homeload": VStack(spacing: 20) {
                AlbumSkeleton().frame(height: 440)
                AlbumLoadFailed(message: L("通信できませんでした。電波のよい場所でもう一度お試しください。")) {}.frame(height: 300)
            }.padding(16).background(HomeBackground())
            default: Text("unknown preview: \(name)")
            }
        }
        // Scenes that mark a known element of their own (the quiz card, the analysis view, the web-images
        // section) are ready only when that element is up; every other scene when its root appears.
        .uiReady(Self.marksOwnElement.contains(name) ? "root-\(name)" : "preview")
        .environment(router)
    }

    private static let marksOwnElement: Set<String> = ["analyzing", "scanslow", "quiz", "answer", "jaquiz", "enanswer",
                                                       "variants", "choose", "landing", "landing-again", "typed"]
}

/// The catch scan's photo for the simulator (Vision's cut-out does not run there): a mango on a plate and a cup,
/// drawn from the same shapes as its label mask, so the outlines traced from the mask (`CatchOutlineTracer`, the
/// app's own code) sit on the things in the photo.
enum ScanFixtures {
    static let size = CGSize(width: 900, height: 1200)

    private static let mango = CGRect(x: 280, y: 500, width: 340, height: 270)
    private static let plate = CGRect(x: 150, y: 640, width: 600, height: 180)
    private static let cup = CGRect(x: 640, y: 380, width: 160, height: 210)
    private static let handle = CGRect(x: 780, y: 430, width: 70, height: 90)

    static let photo: UIImage = UIGraphicsImageRenderer(size: size).image { ctx in
        let c = ctx.cgContext
        let colors = [UIColor(red: 0.72, green: 0.84, blue: 0.93, alpha: 1).cgColor,
                      UIColor(red: 0.95, green: 0.9, blue: 0.82, alpha: 1).cgColor] as CFArray
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            c.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height * 0.55), options: [])
        }
        UIColor(red: 0.66, green: 0.5, blue: 0.36, alpha: 1).setFill()
        c.fill(CGRect(x: 0, y: size.height * 0.55, width: size.width, height: size.height * 0.45))
        UIColor(white: 0.97, alpha: 1).setFill()
        c.fillEllipse(in: plate)
        UIColor(red: 0.2, green: 0.45, blue: 0.85, alpha: 1).setFill()
        c.fill(cup)
        c.setStrokeColor(UIColor(red: 0.2, green: 0.45, blue: 0.85, alpha: 1).cgColor)
        c.setLineWidth(22)
        c.strokeEllipse(in: handle.insetBy(dx: 11, dy: 11))
        UIColor(red: 1, green: 0.72, blue: 0.16, alpha: 1).setFill()
        c.fillEllipse(in: mango)
        UIColor(red: 0.95, green: 0.45, blue: 0.2, alpha: 1).setFill()
        c.fillEllipse(in: CGRect(x: 470, y: 530, width: 120, height: 100))
    }

    /// The label mask (a quarter of the photo's size): 1 mango, 2 plate, 3 cup — the mango in front of the plate.
    private static let labels: (mask: [UInt8], width: Int, height: Int) = {
        let w = Int(size.width / 4), h = Int(size.height / 4)
        var mask = [UInt8](repeating: 0, count: w * h)
        func inEllipse(_ r: CGRect, _ p: CGPoint) -> Bool {
            let dx = (p.x - r.midX) / (r.width / 2), dy = (p.y - r.midY) / (r.height / 2)
            return dx * dx + dy * dy <= 1
        }
        func inRing(_ r: CGRect, _ p: CGPoint) -> Bool {
            inEllipse(r, p) && !inEllipse(r.insetBy(dx: 22, dy: 22), p)
        }
        for y in 0..<h {
            for x in 0..<w {
                let p = CGPoint(x: CGFloat(x) * 4 + 2, y: CGFloat(y) * 4 + 2)
                var v: UInt8 = 0
                if inEllipse(plate, p) { v = 2 }
                if cup.contains(p) || inRing(handle, p) { v = 3 }
                if inEllipse(mango, p) { v = 1 }
                mask[y * w + x] = v
            }
        }
        return (mask: mask, width: w, height: h)
    }()

    static let outlines: [CatchOutline] = CatchOutlineTracer.outlines(mask: labels.mask, width: labels.width,
                                                                      height: labels.height)

    /// Where each thing's tag sits, by label, as `InstanceMasks.anchors` measures it from Vision's mask on a phone.
    static let anchors: [Int: CGPoint] = CatchAnchor.anchors(mask: labels.mask, width: labels.width, height: labels.height)

    /// What the AI "names": the mango (two names), the plate and the cup, each on its thing (0–1000 of the photo).
    static func candidates() -> [Candidate] {
        let i = L10n.lang == "en" ? 1 : L10n.lang == "zh-TW" ? 2 : 0
        func c(_ head: String, _ zy: String, _ meaning: [String], _ register: String?, _ group: Int, _ x: Double, _ y: Double) -> Candidate {
            Candidate(kind: "object", headword: head, zhuyin: zy, pinyin: "", meaningJa: meaning[i], pos: NativeAPI.defaultPos,
                      point: [x, y], confidence: 0.9, alternatives: [], distinction: "", register: register, group: group)
        }
        return [c("芒果", "ㄇㄤˊ ㄍㄨㄛˇ", ["マンゴー", "mango", "芒果"], "common", 0, 500, 530),
                c("愛文芒果", "ㄞˋ ㄨㄣˊ ㄇㄤˊ ㄍㄨㄛˇ", ["アーウィンマンゴー", "Irwin mango", "愛文芒果"], "specific", 0, 500, 530),
                c("盤子", "ㄆㄢˊ ㄗ˙", ["お皿", "plate", "盤子"], nil, 1, 500, 665),
                c("杯子", "ㄅㄟ ㄗ˙", ["カップ", "cup", "杯子"], nil, 2, 800, 400)]
    }
}

/// The catch scan (v10) from the shutter: the outlines come 0.25 s in, the names `namesAfter` s in (2.4 s: the pen
/// catches up; 6.0 s: the drawing ends first and the small light goes round). Replayed every `namesAfter + 5` s.
private struct ScanPreview: View {
    var namesAfter: Double
    @State private var vm = CaptureViewModel()
    @State private var round = 0

    var body: some View {
        CandidatePickerView(vm: vm, scanning: vm.step == .processing)
            .id(round)
            .task(id: round) {
                await play()
                try? await Task.sleep(for: .seconds(5))
                round += 1
            }
    }

    private func play() async {
        NativeAPI.targetLanguage = "zh-TW"
        let session = CatchScanSession()
        vm.photo = ScanFixtures.photo
        vm.objects = []
        vm.candidates = []
        vm.scan = session
        vm.step = .processing
        try? await Task.sleep(for: .milliseconds(250))
        session.setOutlines(ScanFixtures.outlines, at: Date())
        try? await Task.sleep(for: .seconds(max(0, namesAfter - 0.25)))
        let found = ScanFixtures.candidates()
        var objects = CatchObject.build(candidates: found, masks: nil, photoSize: ScanFixtures.size)
        // The instances under each thing and the tags' places inside them, as `CatchObject.build` finds them from
        // Vision's mask on a phone.
        for k in objects.indices {
            objects[k].instance = k + 1
            if let a = ScanFixtures.anchors[k + 1] { objects[k].anchor = a }
        }
        vm.objects = objects
        session.setNames(objects, at: Date())
        vm.candidates = found
        vm.step = .select
    }
}

/// A made-up photo (sky + ground + a round "mango") and its lifted subject, the same size,
/// because the Vision cut-out does not run on the simulator.
enum PreviewFixtures {
    static let size = CGSize(width: 900, height: 900)

    static let photo: UIImage = UIGraphicsImageRenderer(size: size).image { ctx in
        let c = ctx.cgContext
        let colors = [UIColor(red: 0.55, green: 0.78, blue: 0.95, alpha: 1).cgColor,
                      UIColor(red: 0.93, green: 0.88, blue: 0.78, alpha: 1).cgColor] as CFArray
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            c.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
        UIColor(red: 0.62, green: 0.48, blue: 0.36, alpha: 1).setFill()
        c.fill(CGRect(x: 0, y: size.height * 0.68, width: size.width, height: size.height * 0.32))
        drawSubject(in: c)
    }

    static let subject: UIImage = {
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in drawSubject(in: ctx.cgContext) }
    }()

    private static func drawSubject(in c: CGContext) {
        UIColor(red: 1, green: 0.72, blue: 0.16, alpha: 1).setFill()
        c.fillEllipse(in: CGRect(x: 250, y: 300, width: 400, height: 330))
        UIColor(red: 0.95, green: 0.45, blue: 0.2, alpha: 1).setFill()
        c.fillEllipse(in: CGRect(x: 470, y: 330, width: 150, height: 120))
        UIColor(red: 0.2, green: 0.55, blue: 0.25, alpha: 1).setFill()
        c.fillEllipse(in: CGRect(x: 420, y: 250, width: 110, height: 70))
    }

    /// The owner's desk (2026-10-15): a tablet in the middle with a stylus lying on it, a cup top right and a box of
    /// tissues bottom left, drawn as the AI's boxes describe them (`PickerPreview.deskRows`), portrait like a phone photo.
    static let deskSize = CGSize(width: 900, height: 1200)

    static let deskPhoto: UIImage = UIGraphicsImageRenderer(size: deskSize).image { ctx in
        let c = ctx.cgContext
        UIColor(red: 0.78, green: 0.66, blue: 0.5, alpha: 1).setFill()
        c.fill(CGRect(origin: .zero, size: deskSize))
        // The tablet: a dark slab with a lighter screen.
        UIColor(red: 0.16, green: 0.17, blue: 0.2, alpha: 1).setFill()
        c.addPath(UIBezierPath(roundedRect: CGRect(x: 150, y: 300, width: 600, height: 600), cornerRadius: 36).cgPath)
        c.fillPath()
        UIColor(red: 0.3, green: 0.36, blue: 0.46, alpha: 1).setFill()
        c.fill(CGRect(x: 185, y: 335, width: 530, height: 530))
        // The stylus lying across the screen.
        c.saveGState()
        c.translateBy(x: 450, y: 445)
        c.rotate(by: -0.12)
        UIColor(white: 0.93, alpha: 1).setFill()
        c.addPath(UIBezierPath(roundedRect: CGRect(x: -150, y: -11, width: 300, height: 22), cornerRadius: 11).cgPath)
        c.fillPath()
        c.restoreGState()
        // The cup, top right, with its handle.
        UIColor(red: 0.95, green: 0.95, blue: 0.92, alpha: 1).setFill()
        c.fillEllipse(in: CGRect(x: 700, y: 170, width: 160, height: 160))
        UIColor(red: 0.45, green: 0.3, blue: 0.2, alpha: 1).setFill()
        c.fillEllipse(in: CGRect(x: 725, y: 195, width: 110, height: 110))
        // The tissue box, bottom left.
        UIColor(red: 0.98, green: 0.98, blue: 0.97, alpha: 1).setFill()
        c.addPath(UIBezierPath(roundedRect: CGRect(x: 60, y: 950, width: 270, height: 180), cornerRadius: 14).cgPath)
        c.fillPath()
        UIColor(red: 0.85, green: 0.6, blue: 0.65, alpha: 1).setFill()
        c.fillEllipse(in: CGRect(x: 150, y: 990, width: 90, height: 40))
    }

    /// The subject cropped to its bounds, like the saved sticker.
    static let subjectCropped: UIImage = {
        // cgImage is in pixels (the renderer draws at screen scale), so scale the point rect.
        let s = subject.scale
        let rect = CGRect(x: 240 * s, y: 240 * s, width: 420 * s, height: 400 * s)
        guard let cg = subject.cgImage?.cropping(to: rect) else { return subject }
        return UIImage(cgImage: cg, scale: s, orientation: .up)
    }()
}

/// The words on the photo with made-up suggestions (two objects; the first has other names): the mango's
/// names sit on the mango, the plate's below it.
private struct PickerPreview: View {
    var learning: String = "zh-TW"
    /// Film v6 "D": the mango's three ways to say it open by themselves (`-uiPreview variants`), the mango as a cut-out.
    var autoOpen: Bool = false
    /// `-uiPreview choose`: the choose screen stays open — every name's register tag and the field to type a word.
    var holdOpen: Bool = false
    /// `-uiPreview typed`: ボクサーパンツ typed under the photo — the choose screen opens on the names found (never straight
    /// on to the catch), each with its register tag, the everyday 內褲 first.
    var typed: Bool = false
    /// `-uiPreview picker4` / `picker4-nopos`: the owner's desk with four things (2026-10-15), with the AI's boxes
    /// (`placed`: every tag on its own thing) or without any position (`unplaced`: the tags spread over the photo
    /// instead of one pile in the middle, and the developer log notes it).
    enum Desk { case placed, unplaced }
    var desk: Desk? = nil
    @State private var vm = CaptureViewModel()

    /// The desk's four things: headword, zhuyin, label in ja / en / zh-TW, `box_2d` ([ymin, xmin, ymax, xmax], 0–1000
    /// of the photo) as the AI draws them round the shapes of `PreviewFixtures.deskPhoto`.
    private var deskRows: [(String, String, [String], [Double])] {
        [("平板", "ㄆㄧㄥˊ ㄅㄢˇ", ["タブレット", "tablet", "平板"], [250, 167, 750, 833]),
         ("杯子", "ㄅㄟ ㄗ˙", ["コップ", "cup", "杯子"], [142, 778, 275, 956]),
         ("觸控筆", "ㄔㄨˋ ㄎㄨㄥˋ ㄅㄧˇ", ["スタイラス", "stylus", "觸控筆"], [350, 333, 392, 667]),
         ("衛生紙", "ㄨㄟˋ ㄕㄥ ㄓˇ", ["ティッシュ", "tissue", "衛生紙"], [792, 67, 942, 367])]
    }

    /// headword, reading, meaning in ja / en / zh-TW, distinction in ja / en / zh-TW, register, group
    private typealias Row = (String, String, [String], [String], String?, Int)

    private var rows: [Row] {
        switch learning {
        case "ja":
            return [("マンゴー", "", ["マンゴー", "mango", "芒果"], ["ふだんの言い方", "the everyday word", "日常說法"], "common", 0),
                    ("アップルマンゴー", "", ["アップルマンゴー", "apple mango", "蘋果芒果"], ["品種の名前", "a variety", "品種名稱"], "specific", 0),
                    ("皿", "さら", ["皿", "plate", "盤子"], ["", "", ""], nil, 1)]
        case "en":
            return [("mango", "", ["マンゴー", "mango", "芒果"], ["ふだんの言い方", "the everyday word", "日常說法"], "common", 0),
                    ("Irwin mango", "", ["アーウィンマンゴー", "Irwin mango", "愛文芒果"], ["品種の名前", "a variety", "品種名稱"], "specific", 0),
                    ("plate", "", ["お皿", "plate", "盤子"], ["", "", ""], nil, 1)]
        default:
            return [("芒果", "ㄇㄤˊ ㄍㄨㄛˇ", ["マンゴー", "mango", "芒果"], ["ふだんの言い方", "the everyday word", "日常說法"], "common", 0),
                    ("愛文芒果", "ㄞˋ ㄨㄣˊ ㄇㄤˊ ㄍㄨㄛˇ", ["アーウィンマンゴー", "Irwin mango", "愛文芒果"], ["品種の名前", "a variety", "品種名稱"], "specific", 0),
                    ("檨仔", "ㄙㄨㄟˋ ㄚˇ", ["マンゴー（台湾語由来）", "mango (from Taiwanese)", "芒果（台語）"], ["年配の人の言い方", "older people's word", "長輩的說法"], "casual", 0),
                    ("盤子", "ㄆㄢˊ ㄗ˙", ["お皿", "plate", "盤子"], ["", "", ""], nil, 1)]
        }
    }

    var body: some View {
        CandidatePickerView(vm: vm, scanning: false, autoOpen: autoOpen, holdOpen: holdOpen)
            .onAppear {
                NativeAPI.targetLanguage = learning
                let i = L10n.lang == "en" ? 1 : L10n.lang == "zh-TW" ? 2 : 0
                if let desk {
                    vm.photo = PreviewFixtures.deskPhoto
                    vm.candidates = deskRows.enumerated().map { n, r in
                        // As an answer without `point` / `box_2d` decodes: the middle as a stand-in, not a position.
                        let placed = desk == .placed
                        var c = Candidate(kind: "object", headword: r.0, zhuyin: r.1, pinyin: "", meaningJa: r.2[i],
                                          pos: NativeAPI.defaultPos,
                                          point: placed ? [(r.3[1] + r.3[3]) / 2, (r.3[0] + r.3[2]) / 2] : [500, 500],
                                          confidence: 0.9, alternatives: [], register: "common", group: n)
                        c.objectLabel = r.2[i]
                        c.box = placed ? r.3 : nil
                        c.positioned = placed
                        return c
                    }
                    vm.objects = CatchObject.build(candidates: vm.candidates, masks: nil, photoSize: PreviewFixtures.deskSize)
                    if let note = CatchObject.placementNote(vm.objects) { DevLog.shared.add("tags", note) }
                    // As the camera flow brings the tags up on the simulator (no Vision outlines): the catch scan
                    // reveals each one where it sits.
                    let session = CatchScanSession()
                    session.setOutlines([], at: Date())
                    session.setNames(vm.objects, at: Date())
                    vm.scan = session
                    vm.step = .select
                    return
                }
                vm.photo = PreviewFixtures.photo
                vm.candidates = rows.map { r in
                    Candidate(kind: "object", headword: r.0, zhuyin: r.1, pinyin: "", meaningJa: r.2[i], pos: NativeAPI.defaultPos,
                              point: r.5 == 0 ? [500, 500] : [500, 820], confidence: 0.9, alternatives: [],
                              distinction: r.3[i], register: r.4, group: r.5)
                }
                if autoOpen {
                    // The mango's Vision cut-out, as a phone would have it (the simulator has no Vision cut-out).
                    let box = CGRect(x: 240.0 / 900, y: 240.0 / 900, width: 420.0 / 900, height: 400.0 / 900)
                    vm.objects = CatchObject.build(candidates: vm.candidates, masks: nil, photoSize: PreviewFixtures.size).map { o in
                        guard o.id == 0 else { return o }
                        return CatchObject(id: o.id, words: o.words, point: o.point, box: box,
                                           anchor: CGPoint(x: box.midX, y: box.midY), cut: PreviewFixtures.subjectCropped)
                    }
                }
                if typed {
                    // ボクサーパンツ typed (owner 2026-10-15): 內褲 the everyday word at the top, then the narrower names.
                    let found: [(String, String, [String], String?)] = [
                        ("平口褲", "ㄆㄧㄥˊ ㄎㄡˇ ㄎㄨˋ", ["ボクサーパンツ", "boxer briefs", "平口褲"], "specific"),
                        ("內褲", "ㄋㄟˋ ㄎㄨˋ", ["下着", "underwear", "內褲"], "common"),
                        ("四角褲", "ㄙˋ ㄐㄧㄠˇ ㄎㄨˋ", ["トランクス", "boxer shorts", "四角褲"], "specific"),
                    ]
                    vm.typedCandidates = NameRegister.finalized(found.map { f in
                        Candidate(kind: "object", headword: f.0, zhuyin: f.1, pinyin: "", meaningJa: f.2[i], pos: NativeAPI.defaultPos,
                                  point: [500, 500], confidence: 0.9, alternatives: [], register: f.3)
                    })
                    vm.typedQuery = ["ボクサーパンツ", "boxer briefs", "平口褲"][i]
                }
                vm.step = .select
            }
            .task {
                guard typed else { return }
                // As a lookup does when its words come (`CaptureViewModel.search`): the choose screen opens on them.
                try? await Task.sleep(for: .milliseconds(500))
                vm.typedRound += 1
                // The card's rows have come in.
                try? await Task.sleep(for: .seconds(1.6))
                UIReady.mark("preview")
            }
    }
}

/// The celebration after a word is tapped: the cut-out sticker on the blurred photo (or, without a cut-out,
/// the photo as a white-edged card), the word and 「図鑑に追加」. Replayed every 7 seconds.
private struct CelebrationPreview: View {
    var withCutout: Bool = true
    /// Seconds between replays (the GET moment hands over at 3.0 s; here it then simply holds).
    var replay: Double = 7
    /// `-uiPreview get-again`: the mango is in the dex already (caught 12 days ago in 台北, met once since): the same
    /// moment says 「また会えた！」 with 「再会 3回目」 and when and where it was first caught.
    var again: Bool = false
    @State private var vm = CaptureViewModel()
    @State private var round = 0

    var body: some View {
        CatchCelebrationView(vm: vm, onAdd: { true })
            .id(round)
            .onAppear {
                NativeAPI.targetLanguage = "zh-TW"
                vm.photo = PreviewFixtures.photo
                vm.cutout = withCutout ? PreviewFixtures.subjectCropped : nil
                vm.picked = Candidate(kind: "object", headword: "芒果", zhuyin: "ㄇㄤˊ ㄍㄨㄛˇ", pinyin: "mángguǒ",
                                      meaningJa: L10n.lang == "en" ? "mango" : L10n.lang == "zh-TW" ? "芒果" : "マンゴー",
                                      pos: NativeAPI.defaultPos, point: [500, 500], confidence: 0.9, alternatives: [],
                                      distinction: L10n.lang == "en" ? "the everyday word" : L10n.lang == "zh-TW" ? "日常說法" : "ふだんの言い方")
                if again {
                    vm.owned = OwnedWord(stickerId: "again", wordId: "w-again", headword: "芒果",
                                         meaningJa: L10n.lang == "en" ? "mango" : L10n.lang == "zh-TW" ? "芒果" : "マンゴー",
                                         readingZhuyin: "ㄇㄤˊ ㄍㄨㄛˇ", pinyin: "mángguǒ", cutoutUrl: nil, encounterCount: 2,
                                         takenAt: SupabaseDate.string(Date().addingTimeInterval(-12 * 86_400)),
                                         locationName: L10n.lang == "en" ? "Taipei" : "台北")  // l10n-ignore (place name)
                }
                vm.step = .celebrate
            }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(replay))
                    round += 1
                }
            }
    }
}

/// Film v6's finale in the 図鑑 (`-uiPreview landing`): three drinks caught, 果汁 (No.004) lands — the page rises, the
/// sticker flies into its square, NEW, the counters roll, the next shadow's ring and the goal toast (あと1語).
/// `-uiPreview landing-again`: 咖啡, caught before, is met again — the same flight and impact into its own square,
/// without NEW, counters or toast. Replayed every 6.5 s.
private struct LandingPreview: View {
    var again: Bool = false
    @Environment(DexStore.self) private var dex
    @Environment(AppRouter.self) private var router
    @State private var round = 0

    private static func cutout(_ body: UIColor, _ top: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: 300, height: 420), format: format).image { ctx in
            let c = ctx.cgContext
            body.setFill()
            c.addPath(UIBezierPath(roundedRect: CGRect(x: 50, y: 90, width: 200, height: 320), cornerRadius: 34).cgPath)
            c.fillPath()
            top.setFill()
            c.addPath(UIBezierPath(roundedRect: CGRect(x: 36, y: 60, width: 228, height: 52), cornerRadius: 18).cgPath)
            c.fillPath()
            UIColor(white: 1, alpha: 0.35).setFill()
            c.fill(CGRect(x: 78, y: 130, width: 22, height: 240))
        }
    }

    private static func sticker(_ id: String, _ head: String, _ zy: String, _ meaning: String, image: UIImage, ago: Double) -> Sticker? {
        let path = "preview/landing-\(id).png"
        ImageCache.shared.set(image, for: path)
        let json = #"{"id":"w\#(id)","headword":"\#(head)","reading_zhuyin":"\#(zy)","meaning_ja":"\#(meaning)"}"#
        guard let word = try? JSONDecoder().decode(Word.self, from: Data(json.utf8)) else { return nil }
        return Sticker(id: id, wordId: "w\(id)", objectImageUrl: path, cutoutImageUrl: path, selfieImageUrl: nil,
                       caption: nil, locationName: nil, takenAt: Date().addingTimeInterval(-ago), captureType: "photo", word: word)
    }

    private static let juice = cutout(UIColor(red: 1, green: 0.62, blue: 0.12, alpha: 1), UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1))

    private static let coffee = cutout(UIColor(red: 0.35, green: 0.22, blue: 0.15, alpha: 1), .white)

    private static let caught: [Sticker] = [
        sticker("l-tea", "茶", "ㄔㄚˊ", "tea", image: cutout(UIColor(red: 0.78, green: 0.45, blue: 0.2, alpha: 1), .white), ago: 3000),
        sticker("l-coffee", "咖啡", "ㄎㄚ ㄈㄟ", "coffee", image: coffee, ago: 2000),
        sticker("l-bubble", "珍珠奶茶", "ㄓㄣ ㄓㄨ ㄋㄞˇ ㄔㄚˊ", "bubble tea",
                image: cutout(UIColor(red: 0.84, green: 0.66, blue: 0.48, alpha: 1), UIColor(red: 0.3, green: 0.2, blue: 0.15, alpha: 1)), ago: 1000),
    ].compactMap { $0 }

    var body: some View {
        ZStack {
            DexView().id(round)
            if let l = router.landing { CatchLandingOverlay(controller: l) }
        }
        .task(id: round) {
            await play()
            try? await Task.sleep(for: .seconds(6.5))
            round += 1
        }
    }

    private func play() async {
        NativeAPI.targetLanguage = "zh-TW"
        if again {
            await playAgain()
            return
        }
        guard let new = Self.sticker("local-preview-\(round)", "果汁", "ㄍㄨㄛˇ ㄓ", "juice", image: Self.juice, ago: 0) else { return }
        dex.stickers = [new] + Self.caught
        dex.hasLoaded = true
        try? await Task.sleep(for: .milliseconds(200))
        let screen = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds.size ?? CGSize(width: 393, height: 852)
        let box = Film6.stickerSize(aspect: Self.juice.size.width / Self.juice.size.height, screen: screen, get: true)
        router.catchStar = CatchStar(center: CGPoint(x: screen.width / 2, y: Film6.y(Film6.getPosY, screen.height)),
                                     size: box.width, k: 1, image: Self.juice, box: box)
        CatchLanding.land(stickerId: new.id, router: router, calm: false,
                          goal: CatchGoal.make(headword: "果汁", stickers: dex.stickers, lang: "zh-TW"))
        UIReady.mark("preview")
    }

    /// A re-encounter of 咖啡: the dex as it was (no new entry), the sticker flies from the GET stage into 咖啡's square.
    private func playAgain() async {
        dex.stickers = Self.caught
        dex.hasLoaded = true
        try? await Task.sleep(for: .milliseconds(200))
        let screen = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds.size ?? CGSize(width: 393, height: 852)
        let box = Film6.stickerSize(aspect: Self.coffee.size.width / Self.coffee.size.height, screen: screen, get: true)
        router.catchStar = CatchStar(center: CGPoint(x: screen.width / 2, y: Film6.y(Film6.getPosY, screen.height)),
                                     size: box.width, k: 1, image: Self.coffee, box: box)
        CatchLanding.land(stickerId: "l-coffee", router: router, calm: false, alreadyCaught: true)
        UIReady.mark("preview")
    }
}

/// The tab bar over the home album's paper, over a map-like ground and over the camera's dark machine: as shipped
/// (`-uiPreview tabbar`, the original look — owner 2026-10-16), or with the raised camera disc kept for later
/// (`-uiPreview tabbar-b`, `DevChoices.tabBar`).
private struct TabBarPreview: View {
    @State private var home: AppTab = .home
    @State private var dex: AppTab = .dex
    @State private var camera: AppTab = .camera

    init(variant: String = DevChoices.tabBarDefault) {
        UserDefaults.standard.set(variant, forKey: DevChoices.tabBarKey)
        DevChoices.previewing = true
    }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                HomeBackground().frame(height: 150)
                CapsuleTabBar(selection: $home, onCamera: false).padding(.bottom, 8)
            }
            ZStack {
                LinearGradient(colors: [Color(hex: 0xE9F1DE), Color(hex: 0xD5E6EE)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .frame(height: 150)
                CapsuleTabBar(selection: $dex, onCamera: false).padding(.bottom, 8)
            }
            ZStack {
                Theme.navyDeep.frame(height: 150)
                CapsuleTabBar(selection: $camera, onCamera: true).padding(.bottom, 8)
            }
            Spacer()
        }
        .background(AppBackground())
    }
}
/// 「表示する写真」: the sheet's grid with original, cut-out and selfie, the cut-out chosen.
private struct HeroPickerPreview: View {
    private static let sticker: Sticker = {
        ImageCache.shared.set(PreviewFixtures.photo, for: "preview/hero-object.jpg")
        ImageCache.shared.set(PreviewFixtures.subject, for: "preview/hero-cutout.png")
        let selfie = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 600)).image { ctx in
            UIColor(red: 0.98, green: 0.86, blue: 0.78, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 600, height: 600))
            UIColor(red: 0.45, green: 0.32, blue: 0.25, alpha: 1).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 190, y: 120, width: 220, height: 260))
        }
        ImageCache.shared.set(selfie, for: "preview/hero-selfie.jpg")
        var s = Sticker(id: "hero", wordId: "w", objectImageUrl: "preview/hero-object.jpg",
                        cutoutImageUrl: "preview/hero-cutout.png", selfieImageUrl: "preview/hero-selfie.jpg",
                        caption: nil, locationName: nil, takenAt: Date(), captureType: "photo", word: nil)
        s.heroRole = "cutout"
        return s
    }()

    var body: some View {
        HeroPhotoPickerSheet(sticker: Self.sticker) { _ in }
            .padding(.top, 60)
    }
}
/// The milestone celebration (day count, confetti, photos fanning out).
private struct MemorialPreview: View {
    private static let photos: [String] = (0..<7).map { i in
        let path = "preview/memorial-\(i).jpg"
        let img = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 380)).image { ctx in
            let h = CGFloat(i) / 7
            UIColor(hue: h, saturation: 0.35, brightness: 0.95, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 380))
            UIColor(hue: h, saturation: 0.7, brightness: 0.75, alpha: 1).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 70, y: 90, width: 160, height: 150))
        }
        ImageCache.shared.set(img, for: path)
        return path
    }

    var body: some View {
        MemorialReveal(n: 30, words: 48, photos: Self.photos) {}
    }
}
/// The dex slide view (white cards on a ring in the pale blue room), opened on the second card.
private struct CarouselPreview: View {
    private static let stickers: [Sticker] = {
        let words = [("芒果", "マンゴー"), ("咖啡", "コーヒー"), ("雨傘", "傘"), ("盤子", "お皿"), ("花", "花"), ("麵包", "パン")]
        return words.enumerated().compactMap { i, w -> Sticker? in
            let json = #"{"id":"cw\#(i)","headword":"\#(w.0)","meaning_ja":"\#(w.1)"}"#
            guard let word = try? JSONDecoder().decode(Word.self, from: Data(json.utf8)) else { return nil }
            let path = "preview/carousel-\(i).jpg"
            let img = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 600)).image { ctx in
                let hue = CGFloat(i) / 6
                UIColor(hue: hue, saturation: 0.4, brightness: 0.93, alpha: 1).setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 600, height: 600))
                UIColor(hue: hue, saturation: 0.7, brightness: 0.72, alpha: 1).setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: 150, y: 150, width: 300, height: 300))
            }
            ImageCache.shared.set(img, for: path)
            return Sticker(id: "c\(i)", wordId: "w", objectImageUrl: path, cutoutImageUrl: nil, selfieImageUrl: nil,
                           caption: nil, locationName: i == 1 ? "台北" : nil,
                           takenAt: Date().addingTimeInterval(Double(-i) * 86400), captureType: "photo", word: word)
        }
    }()

    var body: some View {
        ZStack(alignment: .top) {
            DexGalleryBackdrop()
            DexCoverFlow(stickers: Self.stickers, onOpen: { _ in }, initialIndex: 1)
                .padding(.top, 118)
        }
    }
}

/// The word page's chunk / measure-word / related-word cards (web WordCard look), scrolled to the chunks.
private struct DetailPreview: View {
    /// The same word as each display language's reader would get it (notes written in their language).
    private static var notes: (meaning: String, translation: String, chunks: [String], measure: String, related: [String]) {
        switch L10n.lang {
        case "en":
            return ("teppan noodles", "I want teppan noodles for breakfast.",
                    ["teppan noodles with mushroom sauce", "teppan noodles with black pepper sauce", "order teppan noodles"],
                    "one serving (the most common measure word for dishes)",
                    ["Ordinary stir-fried noodles. 鐵板麵 is served sizzling on an iron plate with sauce poured over.",
                     "Pasta. 鐵板麵 is cheaper — a light meal sold at breakfast shops."])
        case "zh-TW":
            return ("鐵板上淋醬的麵", "",
                    ["蘑菇醬的鐵板麵", "黑胡椒醬的鐵板麵", "點一份鐵板麵"],
                    "一盤的量（數餐點最常用的量詞）",
                    ["一般的炒麵。鐵板麵是放在熱鐵板上再淋醬。", "比義大利麵便宜，是早餐店的輕食。"])
        default:
            return ("鉄板焼きそば", "朝ごはんに鉄板焼きそばが食べたい。",
                    ["マッシュルームソースの鉄板焼きそば", "黒胡椒ソースの鉄板焼きそば", "鉄板焼きそばを注文する"],
                    "一皿分（料理を数える際の最も一般的な量詞）",
                    ["一般的な炒め麺。鐵板麵は鉄板の上でソースをかけて調理する点が異なる。",
                     "パスタ。鐵板麵はパスタより安価で、朝食店で提供される軽食という位置づけ。"])
        }
    }

    /// The prose sections (台湾メモ and the synonyms' difference; 発音のコツ・語源・覚え方 as older cards still carry them, never
    /// shown), several sentences each — the first is the owner's sentence that broke early on an iPad (2026-10-15).
    private static var prose: [String: String] {
        switch L10n.lang {
        case "en":
            return ["pronunciation_tips": "Say 鐵 in the third tone, low and dipping. However, in Taiwan, take care to keep each tone clear. The last syllable 麵 falls sharply!",
                    "etymology": "鐵 means iron (e.g. an iron plate). 板 is a board, and 麵 is noodles.",
                    "mnemonic": "Think of noodles sizzling on an iron board. The sound \"tiě\" is like a hot pan's hiss.",
                    "taiwan_note": "A breakfast-shop classic in Taiwan. Ask for black-pepper or mushroom sauce, and an egg on top. It comes sizzling, so wait a moment before you eat!",
                    "synonym_diff": "炒麵 is fried in a wok. 鐵板麵 comes on a hot iron plate with sauce poured over."]
        case "zh-TW":
            return ["pronunciation_tips": "「鐵」是三聲，先降再升。不過，在台灣要特別注意把每個聲調唸清楚。最後的「麵」是四聲，要往下降！",
                    "etymology": "「鐵」是金屬（例如：鐵板）。「板」是平板，「麵」是麵條。",
                    "mnemonic": "想像麵在熱鐵板上滋滋作響。「鐵」的聲音像熱鍋的聲音。",
                    "taiwan_note": "台灣早餐店的經典。可以選黑胡椒醬或蘑菇醬，再加一顆蛋。端上來時還在滋滋作響，小心燙！",
                    "synonym_diff": "炒麵是在鍋裡炒的。鐵板麵是放在熱鐵板上，再淋上醬汁。"]
        default:
            return ["pronunciation_tips": "「鐵」は3声で、低く下げてから上げます。ただし、台湾では声調をしっかりと意識しましょう。最後の「麵」は4声で、すとんと下げます！",
                    "etymology": "「鐵」は鉄（例：鉄板）のことです。「板」は板、「麵」は麺を表します。",
                    "mnemonic": "熱い鉄板の上で麺がジュウジュウ鳴る様子を思い浮かべましょう。「tiě」の音は鉄板の音に似ています。",
                    "taiwan_note": "台湾の朝食店の定番です。黒胡椒ソースかマッシュルームソースを選び、目玉焼きをのせることもできます。ジュウジュウと音を立てて出てくるので、やけどに気をつけましょう。朝の7時から行列ができる店もあります。",
                    "synonym_diff": "炒麵は中華鍋で炒めた麺です。鐵板麵は熱い鉄板にのせて、上からソースをかけます。"]
        }
    }

    /// The other usage patterns' examples, each with its label and the sentence it was written for (the third one's
    /// label was written for another sentence).
    private static var examples: (scene: String, extra: [[String: String]]) {
        switch L10n.lang {
        case "en":
            return ("Ordering at a breakfast shop", [
                ["zh": "這家的鐵板麵很好吃。", "ja": "The teppan noodles here are really good.", "scene": "Recommending a shop to a friend", "scene_for": "這家的鐵板麵很好吃！"],
                ["zh": "鐵板麵要加蛋嗎？", "ja": "Would you like an egg on your teppan noodles?", "scene": "When the clerk asks", "scene_for": "鐵板麵要加蛋嗎？"],
                ["zh": "我不要鐵板麵了。", "ja": "I don't want the teppan noodles anymore.", "scene": "Recommending a shop to a friend", "scene_for": "這家的鐵板麵很好吃。"],
            ])
        case "zh-TW":
            return ("在早餐店點餐時", [
                ["zh": "這家的鐵板麵很好吃。", "ja": "", "scene": "跟朋友推薦店家時", "scene_for": "這家的鐵板麵很好吃！"],
                ["zh": "鐵板麵要加蛋嗎？", "ja": "", "scene": "店員問你的時候", "scene_for": "鐵板麵要加蛋嗎？"],
                ["zh": "我不要鐵板麵了。", "ja": "", "scene": "跟朋友推薦店家時", "scene_for": "這家的鐵板麵很好吃。"],
            ])
        default:
            return ("朝ごはんの店で注文するとき", [
                ["zh": "這家的鐵板麵很好吃。", "ja": "この店の鉄板焼きそばはおいしい。", "scene": "友達に店をすすめるとき", "scene_for": "這家的鐵板麵很好吃！"],
                ["zh": "鐵板麵要加蛋嗎？", "ja": "鉄板焼きそばに卵をのせますか？", "scene": "店員に聞かれたとき", "scene_for": "鐵板麵要加蛋嗎？"],
                ["zh": "我不要鐵板麵了。", "ja": "もう鉄板焼きそばはいらない。", "scene": "友達に店をすすめるとき", "scene_for": "這家的鐵板麵很好吃。"],
            ])
        }
    }

    private static func sticker(withProse: Bool, withExamples: Bool = false) -> Sticker {
        let n = notes
        var extras: [String: Any] = [
                "explain_lang": L10n.lang,
                "usage_chunks": [
                    ["parts": [["text": "蘑菇", "pos": "N"], ["text": "鐵板麵", "pos": "N"]], "ja": n.chunks[0]],
                    ["parts": [["text": "黑胡椒", "pos": "N"], ["text": "鐵板麵", "pos": "N"]], "ja": n.chunks[1]],
                    ["parts": [["text": "點", "pos": "V"], ["text": "鐵板麵", "pos": "N"]], "ja": n.chunks[2]],
                    // Every kind of block, so the legend under the chunks shows all five (owner 2026-10-15: the English
                    // legend wrapped inside its labels).
                    ["parts": [["text": "在", "pos": "P"], ["text": "早餐店", "pos": "N"], ["text": "點", "pos": "V"], ["text": "鐵板麵", "pos": "N"]],
                     "ja": L10n.lang == "en" ? "order teppan noodles at a breakfast shop" : L10n.lang == "zh-TW" ? "在早餐店點鐵板麵" : "朝ごはんの店で鉄板焼きそばを注文する"],
                    ["parts": [["text": "鐵板麵", "pos": "N"], ["text": "很", "pos": "Adv"], ["text": "香", "pos": "Vs"]],
                     "ja": L10n.lang == "en" ? "teppan noodles smell great" : L10n.lang == "zh-TW" ? "鐵板麵很香" : "鉄板焼きそばはいい香り"],
                ],
                "measure_words": [["word": "份", "zhuyin": "ㄈㄣˋ", "note": n.measure]],
                "related_words": [
                    ["word": "炒麵", "kind": "syn", "reading": "ㄔㄠˇ ㄇㄧㄢˋ", "note": n.related[0]],
                    ["word": "義大利麵", "kind": "rel", "reading": "ㄧˋ ㄉㄚˋ ㄌㄧˋ ㄇㄧㄢˋ", "note": n.related[1]],
                ],
        ]
        if withProse { for (k, v) in prose { extras[k] = v } }
        if withExamples {
            let ex = examples
            extras["example_scene"] = ex.scene
            extras["example_scene_for"] = "早餐我想吃鐵板麵。"
            extras["example_pattern_count"] = 4
            extras["examples_extra"] = ex.extra
        }
        let obj: [String: Any] = [
            "id": "w-teppan", "headword": "鐵板麵", "language": "zh-TW", "reading_zhuyin": "ㄊㄧㄝˇ ㄅㄢˇ ㄇㄧㄢˋ", "meaning_ja": n.meaning,
            "part_of_speech": "名詞", "example_sentence": "早餐我想吃鐵板麵。", "example_translation": n.translation,
            "extras": extras,
        ]
        let data = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
        // Through the same reader-language filter as real cards.
        let word = (try? JSONDecoder().decode(Word.self, from: data))
            .map { ReaderLanguage.resolve($0, explanation: nil, readerMeaning: nil, reader: L10n.lang) }
        return Sticker(id: "detail", wordId: "w-teppan", objectImageUrl: nil, cutoutImageUrl: nil, selfieImageUrl: nil,
                       caption: nil, locationName: nil, takenAt: Date(), captureType: "photo", word: word)
    }

    var focus: CardSection = .usageChunks
    var withProse: Bool = false
    var withExamples: Bool = false

    var body: some View {
        WordDetailView(sticker: Self.sticker(withProse: withProse, withExamples: withExamples), previewFocus: focus)
    }

    static var previewSticker: Sticker { sticker(withProse: false) }
}

/// The word page's prose sections (`-uiPreview tips`), scrolled to 台湾メモ: one sentence per row with the same spacing,
/// and no line under its sentences (owner 2026-10-15); 類義語 keeps its look. The card's old 語源 text is in its payload
/// and never shown (the section is gone). 台湾メモ is switched on first (shown on a new card since 1.0.1; a saved choice may hide it).
private struct TipsPreview: View {
    init() {
        CardPrefsStore.shared.use("zh-TW")
        CardPrefsStore.shared.setVisible(.taiwanNote, true)
    }

    var body: some View {
        DetailPreview(focus: .taiwanNote, withProse: true)
    }
}

/// 「例文」 with every usage pattern's example, each with its situation label (`-uiPreview examples`); the third
/// pattern's label was written for another sentence and is not shown.
private struct ExamplesPreview: View {
    var body: some View {
        DetailPreview(focus: .example, withExamples: true)
    }
}

/// 「例文」 of a card as the server writes it now (`-uiPreview sunscreen`, production shape of 2026-10-15: `example_v` 3,
/// `example_scene` / `example_scene_for` on the main example, `examples_extra` items `{zh, ja, scene, scene_for, chunks}`):
/// 防曬乳 with its main example and one more, each with its short scene label right above it.
private struct SunscreenExamplesPreview: View {
    private func pick(_ ja: String, _ en: String, _ zh: String) -> String {
        L10n.lang == "en" ? en : L10n.lang == "zh-TW" ? zh : ja
    }

    private var sticker: Sticker {
        let main = "出門前記得擦防曬乳。"
        let extra = "這瓶防曬乳擦起來很清爽。"
        let obj: [String: Any] = [
            "id": "w-sunscreen", "headword": "防曬乳", "language": "zh-TW", "reading_zhuyin": "ㄈㄤˊ ㄕㄞˋ ㄖㄨˇ",
            "pinyin": "fángshàirǔ", "meaning_ja": pick("日焼け止め", "sunscreen", "防曬乳"), "part_of_speech": "N",
            "category_key": "body_care", "level": "TOCFL-3",
            "example_sentence": main,
            "example_translation": pick("出かける前に日焼け止めを塗るのを忘れないでね。", "Remember to put on sunscreen before you go out.", ""),
            "extras": [
                "explain_lang": L10n.lang,
                "example_v": 3,
                "example_pattern_count": 2,
                "example_scene": pick("出かける家族に声をかけるとき", "Reminding family as they head out", "提醒家人出門時"),
                "example_scene_for": main,
                "example_chunks": [["parts": [["text": "擦", "pos": "V"], ["text": "防曬乳", "pos": "N"]],
                                    "ja": pick("日焼け止めを塗る", "put on sunscreen", "擦防曬乳")]],
                "examples_extra": [[
                    "zh": extra,
                    "ja": pick("この日焼け止めは塗り心地がさっぱりしている。", "This sunscreen feels light on the skin.", ""),
                    "scene": pick("ドラッグストアで使い心地を話すとき", "Talking about how it feels at a drugstore", "在藥妝店聊使用感時"),
                    "scene_for": extra,
                    "chunks": [["parts": [["text": "擦起來", "pos": "V"], ["text": "很清爽", "pos": "Vs"]],
                                "ja": pick("塗るとさっぱりする", "feels light when applied", "擦起來很清爽")]],
                ] as [String: Any]],
            ] as [String: Any],
        ]
        let data = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
        // Through the same reader-language filter as real cards.
        let word = (try? JSONDecoder().decode(Word.self, from: data))
            .map { ReaderLanguage.resolve($0, explanation: nil, readerMeaning: nil, reader: L10n.lang) }
        return Sticker(id: "sunscreen", wordId: "w-sunscreen", objectImageUrl: nil, cutoutImageUrl: nil, selfieImageUrl: nil,
                       caption: nil, locationName: nil, takenAt: Date(), captureType: "photo", word: word)
    }

    var body: some View {
        WordDetailView(sticker: sticker, previewFocus: .example)
    }
}

/// The App Store preview's word page (`-uiPreview milktea`, owner 2026-10-23: 「単語の詳細…実際のアプリに準拠して」):
/// 珍珠奶茶 as the catch films show it — the same photo and cut-out (copied by `ios-store-preview.yml` into
/// Caches/preview-assets; a plain cup is drawn without them), the example sentences with the readings the server's
/// dictionary gives them.
private struct MilkTeaDetailPreview: View {
    private static func pick(_ ja: String, _ en: String) -> String { L10n.lang == "en" ? en : ja }

    private static func image(_ name: String) -> UIImage? {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("preview-assets")
        return UIImage(contentsOfFile: dir.appendingPathComponent(name).path)
    }

    private static let main = "我要一杯珍珠奶茶，半糖少冰。"
    private static let extra = "這家的珍珠奶茶很好喝。"

    /// The dictionary's readings, one per character (punctuation none).
    private static func units(_ s: String, _ readings: [(String, String)?]) -> [SentenceUnit] {
        zip(s.map(String.init), readings).map { ch, r in SentenceUnit(char: ch, pinyin: r?.0, zhuyin: r?.1) }
    }

    private static func seedReadings() {
        let tea: [(String, String)?] = [("zhēn", "ㄓㄣ"), ("zhū", "ㄓㄨ"), ("nǎi", "ㄋㄞˇ"), ("chá", "ㄔㄚˊ")]
        SentenceReadings.shared.seedForPreview(main, units(main, [("wǒ", "ㄨㄛˇ"), ("yào", "ㄧㄠˋ"), ("yī", "ㄧ"), ("bēi", "ㄅㄟ")]
            + tea + [nil, ("bàn", "ㄅㄢˋ"), ("táng", "ㄊㄤˊ"), ("shǎo", "ㄕㄠˇ"), ("bīng", "ㄅㄧㄥ"), nil]))
        SentenceReadings.shared.seedForPreview(extra, units(extra, [("zhè", "ㄓㄜˋ"), ("jiā", "ㄐㄧㄚ"), ("de", "˙ㄉㄜ")]
            + tea + [("hěn", "ㄏㄣˇ"), ("hǎo", "ㄏㄠˇ"), ("hē", "ㄏㄜ"), nil]))
    }

    private static var sticker: Sticker {
        seedReadings()   // before the page asks for them
        let obj: [String: Any] = [
            "id": "w-milktea", "headword": "珍珠奶茶", "language": "zh-TW", "reading_zhuyin": "ㄓㄣ ㄓㄨ ㄋㄞˇ ㄔㄚˊ",
            "pinyin": "zhēnzhū nǎichá", "meaning_ja": pick("タピオカミルクティー", "bubble tea"), "part_of_speech": "N",
            "category_key": "drink",
            "example_sentence": main,
            "example_translation": pick("珍珠奶茶を1杯、甘さ半分・氷少なめで。", "One bubble tea, half sugar, less ice, please."),
            "extras": [
                "explain_lang": L10n.lang,
                "example_v": 3,
                "example_pattern_count": 2,
                "example_scene": pick("ドリンクスタンドで注文するとき", "Ordering at a drink stand"),
                "example_scene_for": main,
                "examples_extra": [[
                    "zh": extra, "ja": pick("この店の珍珠奶茶はおいしい。", "This shop's bubble tea is really good."),
                    "scene": pick("友達に店をすすめるとき", "Recommending a shop to a friend"), "scene_for": extra,
                ] as [String: Any]],
                "usage_chunks": [
                    ["parts": [["text": "點", "pos": "V"], ["text": "珍珠奶茶", "pos": "N"]], "ja": pick("珍珠奶茶を注文する", "order bubble tea")],
                    ["parts": [["text": "喝", "pos": "V"], ["text": "珍珠奶茶", "pos": "N"]], "ja": pick("珍珠奶茶を飲む", "drink bubble tea")],
                    ["parts": [["text": "珍珠奶茶", "pos": "N"], ["text": "很", "pos": "Adv"], ["text": "好喝", "pos": "Vs"]],
                     "ja": pick("珍珠奶茶がおいしい", "bubble tea tastes great")],
                ],
                "measure_words": [["word": "杯", "zhuyin": "ㄅㄟ", "note": pick("一杯（カップの飲み物を数える量詞）", "a cup (the measure word for drinks in cups)")]],
                "related_words": [
                    ["word": "珍奶", "kind": "syn", "reading": "ㄓㄣ ㄋㄞˇ", "note": pick("珍珠奶茶の略。会話や注文でよく使う", "Short for 珍珠奶茶. Used when chatting and ordering")],
                    ["word": "波霸奶茶", "kind": "rel", "reading": "ㄅㄛ ㄅㄚˋ ㄋㄞˇ ㄔㄚˊ", "note": pick("大粒のタピオカのもの", "With large pearls")],
                ],
            ] as [String: Any],
        ]
        let data = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
        let word = (try? JSONDecoder().decode(Word.self, from: data))
            .map { ReaderLanguage.resolve($0, explanation: nil, readerMeaning: nil, reader: L10n.lang) }
        if let photo = image("milktea-photo.jpg") { ImageCache.shared.set(photo, for: "preview/milktea-photo.jpg") }
        else { ImageCache.shared.set(PreviewFixtures.photo, for: "preview/milktea-photo.jpg") }
        if let cut = image("milktea-cutout.png") { ImageCache.shared.set(cut, for: "preview/milktea-cutout.png") }
        else { ImageCache.shared.set(PreviewFixtures.subject, for: "preview/milktea-cutout.png") }
        return Sticker(id: "milktea", wordId: "w-milktea", objectImageUrl: "preview/milktea-photo.jpg",
                       cutoutImageUrl: "preview/milktea-cutout.png", selfieImageUrl: nil, caption: nil, locationName: "台北",  // l10n-ignore (place name)
                       takenAt: Date(), captureType: "photo", word: word)
    }

    var body: some View {
        WordDetailView(sticker: Self.sticker)
            .uiReady("preview")
    }
}

/// A catch whose save failed (`-uiPreview unsaved`): its word page says why (a connection that dropped, not 「offline」),
/// that the word stays in the dex as 「保存待ち」, and offers 「もう一度保存」 (nothing is sent in the preview).
private struct UnsavedWordPreview: View {
    @Environment(DexStore.self) private var dex

    private var sticker: Sticker {
        let obj: [String: Any] = [
            "id": "", "headword": "花束", "language": "zh-TW", "reading_zhuyin": "ㄏㄨㄚ ㄕㄨˋ", "pinyin": "huāshù",
            "meaning_ja": L10n.lang == "en" ? "bouquet" : L10n.lang == "zh-TW" ? "花束" : "花束", "part_of_speech": "N",
            "category_key": "plant",
        ]
        let data = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
        let word = try? JSONDecoder().decode(Word.self, from: data)
        ImageCache.shared.set(PreviewFixtures.photo, for: "preview/unsaved.jpg")
        return Sticker(id: DexStore.provisionalPrefix + "preview-unsaved", wordId: "", objectImageUrl: "preview/unsaved.jpg",
                       cutoutImageUrl: nil, selfieImageUrl: nil, caption: nil, locationName: nil, takenAt: Date(),
                       captureType: "photo", word: word)
    }

    var body: some View {
        let s = sticker
        WordDetailView(sticker: s)
            .onAppear {
                dex.stickers = [s]
                dex.hasLoaded = true
                let reason = SaveFailure.message(for: CatchSaveError(stage: .save, underlying: APIError.connectionLost(-1005), uploads: nil))
                if let item = PendingQueue.shared.add(image: PreviewFixtures.photo, reason: reason, lat: nil, lng: nil) {
                    dex.previewUnsaved(s.id, pendingId: item.id)
                }
            }
    }
}

/// 設定 › 開発者 › アプリの情報 with the developer log (`-uiPreview devlog`): a dropped save, a decode failure and an example
/// shown without its label, as a failed catch writes them.
private struct DevLogPreview: View {
    init() {
        DevLog.shared.clear()
        DevLog.shared.add("example", "草莓蛋糕 「我買了一個草莓蛋糕。」: scene label without scene_for (example_v 2)")
        DevLog.shared.add("decode", "suggestWordCandidates: DecodingError keyNotFound candidates")
        DevLog.shared.add("save", SaveFailure.log(CatchSaveError(stage: .save, underlying: APIError.connectionLost(-1005),
                                                                 uploads: CatchUploads(object: "uid/1760500000000-object.jpg",
                                                                                       cutout: "uid/1760500000000-cutout.png", selfie: nil)),
                                                  headword: "花束"))
    }

    var body: some View {
        NavigationStack { AppInfoView() }
    }
}

/// A Japanese word (傘) and an English word (umbrella) as an English / Chinese / Japanese reader sees them —
/// to check each language's own sections and that every note is in the reader's language.
private struct LanguageCardPreview: View {
    enum Kind { case ja, en }
    let kind: Kind

    private var sticker: Sticker {
        let zh = L10n.lang == "zh-TW"
        let obj: [String: Any]
        switch kind {
        case .ja:
            obj = [
                "id": "w-kasa", "headword": "傘", "reading_zhuyin": "かさ", "pinyin": "kasa", "language": "ja",
                "meaning_ja": zh ? "雨傘" : "umbrella", "part_of_speech": "名詞",
                "example_sentence": "雨が降ってきたので、傘をさしました。",
                "example_translation": zh ? "因為開始下雨了，所以撐了傘。" : "It started to rain, so I put up my umbrella.",
                "extras": [
                    "explain_lang": L10n.lang,
                    "usage_chunks": [
                        ["parts": [["text": "傘", "pos": "N"], ["text": "を", "pos": "P"], ["text": "さす", "pos": "V"]], "ja": zh ? "撐傘" : "put up an umbrella"],
                        ["parts": [["text": "傘", "pos": "N"], ["text": "を", "pos": "P"], ["text": "たたむ", "pos": "V"]], "ja": zh ? "把傘收起來" : "fold an umbrella"],
                    ],
                    "kanji_breakdown": [["kanji": "傘", "meaning": zh ? "傘" : "umbrella", "on": "サン", "kun": "かさ"]],
                    "counters": [["word": "一本", "reading": "いっぽん",
                                  "note": zh ? "細長的東西用「本」來數，傘也是。" : "Long, thin things — umbrellas too — are counted with 本."]],
                    "related_words": [["word": "日傘", "kind": "rel", "reading": "ひがさ", "note": zh ? "遮陽用的傘" : "a parasol for the sun"]],
                ] as [String: Any],
            ]
        case .en:
            obj = [
                "id": "w-umbrella", "headword": "umbrella", "language": "en",
                "meaning_ja": zh ? "雨傘" : "傘", "part_of_speech": "noun",
                "example_sentence": "Don't forget your umbrella — it's going to rain.",
                "example_translation": zh ? "別忘了帶傘，快要下雨了。" : "傘を忘れないで。雨が降りそうだよ。",
                "extras": [
                    "explain_lang": L10n.lang,
                    "usage_chunks": [
                        ["parts": [["text": "open", "pos": "V"], ["text": "an umbrella", "pos": "N"]], "ja": zh ? "打開傘" : "傘を開く"],
                        ["parts": [["text": "share", "pos": "V"], ["text": "an umbrella", "pos": "N"]], "ja": zh ? "一起撐一把傘" : "相合い傘をする"],
                    ],
                    "forms": ["plural": "umbrellas"],
                    "countability": ["kind": "countable", "article": "an",
                                     "note": zh ? "可數名詞，前面用 an（母音開頭）。" : "数えられる名詞。母音で始まるので an を付ける。"],
                    "stress": ["syllables": ["um", "brel", "la"], "primary": 1],
                ] as [String: Any],
            ]
        }
        let data = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
        let word = (try? JSONDecoder().decode(Word.self, from: data))
            .map { ReaderLanguage.resolve($0, explanation: nil, readerMeaning: nil, reader: L10n.lang) }
        return Sticker(id: "lang-\(kind)", wordId: kind == .ja ? "w-kasa" : "w-umbrella", objectImageUrl: nil, cutoutImageUrl: nil,
                       selfieImageUrl: nil, caption: nil, locationName: nil, takenAt: Date(), captureType: "photo", word: word)
    }

    var body: some View {
        WordDetailView(sticker: sticker, previewFocus: .usageChunks)
    }
}
/// The review 4-choice card and its answer panel, for a Mandarin, Japanese or English word — to check
/// the quiz prompt, the choices (learning language only) and the notes (display language only).
private struct ReviewPreview: View {
    let learning: String
    let answered: Bool

    private var card: ReviewCard {
        ImageCache.shared.set(PreviewFixtures.photo, for: "preview/review.jpg")
        let zh = L10n.lang == "zh-TW", en = L10n.lang == "en"
        let w: [String: Any]
        switch learning {
        case "ja":
            w = ["id": "rq", "headword": "傘", "reading_zhuyin": "かさ", "language": "ja",
                 "meaning_ja": zh ? "雨傘" : "umbrella", "example_sentence": "傘をさしました。",
                 "example_translation": zh ? "撐了傘。" : "I put up my umbrella."]
        case "en":
            w = ["id": "rq", "headword": "mango", "language": "en", "meaning_ja": zh ? "芒果" : "マンゴー",
                 "example_sentence": "This mango is really sweet.", "example_translation": zh ? "這顆芒果很甜。" : "このマンゴーはとても甘い。",
                 "extras": ["explain_lang": L10n.lang,
                            "usage_chunks": [["parts": [["text": "a ripe", "pos": "A"], ["text": "mango", "pos": "N"]], "ja": zh ? "熟透的芒果" : "熟したマンゴー"]]] as [String: Any]]
        default:
            w = ["id": "rq", "headword": "芒果", "reading_zhuyin": "ㄇㄤˊ ㄍㄨㄛˇ", "language": "zh-TW",
                 "meaning_ja": en ? "mango" : "マンゴー", "example_sentence": "這顆芒果很甜。",
                 "example_translation": en ? "This mango is very sweet." : "このマンゴーはとても甘い。",
                 "extras": ["explain_lang": L10n.lang,
                            "usage_chunks": [["parts": [["text": "芒果", "pos": "N"], ["text": "很", "pos": "ADV"], ["text": "甜", "pos": "VS"]], "ja": en ? "Mangoes are very sweet" : "マンゴーはとても甘い"],
                                             ["parts": [["text": "切", "pos": "V"], ["text": "芒果", "pos": "N"]], "ja": en ? "cut a mango" : "マンゴーを切る"]],
                            "measure_words": [["word": "顆", "zhuyin": "ㄎㄜ", "note": en ? "for round fruit" : "丸い果物に"]]] as [String: Any]]
        }
        let data = (try? JSONSerialization.data(withJSONObject: w)) ?? Data()
        let word = (try? JSONDecoder().decode(Word.self, from: data))
            .map { ReaderLanguage.resolve($0, explanation: nil, readerMeaning: nil, reader: L10n.lang) }
        let s = Sticker(id: "review", wordId: "rq", objectImageUrl: "preview/review.jpg", cutoutImageUrl: nil, selfieImageUrl: nil,
                        caption: nil, locationName: nil, takenAt: Date(), captureType: "photo", word: word)
        return ReviewCard(review: ReviewState(id: "r1", stickerId: "review", ease: 2.5, intervalDays: 1), sticker: s)
    }

    var body: some View {
        // The learning language first, so the choices and readings are drawn for it (DEBUG preview only).
        let _ = { NativeAPI.targetLanguage = learning }()
        let c = card
        let choices = [QuizChoice(headword: c.sticker.word?.headword ?? "", zhuyin: c.sticker.word?.readingZhuyin)]
            + ReviewStore.fallback(for: learning, categoryKey: c.sticker.categoryKey).filter { $0.headword != c.sticker.word?.headword }.prefix(3)
        ZStack(alignment: .bottom) {
            AppBackground()
            ScrollView {
                QuizCard(card: c, choices: choices, percent: 62, isAnswered: answered, onAnswer: { _, _ in }, onBadge: {})
                    .padding(.top, 40)
                    .uiReady("preview")
            }
            if answered {
                AnswerPanel(sticker: c.sticker, correct: true, onDex: {}, onNext: {})
            }
        }
    }
}

/// The word page of a catch made in selfie mode (冰火菠蘿油 held up in the selfie), opened on the selfie side: its
/// cut-out (the person and the bun) with 「元の写真」 (`-uiPreview selfie`), or the selfie as it was taken, whole and at
/// its own shape (`-uiPreview selfie-original`). Vision does not run on the simulator, so the cut-out is drawn here.
private struct SelfieDetailPreview: View {
    let original: Bool

    private static let selfieSize = CGSize(width: 900, height: 1200)

    /// The person and the bun they hold (the selfie's foreground).
    private static func drawPersonWithBun(_ c: CGContext) {
        UIColor(red: 0.2, green: 0.36, blue: 0.62, alpha: 1).setFill()   // shirt
        c.addPath(UIBezierPath(roundedRect: CGRect(x: 200, y: 700, width: 500, height: 520), cornerRadius: 160).cgPath)
        c.fillPath()
        UIColor(red: 0.96, green: 0.8, blue: 0.68, alpha: 1).setFill()   // face and hands
        c.fillEllipse(in: CGRect(x: 320, y: 300, width: 260, height: 320))
        c.fillEllipse(in: CGRect(x: 250, y: 720, width: 110, height: 90))
        c.fillEllipse(in: CGRect(x: 540, y: 720, width: 110, height: 90))
        UIColor(red: 0.2, green: 0.14, blue: 0.1, alpha: 1).setFill()    // hair
        c.addPath(UIBezierPath(roundedRect: CGRect(x: 310, y: 270, width: 280, height: 130), cornerRadius: 60).cgPath)
        c.fillPath()
        drawBun(c, in: CGRect(x: 300, y: 640, width: 300, height: 190))
    }

    private static func drawBun(_ c: CGContext, in r: CGRect) {
        UIColor(red: 0.93, green: 0.66, blue: 0.22, alpha: 1).setFill()
        c.fillEllipse(in: r)
        UIColor(red: 0.98, green: 0.82, blue: 0.42, alpha: 1).setFill()
        c.fillEllipse(in: r.insetBy(dx: r.width * 0.12, dy: r.height * 0.16))
        UIColor(red: 1, green: 0.95, blue: 0.7, alpha: 1).setFill()      // the cold butter
        c.fill(CGRect(x: r.midX - r.width * 0.22, y: r.midY - r.height * 0.08, width: r.width * 0.44, height: r.height * 0.16))
    }

    private static let sticker: Sticker = {
        let clear = UIGraphicsImageRendererFormat.default()
        clear.opaque = false
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 900)).image { ctx in
            UIColor(red: 0.95, green: 0.9, blue: 0.82, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 900, height: 900))
            drawBun(ctx.cgContext, in: CGRect(x: 180, y: 260, width: 540, height: 360))
        }
        let cut = UIGraphicsImageRenderer(size: CGSize(width: 560, height: 380), format: clear).image { ctx in
            drawBun(ctx.cgContext, in: CGRect(x: 10, y: 10, width: 540, height: 360))
        }
        let selfie = UIGraphicsImageRenderer(size: selfieSize).image { ctx in
            let colors = [UIColor(red: 0.82, green: 0.9, blue: 0.86, alpha: 1).cgColor,
                          UIColor(red: 0.62, green: 0.74, blue: 0.7, alpha: 1).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: selfieSize.height), options: [])
            }
            UIColor(white: 1, alpha: 0.5).setFill()   // a shop sign behind
            ctx.fill(CGRect(x: 60, y: 90, width: 300, height: 120))
            drawPersonWithBun(ctx.cgContext)
        }
        let selfieCut = UIGraphicsImageRenderer(size: CGSize(width: 500, height: 950), format: clear).image { ctx in
            ctx.cgContext.translateBy(x: -200, y: -270)
            drawPersonWithBun(ctx.cgContext)
        }
        ImageCache.shared.set(photo, for: "preview/bun-photo.jpg")
        ImageCache.shared.set(cut, for: "preview/bun-cutout.png")
        ImageCache.shared.set(selfie, for: "preview/bun-selfie.jpg")
        SelfieCutouts.shared.seedForPreview("preview/bun-selfie.jpg", cutout: selfieCut)
        let json = #"{"id":"w-bun","headword":"冰火菠蘿油","language":"zh-TW","reading_zhuyin":"ㄅㄧㄥ ㄏㄨㄛˇ ㄅㄛ ㄌㄨㄛˊ ㄧㄡˊ","meaning_ja":"冷たいバター入りのパイナップルパン"}"#
        let word = try? JSONDecoder().decode(Word.self, from: Data(json.utf8))
        var s = Sticker(id: "selfie-preview", wordId: "w-bun", objectImageUrl: "preview/bun-photo.jpg",
                        cutoutImageUrl: "preview/bun-cutout.png", selfieImageUrl: "preview/bun-selfie.jpg",
                        caption: nil, locationName: "香港", takenAt: Date(), captureType: "photo", word: word)  // l10n-ignore (place name)
        s.heroRole = "selfie"
        return s
    }()

    var body: some View {
        WordDetailView(sticker: Self.sticker, previewSelfieOriginal: original)
    }
}

/// A word met three times (`-uiPreview slides`): the first catch's cut-out, a re-encounter's cut-out and a
/// re-encounter's photo with no cut-out slide by every 3 seconds, the last followed by the first.
private struct SlidesPreview: View {
    @Environment(DexStore.self) private var dex

    private static func mango(_ hue: CGFloat, size: CGSize, background: Bool) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = background
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let c = ctx.cgContext
            if background {
                UIColor(hue: 0.55, saturation: 0.25, brightness: 0.95, alpha: 1).setFill()
                c.fill(CGRect(origin: .zero, size: size))
            }
            UIColor(hue: hue, saturation: 0.85, brightness: 0.98, alpha: 1).setFill()
            c.fillEllipse(in: CGRect(x: size.width * 0.12, y: size.height * 0.2, width: size.width * 0.76, height: size.height * 0.62))
            UIColor(red: 0.2, green: 0.55, blue: 0.25, alpha: 1).setFill()
            c.fillEllipse(in: CGRect(x: size.width * 0.42, y: size.height * 0.08, width: size.width * 0.2, height: size.height * 0.16))
        }
    }

    private static let sticker: Sticker = {
        ImageCache.shared.set(mango(0.11, size: CGSize(width: 520, height: 460), background: false), for: "preview/slide-0.png")
        ImageCache.shared.set(mango(0.08, size: CGSize(width: 900, height: 900), background: true), for: "preview/slide-1.jpg")
        ImageCache.shared.set(mango(0.08, size: CGSize(width: 600, height: 420), background: false), for: "preview/slide-1.png")
        ImageCache.shared.set(mango(0.14, size: CGSize(width: 900, height: 1100), background: true), for: "preview/slide-2.jpg")
        let json = #"{"id":"w-slides","headword":"芒果","language":"zh-TW","reading_zhuyin":"ㄇㄤˊ ㄍㄨㄛˇ","meaning_ja":"マンゴー"}"#
        let word = try? JSONDecoder().decode(Word.self, from: Data(json.utf8))
        return Sticker(id: "slides", wordId: "w-slides", objectImageUrl: "preview/slide-1.jpg", cutoutImageUrl: "preview/slide-0.png",
                       selfieImageUrl: nil, caption: nil, locationName: nil, takenAt: Date().addingTimeInterval(-9 * 86_400),
                       captureType: "photo", word: word)
    }()

    var body: some View {
        WordDetailView(sticker: Self.sticker)
            .onAppear {
                dex.seedEncountersForPreview([
                    .init(id: "e1", stickerId: "slides", image: "preview/slide-1.jpg", cutout: "preview/slide-1.png",
                          place: "台北", at: Date().addingTimeInterval(-4 * 86_400)),  // l10n-ignore (place name)
                    .init(id: "e2", stickerId: "slides", image: "preview/slide-2.jpg", cutout: nil,
                          place: "台南", at: Date().addingTimeInterval(-86_400)),  // l10n-ignore (place name)
                ])
            }
    }
}

/// The cost card of the AI settings on its own (the whole screen is taller than one screenshot).
private struct AdminAiCostsPreview: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                if let costs = AdminAiSettingsPreview.costs {
                    AdminAiCostCard(preview: costs)
                        .padding(16)
                } else {
                    Text("AdminAiCosts mock did not decode")
                }
            }
            .background(AppBackground())
        }
    }
}

/// The speed and accuracy card of the AI settings on its own (the whole screen is taller than one screenshot).
private struct AdminAiStatsPreview: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                if let settings = AdminAiSettingsPreview.settings {
                    AdminAiStatsCard(settings: settings, preview: AdminAiSettingsPreview.stats)
                        .padding(16)
                } else {
                    Text("AdminAiSettings mock did not decode")
                }
            }
            .background(AppBackground())
        }
    }
}

/// 設定 → 開発者 →「AI の設定（開発者）」 with made-up settings (no server, no admin check):
/// scan on auto, diary correction moved to OpenRouter, one feature whose provider lost its key.
private struct AdminAiSettingsPreview: View {
    private static let json = """
    {
      "isAdmin": true,
      "status": { "ok": true, "provider": "google", "error": null },
      "features": [
        { "id": "scan", "tier": "flash-lite", "needsVision": true, "labelKey": "aiSet.feature.scan",
          "label": { "ja": "スキャン", "en": "Scan", "zh-TW": "掃描" },
          "description": { "ja": "写真の物・文字の検出、単語の候補、単語帳の読み取り（写真を読めるモデルだけ）。",
                           "en": "Finds objects and text in photos, suggests words and reads wordbook pages (image-capable models only).",
                           "zh-TW": "偵測照片中的物品與文字、提出單字候選、讀取單字本（僅限能讀圖片的模型）。" },
          "value": "auto", "provider": "google", "model": "latest-flash-lite", "resolved": "gemini-3.8-flash-lite", "error": null },
        { "id": "card", "tier": "flash", "needsVision": false, "labelKey": "aiSet.feature.card",
          "label": { "ja": "単語カード", "en": "Word cards", "zh-TW": "單字卡" },
          "description": { "ja": "単語・フレーズのカード生成と作り直し。", "en": "Writes and rewrites word and phrase cards.", "zh-TW": "產生與重寫單字、片語卡。" },
          "value": "auto", "provider": "google", "model": "latest-flash", "resolved": "gemini-3.8-flash", "error": null },
        { "id": "journal", "tier": "flash", "needsVision": false, "labelKey": "aiSet.feature.journal",
          "label": { "ja": "日記の添削", "en": "Diary correction", "zh-TW": "日記批改" },
          "description": { "ja": "日記の添削・書き出しの質問。", "en": "Diary corrections and writing prompts.", "zh-TW": "日記批改與開頭提問。" },
          "value": "openrouter:anthropic/claude-sonnet-4.5", "provider": "openrouter", "model": "anthropic/claude-sonnet-4.5",
          "resolved": "anthropic/claude-sonnet-4.5", "error": null },
        { "id": "audit", "tier": "flash", "needsVision": false, "labelKey": "aiSet.feature.audit",
          "label": { "ja": "自己点検", "en": "Self-check", "zh-TW": "自我檢查" },
          "description": { "ja": "報告された項目の特定・作り直しの判定。", "en": "Finds reported items and decides what to rewrite.", "zh-TW": "找出回報的項目並判斷是否重寫。" },
          "value": "openai:gpt-5-mini", "provider": "google", "model": "latest-flash", "resolved": "gemini-3.8-flash",
          "error": "openai の鍵が無いため既定の AI で動いています" },
        { "id": "future_feature", "tier": "something-new", "needsVision": false,
          "label": { "ja": "新しい機能" }, "value": "auto", "provider": null, "model": null, "resolved": null, "error": null }
      ],
      "tasks": [
        { "id": "photo_candidates", "feature": "scan", "needsVision": true, "ios": true,
          "label": { "ja": "写真の単語の候補", "en": "Words from a photo", "zh-TW": "照片的單字候選" },
          "description": { "ja": "撮った写真から単語の候補を出す（写真を読む）", "en": "Suggests words for the photo just taken (reads the photo)", "zh-TW": "從剛拍的照片提出單字候選（讀取照片）" },
          "value": "auto", "backup": "auto", "provider": "google", "model": "latest-flash-lite", "resolved": "gemini-3.8-flash-lite",
          "backupProvider": "lovable", "backupModel": "google/gemini-2.5-flash", "backupResolved": "google/gemini-2.5-flash", "error": null },
        { "id": "card", "feature": "card", "needsVision": false, "ios": true,
          "label": { "ja": "単語カード", "en": "Word card", "zh-TW": "單字卡" },
          "description": { "ja": "解説・例文・分類など、カードの中身を作る", "en": "Writes the card: explanation, examples, category", "zh-TW": "產生單字卡的內容：解說、例句、分類" },
          "value": "openrouter:anthropic/claude-sonnet-4.5", "backup": "auto", "provider": "openrouter", "model": "anthropic/claude-sonnet-4.5",
          "resolved": "anthropic/claude-sonnet-4.5", "backupProvider": "lovable", "backupModel": "google/gemini-2.5-flash",
          "backupResolved": "google/gemini-2.5-flash", "error": null },
        { "id": "section_regen", "feature": "card", "needsVision": false, "ios": true,
          "label": { "ja": "項目の作り直し", "en": "Section rewrite", "zh-TW": "重新產生項目" },
          "description": { "ja": "単語ページの項目の作り直し・空欄の補完・報告での直しの案", "en": "Rewrites a section of the word page, fills blanks, drafts fixes for reports", "zh-TW": "重新產生單字頁的項目、補上空白、回報時的修正案" },
          "value": "auto", "backup": "off", "provider": "google", "model": "latest-flash", "resolved": "gemini-3.8-flash",
          "backupProvider": null, "backupModel": null, "backupResolved": null, "error": null },
        { "id": "report_locate", "feature": "audit", "needsVision": false, "ios": true,
          "label": { "ja": "報告: 間違った項目を探す", "en": "Report: find the wrong part", "zh-TW": "回報：找出錯誤的項目" },
          "description": { "ja": "項目を選ばずに報告された時、どの項目が違うかを探す", "en": "Finds which section is wrong when a report names none", "zh-TW": "回報沒選項目時，找出哪個項目有錯" },
          "value": "openai:gpt-5-mini", "backup": "auto", "provider": "google", "model": "latest-flash", "resolved": "gemini-3.8-flash",
          "backupProvider": "lovable", "backupModel": "google/gemini-2.5-flash", "backupResolved": "google/gemini-2.5-flash",
          "error": "openai の鍵が無いため機能の設定・既定の AI で動いています" },
        { "id": "journal_correct", "feature": "journal", "needsVision": false, "ios": false,
          "label": { "ja": "日記の添削" }, "value": "auto", "backup": "auto", "provider": "google", "model": "latest-flash",
          "resolved": "gemini-3.8-flash", "error": null }
      ],
      "providers": [
        { "id": "google", "name": "Google Gemini", "hasKey": true,
          "models": ["latest-flash-lite", "latest-flash", "latest-pro", "gemini-3.8-flash", "gemini-3.8-flash-lite"],
          "visionModels": ["latest-flash-lite", "latest-flash", "latest-pro", "gemini-3.8-flash", "gemini-3.8-flash-lite"], "error": null },
        { "id": "openai", "name": "OpenAI (ChatGPT)", "hasKey": false, "models": [], "visionModels": [], "error": null },
        { "id": "openrouter", "name": "OpenRouter", "hasKey": true,
          "models": ["anthropic/claude-sonnet-4.5", "openai/gpt-5-mini"], "visionModels": ["anthropic/claude-sonnet-4.5"], "error": null },
        { "id": "brand-new", "name": "Brand New AI", "hasKey": true, "models": [], "visionModels": [], "error": "401 invalid key" }
      ],
      "image": {
        "provider": "google", "model": "gemini-2.5-flash-image", "saved": { "provider": "google", "model": "gemini-2.5-flash-image" },
        "providers": [
          { "id": "lovable", "name": "Lovable AI", "hasKey": true, "defaultModel": "openai/gpt-image-1-mini" },
          { "id": "google", "name": "Google AI Studio", "hasKey": true, "defaultModel": "gemini-2.5-flash-image" },
          { "id": "higgsfield", "name": "Higgsfield", "hasKey": false, "defaultModel": "bytedance/seedream/v4/text-to-image" },
          { "id": "off", "name": "Off", "hasKey": true, "defaultModel": "" }
        ]
      },
      "tts": {
        "defaultEngine": "OpenAI-compatible TTS",
        "languages": {
          "zh-TW": { "provider": "azure", "voice": "zh-TW-HsiaoChenNeural", "model": null, "gender": "female", "incomplete": false },
          "en": { "provider": "default", "voice": "", "model": null, "gender": null, "incomplete": false },
          "ja": { "provider": "elevenlabs", "voice": "", "model": "eleven_flash_v2_5", "gender": null, "incomplete": true }
        },
        "providers": [
          { "id": "azure", "name": "Azure AI Speech", "hasKey": true, "keyEnvs": ["AZURE_SPEECH_KEY"], "models": [],
            "voices": { "zh-TW": ["zh-TW-HsiaoChenNeural", "zh-TW-HsiaoYuNeural", "zh-TW-YunJheNeural"],
                        "en": ["en-US-AvaMultilingualNeural", "en-US-JennyNeural"], "ja": ["ja-JP-NanamiNeural", "ja-JP-KeitaNeural"] } },
          { "id": "gemini", "name": "Gemini TTS", "hasKey": true, "keyEnvs": ["GEMINI_API_KEY"],
            "models": ["gemini-3.8-flash-lite-tts", "gemini-3.8-flash-tts"], "voices": { "zh-TW": [], "en": [], "ja": [] } },
          { "id": "elevenlabs", "name": "ElevenLabs", "hasKey": true, "keyEnvs": ["ELEVENLABS_API_KEY"],
            "models": ["eleven_flash_v2_5", "eleven_v3"], "voices": { "zh-TW": [], "en": [], "ja": [] } }
        ]
      }
    }
    """

    static let settings: AdminAiSettings? = try? JSONDecoder().decode(AdminAiSettings.self, from: Data(json.utf8))

    /// The speed and accuracy numbers (web `adminGetAiStats`): the scan compares Flash-Lite with Claude Haiku.
    static let statsJSON = """
    {
      "isAdmin": true, "truncated": false, "days": 7, "mine": false,
      "tasks": [
        { "task": "photo_candidates", "feature": "scan", "models": [
          { "model": "google:gemini-3.8-flash-lite", "calls": 9, "ok": 8, "failed": 0, "timeouts": 1, "cancelled": 2,
            "okPct": 88.9, "p50": 2200, "p90": 3400, "avgIn": 1850, "avgOut": 320, "costUsd": null,
            "unusable": { "n": 1, "of": 8, "pct": 12.5 },
            "picks": { "n": 7, "top1": 4, "top3": 6, "nativeSearch": 1, "top1Pct": 57.1, "top3Pct": 85.7 } },
          { "model": "anthropic:claude-haiku-5-5", "calls": 4, "ok": 4, "failed": 0, "timeouts": 0, "cancelled": 0,
            "okPct": 100, "p50": 1600, "p90": 2600, "avgIn": 1850, "avgOut": 320, "costUsd": 0.000345,
            "unusable": { "n": 0, "of": 3, "pct": 0 },
            "picks": { "n": 3, "top1": 2, "top3": 3, "nativeSearch": 0, "top1Pct": 66.7, "top3Pct": 100 } }
        ] },
        { "task": "card", "feature": "card", "models": [
          { "model": "google:gemini-3.8-flash", "calls": 4, "ok": 4, "failed": 0, "timeouts": 0, "cancelled": 0,
            "okPct": 100, "p50": 15800, "p90": 21000, "avgIn": 10200, "avgOut": 2050, "costUsd": 0.0153,
            "unusable": null, "picks": null }
        ] }
      ],
      "tests": [
        { "task": "photo_candidates", "model": "google:gemini-3.8-flash-lite", "lang": "zh-TW", "n": 33, "ok": 33,
          "failed": 0, "top1": 23, "top3": 30, "top1Pct": 69.7, "top3Pct": 90.9, "p50": 2100, "p90": 2900, "costUsd": null },
        { "task": "photo_candidates", "model": "anthropic:claude-haiku-5-5", "variant": "thinking-off", "lang": "zh-TW",
          "n": 33, "ok": 32, "failed": 1, "top1": 21, "top3": 28, "top1Pct": 63.6, "top3Pct": 84.8, "p50": 1600,
          "p90": 2300, "costUsd": 0.0003 }
      ]
    }
    """

    static let stats: AdminAiStats? = try? JSONDecoder().decode(AdminAiStats.self, from: Data(statsJSON.utf8))

    /// What the AI cost (web `adminGetAiCosts`): cards on Gemini and on the Lovable gateway (no price entered yet).
    static let costsJSON = """
    {
      "isAdmin": true, "truncated": false, "days": 30, "since": "2026-09-14T12:00:00.000Z", "usdJpy": 156,
      "total": { "calls": 104, "ok": 79, "failed": 25, "tokensIn": 393800, "tokensOut": 87700, "usd": 0.0918, "unpricedCalls": 35 },
      "tasks": [
        { "task": "card", "feature": "card", "ios": true, "label": { "ja": "単語カード", "en": "Word card", "zh-TW": "單字卡" },
          "calls": 58, "ok": 33, "failed": 25, "tokensIn": 333698, "tokensOut": 78245, "usd": 0.0411, "unpricedCalls": 25,
          "models": [ { "model": "google:gemini-3.8-flash", "calls": 19, "usd": 0.0411 },
                      { "model": "lovable:google/gemini-2.5-flash", "calls": 25, "usd": null } ] },
        { "task": "photo_candidates", "feature": "scan", "ios": true, "label": { "ja": "写真の単語の候補", "en": "Words from a photo", "zh-TW": "照片的單字候選" },
          "calls": 26, "ok": 15, "failed": 11, "tokensIn": 60074, "tokensOut": 8830, "usd": 0.0100, "unpricedCalls": 10,
          "models": [ { "model": "google:gemini-3.5-flash-lite", "calls": 15, "usd": 0.0100 },
                      { "model": "lovable:google/gemini-2.5-flash", "calls": 11, "usd": null } ] },
        { "task": "category_backfill", "feature": "lexicon", "ios": false, "label": { "ja": "棚の分類の付け直し", "en": "Category backfill", "zh-TW": "分類的重新整理" },
          "calls": 4, "ok": 0, "failed": 4, "tokensIn": 0, "tokensOut": 0, "usd": 0, "unpricedCalls": 0,
          "models": [ { "model": "google:gemini-3.8-flash", "calls": 4, "usd": 0 } ] }
      ],
      "models": [
        { "model": "google:gemini-3.8-flash", "calls": 23, "ok": 3, "failed": 20, "tokensIn": 30487, "tokensOut": 4850, "usd": 0.0411, "unpricedCalls": 0,
          "price": { "inUsd": 0.75, "outUsd": 3.75, "source": "ai.google.dev/gemini-api/docs/pricing (checked 2026-10-11)", "custom": false } },
        { "model": "google:gemini-3.5-flash-lite", "calls": 15, "ok": 5, "failed": 10, "tokensIn": 19275, "tokensOut": 1697, "usd": 0.0100, "unpricedCalls": 0,
          "price": { "inUsd": 0.3, "outUsd": 2.5, "source": "ai.google.dev/gemini-api/docs/pricing (checked 2026-10-11)", "custom": false } },
        { "model": "lovable:google/gemini-2.5-flash", "calls": 36, "ok": 35, "failed": 1, "tokensIn": 293196, "tokensOut": 70487, "usd": 0, "unpricedCalls": 35,
          "price": null }
      ],
      "daily": [
        { "day": "2026-10-08", "calls": 0, "usd": 0 }, { "day": "2026-10-09", "calls": 6, "usd": 0.006 },
        { "day": "2026-10-10", "calls": 14, "usd": 0.021 }, { "day": "2026-10-11", "calls": 31, "usd": 0.034 },
        { "day": "2026-10-12", "calls": 12, "usd": 0.004 }, { "day": "2026-10-13", "calls": 18, "usd": 0.011 },
        { "day": "2026-10-14", "calls": 23, "usd": 0.0158 }
      ],
      "customPrices": []
    }
    """

    static let costs: AdminAiCosts? = try? JSONDecoder().decode(AdminAiCosts.self, from: Data(costsJSON.utf8))

    var body: some View {
        NavigationStack {
            if let settings = Self.settings {
                AdminAiSettingsView(preview: settings, previewStats: Self.stats, previewCosts: Self.costs)
            } else {
                Text("AdminAiSettings mock did not decode")
            }
        }
    }
}

/// 「作り直す」 on 台湾メモ (`-uiPreview regen`, `RegenDust`): every 4.5 s the button is pressed; the old text breaks
/// into dust from left to right, the cloud swirls while the "server" writes (1.6 s), then the new text gathers back.
/// CI records it as a video (ios-check.yml).
private struct RegenPreview: View {
    @State private var running = false
    @State private var second = false

    private var text: String {
        let zh = L10n.lang == "zh-TW", en = L10n.lang == "en"
        if second {
            return zh ? "夏天的台灣到處都買得到冰淇淋。便利商店的冰品也很多。" : en ? "In summer, ice cream is sold everywhere in Taiwan. Convenience stores have many frozen treats too." : "台湾の夏は、どこでもアイスが買えます。コンビニのアイスも種類が豊富です。"
        }
        return zh ? "台灣的冰淇淋口味很多，芋頭和花生最受歡迎。夜市也常常看到。" : en ? "Ice cream in Taiwan comes in many flavours; taro and peanut are favourites. You often see it at night markets." : "台湾のアイスは味が豊富で、タロイモやピーナッツが人気です。夜市でもよく見かけます。"
    }

    var body: some View {
        ScrollView {
            SectionCard(title: L("台湾メモ"), icon: "mappin") {
                SentenceRows(text: text, ruled: false)
            }
            .environment(\.sectionRefresh, SectionRefresh(running: running) {})
            .padding(16)
            .uiReady("preview")
        }
        .background(Theme.background)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.2))
                running = true
                try? await Task.sleep(for: .seconds(1.6))
                second.toggle()
                running = false
                try? await Task.sleep(for: .seconds(1.7))
            }
        }
    }
}
#endif

/// The end of a review round: score ring, missed words to try again, and "review more".
private struct DonePreview: View {
    var body: some View {
        ZStack {
            AppBackground()
            ReviewDone(total: 12, correct: 9, doneToday: 12, missed: 3, isRetry: false, canLoadMore: true) {}
                .padding(16)
        }
    }
}

/// Home (the album) as a guest sees it: the empty album, read once so the skeleton ends.
private struct HomePreview: View {
    @Environment(DexStore.self) private var dex
    /// `-uiPreview home-again` (owner 2026-10-16): the newest word met again twice today — the day still shows it once
    /// and counts it once (`AlbumDay.onePerWord`).
    var metAgain = false

    var body: some View {
        HomeView()
            .environment(\.colorScheme, .light)  // as in MainTabView: the paper album stays paper
            .task {
                guard metAgain else { return await dex.load() }
                // 眼鏡 caught yesterday and met again twice today, a cup caught today: today shows 眼鏡 once, 「2語」.
                let now = Date()
                let glasses = Self.sticker("again-glasses", "眼鏡", hue: 0.58, at: now.addingTimeInterval(-86_400))
                let cup = Self.sticker("again-cup", "杯子", hue: 0.08, at: now.addingTimeInterval(-30))
                dex.stickers = [cup, glasses]
                #if DEBUG
                dex.seedEncountersForPreview([
                    .init(id: "again-1", stickerId: glasses.id, image: glasses.objectImageUrl, cutout: glasses.cutoutImageUrl,
                          place: nil, at: now.addingTimeInterval(-180)),
                    .init(id: "again-2", stickerId: glasses.id, image: glasses.objectImageUrl, cutout: glasses.cutoutImageUrl,
                          place: nil, at: now.addingTimeInterval(-120)),
                ])
                #endif
                dex.hasLoaded = true
                try? await Task.sleep(for: .milliseconds(600))
                UIReady.mark("preview")
            }
    }

    /// A made-up word with a photo and a cut-out kept in memory (no network in the preview).
    private static func sticker(_ id: String, _ head: String, hue: CGFloat, at: Date) -> Sticker {
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 450)).image { ctx in
            UIColor(hue: hue, saturation: 0.25, brightness: 0.95, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 600, height: 450))
            UIColor(hue: hue, saturation: 0.7, brightness: 0.6, alpha: 1).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 150, y: 90, width: 300, height: 270))
        }
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let cutout = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 270), format: format).image { ctx in
            UIColor(hue: hue, saturation: 0.7, brightness: 0.6, alpha: 1).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: 300, height: 270))
        }
        ImageCache.shared.set(photo, for: "preview/\(id).jpg")
        ImageCache.shared.set(cutout, for: "preview/\(id)-cutout.png")
        let word = try? JSONDecoder().decode(Word.self, from: Data(#"{"id":"w-\#(id)","headword":"\#(head)"}"#.utf8))
        return Sticker(id: id, wordId: "w-\(id)", objectImageUrl: "preview/\(id).jpg", cutoutImageUrl: "preview/\(id)-cutout.png",
                       selfieImageUrl: nil, caption: nil, locationName: nil, takenAt: at, captureType: "photo", word: word)
    }
}

/// The camera screen when camera access was refused (CaptureView `.denied`).
private struct CameraBlockedPreview: View {
    var body: some View {
        CameraMessageView(icon: "camera.fill", title: L("カメラの使用が許可されていません"),
                          message: L("1. 下の「設定を開く」を押す\n2. 「カメラ」をオンにして、この画面に戻る"),
                          buttonTitle: L("設定を開く")) {}
            .ignoresSafeArea()
            .denseTypeSizeCap()  // as inside CaptureView
    }
}

/// Swappable chunk parts with the wheel open (docs/chunk-rules.md C5/C6): 跟＋男朋友＋吵架 and 芒果＋很＋甜.
private struct ChunkWheelPreview: View {
    private var reader: String { L10n.lang }

    private func gloss(_ ja: String, _ en: String, _ zh: String) -> String { reader == "en" ? en : reader == "zh-TW" ? zh : ja }

    private var quarrel: UsageChunk {
        let alts = [("女朋友", "彼女", "girlfriend", "女朋友"), ("朋友", "友達", "a friend", "朋友"), ("同事", "同僚", "a coworker", "同事"),
                    ("爸媽", "両親", "my parents", "爸媽"), ("室友", "ルームメイト", "a roommate", "室友")]  // l10n-ignore (preview data)
        return UsageChunk(parts: [
            ChunkPart(text: "跟", pos: "Prep"),  // l10n-ignore (target word)
            ChunkPart(text: "男朋友", pos: "N", slot: true, ja: gloss("彼氏", "my boyfriend", "男朋友"),  // l10n-ignore (preview data)
                      alts: alts.map { ChunkAlt(text: $0.0, ja: gloss($0.1, $0.2, $0.3)) }),
            ChunkPart(text: "吵架", pos: "V"),  // l10n-ignore (target word)
        ], ja: gloss("彼氏と喧嘩する", "argue with my boyfriend", "跟男朋友吵架"))  // l10n-ignore (preview data)
    }

    private var mango: UsageChunk {
        let raw = [ChunkPart(text: "芒果", pos: "N"), ChunkPart(text: "甜", pos: "Vs")]  // l10n-ignore (target word)
        return UsageChunk(parts: ChunkRules.tidy(raw, headword: "芒果", target: "zh-TW", reader: reader),  // l10n-ignore (target word)
                          ja: gloss("マンゴーはとても甘い", "Mangoes are very sweet", "芒果很甜"))  // l10n-ignore (preview data)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ChunkLineView(chunk: quarrel, headword: "吵架", target: "zh-TW", startOpen: 1)  // l10n-ignore (target word)
                Divider()
                ChunkLineView(chunk: mango, headword: "芒果", target: "zh-TW", startOpen: 1)  // l10n-ignore (target word)
            }
            .padding(20)
            .background(.white, in: .rect(cornerRadius: 24))
            .padding(16)
        }
        .background(Theme.background)
    }
}

/// Chunk blocks with the server's per-token readings (`-uiPreview readings` zhuyin / `readings-pinyin`, 2026-10-15):
/// the first two chunks carry readings on every token, the third is an older card's chunk without any.
private struct ChunkReadingsPreview: View {
    /// The card's inner width (nil: the screen's).
    var width: CGFloat?

    init(pref: String, width: CGFloat? = nil) {
        UserDefaults.standard.set(pref, forKey: "reading.pref")
        self.width = width
    }

    private func gloss(_ ja: String, _ en: String, _ zh: String) -> String { L10n.lang == "en" ? en : L10n.lang == "zh-TW" ? zh : ja }

    private var order: UsageChunk {
        UsageChunk(parts: [ChunkPart(text: "點", pos: "V", pinyin: "diǎn", zhuyin: "ㄉㄧㄢˇ"),
                           ChunkPart(text: "一份", pos: "M", pinyin: "yí fèn", zhuyin: "ㄧˊ ㄈㄣˋ"),
                           ChunkPart(text: "鐵板麵", pos: "N", pinyin: "tiě bǎn miàn", zhuyin: "ㄊㄧㄝˇ ㄅㄢˇ ㄇㄧㄢˋ")],
                   ja: gloss("鉄板焼きそばを一人前注文する", "order one teppan noodles", "點一份鐵板麵"))
    }

    private var quarrel: UsageChunk {
        UsageChunk(parts: [ChunkPart(text: "跟", pos: "Prep", pinyin: "gēn", zhuyin: "ㄍㄣ"),
                           ChunkPart(text: "男朋友", pos: "N", slot: true, ja: gloss("彼氏", "my boyfriend", "男朋友"),
                                     alts: [ChunkAlt(text: "朋友", ja: gloss("友達", "a friend", "朋友"))],
                                     pinyin: "nán péng yǒu", zhuyin: "ㄋㄢˊ ㄆㄥˊ ㄧㄡˇ"),
                           ChunkPart(text: "吵架", pos: "V", pinyin: "chǎo jià", zhuyin: "ㄔㄠˇ ㄐㄧㄚˋ")],
                   ja: gloss("彼氏と喧嘩する", "argue with my boyfriend", "跟男朋友吵架"))
    }

    /// A neutral tone (˙ㄗ) and the degree word the app puts in (C8: 滷味＋很＋入味), drawn like the others.
    private var tasty: UsageChunk {
        UsageChunk(parts: [ChunkPart(text: "鐵板麵", pos: "N", pinyin: "tiě bǎn miàn", zhuyin: "ㄊㄧㄝˇ ㄅㄢˇ ㄇㄧㄢˋ"),
                           ChunkPart(text: "很", pos: "Adv", pinyin: "hěn", zhuyin: "ㄏㄣˇ"),
                           ChunkPart(text: "香", pos: "Vs", pinyin: "xiāng", zhuyin: "ㄒㄧㄤ")],
                   ja: gloss("鉄板焼きそばがいい香り", "the teppan noodles smell great", "鐵板麵很香"))
    }

    private var brush: UsageChunk {
        UsageChunk(parts: [ChunkPart(text: "用", pos: "V", pinyin: "yòng", zhuyin: "ㄩㄥˋ"),
                           ChunkPart(text: "刷子", pos: "N", pinyin: "shuā zi", zhuyin: "ㄕㄨㄚ ˙ㄗ"),
                           ChunkPart(text: "刷鐵板", pos: "VO", pinyin: "shuā tiě bǎn", zhuyin: "ㄕㄨㄚ ㄊㄧㄝˇ ㄅㄢˇ")],
                   ja: gloss("ブラシで鉄板をこする", "scrub the griddle with a brush", "用刷子刷鐵板"))
    }

    private var old: UsageChunk {
        UsageChunk(parts: [ChunkPart(text: "蘑菇", pos: "N"), ChunkPart(text: "鐵板麵", pos: "N")],
                   ja: gloss("マッシュルームソースの鉄板焼きそば", "teppan noodles with mushroom sauce", "蘑菇鐵板麵"))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach([order, quarrel, tasty, brush, old], id: \.self) { c in
                    ChunkLineView(chunk: c, headword: "鐵板麵", target: "zh-TW").padding(.vertical, 14)
                    Divider().overlay(Theme.border)
                }
            }
            .frame(width: width)
            .padding(20)
            .background(Theme.card, in: .rect(cornerRadius: 24))
            .padding(16)
            .uiReady("preview")
        }
        .background(Theme.background)
    }
}

/// 設定 › 開発者 › 報告された誤り with made-up reports (`-uiPreview reports`): the rows as the server's answer carries them.
private struct AdminReportsPreview: View {
    private static let rows = """
    [{"id":"7a1c9e2d-0000-4000-8000-000000000001","headword":"鐵板麵","kind":"content","item":"meaning","note":"意味が「鉄板焼き」だけで、麺のことが書かれていない","status":"needs_review","outcome":"直しの案が確認を通らなかった","reporter_lang":"ja","word_id":"w-1","created_at":"2026-10-15T11:20:00Z","outcome_at":"2026-10-15T11:21:00Z"},
     {"id":"7a1c9e2d-0000-4000-8000-000000000002","headword":"珍珠奶茶","kind":"content","item":"example","note":"The example sentence uses 珍奶, not the headword.","status":"fixed","outcome":"例文を作り直した","reporter_lang":"en","word_id":"w-2","created_at":"2026-10-14T03:05:00Z","outcome_at":"2026-10-14T03:06:00Z"},
     {"id":"7a1c9e2d-0000-4000-8000-000000000003","headword":"便當","kind":"content","item":"pronunciation","note":"注音的聲調不對","status":"open","outcome":null,"reporter_lang":"zh-TW","word_id":"w-3","created_at":"2026-10-13T09:48:00Z","outcome_at":null}]
    """

    var body: some View {
        NavigationStack {
            AdminReportsView(fixture: (try? JSONDecoder().decode(JSONValue.self, from: Data(Self.rows.utf8))) ?? .array([]))
        }
    }
}

/// The Collection map of one day in Taipei (`-uiPreview map`): the timeline panel at its low height over the map —
/// one row's picture and time show, the map stays readable (owner 2026-10-15).
private struct MapPreview: View {
    private static func word(_ head: String, _ meaning: String) -> Word? {
        let obj: [String: Any] = ["id": "w-\(head)", "headword": head, "language": "zh-TW", "meaning_ja": meaning]
        return (try? JSONSerialization.data(withJSONObject: obj)).flatMap { try? JSONDecoder().decode(Word.self, from: $0) }
    }

    private static var stickers: [Sticker] {
        let day = Calendar.current.startOfDay(for: Date())
        let rows: [(String, String, Double, Double, Double, String)] = [
            ("珍珠奶茶", "タピオカミルクティー", 9.5, 25.0339, 121.5645, "信義區"),
            ("便當", "弁当", 12.25, 25.0478, 121.5170, "台北車站"),
            ("芒果冰", "マンゴーかき氷", 15.0, 25.0418, 121.5440, "大安區"),
            ("雞排", "フライドチキン", 19.5, 25.0880, 121.5240, "士林夜市"),
        ]
        return rows.enumerated().map { i, r in
            var s = Sticker(id: "map-\(i)", wordId: "w-\(r.0)", objectImageUrl: nil, cutoutImageUrl: nil, selfieImageUrl: nil,
                            caption: nil, locationName: r.5, takenAt: day.addingTimeInterval(r.2 * 3600), captureType: "photo",
                            word: word(r.0, r.1))
            s.lat = r.3
            s.lng = r.4
            return s
        }
    }

    var body: some View {
        DexMapView(stickers: Self.stickers) { _ in }
    }
}
