import SwiftUI

/// Sentences with the names of legal pages as tappable links, in the display language.
///
/// The sentence is translated as a whole (`{1}`, `{2}` mark where each page's name goes, so every language
/// keeps its own word order); the names become links afterwards.
enum LegalLinks {
    /// Where each link goes into a translated sentence (control characters never appear in the texts).
    private static let slot1 = "\u{1}"
    private static let slot2 = "\u{2}"

    /// Sign-in: 「続けることで、利用規約とプライバシーポリシーに同意したものとみなされます。」
    static func signInAgreement() -> AttributedString {
        linked(L("続けると、\(slot1)と\(slot2)に同意したことになります。"), [
            (L("利用規約"), AppConfig.termsURL),
            (L("プライバシーポリシー"), AppConfig.privacyURL),
        ])
    }

    /// AI consent: where the details are (privacy policy chapter 4 AI, chapter 6 the providers and countries).
    static func aiConsentDetails() -> AttributedString {
        linked(L("詳しくは\(slot1)（第4条・第5条）をご覧ください。"), [
            (L("プライバシーポリシー"), AppConfig.privacyURL),
        ])
    }

    /// Replaces each slot character (U+0001, U+0002 …) in `template` with its link.
    private static func linked(_ template: String, _ links: [(title: String, url: URL)]) -> AttributedString {
        var out = AttributedString()
        var plain = ""
        for ch in template {
            let scalars = ch.unicodeScalars
            if scalars.count == 1, let v = scalars.first?.value, v >= 1, Int(v) <= links.count {
                out += AttributedString(plain)
                plain = ""
                let link = links[Int(v) - 1]
                var run = AttributedString(link.title)
                run.link = link.url
                run.underlineStyle = .single
                out += run
            } else {
                plain.append(ch)
            }
        }
        out += AttributedString(plain)
        return out
    }
}
