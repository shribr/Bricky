import XCTest
import SceneKit
@testable import Bricky

/// Covers the "add these pieces now" polish on the 3D build viewer: the pulsing
/// highlight lifecycle keyed on `BrickStepStyler.pulseActionKey`.
///
/// SCNActions only *tick* while the node is in a rendered scene, so these tests
/// verify the action lifecycle (start / stop / idempotency), which is the logic
/// the viewer relies on to cleanly start and stop the pulse as steps change. The
/// per-frame glow itself is a pure visual effect and isn't asserted here.
final class BuildStepViewerPolishTests: XCTestCase {

    /// A brick-like node: a body geometry plus an outline shell, mirroring what
    /// the scene builders produce.
    private func brickNode() -> SCNNode {
        let brick = SCNNode(geometry: SCNBox(width: 8, height: 3, length: 8, chamferRadius: 0))
        brick.geometry?.firstMaterial?.diffuse.contents = UIColor.systemRed
        BrickStepStyler.addBoxOutline(to: brick, width: 8, height: 3, length: 8)
        return brick
    }

    func testStartPulsingAttachesKeyedAction() {
        let node = brickNode()
        XCTAssertNil(node.action(forKey: BrickStepStyler.pulseActionKey))

        BrickStepStyler.startPulsing(node)

        XCTAssertNotNil(node.action(forKey: BrickStepStyler.pulseActionKey),
                        "Current-step piece should carry the pulse action")
    }

    func testStartPulsingIsIdempotent() {
        let node = brickNode()
        BrickStepStyler.startPulsing(node)
        let first = node.action(forKey: BrickStepStyler.pulseActionKey)

        BrickStepStyler.startPulsing(node)
        let second = node.action(forKey: BrickStepStyler.pulseActionKey)

        // Re-styling (e.g. the see-through slider) must not restart or stack the
        // pulse — the same action stays in place.
        XCTAssertTrue(first === second,
                      "Repeated startPulsing should keep the existing action, not replace it")
    }

    func testStopPulsingRemovesAction() {
        let node = brickNode()
        BrickStepStyler.startPulsing(node)
        XCTAssertNotNil(node.action(forKey: BrickStepStyler.pulseActionKey))

        BrickStepStyler.stopPulsing(node)

        XCTAssertNil(node.action(forKey: BrickStepStyler.pulseActionKey),
                     "Leaving the current step must remove the pulse cleanly")
    }

    func testStopPulsingIsSafeWhenNotPulsing() {
        let node = brickNode()
        // No action attached — stopping should be a harmless no-op.
        BrickStepStyler.stopPulsing(node)
        XCTAssertNil(node.action(forKey: BrickStepStyler.pulseActionKey))
    }

    func testStartStopCyclesLeaveNoLingeringAction() {
        let node = brickNode()
        for _ in 0..<5 {
            BrickStepStyler.startPulsing(node)
            BrickStepStyler.stopPulsing(node)
        }
        XCTAssertNil(node.action(forKey: BrickStepStyler.pulseActionKey),
                     "Stepping back and forth repeatedly must not leave a stuck pulse")
    }
}
