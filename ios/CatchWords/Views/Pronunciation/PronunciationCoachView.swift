import SwiftUI
import UIKit

/// 発音チェック (docs/pronunciation-coach.md). The learner says the word; the app measures pitch, length and loudness on
/// the phone and compares each syllable with the natives' range on the learner's own scale. One score, the three parts,
/// and the one thing to fix first.
struct PronunciationCoachView: View {
    let word: WordTones
    let zhuyin: String?
    let pinyin: String?
    let language: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appReduceMotion) private var reduceMotion
    @State private var recorder = VoiceRecorder()
    @State private var range: SpeakerRange?
    @State private var measuring = false
    @State private var reference: NativeReference?
    @State private var referenceState: ReferenceState = .loading
    @State private var result: CoachResult?
    @State private var analysing = false
    @State private var problem: Problem?
    @State private var history: [PronunciationHistory.Attempt] = []

    enum ReferenceState { case loading, ready, failed }
    enum Problem: Equatable { case micDenied, noInput, unheard }

    struct CoachResult: Equatable {
        let take: [NormalizedSyllable]
        let score: ProsodyScore
    }

    init(word: WordTones, zhuyin: String?, pinyin: String?, language: String?) {
        self.word = word
        self.zhuyin = zhuyin
        self.pinyin = pinyin
        self.language = language
        _range = State(initialValue: LearnerVoiceRange.current)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    wordCard
                    if range == nil || measuring {
                        VoiceRangeCard(recorder: recorder, hasRange: range != nil) { measured in
                            LearnerVoiceRange.save(measured)
                            withAnimation(.easeOut(duration: 0.25)) {
                                range = measured
                                measuring = false
                            }
                        } onCancel: {
                            measuring = false
                        }
                    } else {
                        chartCard
                        if let result { resultCard(result) }
                        if let problem { problemCard(problem) }
                        footer
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            if range != nil, !measuring { micBar }
        }
        .task {
            history = PronunciationHistory.attempts(word.headword)
            await loadReference()
        }
        .onDisappear { recorder.cancel() }
    }

    // MARK: - Parts

    private var header: some View {
        HStack {
            Text(L("発音チェック"))
                .scaledFont(size: 17, weight: .bold)
                .foregroundStyle(Theme.foreground)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                    .frame(width: 44, height: 44)
                    .background(Theme.card, in: Circle())
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .accessibilityLabel(L("閉じる"))
            .accessibilityIdentifier("pron.close")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private var wordCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .hanCenter, spacing: 10) {
                ZhuyinWordView(headword: word.headword, zhuyin: zhuyin, size: 36, weight: .heavy,
                               pinyin: pinyin, language: language)
                Spacer(minLength: 8)
                DetailSpeakButton(text: word.headword, style: .hero)
            }
            sourceLine
        }
        .coachCard()
    }

    @ViewBuilder
    private var sourceLine: some View {
        HStack(alignment: .top, spacing: 6) {
            switch referenceState {
            case .loading:
                ProgressView().controlSize(.mini)
                Text(L("手本の音を分析しています…"))
            case .failed:
                Image(systemName: "exclamationmark.triangle")
                Text(L("手本の音を読み込めませんでした。通信を確かめて、もう一度開いてください。"))
            case .ready:
                switch reference?.source ?? .aiVoice {
                case .natives(let speakers, let recordings, true):
                    Image(systemName: "person.2.wave.2")
                    Text(L("台湾の人 \(speakers) 人の録音（\(recordings) 回）から作った範囲と比べます"))
                case .natives(let speakers, _, false):
                    Image(systemName: "person.2.wave.2")
                    Text(L("同じ声調の単語を台湾の人 \(speakers) 人が読んだ録音から作った範囲と比べます"))
                case .aiVoice:
                    Image(systemName: "waveform")
                    Text(L("今はアプリの AI 音声（台湾の発音）を分析した仮の範囲と比べます。ネイティブの録音が集まると置き換わります。"))
                }
            }
        }
        .scaledFont(size: 12)
        .foregroundStyle(Theme.muted)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProsodyChartView(
                syllables: word.syllables,
                band: reference?.band,
                take: result?.take,
                totals: result?.score.syllables.map(\.total),
                live: recorder.phase == .recording ? recorder.live.map { $0.map { range?.level($0) ?? 3 } } : nil
            )
            HStack(spacing: 14) {
                legend(color: Theme.primary.opacity(0.25), text: L("ネイティブの範囲"))
                legend(color: result == nil ? Theme.primaryInk : Theme.ok, text: L("あなたの声"))
            }
            Text(L("1 はあなたの一番低い声、5 は一番高い声です。声の高さが違う人どうしも、同じ目盛りで比べます。"))
                .scaledFont(size: 11)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            if let result, let band = reference?.band, word.syllables.count > 1 {
                Divider().overlay(Theme.border)
                Text(L("長さ"))
                    .scaledFont(size: 13, weight: .semibold)
                    .foregroundStyle(Theme.foreground)
                TimingBarsView(syllables: word.syllables, band: band, take: result.take, score: result.score)
            }
        }
        .coachCard()
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 16, height: 8)
            Text(text).scaledFont(size: 12, weight: .medium).foregroundStyle(Theme.muted)
        }
    }

    private func resultCard(_ result: CoachResult) -> some View {
        let score = result.score
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(verbatim: "\(score.total)")
                    .scaledFont(size: 46, weight: .heavy, monospacedDigit: true)
                    .foregroundStyle(ProsodyChartView.color(score.total))
                VStack(alignment: .leading, spacing: 2) {
                    Text(verdict(score.total))
                        .scaledFont(size: 16, weight: .bold)
                        .foregroundStyle(Theme.foreground)
                    if let previous = history.dropLast().last {
                        Text(L("前回 \(previous.score) 点"))
                            .scaledFont(size: 12)
                            .foregroundStyle(Theme.muted)
                    }
                }
                Spacer(minLength: 0)
            }
            VStack(spacing: 8) {
                meter(L("高さ"), score.pitch)
                meter(L("長さ"), score.length)
                meter(L("強さ"), score.loudness)
            }
            syllableChips(score)
            adviceLine(score.advice)
            if history.count >= 2 { trend }
        }
        .coachCard()
    }

    private func verdict(_ total: Int) -> String {
        if total >= ProsodyScore.good { return L("ネイティブの範囲です") }
        if total >= ProsodyScore.close { return L("あと少しです") }
        return L("手本を聞いて、もう一度")
    }

    private func meter(_ title: String, _ value: Int) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .scaledFont(size: 13, weight: .semibold)
                .foregroundStyle(Theme.foreground)
                .frame(width: 44, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.secondary)
                    Capsule().fill(ProsodyChartView.color(value))
                        .frame(width: max(8, geo.size.width * CGFloat(value) / 100))
                }
            }
            .frame(height: 8)
            Text(verbatim: "\(value)")
                .scaledFont(size: 13, weight: .bold, monospacedDigit: true)
                .foregroundStyle(Theme.foreground)
                .frame(width: 32, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func syllableChips(_ score: ProsodyScore) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(word.syllables.enumerated()), id: \.offset) { i, s in
                let total = score.syllables[safe: i]?.total ?? 0
                VStack(spacing: 2) {
                    Text(verbatim: s.char).scaledFont(size: 18, weight: .bold).foregroundStyle(Theme.foreground)
                    Text(verbatim: s.pinyin).scaledFont(size: 11).foregroundStyle(Theme.muted)
                    Image(systemName: total >= ProsodyScore.good ? "checkmark.circle.fill"
                          : total >= ProsodyScore.close ? "exclamationmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ProsodyChartView.color(total))
                }
                .frame(minWidth: 52)
                .padding(.vertical, 8)
                .background(ProsodyChartView.color(total).opacity(0.1), in: .rect(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func adviceLine(_ advice: ProsodyScore.Advice) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: advice == .great ? "sparkles" : "lightbulb")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.primaryInk)
            Text(adviceText(advice))
                .scaledFont(size: 15, weight: .semibold)
                .foregroundStyle(Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.inset, in: .rect(cornerRadius: 14, style: .continuous))
    }

    private func adviceText(_ advice: ProsodyScore.Advice) -> String {
        let s = advice.syllable.map { word.label($0) } ?? ""
        switch advice {
        case .great: return L("どの音節もネイティブの範囲に入っています。この調子！")
        case .higher: return L("「\(s)」を、もっと高い声で言いましょう")
        case .lower: return L("「\(s)」を、もっと低い声で言いましょう")
        case .riseMore: return L("「\(s)」は、最後までしっかり上げましょう")
        case .fallMore: return L("「\(s)」は、高い所から一気に下げましょう")
        case .keepLevel: return L("「\(s)」は、高さを変えずにまっすぐ伸ばしましょう")
        case .followMovement: return L("「\(s)」の高さの動きを、青い帯に合わせましょう")
        case .longer: return L("「\(s)」を、もう少し長く伸ばしましょう")
        case .shorter: return L("「\(s)」を、もう少し短く言いましょう")
        case .stronger: return L("「\(s)」を、もう少し強く言いましょう")
        case .softer: return L("「\(s)」を、軽く弱めに言いましょう")
        case .followStress: return L("「\(s)」の声の強さの山を、手本に合わせましょう")
        }
    }

    /// The last tries' scores, oldest first.
    private var trend: some View {
        let recent = Array(history.suffix(8))
        return HStack(spacing: 6) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.muted)
            Text(recent.map { "\($0.score)" }.joined(separator: " → "))
                .scaledFont(size: 12, weight: .medium, monospacedDigit: true)
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityLabel(L("これまでの点数"))
    }

    private func problemCard(_ problem: Problem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: problem == .micDenied ? "mic.slash" : "ear")
                    .foregroundStyle(Theme.destructive)
                Text(problemText(problem))
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if problem == .micDenied {
                Button(L("設定を開く")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .scaledFont(size: 14, weight: .semibold)
            }
        }
        .coachCard()
    }

    private func problemText(_ problem: Problem) -> String {
        switch problem {
        case .micDenied: L("マイクの使用が許可されていません。設定でマイクをオンにすると、発音をチェックできます。")
        case .noInput: L("マイクを使えませんでした。ほかのアプリが使っていないか確かめてください。")
        case .unheard: L("うまく聞き取れませんでした。静かな所で、少し大きな声ではっきり言ってみてください。")
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("声は端末の中だけで分析し、保存も送信もしません"), systemImage: "lock")
                .scaledFont(size: 12)
                .foregroundStyle(Theme.muted)
            Button {
                measuring = true
            } label: {
                Label(L("声の高さをはかり直す"), systemImage: "slider.vertical.3")
                    .scaledFont(size: 13, weight: .semibold)
            }
            .accessibilityIdentifier("pron.remeasure")
        }
        .padding(.horizontal, 4)
    }

    private var micBar: some View {
        let recording = recorder.phase == .recording
        return VStack(spacing: 8) {
            Button(action: toggle) {
                ZStack {
                    Circle()
                        .stroke(Theme.primary.opacity(0.25), lineWidth: 6)
                        .scaleEffect(recording && !reduceMotion ? 1 + 0.25 * recorder.meter : 1)
                        .animation(.easeOut(duration: 0.1), value: recorder.meter)
                    Circle().fill(recording ? Theme.destructive : Theme.primary)
                    if analysing {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: recording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 76, height: 76)
                .shadow(color: Theme.primary.opacity(0.3), radius: 10, y: 4)
            }
            .buttonStyle(PressableStyle(scale: 0.92))
            .disabled(analysing || referenceState != .ready)
            .accessibilityLabel(recording ? L("止める") : L("話す"))
            .accessibilityIdentifier("pron.mic")
            Text(recording ? L("話し終わると自動で止まります") : analysing ? L("分析しています…") : L("タップして、単語を言ってみましょう"))
                .scaledFont(size: 13, weight: .medium)
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Theme.background.opacity(0.96))
    }

    // MARK: - Actions

    private func loadReference() async {
        referenceState = .loading
        if let found = await NativeReferenceLoader.load(word) {
            reference = found
            referenceState = .ready
        } else {
            referenceState = .failed
        }
    }

    private func toggle() {
        if recorder.phase == .recording {
            recorder.stop()
            return
        }
        Haptics.selection()
        problem = nil
        Task {
            guard await VoiceRecorder.requestPermission() else {
                problem = .micDenied
                return
            }
            do {
                try recorder.start { samples in analyse(samples) }
            } catch {
                problem = .noInput
            }
        }
    }

    private func analyse(_ samples: [Float]) {
        guard let range, let band = reference?.band else { return }
        let n = word.syllables.count
        analysing = true
        Task {
            let take = await Task.detached(priority: .userInitiated) {
                ProsodyAnalyzer.analyze(samples, syllables: n)
            }.value
            analysing = false
            guard let take, let score = ProsodyScore.score(NormalizedSyllable.make(take, range: range), against: band) else {
                problem = .unheard
                Haptics.warning()
                return
            }
            PronunciationHistory.add(word.headword, score: score.total)
            history = PronunciationHistory.attempts(word.headword)
            withAnimation(.easeOut(duration: 0.3)) {
                result = CoachResult(take: NormalizedSyllable.make(take, range: range), score: score)
            }
            if score.total >= ProsodyScore.good { Haptics.success() } else { Haptics.selection() }
        }
    }
}

// MARK: - Measuring the learner's range

/// The first step (and 「声の高さをはかり直す」): a glide from the lowest to the highest comfortable 「あー」.
struct VoiceRangeCard: View {
    let recorder: VoiceRecorder
    let hasRange: Bool
    let onMeasured: (SpeakerRange) -> Void
    let onCancel: () -> Void

    @State private var measured: SpeakerRange?
    @State private var failed = false
    @State private var micDenied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("まず、あなたの声の高さをはかります"))
                .scaledFont(size: 17, weight: .bold)
                .foregroundStyle(Theme.foreground)
            Text(L("人によって声の高さは違います。あなたの一番低い声から一番高い声までを 1〜5 の目盛りにして、ネイティブと同じ物差しで比べます。"))
                .scaledFont(size: 13)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Label(L("ボタンを押したら、一番低い声から一番高い声まで、なめらかに「あー」と上げてください（3 秒ほど）。"),
                  systemImage: "arrow.up.right")
                .scaledFont(size: 14, weight: .semibold)
                .foregroundStyle(Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)

            liveGlide

            if let measured {
                Text(L("あなたの声：\(Int(measured.lowHz.rounded())) Hz 〜 \(Int(measured.highHz.rounded())) Hz"))
                    .scaledFont(size: 14, weight: .bold, monospacedDigit: true)
                    .foregroundStyle(Theme.primaryInk)
                Button {
                    onMeasured(measured)
                } label: {
                    Text(L("この範囲で始める"))
                        .scaledFont(size: 16, weight: .bold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Theme.primary, in: Capsule())
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("pron.rangeOK")
            }
            if failed {
                Text(L("うまくはかれませんでした。もう少し大きな声で、低い声から高い声までしっかり上げてください。"))
                    .scaledFont(size: 13, weight: .semibold)
                    .foregroundStyle(Theme.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if micDenied {
                Text(L("マイクの使用が許可されていません。設定でマイクをオンにすると、発音をチェックできます。"))
                    .scaledFont(size: 13, weight: .semibold)
                    .foregroundStyle(Theme.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                Button(action: measure) {
                    Label(recorder.phase == .recording ? L("止める") : (measured == nil ? L("はかる") : L("もう一度はかる")),
                          systemImage: recorder.phase == .recording ? "stop.fill" : "mic.fill")
                        .scaledFont(size: 15, weight: .bold)
                        .foregroundStyle(measured == nil ? .white : Theme.primaryInk)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(measured == nil ? Theme.primary : Theme.primary.opacity(0.12), in: Capsule())
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("pron.measure")
                if hasRange {
                    Button(L("やめる"), action: onCancel)
                        .scaledFont(size: 15, weight: .semibold)
                }
            }
            Label(L("声は端末の中だけで分析し、保存も送信もしません"), systemImage: "lock")
                .scaledFont(size: 12)
                .foregroundStyle(Theme.muted)
        }
        .coachCard()
    }

    /// The glide drawn as it is sung (semitones, scaled to what has been heard so far).
    private var liveGlide: some View {
        let values = recorder.live
        let voiced = values.compactMap { $0 }
        let lo = (voiced.min() ?? 0) - 1, hi = (voiced.max() ?? 1) + 1
        return Canvas { ctx, size in
            var segment: [CGPoint] = []
            let window = max(300, values.count)
            func flush() {
                if segment.count > 1 {
                    ctx.stroke(ProsodyChartView.smooth(segment), with: .color(Theme.primaryInk),
                               style: StrokeStyle(lineWidth: 3, lineCap: .round))
                }
                segment.removeAll()
            }
            for (i, v) in values.enumerated() {
                guard let v else { flush(); continue }
                let x = size.width * CGFloat(i) / CGFloat(window - 1)
                let y = size.height - size.height * CGFloat((v - lo) / max(hi - lo, 1))
                segment.append(CGPoint(x: x, y: y))
            }
            flush()
        }
        .frame(height: 70)
        .background(Theme.secondary.opacity(0.6), in: .rect(cornerRadius: 12, style: .continuous))
        .accessibilityHidden(true)
    }

    private func measure() {
        if recorder.phase == .recording {
            recorder.stop()
            return
        }
        failed = false
        micDenied = false
        Task {
            guard await VoiceRecorder.requestPermission() else {
                micDenied = true
                return
            }
            recorder.maxSeconds = 6
            recorder.silenceToStop = 0.6
            try? recorder.start { samples in
                Task {
                    let range = await Task.detached(priority: .userInitiated) {
                        SpeakerRange.fromGlide(ProsodyAnalyzer.track(PitchTracker.frames(samples)).compactMap { $0 })
                    }.value
                    recorder.maxSeconds = 6
                    recorder.silenceToStop = 0.7
                    withAnimation(.easeOut(duration: 0.2)) {
                        measured = range
                        failed = range == nil
                    }
                    if range != nil { Haptics.success() } else { Haptics.warning() }
                }
            }
        }
    }
}

// MARK: - Style

extension View {
    /// The coach's white cards (the same as the word page's).
    func coachCard() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: .rect(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}
