import Foundation
import CoreGraphics

nonisolated struct AuthSession: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let userId: String
    let email: String?
}

/// Row of the shared `words` table (same schema as the web app). `words.level` (the word's own exam level) is
/// not decoded: per-word exam levels are gone on iOS (owner 2026-10-03). The learner's level lives in the profile.
nonisolated struct Word: Codable, Sendable, Hashable {
    let id: String
    let headword: String
    let readingZhuyin: String?
    let pinyin: String?
    var meaningJa: String
    let partOfSpeech: String?
    /// `var`: a word just saved keeps the category it landed in until its landing is over (`DexStore.settleLanding`).
    var categoryKey: String?
    let exampleSentence: String?
    var exampleTranslation: String?
    var extras: WordExtras?
    /// `words.language` (null on old rows = 台湾華語).
    let language: String?

    enum CodingKeys: String, CodingKey {
        case id, headword, pinyin, extras, language
        case readingZhuyin = "reading_zhuyin"
        case meaningJa = "meaning_ja"
        case partOfSpeech = "part_of_speech"
        case categoryKey = "category_key"
        case exampleSentence = "example_sentence"
        case exampleTranslation = "example_translation"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        headword = try c.decode(String.self, forKey: .headword)
        readingZhuyin = try? c.decodeIfPresent(String.self, forKey: .readingZhuyin)
        pinyin = try? c.decodeIfPresent(String.self, forKey: .pinyin)
        meaningJa = (try? c.decodeIfPresent(String.self, forKey: .meaningJa)) ?? ""
        partOfSpeech = try? c.decodeIfPresent(String.self, forKey: .partOfSpeech)
        categoryKey = try? c.decodeIfPresent(String.self, forKey: .categoryKey)
        exampleSentence = try? c.decodeIfPresent(String.self, forKey: .exampleSentence)
        exampleTranslation = try? c.decodeIfPresent(String.self, forKey: .exampleTranslation)
        extras = try? c.decodeIfPresent(WordExtras.self, forKey: .extras)
        language = try? c.decodeIfPresent(String.self, forKey: .language)
    }

    /// Same rule as the web's `matchesTargetLanguage` (language-filter.ts): an empty language is 台湾華語.
    func matches(_ target: String) -> Bool {
        let raw = (language ?? "").trimmingCharacters(in: .whitespaces)
        return raw.isEmpty ? target == "zh-TW" : raw == target
    }
}

/// Subset of `words.extras` the native card draws. Every field is optional/lenient,
/// mirroring the web's `ExtrasSchema` with `.catch()` defaults.
nonisolated struct WordExtras: Codable, Sendable, Hashable {
    var frequencyLevel: Int?
    var registerScale: Int?
    var registerTag: String?
    var sceneWeights: [String: Double]?
    var usageChunks: [UsageChunk]?
    var usageContext: String?
    var mnemonic: String?
    var measureWords: [MeasureWord]?
    var relatedWords: [RelatedWord]?
    var synonyms: [String]?
    var antonyms: [String]?
    var taiwanNote: String?
    var examplesExtra: [ExampleExtra]?
    /// The scene / feeling the main example is said in (server 2026-10-14; empty on older cards).
    var exampleScene: String?
    /// The sentence `exampleScene` was written for (server PR #182, 2026-10-15; absent on older cards). The label is
    /// shown only over that very sentence (`shownExampleScene(for:)`).
    var exampleSceneFor: String?
    /// The version of the way the examples were written (server PR #182; nil on older cards).
    var exampleV: Int?
    /// How many usage patterns the word has (1–4; nil on older cards). 1 = it is used in one situation only: no
    /// 「追加の例文」, and that is complete (never filled in).
    var examplePatternCount: Int?
    var pronunciationTips: String?
    var studyTips: String?
    /// 語源・部首 is no longer shown (owner 2026-10-15) and no longer written by the server; an older card's text is still
    /// read (and its `etymology_diagram` simply skipped), so nothing about an old payload stops it from decoding.
    var etymology: String?
    var radicals: String?
    var trivia: String?
    var usageNote: String?
    var synonymDiff: String?
    /// Which display language these notes were written in (`explain_lang`; empty on old rows).
    var explainLang: String?
    // English cards (target-profile.ts EN sections).
    var forms: WordForms?
    var countability: Countability?
    var stress: StressInfo?
    var phrasalVerbs: [PhrasalVerb]?
    var cultureNote: String?
    var etymologyRelatives: [NotedWord]?
    // Japanese cards (target-profile.ts JA sections).
    var kanjiBreakdown: [KanjiPart]?
    var pitchAccent: String?
    var conjugation: [ConjugationRow]?
    var politeness: String?
    var counters: [CounterWord]?
    var wordOrigin: String?
    var japanNote: String?
    /// English search words for the word's picture, written with the card (`image_query`; empty on old cards).
    var imageQuery: String?
    /// English words that mean a wrong picture if they show (`image_avoid`: 蓮藕 → flower, pond).
    var imageAvoid: [String]?

    enum CodingKeys: String, CodingKey {
        case mnemonic, synonyms, antonyms, etymology, radicals, trivia
        case explainLang = "explain_lang"
        case forms, countability, stress, conjugation, politeness, counters
        case phrasalVerbs = "phrasal_verbs"
        case cultureNote = "culture_note"
        case etymologyRelatives = "etymology_relatives"
        case kanjiBreakdown = "kanji_breakdown"
        case pitchAccent = "pitch_accent"
        case wordOrigin = "word_origin"
        case japanNote = "japan_note"
        case taiwanNote = "taiwan_note"
        case examplesExtra = "examples_extra"
        case exampleScene = "example_scene"
        case exampleSceneFor = "example_scene_for"
        case exampleV = "example_v"
        case examplePatternCount = "example_pattern_count"
        case pronunciationTips = "pronunciation_tips"
        case studyTips = "study_tips"
        case usageNote = "usage_note"
        case synonymDiff = "synonym_diff"
        case relatedWords = "related_words"
        case frequencyLevel = "frequency_level"
        case registerScale = "register_scale"
        case registerTag = "register_tag"
        case sceneWeights = "scene_weights"
        case usageChunks = "usage_chunks"
        case usageContext = "usage_context"
        case measureWords = "measure_words"
        case imageQuery = "image_query"
        case imageAvoid = "image_avoid"
    }

    init(frequencyLevel: Int? = nil, registerScale: Int? = nil, registerTag: String? = nil,
         sceneWeights: [String: Double]? = nil, usageChunks: [UsageChunk]? = nil,
         usageContext: String? = nil, mnemonic: String? = nil, measureWords: [MeasureWord]? = nil) {
        self.frequencyLevel = frequencyLevel
        self.registerScale = registerScale
        self.registerTag = registerTag
        self.sceneWeights = sceneWeights
        self.usageChunks = usageChunks
        self.usageContext = usageContext
        self.mnemonic = mnemonic
        self.measureWords = measureWords
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        frequencyLevel = (try? c.decodeIfPresent(Int.self, forKey: .frequencyLevel)).flatMap { $0 }
        registerScale = (try? c.decodeIfPresent(Int.self, forKey: .registerScale)).flatMap { $0 }
        registerTag = (try? c.decodeIfPresent(String.self, forKey: .registerTag)).flatMap { $0 }
        sceneWeights = (try? c.decodeIfPresent([String: Double].self, forKey: .sceneWeights)).flatMap { $0 }
        usageChunks = (try? c.decodeIfPresent([UsageChunk].self, forKey: .usageChunks)).flatMap { $0 }
        usageContext = (try? c.decodeIfPresent(String.self, forKey: .usageContext)).flatMap { $0 }
        mnemonic = (try? c.decodeIfPresent(String.self, forKey: .mnemonic)).flatMap { $0 }
        measureWords = (try? c.decodeIfPresent([MeasureWord].self, forKey: .measureWords)).flatMap { $0 }
        relatedWords = (try? c.decodeIfPresent([RelatedWord].self, forKey: .relatedWords)).flatMap { $0 }
        synonyms = (try? c.decodeIfPresent([String].self, forKey: .synonyms)).flatMap { $0 }
        antonyms = (try? c.decodeIfPresent([String].self, forKey: .antonyms)).flatMap { $0 }
        taiwanNote = (try? c.decodeIfPresent(String.self, forKey: .taiwanNote)).flatMap { $0 }
        examplesExtra = (try? c.decodeIfPresent([ExampleExtra].self, forKey: .examplesExtra)).flatMap { $0 }
        exampleScene = (try? c.decodeIfPresent(String.self, forKey: .exampleScene)).flatMap { $0 }
        exampleSceneFor = (try? c.decodeIfPresent(String.self, forKey: .exampleSceneFor)).flatMap { $0 }
        exampleV = Self.lenientInt(c, .exampleV)
        examplePatternCount = Self.lenientInt(c, .examplePatternCount)
        pronunciationTips = (try? c.decodeIfPresent(String.self, forKey: .pronunciationTips)).flatMap { $0 }
        studyTips = (try? c.decodeIfPresent(String.self, forKey: .studyTips)).flatMap { $0 }
        etymology = (try? c.decodeIfPresent(String.self, forKey: .etymology)).flatMap { $0 }
        radicals = (try? c.decodeIfPresent(String.self, forKey: .radicals)).flatMap { $0 }
        trivia = (try? c.decodeIfPresent(String.self, forKey: .trivia)).flatMap { $0 }
        usageNote = (try? c.decodeIfPresent(String.self, forKey: .usageNote)).flatMap { $0 }
        synonymDiff = (try? c.decodeIfPresent(String.self, forKey: .synonymDiff)).flatMap { $0 }
        explainLang = (try? c.decodeIfPresent(String.self, forKey: .explainLang)).flatMap { $0 }
        forms = (try? c.decodeIfPresent(WordForms.self, forKey: .forms)).flatMap { $0 }
        countability = (try? c.decodeIfPresent(Countability.self, forKey: .countability)).flatMap { $0 }
        stress = (try? c.decodeIfPresent(StressInfo.self, forKey: .stress)).flatMap { $0 }
        phrasalVerbs = (try? c.decodeIfPresent([PhrasalVerb].self, forKey: .phrasalVerbs)).flatMap { $0 }
        cultureNote = (try? c.decodeIfPresent(String.self, forKey: .cultureNote)).flatMap { $0 }
        etymologyRelatives = (try? c.decodeIfPresent([NotedWord].self, forKey: .etymologyRelatives)).flatMap { $0 }
        kanjiBreakdown = (try? c.decodeIfPresent([KanjiPart].self, forKey: .kanjiBreakdown)).flatMap { $0 }
        pitchAccent = (try? c.decodeIfPresent(String.self, forKey: .pitchAccent)).flatMap { $0 }
        conjugation = (try? c.decodeIfPresent([ConjugationRow].self, forKey: .conjugation)).flatMap { $0 }
        politeness = (try? c.decodeIfPresent(String.self, forKey: .politeness)).flatMap { $0 }
        counters = (try? c.decodeIfPresent([CounterWord].self, forKey: .counters)).flatMap { $0 }
        wordOrigin = (try? c.decodeIfPresent(String.self, forKey: .wordOrigin)).flatMap { $0 }
        japanNote = (try? c.decodeIfPresent(String.self, forKey: .japanNote)).flatMap { $0 }
        imageQuery = (try? c.decodeIfPresent(String.self, forKey: .imageQuery)).flatMap { $0 }
        imageAvoid = (try? c.decodeIfPresent([String].self, forKey: .imageAvoid)).flatMap { $0 }
    }

    /// An optional whole number however it comes (1, 1.0, "1"); anything else or null is nil.
    private static func lenientInt(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int? {
        if let i = (try? c.decodeIfPresent(Int.self, forKey: key)).flatMap({ $0 }) { return i }
        if let d = (try? c.decodeIfPresent(Double.self, forKey: key)).flatMap({ $0 }), d.isFinite, d == d.rounded() { return Int(d) }
        if let t = (try? c.decodeIfPresent(String.self, forKey: key)).flatMap({ $0 }) { return Int(t.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    /// The scene label to draw over `sentence` (the example on screen): only when it was written for that very sentence
    /// (`example_scene_for`, compared without spaces and punctuation). Older labels carry no such mark and could belong
    /// to another sentence (眼鏡: 「友達が眼鏡をしていないことに気づいたとき」 over 我戴眼鏡。), so they are not shown.
    func shownExampleScene(for sentence: String) -> String? {
        let scene = (exampleScene ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !scene.isEmpty else { return nil }
        let written = Self.sceneMatchKey(exampleSceneFor ?? "")
        guard !written.isEmpty, written == Self.sceneMatchKey(sentence) else { return nil }
        return scene
    }

    /// A sentence without its spaces and punctuation, full-width and half-width alike (「我戴眼鏡。」 = 「我戴眼鏡」 =
    /// "我 戴 眼鏡!" = 「我戴眼鏡！」; ＡＢＣ = ABC): compared after NFKC, which folds the full-width forms.
    static func sceneMatchKey(_ s: String) -> String {
        let folded = s.precomposedStringWithCompatibilityMapping
        return String(String.UnicodeScalarView(folded.unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.punctuationCharacters.contains($0)
                && !CharacterSet.symbols.contains($0)
        }))
    }

    /// 「追加の例文」 is complete as it is when the word has a single usage pattern (no other examples to write): the word
    /// page then never asks the server to fill it (`regenerateCardSection` only_if_empty) and shows no empty section.
    var examplesExtraComplete: Bool { examplePatternCount == 1 }

    /// related_words, falling back to the legacy synonyms/antonyms string lists (card-sections.ts).
    var allRelated: [RelatedWord] {
        if let r = relatedWords?.filter({ !$0.word.isEmpty }), !r.isEmpty { return r }
        return (synonyms ?? []).map { RelatedWord(word: $0, kind: "syn") } + (antonyms ?? []).map { RelatedWord(word: $0, kind: "ant") }
    }

    /// `register_scale` first, else map the legacy free-text tag (register-scale.ts).
    var resolvedRegister: Int? {
        if let registerScale { return max(-2, min(2, registerScale)) }
        guard let tag = registerTag, !tag.isEmpty else { return nil }
        if tag.contains("口語") && tag.contains("書面") { return 0 }  // l10n-ignore (matching data)
        if tag.contains("口語") { return -1 }  // l10n-ignore (matching data)
        if tag.contains("書面") { return 1 }  // l10n-ignore (matching data)
        return nil
    }
}

// UsageChunk / ChunkPart / ChunkAlt live in Utilities/ChunkRules.swift with the rules that draw them.

/// extras.related_words entry (RelatedWordSchema): kind is syn / ant / rel.
nonisolated struct RelatedWord: Codable, Sendable, Hashable {
    var word: String
    var kind: String
    var note: String
    var reading: String

    init(word: String, kind: String, note: String = "", reading: String = "") {
        self.word = word
        self.kind = kind
        self.note = note
        self.reading = reading
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        word = (try? c.decode(String.self, forKey: .word)) ?? ""
        let k = (try? c.decode(String.self, forKey: .kind)) ?? "rel"
        kind = ["syn", "ant", "rel"].contains(k) ? k : "rel"
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
        reading = (try? c.decode(String.self, forKey: .reading)) ?? ""
    }
}

/// `examples_extra` item: sentence + translation + when you'd say it, and the sentence that label was written for
/// (`scene_for`, server 2026-10-15; absent on older items — then no label is shown, `shownScene`).
nonisolated struct ExampleExtra: Codable, Sendable, Hashable {
    var zh: String
    var ja: String
    var scene: String
    var sceneFor: String = ""

    enum CodingKeys: String, CodingKey {
        case zh, ja, scene
        case sceneFor = "scene_for"
    }

    init(zh: String, ja: String = "", scene: String = "", sceneFor: String = "") {
        self.zh = zh
        self.ja = ja
        self.scene = scene
        self.sceneFor = sceneFor
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        zh = (try? c.decode(String.self, forKey: .zh)) ?? ""
        ja = (try? c.decode(String.self, forKey: .ja)) ?? ""
        scene = (try? c.decode(String.self, forKey: .scene)) ?? ""
        sceneFor = (try? c.decode(String.self, forKey: .sceneFor)) ?? ""
    }

    /// The label over this sentence: only when it was written for this very sentence (spaces and punctuation aside),
    /// the rule of the main example (`WordExtras.shownExampleScene`).
    var shownScene: String? {
        let label = scene.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return nil }
        let written = WordExtras.sceneMatchKey(sceneFor)
        guard !written.isEmpty, written == WordExtras.sceneMatchKey(zh) else { return nil }
        return label
    }
}

/// One example in 「例文」: the main one or one of `examples_extra`, each its own usage pattern (owner 2026-10-15:
/// 「追加の例文」 is gone, every pattern's example is in 「例文」 with its short situation label above it).
nonisolated struct ExampleItem: Hashable, Sendable {
    let sentence: String
    let translation: String?
    let scene: String?

    /// Every example to show, the main one first. With one usage pattern (`example_pattern_count` 1) only the main
    /// example; an extra one not in the learning language, or the main sentence again, is left out.
    static func all(sentence: String?, translation: String?, extras: WordExtras?, target: String) -> [ExampleItem] {
        var out: [ExampleItem] = []
        var seen = Set<String>()
        let main = (sentence ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !main.isEmpty, main.isIn(target: target) {
            out.append(ExampleItem(sentence: main, translation: translation, scene: extras?.shownExampleScene(for: main)))
            seen.insert(WordExtras.sceneMatchKey(main))
        }
        guard extras?.examplesExtraComplete != true else { return out }
        for x in extras?.examplesExtra ?? [] {
            let zh = x.zh.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !zh.isEmpty, zh.isIn(target: target), seen.insert(WordExtras.sceneMatchKey(zh)).inserted else { continue }
            out.append(ExampleItem(sentence: zh, translation: x.ja.isEmpty ? nil : x.ja, scene: x.shownScene))
        }
        return out
    }

    /// Why each example shown without its scene label has none, for the developer log (owner 2026-10-15: an example with
    /// no matching label is still shown, and logged): no label at all (or one not in the reader's language), a label
    /// without the mark of the sentence it was written for (an older card), or a label written for another sentence.
    static func missingLabels(sentence: String?, extras: WordExtras?, target: String) -> [String] {
        let main = (sentence ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let version = extras?.exampleV.map { "example_v \($0)" } ?? "no example_v"
        return all(sentence: sentence, translation: nil, extras: extras, target: target).compactMap { ex in
            guard ex.scene == nil else { return nil }
            let label: String
            let written: String
            if !main.isEmpty, ex.sentence == main {
                label = extras?.exampleScene ?? ""
                written = extras?.exampleSceneFor ?? ""
            } else if let x = extras?.examplesExtra?.first(where: {
                WordExtras.sceneMatchKey($0.zh) == WordExtras.sceneMatchKey(ex.sentence)
            }) {
                label = x.scene
                written = x.sceneFor
            } else {
                label = ""
                written = ""
            }
            let why: String
            if label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                why = "no scene label"
            } else if written.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                why = "scene label without scene_for"
            } else {
                why = "scene label written for 「\(written)」"
            }
            return "「\(ex.sentence)」: \(why) (\(version))"
        }
    }
}

/// A lenient string field (missing or null → "").
private extension KeyedDecodingContainer {
    nonisolated func str(_ k: Key) -> String { ((try? decodeIfPresent(String.self, forKey: k)) ?? nil) ?? "" }
}

/// extras.forms (English inflections; from the dictionary).
nonisolated struct WordForms: Codable, Sendable, Hashable {
    var plural = "", past = "", pastParticiple = "", ing = "", third = "", comparative = "", superlative = ""
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        plural = c.str(.plural); past = c.str(.past); pastParticiple = c.str(.pastParticiple); ing = c.str(.ing)
        third = c.str(.third); comparative = c.str(.comparative); superlative = c.str(.superlative)
    }
    var isEmpty: Bool { [plural, past, pastParticiple, ing, third, comparative, superlative].allSatisfy(\.isEmpty) }
}

/// extras.countability: countable / uncountable / both, the article and a note.
nonisolated struct Countability: Codable, Sendable, Hashable {
    var kind = "countable", article = "", note = ""
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = c.str(.kind).isEmpty ? "countable" : c.str(.kind); article = c.str(.article); note = c.str(.note)
    }
}

/// extras.stress: syllables and which one is stressed.
nonisolated struct StressInfo: Codable, Sendable, Hashable {
    var syllables: [String] = []
    var primary: Int?
    var secondary: Int?
    var note = ""
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        syllables = ((try? c.decodeIfPresent([String].self, forKey: .syllables)) ?? nil) ?? []
        primary = (try? c.decodeIfPresent(Int.self, forKey: .primary)) ?? nil
        secondary = (try? c.decodeIfPresent(Int.self, forKey: .secondary)) ?? nil
        note = c.str(.note)
    }
}

nonisolated struct PhrasalVerb: Codable, Sendable, Hashable {
    var phrase = "", meaning = "", example = ""
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        phrase = c.str(.phrase); meaning = c.str(.meaning); example = c.str(.example)
    }
}

/// A related word with a short note (etymology relatives).
nonisolated struct NotedWord: Codable, Sendable, Hashable {
    var word = "", note = ""
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        word = c.str(.word); note = c.str(.note)
    }
}

/// extras.kanji_breakdown: one kanji, its meaning, on (katakana) and kun (hiragana) readings.
nonisolated struct KanjiPart: Codable, Sendable, Hashable {
    var kanji = "", meaning = "", on = "", kun = ""
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kanji = c.str(.kanji); meaning = c.str(.meaning); on = c.str(.on); kun = c.str(.kun)
    }
}

/// extras.conjugation: the form's name (reader's language) and the Japanese form.
nonisolated struct ConjugationRow: Codable, Sendable, Hashable {
    var form = "", text = ""
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        form = c.str(.form); text = c.str(.text)
    }
}

/// extras.counters: 一本 / いっぽん / when to use it.
nonisolated struct CounterWord: Codable, Sendable, Hashable {
    var word = "", reading = "", note = ""
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        word = c.str(.word); reading = c.str(.reading); note = c.str(.note)
    }
}

nonisolated struct MeasureWord: Codable, Sendable, Hashable {
    var word: String
    var zhuyin: String?
    var note: String?
}

/// Row of `stickers` with the joined word.
nonisolated struct Sticker: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let wordId: String
    let objectImageUrl: String?
    var cutoutImageUrl: String?
    var selfieImageUrl: String?
    var caption: String?
    let locationName: String?
    let takenAt: Date
    let captureType: String?
    var word: Word?
    var lat: Double? = nil
    var lng: Double? = nil
    /// `stickers.shelf_key`, read as the server keeps it (the app no longer moves words or makes shelves).
    /// Only a built-in category key counts (`builtinShelfKey`); anything else falls back to the AI's category.
    var shelfKey: String? = nil
    /// The picture the learner chose for this word (`stickers.hero_role`: object / cutout / selfie).
    var heroRole: String? = nil
    /// Stand-in picture of a card caught without a photo (`stickers.placeholder_image_url`).
    var placeholderImageUrl: String? = nil
    /// Who made that stand-in picture (`stickers.placeholder_credit`): shown on it, as Unsplash asks.
    var placeholderCredit: PlaceholderCredit? = nil

    nonisolated struct PlaceholderCredit: Codable, Sendable, Hashable {
        var name: String?
        var link: String?
        var source: String?

        enum CodingKeys: String, CodingKey { case name, link, source }

        /// `placeholder_credit` is a free JSON column: anything but an object (a string, an array, numbers
        /// where text is expected) reads as "no credit" instead of failing the whole dex read.
        init(from decoder: Decoder) throws {
            guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
            name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? nil
            link = (try? c.decodeIfPresent(String.self, forKey: .link)) ?? nil
            source = (try? c.decodeIfPresent(String.self, forKey: .source)) ?? nil
        }
    }

    /// The learner took or chose a picture of their own (web sticker-photo.ts hasOwnPhoto).
    var hasOwnPhoto: Bool { objectImageUrl != nil || cutoutImageUrl != nil || selfieImageUrl != nil }

    enum CodingKeys: String, CodingKey {
        case id, caption, word, lat, lng
        case heroRole = "hero_role"
        case placeholderImageUrl = "placeholder_image_url"
        case placeholderCredit = "placeholder_credit"
        case wordId = "word_id"
        case shelfKey = "shelf_key"
        case objectImageUrl = "object_image_url"
        case cutoutImageUrl = "cutout_image_url"
        case selfieImageUrl = "selfie_image_url"
        case locationName = "location_name"
        case takenAt = "taken_at"
        case captureType = "capture_type"
    }

    /// The word's own picture (photo-surface.ts): the learner's choice for its page (`hero_role`, long-pressing the
    /// photo there), else the cut-out, else the original, else the stand-in. 設定 › ホームに表示する写真 is for the home
    /// album only (`homePath`, owner 2026-10-11); the dex, the word page and the review show the cut-out.
    var heroPath: String? {
        switch heroRole {
        case "object": objectImageUrl ?? cutoutImageUrl ?? placeholderImageUrl
        case "selfie": selfieImageUrl ?? cutoutImageUrl ?? objectImageUrl ?? placeholderImageUrl
        case "placeholder": placeholderImageUrl ?? cutoutImageUrl ?? objectImageUrl
        default: cutoutImageUrl ?? objectImageUrl ?? placeholderImageUrl
        }
    }

    /// 設定 › ホームに表示する写真 (`"object"` / `"cutout"` / `"selfie"`; never chosen = `"auto"` = the cut-out).
    static let homePhotoKey = "photo.pref"

    /// The picture the home album shows: the kind chosen in 設定 › ホームに表示する写真, each falling back to what the
    /// word has (owner 2026-10-11: 「ホームで表示する画像の種類は設定から元の画像か、切り抜きか、自撮りか選べるように」).
    var homePath: String? {
        switch UserDefaults.standard.string(forKey: Self.homePhotoKey) ?? "auto" {
        case "object": objectImageUrl ?? cutoutImageUrl ?? selfieImageUrl ?? placeholderImageUrl
        case "selfie": selfieImageUrl ?? cutoutImageUrl ?? objectImageUrl ?? placeholderImageUrl
        default: cutoutImageUrl ?? objectImageUrl ?? selfieImageUrl ?? placeholderImageUrl
        }
    }
    var room: Room { Category.room(for: categoryKey) }
    /// The word's category: a built-in key kept in `shelf_key` first, else the headword's rule (`CategoryRules`,
    /// web `wordCategoryKey`), else the AI's category.
    var categoryKey: String {
        builtinShelfKey ?? CategoryRules.normalize(headword: word?.headword, key: word?.categoryKey)
    }
    private var builtinShelfKey: String? { shelfKey.flatMap { Category.isBuiltin($0) ? $0 : nil } }
}

/// Row of `reviews` (SM-2 state) — read only here; the web app owns the schedule.
nonisolated struct ReviewState: Codable, Sendable, Hashable {
    var id: String?
    let stickerId: String
    var ease: Double
    var intervalDays: Int
    var repetitions: Int?
    var lastReviewedAt: Date?
    var dueAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, ease, repetitions
        case stickerId = "sticker_id"
        case intervalDays = "interval_days"
        case lastReviewedAt = "last_reviewed_at"
        case dueAt = "due_at"
    }
}

/// Row of `review_history` (forgetting-curve chart + review streak).
nonisolated struct ReviewHistoryRow: Codable, Sendable, Hashable {
    let reviewedAt: Date
    let score: Int?
    let intervalDaysAfter: Int?
    let easeAfter: Double?
    let stickerId: String?

    enum CodingKeys: String, CodingKey {
        case score
        case stickerId = "sticker_id"
        case reviewedAt = "reviewed_at"
        case intervalDaysAfter = "interval_days_after"
        case easeAfter = "ease_after"
    }

    /// Local row appended right after grading (so the overall line moves without a refetch).
    init?(stickerId: String, reviewedAt: Date, intervalDaysAfter: Int, easeAfter: Double) {
        self.stickerId = stickerId
        self.reviewedAt = reviewedAt
        self.intervalDaysAfter = intervalDaysAfter
        self.easeAfter = easeAfter
        self.score = nil
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reviewedAt = try c.decode(Date.self, forKey: .reviewedAt)
        score = try? c.decodeIfPresent(Int.self, forKey: .score)
        stickerId = (try? c.decodeIfPresent(String.self, forKey: .stickerId)).flatMap { $0 }
        intervalDaysAfter = try? c.decodeIfPresent(Int.self, forKey: .intervalDaysAfter)
        if let d = try? c.decodeIfPresent(Double.self, forKey: .easeAfter) {
            easeAfter = d
        } else if let s = try? c.decodeIfPresent(String.self, forKey: .easeAfter) {
            easeAfter = Double(s)
        } else {
            easeAfter = nil
        }
    }
}

/// A candidate returned by AI detection (scan.functions.ts DetectItemSchema).
nonisolated struct Candidate: Codable, Sendable, Identifiable, Hashable {
    var id: String { headword + "\(point.first ?? 0)" }
    let kind: String
    let headword: String
    let zhuyin: String
    let pinyin: String
    let meaningJa: String
    let pos: String
    let point: [Double]
    let confidence: Double
    let alternatives: [String]
    /// Web `suggestWords` / `suggestWordCandidates`: how this name differs from the others (≤15 chars).
    var distinction: String = ""
    /// What kind of name it is: common / colloquial / specific / academic / proper (server candidate-register.ts,
    /// 2026-10-15). Older answers sent casual, or a typed word's style (spoken / written …): `NameRegister.normalize`.
    /// (The style itself now comes as `style`, which the app does not show.)
    var register: String?
    /// Which object in the photo; other names of the same object share it.
    var group: Int?
    /// Category hint passed to `generateCard` as `hintCategory`.
    var categoryKey: String?
    /// The box the AI drew round the thing (`box_2d`: [ymin, xmin, ymax, xmax], 0–1000 of the photo, web
    /// suggestion-position.ts); nil when it sent none or a broken one. `objectBox` is the same box, 0–1.
    var box: [Double]?
    /// The thing's general everyday name in the reader's language (`object_label`, server #184: the same for every name
    /// of one `group`, e.g. 下着 for boxer briefs): the photo's tag. A typed word's names carry it too (server #185, the
    /// typed thing's name). Empty on older answers.
    var objectLabel: String = ""
    /// A typed word's short meaning in the reader's language (`gloss`, server #185: the first gloss of `meaning_ja`).
    /// Empty on photo candidates and older answers.
    var gloss: String = ""
    /// The server said where the thing is (`point` or `box_2d`). False when it sent neither: `point` is then the
    /// middle only as a stand-in, and the tag must not be put there (`CatchObject.build` finds the thing's own place).
    var positioned: Bool = true

    enum CodingKeys: String, CodingKey {
        case kind, headword, zhuyin, pinyin, pos, point, confidence, alternatives
        case distinction, register, group, gloss
        case box = "box_2d"
        case objectLabel = "object_label"
        case meaningJa = "meaning_ja"
        case readingZhuyin = "reading_zhuyin"
        case categoryKey = "category_key"
    }

    init(kind: String, headword: String, zhuyin: String, pinyin: String, meaningJa: String,
         pos: String, point: [Double], confidence: Double, alternatives: [String],
         distinction: String = "", register: String? = nil, group: Int? = nil, categoryKey: String? = nil) {
        self.kind = kind
        self.headword = headword
        self.zhuyin = zhuyin
        self.pinyin = pinyin
        self.meaningJa = meaningJa
        self.pos = pos
        self.point = point
        self.confidence = confidence
        self.alternatives = alternatives
        self.distinction = distinction
        self.register = register
        self.group = group
        self.categoryKey = categoryKey
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(headword, forKey: .headword)
        try c.encode(zhuyin, forKey: .zhuyin)
        try c.encode(pinyin, forKey: .pinyin)
        try c.encode(meaningJa, forKey: .meaningJa)
        try c.encode(pos, forKey: .pos)
        // A stand-in middle is not written: a candidate kept in the queue and read back stays "no position".
        if positioned || box != nil { try c.encode(point, forKey: .point) }
        try c.encode(confidence, forKey: .confidence)
        try c.encode(alternatives, forKey: .alternatives)
        try c.encode(distinction, forKey: .distinction)
        try c.encodeIfPresent(register, forKey: .register)
        try c.encodeIfPresent(group, forKey: .group)
        try c.encodeIfPresent(categoryKey, forKey: .categoryKey)
        try c.encodeIfPresent(box, forKey: .box)
        if !objectLabel.isEmpty { try c.encode(objectLabel, forKey: .objectLabel) }
        if !gloss.isEmpty { try c.encode(gloss, forKey: .gloss) }
    }

    /// Lenient decode (scan-detect-parse.ts): nulls, percentages, strings all accepted.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let head = ((try? c.decode(String.self, forKey: .headword)) ?? "").trimmingCharacters(in: .whitespaces)
        guard !head.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .headword, in: c, debugDescription: "empty")
        }
        headword = head
        kind = ((try? c.decode(String.self, forKey: .kind)) ?? "object").lowercased() == "text" ? "text" : "object"
        zhuyin = (try? c.decode(String.self, forKey: .zhuyin))
            ?? (try? c.decode(String.self, forKey: .readingZhuyin)) ?? ""
        pinyin = (try? c.decode(String.self, forKey: .pinyin)) ?? ""
        meaningJa = (try? c.decode(String.self, forKey: .meaningJa)) ?? ""
        pos = (try? c.decode(String.self, forKey: .pos)) ?? ""
        let sent = (try? c.decode([Double].self, forKey: .point)).flatMap { raw -> [Double]? in
            raw.count >= 2 && raw[0].isFinite && raw[1].isFinite ? raw : nil
        }
        box = (try? c.decode([Double].self, forKey: .box)).flatMap(Self.validBox)
        // No point but a box: the middle of the box (the server sends both; an answer with the box alone is placed too).
        var p = sent ?? box.map { [($0[1] + $0[3]) / 2, ($0[0] + $0[2]) / 2] } ?? [500, 500]
        if p[0] <= 1 && p[1] <= 1 { p = [p[0] * 1000, p[1] * 1000] }
        point = [max(0, min(1000, p[0])), max(0, min(1000, p[1]))]
        positioned = sent != nil || box != nil
        var conf = (try? c.decode(Double.self, forKey: .confidence)) ?? 0.8
        if conf > 1 { conf /= 100 }
        confidence = max(0, min(1, conf))
        alternatives = (try? c.decode([String].self, forKey: .alternatives)) ?? []
        distinction = ((try? c.decode(String.self, forKey: .distinction)) ?? "").trimmingCharacters(in: .whitespaces)
        register = try? c.decode(String.self, forKey: .register)
        group = try? c.decode(Int.self, forKey: .group)
        categoryKey = try? c.decode(String.self, forKey: .categoryKey)
        objectLabel = ((try? c.decode(String.self, forKey: .objectLabel)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        gloss = ((try? c.decode(String.self, forKey: .gloss)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The short meaning a list row shows, in the reader's language: the server's `gloss` (typed words), else the first
    /// gloss of the meaning.
    var shownMeaning: String { ReaderLanguage.gloss(ReaderLanguage.shown(gloss, meaningJa)) }

    /// validBox2d: four numbers in 0–1000, top above bottom and left before right.
    static func validBox(_ raw: [Double]) -> [Double]? {
        guard raw.count == 4, raw.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1000 }), raw[2] > raw[0], raw[3] > raw[1] else { return nil }
        return raw
    }

    /// The AI's box round the thing, 0–1 of the photo (top-left origin).
    var objectBox: CGRect? {
        guard let b = box, b.count == 4 else { return nil }
        return CGRect(x: b[1] / 1000, y: b[0] / 1000, width: (b[3] - b[1]) / 1000, height: (b[2] - b[0]) / 1000)
    }

    /// The same name with another register (`NameRegister.finalized`).
    func with(register r: NameRegister) -> Candidate {
        var copy = self
        copy.register = r.rawValue
        return copy
    }
}

/// What kind of name a candidate is (server candidate-register.ts, owner 2026-10-15: 「写真のタグは台湾の人がふだん
/// いちばんよく使う言い方」「候補は一般的な言い方を上に、口語・より詳しい言い方・学術的な言い方・固有名詞の順で下へ」
/// 「どの候補にも必ず印を付ける」). The cases are in list order: the everyday name at the top.
nonisolated enum NameRegister: String, CaseIterable, Sendable {
    case common, colloquial, specific, academic, proper

    var rank: Int { NameRegister.allCases.firstIndex(of: self) ?? 0 }

    /// The label on every candidate row (the owner's words).
    var label: String {
        switch self {
        case .common: L("一般的な言い方")
        case .colloquial: L("口語")
        case .specific: L("より詳しい言い方")
        case .academic: L("学術的な言い方")
        case .proper: L("固有名詞")
        }
    }

    /// The server's register (nori-creator/Lovable-catch-words-app#183: always one of the five). The photo's older
    /// `casual` is colloquial. A typed word's style (spoken / written / both / technical / signage — older answers put
    /// it in `register`, it is `style` now) is never read as a register: like a missing one it is nil, and `finalized`
    /// fills it in, so the row still has its label.
    static func normalize(_ raw: String?) -> NameRegister? {
        let v = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if v == "casual" { return .colloquial }
        return NameRegister(rawValue: v)
    }

    /// One thing's names (or a typed word's list) with a register on every one, in list order (finalizeNameRegisters):
    /// a missing register is common for the first name and specific for the others (another name of the same thing is
    /// usually a narrower one); then common → colloquial → specific → academic → proper, the server's order kept within
    /// one register. The first name is always an everyday one: with no common name, the first that is not a proper noun
    /// moves to the top as the common name (the photo's tag is never a detailed name or a brand). Only a list of proper
    /// nouns stays as it is.
    static func finalized(_ words: [Candidate]) -> [Candidate] {
        let filled = words.enumerated().map { i, c in
            c.with(register: normalize(c.register) ?? (i == 0 ? .common : .specific))
        }
        var sorted = filled.indices.sorted { a, b in
            let ra = of(filled[a]).rank, rb = of(filled[b]).rank
            return ra != rb ? ra < rb : a < b
        }.map { filled[$0] }
        if let first = sorted.first, of(first) != .common, let k = sorted.firstIndex(where: { of($0) != .proper }) {
            let promoted = sorted.remove(at: k)
            sorted.insert(promoted.with(register: .common), at: 0)
        }
        return sorted
    }

    /// A candidate's register, read leniently (common when unreadable).
    static func of(_ c: Candidate) -> NameRegister { normalize(c.register) ?? .common }
}

/// AI-generated card content for a picked candidate. The card's `level` (the word's exam level) is not read:
/// per-word exam levels are gone on iOS (owner 2026-10-03). It stays inside `raw`, which is sent back unchanged.
nonisolated struct CardDetails: Codable, Sendable {
    var categoryKey: String
    var exampleSentence: String
    var exampleTranslation: String
    var extras: WordExtras
    /// The whole card exactly as `generateCard` returned it. Saving sends this back
    /// (word fields, every extras key), so nothing the web generated is lost.
    var raw: JSONValue?

    enum CodingKeys: String, CodingKey {
        case extras
        case categoryKey = "category_key"
        case exampleSentence = "example_sentence"
        case exampleTranslation = "example_translation"
    }

    init(categoryKey: String, exampleSentence: String, exampleTranslation: String, extras: WordExtras) {
        self.categoryKey = categoryKey
        self.exampleSentence = exampleSentence
        self.exampleTranslation = exampleTranslation
        self.extras = extras
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        categoryKey = (try? c.decode(String.self, forKey: .categoryKey)) ?? "other"
        exampleSentence = (try? c.decode(String.self, forKey: .exampleSentence)) ?? ""
        exampleTranslation = (try? c.decode(String.self, forKey: .exampleTranslation)) ?? ""
        extras = (try? c.decode(WordExtras.self, forKey: .extras)) ?? WordExtras()
        raw = try? JSONValue(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        if let raw {
            try raw.encode(to: encoder)
            return
        }
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(categoryKey, forKey: .categoryKey)
        try c.encode(exampleSentence, forKey: .exampleSentence)
        try c.encode(exampleTranslation, forKey: .exampleTranslation)
        try c.encode(extras, forKey: .extras)
    }
}

/// Web `checkOwnedWord` → `OwnedWord` (encounters.functions.ts). A word already in the dex:
/// catching it again is a re-encounter ("再会！"), never a duplicate sticker.
nonisolated struct OwnedWord: Codable, Sendable, Hashable {
    let stickerId: String
    let wordId: String
    let headword: String
    let meaningJa: String
    let readingZhuyin: String?
    let pinyin: String?
    let cutoutUrl: String?
    let encounterCount: Int
    let takenAt: String
    let locationName: String?

    enum CodingKeys: String, CodingKey {
        case headword, pinyin
        case stickerId = "sticker_id"
        case wordId = "word_id"
        case meaningJa = "meaning_ja"
        case readingZhuyin = "reading_zhuyin"
        case cutoutUrl = "cutout_url"
        case encounterCount = "encounter_count"
        case takenAt = "taken_at"
        case locationName = "location_name"
    }

    var takenDate: Date? { SupabaseDate.parse(takenAt) }
}
