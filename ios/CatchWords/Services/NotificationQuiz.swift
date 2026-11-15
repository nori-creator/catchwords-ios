import UIKit
import UserNotifications

/// The picture quiz in a review or place reminder (owner 2026-11-15, mock-up
/// https://claude.ai/artifact/2bhi7kCCLAuD9923QRLEr9: 「問題を、クイズを、ユーザーに与えて、なんだっけってユーザーが
/// 思い出すようなきっかけを与えたい」): which word it asks about and the lines around its picture. The headword is never
/// written — the learner recalls it from the picture, and the tap opens that word's 4-choice question.
enum ReminderQuiz {
    struct Pick {
        let sticker: Sticker
        /// The other words due by the same time.
        let others: Int
    }

    /// Each of this account's words with its next review time (`DexStore.reviews`, keyed by sticker id).
    static func dueByWord(_ dex: DexStore) -> [String: Date] {
        let mine = Set(dex.stickers.map(\.id))
        var out: [String: Date] = [:]
        for (id, r) in dex.reviews where mine.contains(id) {
            if let at = r.dueAt { out[id] = at }
        }
        return out
    }

    /// The word a reminder firing at `at` asks about: of this account's words due by then, the one due first that has
    /// a picture (ties: the lower id, so the pick is stable); `others` counts the rest due by then. Not the bundled
    /// sample, not a catch still being saved. nil = no due word with a picture (the plain reminder is sent).
    static func pick(stickers: [Sticker], due: [String: Date], at: Date) -> Pick? {
        let dueBy = stickers
            .filter { $0.word != nil && !$0.isSample && !DexStore.isProvisional($0.id) }
            .compactMap { s -> (sticker: Sticker, at: Date)? in
                guard let d = due[s.id], d <= at else { return nil }
                return (s, d)
            }
            .sorted { $0.at != $1.at ? $0.at < $1.at : $0.sticker.id < $1.sticker.id }
        guard let first = dueBy.first(where: { picturePath($0.sticker) != nil }) else { return nil }
        return Pick(sticker: first.sticker, others: dueBy.count - 1)
    }

    /// The picture the word is shown with (the one its page shows; a stock picture when the learner has none).
    static func picturePath(_ s: Sticker) -> String? { s.heroPath ?? s.placeholderImageUrl }

    /// About how long the round takes: ~10 seconds a card, at least a minute.
    static func minutes(cards: Int) -> Int { max(1, Int((Double(cards) * 10 / 60).rounded(.up))) }

    /// The place line without the street: a learner's own name as they wrote it, else the district (or the city when
    /// there is no district) of the saved address — 「台北市 大安區 和平東路一段162號」 → 「大安區」,
    /// "Taipei, Da'an District, 162 Heping East Road" → "Da'an District". The same cut as the server's `placeArea`.
    static func area(_ saved: String?, custom: Bool) -> String? {
        let v = (saved ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return nil }
        if custom { return v }
        let comma = v.contains(",")
        let parts = (comma ? v.split(separator: ",") : v.split(whereSeparator: { $0 == " " || $0 == "\u{3000}" }))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        func hasDigit(_ s: String) -> Bool { s.contains { $0.isASCII && $0.isNumber } }
        guard let city = parts.first, !hasDigit(city) else { return nil }
        if parts.count > 1, !hasDigit(parts[1]), isAdminArea(parts[1]) { return parts[1] }
        return city
    }

    /// A district / town / ward name (Han, Korean or English), as the server's `ADMIN_AREA`.
    static func isAdminArea(_ s: String) -> Bool {
        s.range(of: "(區|鄉|鎮|市|区|町|村|郡|구|군|시|동|읍|면)$", options: .regularExpression) != nil  // l10n-ignore: a pattern, not shown
            || s.range(of: "\\b(district|township|ward|county|city|borough)\\b", options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// 「10月30日・大安區で撮った物」 (no place: 「10月30日に撮った物」), in the display language.
    static func takenLine(_ s: Sticker) -> String {
        let f = DateFormatter()
        f.locale = L10n.locale
        f.setLocalizedDateFormatFromTemplate("MMMd")
        let day = f.string(from: s.takenAt)
        if let place = area(s.locationName, custom: s.locationCustom == true) {
            return L("\(day)・\(place)で撮った物")
        }
        return L("\(day)に撮った物")
    }

    /// The line under the question: how many more and about how long, in the reminder's own words.
    static func body(reason: ReminderService.Reason, others: Int) -> String {
        let m = minutes(cards: others + 1)
        switch reason {
        case .srs:
            return others > 0 ? L("ほかに\(others)語が思い出しどきです（約\(m)分）") : L("今が思い出しどきです")
        case .habit:
            return others > 0 ? L("いつもの時間です。ほかに\(others)語（約\(m)分）") : L("いつもの時間です。この1語から")
        case .custom:
            return others > 0 ? L("今日の復習：ほかに\(others)語（約\(m)分）") : L("今日の復習：この1語から")
        }
    }
}

/// A picture for a notification (the reminders' word, the photo just analysed, the album's word): at most 300 px,
/// flattened on white (a cut-out is a transparent PNG and iOS shows the thumbnail on its own background), as a JPEG in
/// a fresh temporary file — iOS moves the file into its own store when the request is added. Only pictures already on
/// this phone or behind the dex's signed links; nothing new is sent anywhere. nil = the notification goes without one.
enum NotificationPicture {
    static func attachment(path: String?, dex: DexStore) async -> UNNotificationAttachment? {
        guard let path else { return nil }
        var image = await ImageCache.shared.kept(for: path, maxPixel: 384)
        if image == nil, let url = dex.url(for: path, preferThumb: true) {
            image = await ImageCache.shared.load(url: url, key: path, maxPixel: 384)
        }
        guard let image else { return nil }
        return await attachment(image: image)
    }

    static func attachment(image: UIImage) async -> UNNotificationAttachment? {
        let data = await Task.detached(priority: .utility) { Self.flatJPEG(image) }.value
        guard let data else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("notify-\(UUID().uuidString).jpg")
        do {
            try data.write(to: url, options: .atomic)
            return try UNNotificationAttachment(identifier: "picture", url: url, options: nil)
        } catch {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }

    nonisolated static func flatJPEG(_ image: UIImage, side: CGFloat = 300) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, side / max(size.width, size.height))
        let target = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let flat = UIGraphicsImageRenderer(size: target, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: target))
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return flat.jpegData(compressionQuality: 0.8)
    }
}
