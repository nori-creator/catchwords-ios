import SwiftUI

/// 開発者の「ネイティブの発音を録音」(2026-11-29, owner: 「本物の発音から分析して」; partner and friends record, not
/// dozens of people). A Taiwanese speaker reads words on the developer's phone; the phone measures each recording with
/// the same steps as the learner's (`ProsodyAnalyzer`) and keeps the numbers and the audio on the server under a code for
/// the speaker (`adminSaveNativeProsody`). Learners are then compared with these, on each speaker's own scale.
struct NativeRecordingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DexStore.self) private var dex
    @AppStorage("pron.native.speaker") private var speaker = "A"
    @AppStorage("pron.native.gender") private var gender = "female"
    @State private var consent = false
    @State private var recorder = VoiceRecorder()
    @State private var ranges: [String: SpeakerRange] = NativeSpeakerRanges.all()
    @State private var remeasure = false
    @State private var counts: [String: Int] = [:]
    @State private var current: NativePrompt?
    @State private var take: ProsodyTake?
    @State private var samples: [Float] = []
    @State private var busy = false
    @State private var message: String?

    private var code: String { speaker.trimmingCharacters(in: .whitespaces) }
    private var codeValid: Bool { code.range(of: "^[A-Za-z0-9_-]{1,16}$", options: .regularExpression) != nil }
    private var range: SpeakerRange? { ranges[code] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    speakerCard
                    if codeValid {
                        if range == nil || remeasure {
                            VoiceRangeCard(recorder: recorder, hasRange: range != nil) { measured in
                                NativeSpeakerRanges.save(measured, for: code)
                                ranges = NativeSpeakerRanges.all()
                                remeasure = false
                            } onCancel: {
                                remeasure = false
                            }
                        } else {
                            if let current { recordCard(current) }
                            wordList
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(L("ネイティブの発音を録音"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("閉じる")) { dismiss() }
                }
            }
            .task { await loadCounts() }
            .onChange(of: speaker) { _, _ in Task { await loadCounts() } }
            .onDisappear { recorder.cancel() }
        }
    }

    // MARK: - Speaker

    private var speakerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("話す人"))
                .scaledFont(size: 15, weight: .bold)
            HStack(spacing: 10) {
                TextField(L("記号（例：A）"), text: $speaker)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(10)
                    .background(Theme.secondary, in: .rect(cornerRadius: 10))
                Picker(L("性別"), selection: $gender) {
                    Text(L("女性")).tag("female")
                    Text(L("男性")).tag("male")
                    Text(L("その他")).tag("other")
                }
                .pickerStyle(.menu)
            }
            Text(L("名前は保存しません。記号と、話す人の対応はあなただけが持ってください。"))
                .scaledFont(size: 12)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(isOn: $consent) {
                Text(L("この人は、発音の手本を作るために、声と分析した数値をサーバーに保存することに同意しています"))
                    .scaledFont(size: 13, weight: .semibold)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let range, !remeasure {
                HStack {
                    Text(L("声の範囲：\(Int(range.lowHz.rounded())) Hz 〜 \(Int(range.highHz.rounded())) Hz"))
                        .scaledFont(size: 13, weight: .semibold, monospacedDigit: true)
                        .foregroundStyle(Theme.primaryInk)
                    Spacer()
                    Button(L("はかり直す")) { remeasure = true }
                        .scaledFont(size: 13, weight: .semibold)
                }
            }
        }
        .coachCard()
    }

    // MARK: - Recording one word

    private func recordCard(_ prompt: NativePrompt) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZhuyinWordView(headword: prompt.tones.headword, zhuyin: prompt.zhuyin, size: 30, weight: .heavy,
                               pinyin: prompt.pinyin, language: "zh-TW")
                Spacer()
                DetailSpeakButton(text: prompt.tones.headword)
            }
            if let take, let range,
               let band = ProsodyBand([NormalizedSyllable.make(take, range: range)]) {
                ProsodyChartView(syllables: prompt.tones.syllables, band: band, height: 190)
            } else if recorder.phase == .recording {
                ProsodyChartView(syllables: prompt.tones.syllables, band: nil,
                                 live: recorder.live.map { $0.map { range?.level($0) ?? 3 } }, height: 190)
            }
            if let message {
                Text(message)
                    .scaledFont(size: 13, weight: .semibold)
                    .foregroundStyle(Theme.muted)
            }
            HStack(spacing: 10) {
                Button(action: record) {
                    Label(recorder.phase == .recording ? L("止める") : (take == nil ? L("録音する") : L("録り直す")),
                          systemImage: recorder.phase == .recording ? "stop.fill" : "mic.fill")
                        .scaledFont(size: 15, weight: .bold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(recorder.phase == .recording ? Theme.destructive : Theme.primary, in: Capsule())
                }
                .buttonStyle(PressableStyle())
                .disabled(busy)
                Button(action: save) {
                    Group {
                        if busy { ProgressView() } else { Text(L("保存")).scaledFont(size: 15, weight: .bold) }
                    }
                    .foregroundStyle(Theme.primaryInk)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Theme.primary.opacity(0.12), in: Capsule())
                }
                .buttonStyle(PressableStyle())
                .disabled(take == nil || !consent || busy)
            }
            if !consent {
                Text(L("保存するには、上の同意をオンにしてください"))
                    .scaledFont(size: 12)
                    .foregroundStyle(Theme.destructive)
            }
        }
        .coachCard()
    }

    // MARK: - Words

    private var wordList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("読む単語（声調の組み合わせ順）"))
                .scaledFont(size: 15, weight: .bold)
            Text(L("同じ声調の組み合わせの単語は、ほかの単語の手本にも使います。1つの単語を、何人かに読んでもらうほど正確になります。"))
                .scaledFont(size: 12)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(prompts) { p in
                Button {
                    current = p
                    take = nil
                    samples = []
                    message = nil
                } label: {
                    HStack {
                        Text(verbatim: p.tones.headword)
                            .scaledFont(size: 18, weight: .bold)
                            .foregroundStyle(Theme.foreground)
                        Text(verbatim: p.tones.syllables.map(\.pinyin).joined(separator: " "))
                            .scaledFont(size: 13)
                            .foregroundStyle(Theme.muted)
                        Spacer()
                        Text(verbatim: p.tones.pattern ?? "")
                            .scaledFont(size: 12, weight: .semibold, monospacedDigit: true)
                            .foregroundStyle(Theme.muted)
                        Text(verbatim: "\(counts[p.tones.headword] ?? 0)")
                            .scaledFont(size: 13, weight: .bold, monospacedDigit: true)
                            .foregroundStyle((counts[p.tones.headword] ?? 0) > 0 ? Theme.ok : Theme.muted)
                            .frame(minWidth: 24)
                    }
                    .padding(.vertical, 6)
                }
                Divider().overlay(Theme.border)
            }
        }
        .coachCard()
    }

    /// The bundled tone combinations first, then the developer's own words.
    private var prompts: [NativePrompt] {
        var seen = Set<String>()
        var out: [NativePrompt] = []
        for p in NativePrompt.bundled where seen.insert(p.tones.headword).inserted { out.append(p) }
        for s in dex.stickers {
            guard let w = s.word, !seen.contains(w.headword),
                  let tones = WordTones.make(headword: w.headword, zhuyin: w.readingZhuyin, pinyin: w.pinyin) else { continue }
            seen.insert(w.headword)
            out.append(NativePrompt(tones: tones, zhuyin: w.readingZhuyin, pinyin: w.pinyin))
        }
        return out
    }

    // MARK: - Actions

    private func record() {
        if recorder.phase == .recording {
            recorder.stop()
            return
        }
        guard let current else { return }
        message = nil
        Task {
            guard await VoiceRecorder.requestPermission() else {
                message = L("マイクの使用が許可されていません。設定でマイクをオンにすると、発音をチェックできます。")
                return
            }
            let n = current.tones.syllables.count
            try? recorder.start { recorded in
                Task {
                    let measured = await Task.detached(priority: .userInitiated) {
                        ProsodyAnalyzer.analyze(recorded, syllables: n)
                    }.value
                    samples = recorded
                    take = measured
                    message = measured == nil ? L("うまく聞き取れませんでした。静かな所で、少し大きな声ではっきり言ってみてください。") : nil
                }
            }
        }
    }

    private func save() {
        guard let current, let take, let range, consent,
              let encoded = try? JSONEncoder().encode(take),
              let takeJSON = try? JSONSerialization.jsonObject(with: encoded) else { return }
        busy = true
        var input: [String: Any] = [
            "speaker": code,
            "gender": gender,
            "headword": current.tones.headword,
            "range": ["low": range.low, "high": range.high],
            "take": takeJSON,
            "consent": true,
            "audio_wav_base64": AudioSamples.wav(samples).base64EncodedString(),
        ]
        if let z = current.zhuyin { input["zhuyin"] = z }
        if let p = current.tones.pattern { input["pattern"] = p }
        Task {
            defer { busy = false }
            do {
                _ = try await NativeAPI.call("adminSaveNativeProsody", input, timeout: 30)
                counts[current.tones.headword, default: 0] += 1
                NativeReferenceLoader.forget(current.tones.headword)
                Haptics.success()
                message = L("保存しました")
                self.take = nil
                samples = []
            } catch {
                message = L("保存できませんでした")
                Haptics.warning()
            }
        }
    }

    private func loadCounts() async {
        struct Answer: Decodable {
            struct Count: Decodable {
                let headword: String
                let speaker: String
                let count: Int
            }
            let counts: [Count]
        }
        guard codeValid, let answer = try? await NativeAPI.call("adminListNativeProsody", [:], as: Answer.self) else { return }
        var mine: [String: Int] = [:]
        for c in answer.counts where c.speaker == code { mine[c.headword, default: 0] += c.count }
        counts = mine
    }
}

/// A word to record and its reading.
struct NativePrompt: Identifiable {
    let tones: WordTones
    let zhuyin: String?
    let pinyin: String?
    var id: String { tones.headword }

    init(tones: WordTones, zhuyin: String?, pinyin: String?) {
        self.tones = tones
        self.zhuyin = zhuyin
        self.pinyin = pinyin
    }

    /// Every pair of the four tones, the neutral tone after each, the four tones alone, and a few longer words — common
    /// nouns, readings from the Ministry of Education's dictionary (Taiwan).
    static let bundled: [NativePrompt] = [
        ("書", "ㄕㄨ"), ("茶", "ㄔㄚˊ"), ("水", "ㄕㄨㄟˇ"), ("菜", "ㄘㄞˋ"), // l10n-ignore
        ("飛機", "ㄈㄟ ㄐㄧ"), ("中文", "ㄓㄨㄥ ㄨㄣˊ"), ("鉛筆", "ㄑㄧㄢ ㄅㄧˇ"), ("音樂", "ㄧㄣ ㄩㄝˋ"), // l10n-ignore
        ("時間", "ㄕˊ ㄐㄧㄢ"), ("銀行", "ㄧㄣˊ ㄏㄤˊ"), ("牛奶", "ㄋㄧㄡˊ ㄋㄞˇ"), ("學校", "ㄒㄩㄝˊ ㄒㄧㄠˋ"), // l10n-ignore
        ("老師", "ㄌㄠˇ ㄕ"), ("小孩", "ㄒㄧㄠˇ ㄏㄞˊ"), ("雨傘", "ㄩˇ ㄙㄢˇ"), ("考試", "ㄎㄠˇ ㄕˋ"), // l10n-ignore
        ("麵包", "ㄇㄧㄢˋ ㄅㄠ"), ("地圖", "ㄉㄧˋ ㄊㄨˊ"), ("電腦", "ㄉㄧㄢˋ ㄋㄠˇ"), ("電視", "ㄉㄧㄢˋ ㄕˋ"), // l10n-ignore
        ("桌子", "ㄓㄨㄛ ˙ㄗ"), ("房子", "ㄈㄤˊ ˙ㄗ"), ("椅子", "ㄧˇ ˙ㄗ"), ("筷子", "ㄎㄨㄞˋ ˙ㄗ"), // l10n-ignore
        ("捷運站", "ㄐㄧㄝˊ ㄩㄣˋ ㄓㄢˋ"), ("珍珠奶茶", "ㄓㄣ ㄓㄨ ㄋㄞˇ ㄔㄚˊ"), // l10n-ignore
        ("便利商店", "ㄅㄧㄢˋ ㄌㄧˋ ㄕㄤ ㄉㄧㄢˋ"), // l10n-ignore
    ].compactMap { pair in
        WordTones.make(headword: pair.0, zhuyin: pair.1, pinyin: nil).map { NativePrompt(tones: $0, zhuyin: pair.1, pinyin: nil) }
    }
}

/// Each native speaker's range on the developer's phone, by their code.
@MainActor
enum NativeSpeakerRanges {
    private static let key = "pron.native.ranges"

    static func all() -> [String: SpeakerRange] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode([String: SpeakerRange].self, from: data) else { return [:] }
        return saved
    }

    static func save(_ range: SpeakerRange, for code: String) {
        var saved = all()
        saved[code] = range
        if let data = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(data, forKey: key) }
    }
}
