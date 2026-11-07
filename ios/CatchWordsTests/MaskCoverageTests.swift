import XCTest
@testable import CatchWords

/// The cut-out always contains the thing the word names (owner 2026-10-15: 冰火菠蘿油 held up in a selfie came out as the
/// person alone, and the album sticker showed no bun). Pure decisions on mask counts (`CutCoverage`,
/// `CutoutService.isPerson`); Vision itself does not run on the simulator. Run on its own by
/// .github/workflows/ios-check.yml.
final class MaskCoverageTests: XCTestCase {
    // A 100 × 100 grid: the AI boxed the bun at 40…60 × 40…60 (400 pixels).
    private let boxArea = 400

    func testTheThingItselfIsKept() {
        // The bun's own instance (label 2), all inside its box.
        XCTAssertEqual(CutCoverage.decide(chosen: 2, inBox: [2: 300], totals: [2: 310], boxArea: boxArea), .keep)
        // A thin thing (a bicycle) fills little of its box but lies inside it.
        XCTAssertEqual(CutCoverage.decide(chosen: 3, inBox: [3: 90], totals: [3: 120], boxArea: boxArea), .keep)
    }

    func testAPersonHoldingTheThingAsOneInstanceIsKept() {
        // Vision made the person and the bun one instance: it fills the bun's box although most of it is outside.
        XCTAssertEqual(CutCoverage.decide(chosen: 1, inBox: [1: 380], totals: [1: 3000], boxArea: boxArea), .keep)
    }

    func testThePersonAloneTakesInTheThingBesideThem() {
        // The person (1) only touches the box with a hand; the bun is its own instance (2) that went to no object.
        XCTAssertEqual(CutCoverage.decide(chosen: 1, inBox: [1: 60, 2: 300], totals: [1: 3000, 2: 320], boxArea: boxArea),
                       .union([1, 2]))
    }

    func testNothingCoversTheThingSoVisionLooksAgainNeverACrop() {
        // The bun is no instance at all: only the person's hand is in its box. Never cut to the box (owner 2026-10-16):
        // the instance is far larger than the box, so `CatchPlan` keeps it whole and has Vision look at the region.
        XCTAssertEqual(CutCoverage.decide(chosen: 1, inBox: [1: 60], totals: [1: 3000], boxArea: boxArea), .larger)
        // A small piece of another instance is not enough either.
        XCTAssertEqual(CutCoverage.decide(chosen: 1, inBox: [1: 60, 4: 70], totals: [1: 3000, 4: 900], boxArea: boxArea), .larger)
    }

    func testOneThingInSeveralInstancesIsCutOutTogether() {
        // The dorayaki (owner 2026-10-16): the ice cream (2, under the AI's point) and the two pancakes (5, 6), each
        // mostly inside the box, the ice cream alone filling a third of it.
        XCTAssertEqual(CutCoverage.decide(chosen: 2, inBox: [2: 130, 5: 110, 6: 100], totals: [2: 140, 5: 125, 6: 120],
                                          boxArea: boxArea), .union([2, 5, 6]))
        // Another thing's own instance is never taken in.
        XCTAssertEqual(CutCoverage.decide(chosen: 2, inBox: [2: 130, 5: 110, 6: 100], totals: [2: 140, 5: 125, 6: 120],
                                          boxArea: boxArea, excluding: [6]), .union([2, 5]))
        // A speck in the box is no piece: the instance stays as it is.
        XCTAssertEqual(CutCoverage.decide(chosen: 2, inBox: [2: 130, 7: 10], totals: [2: 140, 7: 10], boxArea: boxArea), .keep)
        // A thin thing's other half (a lint roller's handle 20, its roller 45 of a 400 box mostly floor): under
        // `pieceGain` of the box, but no speck next to what the handle has there (owner 2026-11-03).
        XCTAssertEqual(CutCoverage.decide(chosen: 2, inBox: [2: 20, 8: 45], totals: [2: 20, 8: 45], boxArea: boxArea),
                       .union([2, 8]))
    }

    func testNoBoxOrNoCountsKeepsTheInstance() {
        XCTAssertEqual(CutCoverage.decide(chosen: 1, inBox: [:], totals: [1: 100], boxArea: 0), .keep)
        XCTAssertEqual(CutCoverage.decide(chosen: 1, inBox: [:], totals: [:], boxArea: boxArea), .keep)
    }

    func testSelfieKeepsWhatThePersonHolds() {
        // Owner 2026-11-07: once a person is found, every foreground instance stays (the egg carton held in front of
        // the body hid the body and was dropped by the old "within reach of the person" rule). Only the person test is
        // left: a person, and not a thing.
        XCTAssertTrue(CutoutService.isPerson(total: 1000, onPerson: 600))
        XCTAssertTrue(CutoutService.isPerson(total: 1000, onPerson: 300))
        XCTAssertFalse(CutoutService.isPerson(total: 11000, onPerson: 200))
        XCTAssertFalse(CutoutService.isPerson(total: 5000, onPerson: 0))
        XCTAssertFalse(CutoutService.isPerson(total: 0, onPerson: 0))
    }

    func testTheAIsBoxIsRead() throws {
        let json = #"{"headword":"冰火菠蘿油","box_2d":[400,300,700,600]}"#
        let c = try JSONDecoder().decode(Candidate.self, from: Data(json.utf8))
        let box = try XCTUnwrap(c.objectBox)
        XCTAssertEqual(box.minX, 0.3, accuracy: 0.0001)
        XCTAssertEqual(box.minY, 0.4, accuracy: 0.0001)
        XCTAssertEqual(box.width, 0.3, accuracy: 0.0001)
        XCTAssertEqual(box.height, 0.3, accuracy: 0.0001)
        // A broken box is no box.
        let broken = try JSONDecoder().decode(Candidate.self, from: Data(#"{"headword":"x","box_2d":[700,300,400,600]}"#.utf8))
        XCTAssertNil(broken.objectBox)
        XCTAssertNil(try JSONDecoder().decode(Candidate.self, from: Data(#"{"headword":"x"}"#.utf8)).objectBox)
    }
}
