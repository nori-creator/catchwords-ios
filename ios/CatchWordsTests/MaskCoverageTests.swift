import XCTest
@testable import CatchWords

/// The cut-out always contains the thing the word names (owner 2026-10-15: 冰火菠蘿油 held up in a selfie came out as the
/// person alone, and the album sticker showed no bun). Pure decisions on mask counts (`CutCoverage`,
/// `CutoutService.keepsWithPeople`); Vision itself does not run on the simulator. Run on its own by
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

    func testNothingCoversTheThingSoThePhotoRoundItIsUsed() {
        // The bun is no instance at all: only the person's hand is in its box.
        XCTAssertEqual(CutCoverage.decide(chosen: 1, inBox: [1: 60], totals: [1: 3000], boxArea: boxArea), .crop)
        // A small piece of another instance is not enough either.
        XCTAssertEqual(CutCoverage.decide(chosen: 1, inBox: [1: 60, 4: 70], totals: [1: 3000, 4: 900], boxArea: boxArea), .crop)
    }

    func testNoBoxOrNoCountsKeepsTheInstance() {
        XCTAssertEqual(CutCoverage.decide(chosen: 1, inBox: [:], totals: [1: 100], boxArea: 0), .keep)
        XCTAssertEqual(CutCoverage.decide(chosen: 1, inBox: [:], totals: [:], boxArea: boxArea), .keep)
    }

    func testSelfieKeepsWhatThePersonHolds() {
        // A person.
        XCTAssertTrue(CutoutService.keepsWithPeople(total: 1000, onPerson: 600, nearPerson: 1000))
        // A big bun held up to the camera: it touches the person only along the hand (10 % of it within reach).
        XCTAssertTrue(CutoutService.keepsWithPeople(total: 11000, onPerson: 200, nearPerson: 1100))
        // A drink held beside the face, mostly within reach.
        XCTAssertTrue(CutoutService.keepsWithPeople(total: 400, onPerson: 20, nearPerson: 200))
        // A thing standing apart, and a speck that merely grazes the reach.
        XCTAssertFalse(CutoutService.keepsWithPeople(total: 5000, onPerson: 0, nearPerson: 0))
        XCTAssertFalse(CutoutService.keepsWithPeople(total: 5000, onPerson: 0, nearPerson: 3))
        XCTAssertFalse(CutoutService.keepsWithPeople(total: 0, onPerson: 0, nearPerson: 0))
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
