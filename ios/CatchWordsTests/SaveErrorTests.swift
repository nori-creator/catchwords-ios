import XCTest
import UIKit
import ImageIO
@testable import CatchWords

/// A failed save (owner 2026-10-15: 花束 and 草莓蛋糕 were reported as 「保存に失敗しました。ネットワークに接続できませんでした」
/// whatever had happened, and the words disappeared from the dex): the kind of failure is told apart — no network,
/// a connection that dropped, a server that took too long, refused or failed, an answer that could not be read — and
/// the word is kept in the dex as 「保存待ち」 with everything to save it again, never removed.
/// Run on its own by .github/workflows/ios-check.yml.
@MainActor
final class SaveErrorTests: XCTestCase {
    private func apiError(_ code: URLError.Code) -> APIError? {
        APIError.from(URLError(code)) as? APIError
    }

    // MARK: Mapping the connection's errors

    func testOnlyNoNetworkIsOffline() {
        for code: URLError.Code in [.notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff] {
            guard case .offline? = apiError(code) else { return XCTFail("\(code.rawValue) should read as offline") }
        }
        // Online, but the connection to the server failed or dropped: told apart, with its code.
        for code: URLError.Code in [.networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
                                    .secureConnectionFailed] {
            guard case .connectionLost(let kept)? = apiError(code) else { return XCTFail("\(code.rawValue) is not offline") }
            XCTAssertEqual(kept, code.rawValue)
        }
        guard case .timeout? = apiError(.timedOut) else { return XCTFail("timedOut") }
        guard case .decoding? = apiError(.badServerResponse) else { return XCTFail("badServerResponse") }
        guard case .decoding? = apiError(.cannotParseResponse) else { return XCTFail("cannotParseResponse") }
        XCTAssertTrue(APIError.from(URLError(.cancelled)) is CancellationError)
    }

    func testDroppedConnectionIsRetryableAndNamedInTheLog() {
        let lost = APIError.connectionLost(URLError.Code.networkConnectionLost.rawValue)
        XCTAssertTrue(lost.isRetryable)
        XCTAssertTrue(APIError.describe(lost).contains("-1005"))
        XCTAssertTrue(APIError.describe(lost).contains("networkConnectionLost"))
        XCTAssertTrue(APIError.describe(APIError.server(500, "boom")).contains("500"))
    }

    // MARK: Classifying a failed save

    func testEachFailureIsItsOwnKind() {
        XCTAssertEqual(SaveFailure.classify(APIError.offline), .offline)
        XCTAssertEqual(SaveFailure.classify(APIError.connectionLost(-1005)), .connectionLost)
        XCTAssertEqual(SaveFailure.classify(URLError(.networkConnectionLost)), .connectionLost)
        XCTAssertEqual(SaveFailure.classify(URLError(.notConnectedToInternet)), .offline)
        XCTAssertEqual(SaveFailure.classify(APIError.timeout), .timeout)
        XCTAssertEqual(SaveFailure.classify(APIError.server(500, "")), .rejected)
        XCTAssertEqual(SaveFailure.classify(APIError.server(400, "送った内容の形が違います。")), .rejected)
        XCTAssertEqual(SaveFailure.classify(APIError.decoding), .decoding)
        XCTAssertEqual(SaveFailure.classify(APIError.unauthorized), .signedOut)
        // Through the step it stopped at.
        let wrapped = CatchSaveError(stage: .upload, underlying: APIError.connectionLost(-1004), uploads: nil)
        XCTAssertEqual(SaveFailure.classify(wrapped), .connectionLost)
    }

    func testTheMessageSaysWhatHappened() {
        let offline = SaveFailure.message(for: APIError.offline)
        let dropped = SaveFailure.message(for: APIError.connectionLost(-1005))
        let timeout = SaveFailure.message(for: APIError.timeout)
        let failed = SaveFailure.message(for: APIError.server(500, ""))
        let refused = SaveFailure.message(for: APIError.server(400, ""))
        let unreadable = SaveFailure.message(for: APIError.decoding)
        // Never the same sentence for two different failures (it used to be the network for all of them).
        XCTAssertEqual(Set([offline, dropped, timeout, failed, refused, unreadable]).count, 6)
        XCTAssertTrue(dropped.contains("-1005"))
        XCTAssertTrue(failed.contains("500"))
        XCTAssertTrue(refused.contains("400"))
        // A photo that could not go up says so.
        let upload = SaveFailure.message(for: CatchSaveError(stage: .upload, underlying: APIError.timeout, uploads: nil))
        XCTAssertNotEqual(upload, timeout)
        XCTAssertTrue(upload.contains(timeout))
        // A connection that dropped while a photo was being sent is never called offline (the Wi-Fi was on).
        let sending = SaveFailure.message(for: CatchSaveError(stage: .upload, underlying: APIError.connectionLost(-1005), uploads: nil))
        XCTAssertTrue(sending.contains("-1005"))
        XCTAssertFalse(sending.contains(offline))
        XCTAssertNotEqual(sending, dropped)
    }

    func testWhatIsTriedAgainOnItsOwn() {
        XCTAssertTrue(SaveFailure.isRetryable(APIError.offline))
        XCTAssertTrue(SaveFailure.isRetryable(APIError.connectionLost(-1005)))
        XCTAssertTrue(SaveFailure.isRetryable(APIError.timeout))
        XCTAssertTrue(SaveFailure.isRetryable(APIError.server(503, "")))
        XCTAssertTrue(SaveFailure.isRetryable(APIError.decoding))
        XCTAssertFalse(SaveFailure.isRetryable(APIError.server(400, "")))
        XCTAssertFalse(SaveFailure.isRetryable(APIError.unauthorized))
    }

    func testTheLogKeepsTheStepAndThePhotosAlreadyUp() {
        let error = CatchSaveError(stage: .save, underlying: APIError.connectionLost(-1005),
                                   uploads: CatchUploads(object: "u/1-object.jpg", cutout: nil, selfie: nil))
        let line = SaveFailure.log(error, headword: "花束")
        XCTAssertTrue(line.hasPrefix("花束: save failed (connectionLost)"))
        XCTAssertTrue(line.contains("-1005"))
        XCTAssertTrue(line.contains("u/1-object.jpg"))
        XCTAssertTrue(DexStore.isAccountChanged(CatchSaveError(stage: .save, underlying: DexStore.accountChanged, uploads: nil)))
    }

    // MARK: Uploads: one at a time, tried again, within a budget

    private func picture(_ w: Int, _ h: Int) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: w, height: h)).image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }
    }

    /// Random pixels (a PNG cannot make them smaller), the same every run.
    private func noise(_ w: Int, _ h: Int) throws -> UIImage {
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        var x: UInt32 = 2_463_534_242
        for i in bytes.indices {
            x ^= x << 13
            x ^= x >> 17
            x ^= x << 5
            bytes[i] = UInt8(truncatingIfNeeded: x)
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        let cg = try XCTUnwrap(CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                                       space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        return UIImage(cgImage: cg)
    }

    func testThePhotoGoesFirstAndAloneThenTheCutoutThenTheSelfie() async throws {
        let dex = DexStore()
        var sent: [String] = []
        var inFlight = 0
        var most = 0
        dex.sendUploadOverride = { _, path, _, _ in
            inFlight += 1
            most = max(most, inFlight)
            sent.append(path)
            try? await Task.sleep(for: .milliseconds(20))
            inFlight -= 1
        }
        dex.retrySleepOverride = { _ in }
        let up = try await dex.upload(photo: picture(64, 48), cutout: picture(40, 40), selfie: picture(30, 40), uid: "u", ts: 7)
        XCTAssertEqual(sent, ["u/7-object.jpg", "u/7-cutout.png", "u/7-selfie.jpg"])
        // Never two at once on the connection.
        XCTAssertEqual(most, 1)
        XCTAssertEqual(up.object, "u/7-object.jpg")
        XCTAssertEqual(up.cutout, "u/7-cutout.png")
        XCTAssertEqual(up.selfie, "u/7-selfie.jpg")
    }

    func testADroppedUploadIsTriedAgainAfterOneTwoAndFourSeconds() async throws {
        var waits: [TimeInterval] = []
        var tries: [Int] = []
        try await UploadRetry.run(sleep: { waits.append($0) }) { attempt in
            tries.append(attempt)
            if attempt < 4 { throw APIError.connectionLost(URLError.Code.networkConnectionLost.rawValue) }
        }
        XCTAssertEqual(tries, [1, 2, 3, 4])
        XCTAssertEqual(waits, [1, 2, 4])
    }

    func testOnlyConnectionFailuresAreTriedAgainAndFourTriesAtMost() async {
        for e: Error in [APIError.server(400, "x"), APIError.server(413, ""), APIError.decoding, APIError.unauthorized] {
            var tries = 0
            do {
                try await UploadRetry.run(sleep: { _ in }) { _ in
                    tries += 1
                    throw e
                }
                XCTFail("should have failed")
            } catch {}
            XCTAssertEqual(tries, 1, "\(e)")
        }
        XCTAssertTrue(UploadRetry.isRetryable(APIError.connectionLost(URLError.Code.networkConnectionLost.rawValue)))
        XCTAssertTrue(UploadRetry.isRetryable(APIError.connectionLost(URLError.Code.cannotConnectToHost.rawValue)))
        XCTAssertTrue(UploadRetry.isRetryable(APIError.timeout))
        XCTAssertTrue(UploadRetry.isRetryable(APIError.offline))
        XCTAssertTrue(UploadRetry.isRetryable(CatchSaveError(stage: .upload, underlying: APIError.timeout, uploads: nil)))
        var tries = 0
        do {
            try await UploadRetry.run(sleep: { _ in }) { _ in
                tries += 1
                throw APIError.timeout
            }
            XCTFail("should have failed")
        } catch {
            XCTAssertEqual(SaveFailure.classify(error), .timeout)
        }
        XCTAssertEqual(tries, 4)
    }

    /// Another try sends the very same file and counts it as sent when storage already has it (an earlier try had
    /// landed after all): uploading twice never fails nor makes two files.
    func testATryAgainIsTheSameFileAndAlreadyThereCountsAsSent() async throws {
        let dex = DexStore()
        var calls: [(path: String, again: Bool)] = []
        var cutoutFailures = 0
        dex.sendUploadOverride = { _, path, _, again in
            calls.append((path, again))
            if path.hasSuffix("-cutout.png"), cutoutFailures < 2 {
                cutoutFailures += 1
                throw APIError.connectionLost(URLError.Code.networkConnectionLost.rawValue)
            }
        }
        var waits: [TimeInterval] = []
        dex.retrySleepOverride = { waits.append($0) }
        let up = try await dex.upload(photo: picture(64, 48), cutout: picture(40, 40), selfie: nil, uid: "u", ts: 8)
        XCTAssertEqual(calls.map { $0.path }, ["u/8-object.jpg", "u/8-cutout.png", "u/8-cutout.png", "u/8-cutout.png"])
        XCTAssertEqual(calls.map { $0.again }, [false, false, true, true])
        XCTAssertEqual(waits, [1, 2])
        XCTAssertEqual(up.cutout, "u/8-cutout.png")
        XCTAssertTrue(SupabaseClient.isAlreadyThere(status: 409, json: nil))
        XCTAssertTrue(SupabaseClient.isAlreadyThere(status: 400, json: ["statusCode": "409", "error": "Duplicate",
                                                                         "message": "The resource already exists"]))
        XCTAssertFalse(SupabaseClient.isAlreadyThere(status: 400, json: ["message": "invalid key"]))
        XCTAssertFalse(SupabaseClient.isAlreadyThere(status: 413, json: nil))
    }

    /// A cut-out that never goes up never fails the catch: the photo is saved without it (it is attached later).
    func testACutoutThatNeverGoesUpNeverFailsTheCatch() async throws {
        let dex = DexStore()
        var cutoutTries = 0
        dex.sendUploadOverride = { _, path, _, _ in
            if path.hasSuffix("-cutout.png") {
                cutoutTries += 1
                throw APIError.connectionLost(URLError.Code.networkConnectionLost.rawValue)
            }
        }
        dex.retrySleepOverride = { _ in }
        let up = try await dex.upload(photo: picture(64, 48), cutout: picture(40, 40), selfie: nil, uid: "u", ts: 9)
        XCTAssertEqual(up.object, "u/9-object.jpg")
        XCTAssertNil(up.cutout)
        XCTAssertEqual(cutoutTries, 4)
    }

    /// The photo is the one picture a catch needs: when it never goes up the upload fails (the word waits in 「保存待ち」),
    /// and the cut-out is not even tried on a connection that keeps dropping.
    func testAPhotoThatNeverGoesUpFailsTheUpload() async {
        let dex = DexStore()
        var sent: [String] = []
        dex.sendUploadOverride = { _, path, _, _ in
            sent.append(path)
            throw APIError.connectionLost(URLError.Code.networkConnectionLost.rawValue)
        }
        dex.retrySleepOverride = { _ in }
        do {
            _ = try await dex.upload(photo: picture(64, 48), cutout: picture(40, 40), selfie: nil, uid: "u", ts: 10)
            XCTFail("should have failed")
        } catch {
            XCTAssertEqual(SaveFailure.classify(error), .connectionLost)
        }
        XCTAssertEqual(sent, Array(repeating: "u/10-object.jpg", count: 4))
    }

    func testACutoutIsDrawnSmallerUntilItFitsItsBudget() throws {
        let up = try XCTUnwrap(ImageTools.pngUpload(try noise(1400, 1400)))
        XCTAssertLessThanOrEqual(up.data.count, ImageTools.cutoutBudget)
        XCTAssertLessThan(up.width, 1024)
        XCTAssertTrue(up.shrunk)
        // A plain cut-out is sent at 1024 px, as it is.
        let plain = try XCTUnwrap(ImageTools.pngUpload(picture(1400, 1000)))
        XCTAssertEqual(plain.width, 1024)
        XCTAssertFalse(plain.shrunk)
        // The re-encounter's smaller cut-out keeps its own size.
        XCTAssertEqual(try XCTUnwrap(ImageTools.pngUpload(picture(1400, 1000), maxSide: 800)).width, 800)
        // The photo is sent as before: 1600 px.
        XCTAssertEqual(try XCTUnwrap(ImageTools.jpegUpload(picture(2000, 1500))).width, 1600)
    }

    /// A 16-bit (wide-colour / extended-range) picture is sent as an 8-bit PNG or JPEG.
    func testAWideColourPictureIsSentInEightBits() throws {
        let w = 64, h = 64
        var words = [UInt16](repeating: 0, count: w * h * 4)
        for i in stride(from: 0, to: words.count, by: 4) {
            words[i] = 0xF000
            words[i + 1] = 0x2000
            words[i + 2] = 0x1000
            words[i + 3] = 0xFFFF
        }
        let data = words.withUnsafeBytes { Data($0) }
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let cg = try XCTUnwrap(CGImage(width: w, height: h, bitsPerComponent: 16, bitsPerPixel: 64, bytesPerRow: w * 8,
                                       space: space, bitmapInfo: info, provider: provider, decode: nil,
                                       shouldInterpolate: false, intent: .defaultIntent))
        let source = UIImage(cgImage: cg)
        XCTAssertEqual(source.cgImage?.bitsPerComponent, 16)
        for up in [try XCTUnwrap(ImageTools.pngUpload(source)), try XCTUnwrap(ImageTools.jpegUpload(source))] {
            XCTAssertEqual(up.sourceBits, 16)
            let src = try XCTUnwrap(CGImageSourceCreateWithData(up.data as CFData, nil))
            let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
            XCTAssertEqual(decoded.bitsPerComponent, 8)
        }
        XCTAssertEqual(ImageTools.standardFormat().preferredRange, .standard)
    }

    // MARK: Keeping the word (「保存待ち」)

    private func draft() -> CatchDraft {
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).image { ctx in
            UIColor.systemPink.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }
        let word = Candidate(kind: "object", headword: "花束", zhuyin: "ㄏㄨㄚ ㄕㄨˋ", pinyin: "huāshù", meaningJa: "花束",
                             pos: "N", point: [500, 500], confidence: 0.9, alternatives: [], register: "common")
        let card = CardDetails(categoryKey: "plant", exampleSentence: "我送她一束花。", exampleTranslation: "", extras: WordExtras())
        return CatchDraft(candidate: word, details: card, photo: photo, cutout: nil, selfie: nil, caption: "",
                          location: nil, placeName: "台北", captureType: "photo")
    }

    func testAFailedSaveKeepsTheWordInTheDex() throws {
        let dex = DexStore()
        let d = draft()
        let entry = Sticker(id: DexStore.provisionalPrefix + "test-keep", wordId: "", objectImageUrl: "u/1-object.jpg",
                            cutoutImageUrl: nil, selfieImageUrl: nil, caption: nil, locationName: "台北", takenAt: Date(),
                            captureType: "photo", word: nil)
        dex.stickers = [entry]
        let error = CatchSaveError(stage: .save, underlying: APIError.connectionLost(-1005),
                                   uploads: CatchUploads(object: "u/1-object.jpg", cutout: nil, selfie: nil))
        let pid = try XCTUnwrap(dex.keepUnsaved(d, provisional: entry.id, ts: 1, pendingId: nil, error: error))
        defer { PendingQueue.shared.remove(id: pid) }
        // Still in the dex, marked 「保存待ち」, with why.
        XCTAssertEqual(dex.stickers.map(\.id), [entry.id])
        XCTAssertTrue(dex.isUnsaved(entry.id))
        XCTAssertEqual(dex.unsavedReason(entry.id), SaveFailure.message(for: error))
        // Everything to save it again: the same catch id (never saved twice), the word, the photos already up.
        let kept = try XCTUnwrap(PendingQueue.shared.item(id: pid)?.save)
        XCTAssertEqual(kept.catchId, d.catchId)
        XCTAssertEqual(kept.provisionalId, entry.id)
        XCTAssertEqual(kept.candidate.headword, "花束")
        XCTAssertEqual(kept.uploads?.object, "u/1-object.jpg")
        XCTAssertEqual(kept.details.categoryKey, "plant")
        XCTAssertEqual(kept.details.exampleSentence, "我送她一束花。")
        XCTAssertEqual(kept.placeName, "台北")
        XCTAssertTrue(PendingQueue.shared.unsavedItems().contains { $0.id == pid })
        // Thrown away by the learner: the word and its entry go.
        dex.discardUnsaved(pendingId: pid)
        XCTAssertFalse(dex.isUnsaved(entry.id))
        XCTAssertTrue(dex.stickers.isEmpty)
        XCTAssertNil(PendingQueue.shared.item(id: pid))
    }

    func testTheSameCatchKeepsItsIdOnEveryTry() {
        let d = draft()
        XCTAssertEqual(d.catchId, d.catchId.lowercased())
        XCTAssertNotNil(UUID(uuidString: d.catchId))
        XCTAssertNotEqual(draft().catchId, d.catchId)
    }

    func testKeptSaveSurvivesTheIndexOnDisk() throws {
        let word = Candidate(kind: "object", headword: "草莓蛋糕", zhuyin: "", pinyin: "", meaningJa: "いちごのケーキ",
                             pos: "N", point: [500, 500], confidence: 0.9, alternatives: [])
        let card: JSONValue = .object(["category_key": .string("food"), "example_sentence": .string("我想吃草莓蛋糕。"),
                                       "extras": .object(["example_v": .number(3)])])
        let save = PendingSave(catchId: "6f1c2a4e-1b2c-4d3e-8f9a-0b1c2d3e4f5a", provisionalId: "local-x", ts: 42, language: "zh-TW",
                               candidate: word, card: card, categoryKey: "other", exampleSentence: "", exampleTranslation: "",
                               caption: "", placeName: nil, lat: 25.03, lng: 121.56, captureType: "photo", takenAt: Date(),
                               hasCutout: true, hasSelfie: false, uploads: nil)
        let item = PendingCatch(id: "p1", createdAt: Date(), reason: "x", lat: nil, lng: nil, ownerId: "u", save: save)
        let back = try JSONDecoder().decode(PendingCatch.self, from: JSONEncoder().encode(item))
        XCTAssertTrue(back.isUnsaved)
        XCTAssertEqual(back.save?.catchId, save.catchId)
        // The card that came is the one saved again.
        XCTAssertEqual(back.save?.details.categoryKey, "food")
        XCTAssertEqual(back.save?.details.exampleSentence, "我想吃草莓蛋糕。")
        XCTAssertEqual(back.save?.details.extras.exampleV, 3)
        // An index written before 「保存待ち」 existed still reads: its photos wait for their analysis.
        let old = #"[{"id":"p0","createdAt":0,"reason":"解析中","ownerId":"u"}]"#
        let olds = try JSONDecoder().decode([PendingCatch].self, from: Data(old.utf8))
        XCTAssertEqual(olds.count, 1)
        XCTAssertFalse(olds[0].isUnsaved)
    }
}
