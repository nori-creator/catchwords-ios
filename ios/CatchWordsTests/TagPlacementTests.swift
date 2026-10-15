import XCTest
@testable import CatchWords

/// Where a name tag goes (owner 2026-10-15: 「正確にもののうえに名前のタグを置いて。適当に真ん中ではなく。」): the photo's
/// own coordinates through the rect it really covers on the stage, a bitmap turned upright first, and things without a
/// position of their own spread over the photo instead of piled in the middle. Run on its own by ios-check.yml.
@MainActor
final class TagPlacementTests: XCTestCase {
    private func cand(_ head: String, group: Int, point: [Double]?, box: [Double]? = nil) -> Candidate {
        // Through the decoder, as the server's answer comes: `positioned` is false when neither point nor box came.
        var obj: [String: Any] = ["headword": head, "zhuyin": "", "pinyin": "", "meaning_ja": head, "pos": "N",
                                  "confidence": 0.9, "alternatives": [], "group": group]
        if let point { obj["point"] = point }
        if let box { obj["box_2d"] = box }
        let data = try! JSONSerialization.data(withJSONObject: obj)
        return try! JSONDecoder().decode(Candidate.self, from: data)
    }

    // MARK: The photo on the stage

    func testPortraitPhotoFillsAPortraitStageWithTheSidesCropped() {
        // A 3:4 photo on a narrower 9:19.5 stage: the height is matched, the sides are cut off evenly.
        let r = TagPlacement.displayedRect(image: CGSize(width: 3000, height: 4000), in: CGSize(width: 390, height: 845), mode: .fill)
        XCTAssertEqual(r.height, 845, accuracy: 0.01)
        XCTAssertEqual(r.width, 845 * 0.75, accuracy: 0.01)
        XCTAssertEqual(r.midX, 195, accuracy: 0.01)
        XCTAssertLessThan(r.minX, 0)
        // A point in the middle of the photo is in the middle of the stage; the photo's left edge is off screen.
        let mid = TagPlacement.stagePoint(CGPoint(x: 0.5, y: 0.5), image: CGSize(width: 3000, height: 4000),
                                          in: CGSize(width: 390, height: 845), mode: .fill)
        XCTAssertEqual(mid.x, 195, accuracy: 0.01)
        XCTAssertEqual(mid.y, 422.5, accuracy: 0.01)
        let left = TagPlacement.stagePoint(CGPoint(x: 0, y: 0.5), in: r)
        XCTAssertLessThan(left.x, 0)
    }

    func testLandscapePhotoFillsAPortraitStageWithTheTopAndBottomKeptButSidesCropped() {
        // A 4:3 landscape photo on a portrait stage: the height is matched, most of the width is off screen.
        let stage = CGSize(width: 390, height: 845)
        let r = TagPlacement.displayedRect(image: CGSize(width: 4000, height: 3000), in: stage, mode: .fill)
        XCTAssertEqual(r.height, 845, accuracy: 0.01)
        XCTAssertEqual(r.width, 845 * 4 / 3, accuracy: 0.01)
        XCTAssertEqual(r.midX, 195, accuracy: 0.01)
        // The thing at the photo's right third sits right of the stage's middle, at the right height.
        let p = TagPlacement.stagePoint(CGPoint(x: 0.66, y: 0.25), in: r)
        XCTAssertEqual(p.y, 845 * 0.25, accuracy: 0.01)
        XCTAssertGreaterThan(p.x, 195)
        XCTAssertEqual(p.x, r.minX + 0.66 * r.width, accuracy: 0.01)
    }

    func testAspectFitLetterboxesInsteadOfCropping() {
        // The same landscape photo fit inside the stage: the width is matched, bands above and below.
        let stage = CGSize(width: 390, height: 845)
        let r = TagPlacement.displayedRect(image: CGSize(width: 4000, height: 3000), in: stage, mode: .fit)
        XCTAssertEqual(r.width, 390, accuracy: 0.01)
        XCTAssertEqual(r.height, 390 * 0.75, accuracy: 0.01)
        XCTAssertEqual(r.minX, 0, accuracy: 0.01)
        XCTAssertEqual(r.midY, 422.5, accuracy: 0.01)
        let corner = TagPlacement.stagePoint(.zero, in: r)
        XCTAssertEqual(corner.x, 0, accuracy: 0.01)
        XCTAssertEqual(corner.y, (845 - 390 * 0.75) / 2, accuracy: 0.01)
        let box = TagPlacement.stageRect(CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5), in: r)
        XCTAssertEqual(box.maxX, 390, accuracy: 0.01)
        XCTAssertEqual(box.maxY, r.maxY, accuracy: 0.01)
    }

    func testAnEmptyPhotoOrStageNeverDividesByZero() {
        XCTAssertEqual(TagPlacement.displayedRect(image: .zero, in: CGSize(width: 10, height: 10), mode: .fill),
                       CGRect(x: 0, y: 0, width: 10, height: 10))
        XCTAssertEqual(TagPlacement.displayedRect(image: CGSize(width: 10, height: 10), in: .zero, mode: .fit), .zero)
    }

    // MARK: EXIF orientation

    func testACameraPhotoStoredOnItsSideIsReadUpright() {
        // A photo taken holding the phone upright is stored as a 4000×3000 bitmap with `.right`: upright it is 3000×4000.
        XCTAssertEqual(TagPlacement.uprightSize(pixels: CGSize(width: 4000, height: 3000), orientation: .right),
                       CGSize(width: 3000, height: 4000))
        XCTAssertEqual(TagPlacement.uprightSize(pixels: CGSize(width: 4000, height: 3000), orientation: .up),
                       CGSize(width: 4000, height: 3000))
        // `.right`: the picture is the bitmap turned 90° clockwise — the bitmap's top-left corner ends up top-right,
        // its bottom-left corner top-left.
        XCTAssertEqual(TagPlacement.uprightPoint(CGPoint(x: 0, y: 0), orientation: .right), CGPoint(x: 1, y: 0))
        XCTAssertEqual(TagPlacement.uprightPoint(CGPoint(x: 0, y: 1), orientation: .right), CGPoint(x: 0, y: 0))
        let p = TagPlacement.uprightPoint(CGPoint(x: 0.25, y: 0.1), orientation: .right)
        XCTAssertEqual(p.x, 0.9, accuracy: 1e-9)
        XCTAssertEqual(p.y, 0.25, accuracy: 1e-9)
        // `.left`: 90° counter-clockwise — the bitmap's top-left ends up bottom-left; `.down`: 180°.
        XCTAssertEqual(TagPlacement.uprightPoint(CGPoint(x: 0, y: 0), orientation: .left), CGPoint(x: 0, y: 1))
        XCTAssertEqual(TagPlacement.uprightPoint(CGPoint(x: 1, y: 0), orientation: .left), CGPoint(x: 0, y: 0))
        let down = TagPlacement.uprightPoint(CGPoint(x: 0.2, y: 0.3), orientation: .down)
        XCTAssertEqual(down.x, 0.8, accuracy: 1e-9)
        XCTAssertEqual(down.y, 0.7, accuracy: 1e-9)
        XCTAssertEqual(TagPlacement.uprightPoint(CGPoint(x: 0.2, y: 0.3), orientation: .up), CGPoint(x: 0.2, y: 0.3))
    }

    func testARectTurnsWithItsBitmap() {
        // The box at the bitmap's bottom-left quarter is at the top-left quarter once a `.right` photo is upright.
        let r = TagPlacement.uprightRect(CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5), orientation: .right)
        XCTAssertEqual(r.minX, 0, accuracy: 1e-9)
        XCTAssertEqual(r.minY, 0, accuracy: 1e-9)
        XCTAssertEqual(r.width, 0.5, accuracy: 1e-9)
        XCTAssertEqual(r.height, 0.5, accuracy: 1e-9)
    }

    func testAnEXIFRotatedPhotoLandsWhereItShowsOnTheStage() {
        // The thing at the stored bitmap's (0.25, 0.1) of a `.right` photo shows at (0.9, 0.25) of the upright
        // picture; on a portrait stage that is right of the middle, a quarter of the way down.
        let pixels = CGSize(width: 4000, height: 3000)
        let upright = TagPlacement.uprightSize(pixels: pixels, orientation: .right)
        let p = TagPlacement.uprightPoint(CGPoint(x: 0.25, y: 0.1), orientation: .right)
        let stage = CGSize(width: 390, height: 845)
        let on = TagPlacement.stagePoint(p, image: upright, in: stage, mode: .fill)
        let fill = TagPlacement.displayedRect(image: upright, in: stage, mode: .fill)
        XCTAssertEqual(on.y, fill.minY + 0.25 * fill.height, accuracy: 0.01)
        XCTAssertGreaterThan(on.x, 195)
    }

    // MARK: Missing and shared positions

    func testTheSamePlaceTwiceIsOnlyOnePlace() {
        let flags = TagPlacement.distinct([CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.505, y: 0.5), nil, CGPoint(x: 0.2, y: 0.2)])
        XCTAssertEqual(flags, [true, false, false, true])
    }

    func testSpreadSpotsNeverGatherAtOnePoint() {
        let spots = TagPlacement.spreadSpots(count: 4, avoiding: [])
        XCTAssertEqual(spots.count, 4)
        for i in spots.indices {
            for j in spots.indices where j > i {
                XCTAssertGreaterThan(hypot(spots[i].x - spots[j].x, spots[i].y - spots[j].y), 0.15,
                                     "spots \(i) and \(j) are too close: \(spots[i]) \(spots[j])")
            }
            XCTAssertTrue((0.05...0.95).contains(spots[i].x) && (0.05...0.95).contains(spots[i].y), "inside the photo")
        }
        // The middle is already taken by a placed thing: no spread spot goes there.
        let clear = TagPlacement.spreadSpots(count: 3, avoiding: [CGPoint(x: 0.5, y: 0.5)])
        for s in clear { XCTAssertGreaterThan(hypot(s.x - 0.5, s.y - 0.5), 0.15) }
        XCTAssertEqual(TagPlacement.spreadSpots(count: 0, avoiding: []), [])
    }

    // MARK: Through CatchObject.build (no Vision, as on the simulator)

    func testAServerAnswerWithoutPositionsSpreadsTheTagsInsteadOfPilingThem() {
        // The owner's photo: tablet, cup, stylus, tissue — none with a point or box (2026-10-15).
        let objs = CatchObject.build(candidates: [cand("平板", group: 0, point: nil), cand("杯子", group: 1, point: nil),
                                                  cand("觸控筆", group: 2, point: nil), cand("衛生紙", group: 3, point: nil)],
                                     masks: nil, photoSize: CGSize(width: 3000, height: 4000))
        XCTAssertEqual(objs.count, 4)
        XCTAssertTrue(objs.allSatisfy { !$0.positioned })
        for i in objs.indices {
            for j in objs.indices where j > i {
                let d = hypot(objs[i].anchor.x - objs[j].anchor.x, objs[i].anchor.y - objs[j].anchor.y)
                XCTAssertGreaterThan(d, 0.15, "\(i) and \(j) share a place")
            }
        }
        XCTAssertNotNil(CatchObject.placementNote(objs))
        XCTAssertTrue(CatchObject.placementNote(objs)!.contains("4 of 4"))
    }

    func testTheSameBoxForTwoThingsKeepsTheFirstThereAndMovesTheOther() {
        let box: [Double] = [400, 300, 700, 700]
        let objs = CatchObject.build(candidates: [cand("杯子", group: 0, point: nil, box: box),
                                                  cand("盤子", group: 1, point: nil, box: box)],
                                     masks: nil, photoSize: CGSize(width: 1000, height: 1000))
        XCTAssertTrue(objs[0].positioned)
        XCTAssertFalse(objs[1].positioned)
        XCTAssertEqual(objs[0].anchor.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(objs[0].anchor.y, 0.55, accuracy: 1e-9)
        XCTAssertGreaterThan(hypot(objs[1].anchor.x - 0.5, objs[1].anchor.y - 0.55), 0.15)
    }

    func testAThingWithItsOwnPointKeepsItAndAPlacedListHasNoNote() {
        let objs = CatchObject.build(candidates: [cand("杯子", group: 0, point: [300, 600]), cand("盤子", group: 1, point: [700, 200])],
                                     masks: nil, photoSize: CGSize(width: 1000, height: 1000))
        XCTAssertEqual(objs[0].anchor, CGPoint(x: 0.3, y: 0.6))
        XCTAssertEqual(objs[1].anchor, CGPoint(x: 0.7, y: 0.2))
        XCTAssertTrue(objs.allSatisfy(\.positioned))
        XCTAssertNil(CatchObject.placementNote(objs))
    }

    func testTheDecoderKnowsWhenNoPositionCame() {
        XCTAssertFalse(cand("a", group: 0, point: nil).positioned)
        XCTAssertTrue(cand("a", group: 0, point: [500, 500]).positioned, "the middle given on purpose is a position")
        XCTAssertTrue(cand("a", group: 0, point: nil, box: [100, 100, 300, 300]).positioned)
        XCTAssertFalse(cand("a", group: 0, point: [], box: nil).positioned)
        // A point in 0–1 is still read as 0–1000.
        XCTAssertEqual(cand("a", group: 0, point: [0.25, 0.5]).point, [250, 500])
    }
}
