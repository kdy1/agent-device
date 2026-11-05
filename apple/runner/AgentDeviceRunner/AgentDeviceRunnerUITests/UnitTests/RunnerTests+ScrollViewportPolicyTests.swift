import XCTest
import AgentDeviceSnapshotPresentation

#if AGENT_DEVICE_RUNNER_UNIT_TESTS
private struct ScrollViewportPolicyFixture: Decodable {
  struct Frame: Decodable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    var cgRect: CGRect {
      CGRect(x: x, y: y, width: width, height: height)
    }
  }

  struct Constants: Decodable {
    let minVisibleFraction: Double
    let accessoryAllowance: Double
  }

  struct Expected: Decodable {
    let kind: String
    let viewport: Frame?
    let keyboardMinY: Double?
    let visibleHeight: Double?
  }

  struct TestCase: Decodable {
    let name: String
    let viewport: Frame
    let keyboard: Frame
    let expected: Expected
  }

  let constants: Constants
  let cases: [TestCase]
}

extension RunnerTests {
  /// Golden parity table (#2500): every case in contracts/fixtures/scroll-keyboard-policy.json must
  /// agree with the vitest twin. Add cases there, never fork the rule.
  func testScrollViewportKeyboardClipMatchesGoldenParityTable() throws {
    let fixture = try loadScrollViewportPolicyFixture()
    XCTAssertFalse(fixture.cases.isEmpty, "parity table must not be empty")
    for testCase in fixture.cases {
      let clip = ScrollViewportPolicy.clip(
        viewport: testCase.viewport.cgRect,
        keyboard: testCase.keyboard.cgRect
      )
      switch testCase.expected.kind {
      case "unobstructed":
        XCTAssertEqual(clip, .unobstructed, testCase.name)
      case "avoided":
        let expectedFrame = try XCTUnwrap(testCase.expected.viewport, testCase.name).cgRect
        let expectedMinY = try XCTUnwrap(testCase.expected.keyboardMinY, testCase.name)
        XCTAssertEqual(
          clip,
          .avoided(frame: expectedFrame, keyboardMinY: expectedMinY),
          testCase.name
        )
      case "occluded":
        let expectedMinY = try XCTUnwrap(testCase.expected.keyboardMinY, testCase.name)
        let expectedVisibleHeight = try XCTUnwrap(testCase.expected.visibleHeight, testCase.name)
        XCTAssertEqual(
          clip,
          .occluded(keyboardMinY: expectedMinY, visibleHeight: expectedVisibleHeight),
          testCase.name
        )
      default:
        XCTFail("unknown expected kind `\(testCase.expected.kind)` in \(testCase.name)")
      }
    }
  }

  /// The thresholds are the table's, not RunnerScrollViewportPolicy.swift's. The refusal reason
  /// and the runner code are each one side's own vocabulary: the reason is what the host publishes,
  /// the code is what this runner answers with, and neither is a shared clip constant.
  func testScrollViewportPolicyUsesParityTableConstants() throws {
    let constants = try loadScrollViewportPolicyFixture().constants
    XCTAssertEqual(constants.minVisibleFraction, ScrollViewportPolicy.minVisibleFraction)
    XCTAssertEqual(constants.accessoryAllowance, ScrollViewportPolicy.accessoryAllowance)
  }

  /// The swipe hands its drag the keyboard frame the clip was decided on, so the drag avoids that
  /// frame without probing the keyboard again; an occluded viewport dispatches nothing.
  func testScrollDispatchCarriesTheKeyboardFrameItsViewportWasResolvedAgainst() {
    let viewport = CGRect(x: 0, y: 0, width: 402, height: 874)
    let docked = CGRect(x: 0, y: 538, width: 402, height: 336)
    let cases: [(clip: RunnerScrollKeyboardClip, keyboardFrame: CGRect?)] = [
      (.unobstructed, nil),
      (.unobstructed, CGRect(x: 20, y: 500, width: 120, height: 200)),
      (.avoided(frame: CGRect(x: 0, y: 0, width: 402, height: 526), keyboardMinY: 538), docked),
    ]
    for testCase in cases {
      let resolved = ScrollViewportPolicy.frames(
        referenceFrame: viewport,
        clip: testCase.clip,
        keyboardFrame: testCase.keyboardFrame
      )
      guard case .gesture(let dispatch) = resolved.gestureDispatch(direction: .down, amount: nil, pixels: nil) else {
        return XCTFail("\(testCase.clip) dispatches no gesture")
      }
      XCTAssertEqual(dispatch.keyboardFrame, testCase.keyboardFrame, "\(testCase.clip)")
    }
    let occluded = ScrollViewportPolicy.frames(
      referenceFrame: viewport,
      clip: .occluded(keyboardMinY: 120, visibleHeight: 108),
      keyboardFrame: docked
    )
    guard case .occluded = occluded.gestureDispatch(direction: .down, amount: nil, pixels: nil) else {
      return XCTFail("an occluded viewport dispatches a gesture")
    }
  }

  private func loadScrollViewportPolicyFixture() throws -> ScrollViewportPolicyFixture {
    let fixtureURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent() // UnitTests
      .deletingLastPathComponent() // AgentDeviceRunnerUITests
      .deletingLastPathComponent() // AgentDeviceRunner
      .deletingLastPathComponent() // runner
      .deletingLastPathComponent() // apple
      .deletingLastPathComponent() // repo root
      .appendingPathComponent("contracts")
      .appendingPathComponent("fixtures")
      .appendingPathComponent("scroll-keyboard-policy.json")
    return try JSONDecoder().decode(
      ScrollViewportPolicyFixture.self,
      from: Data(contentsOf: fixtureURL)
    )
  }
}
#endif
