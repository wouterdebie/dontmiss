import Foundation
import Testing
@testable import DontMissCore

struct ActiveDisplayTests {
    let frames = [
        CGRect(x: 0, y: 0, width: 3200, height: 1800),
        CGRect(x: 2482, y: -1169, width: 1800, height: 1169),
        CGRect(x: -3200, y: 90, width: 3200, height: 1800)
    ]

    @Test func selectsMouseDisplayInsteadOfPrimary() {
        #expect(ActiveDisplay.index(frames: frames, pointer: CGPoint(x: -1600, y: 500), fallback: 0) == 2)
        #expect(ActiveDisplay.index(frames: frames, pointer: CGPoint(x: 3000, y: -500), fallback: 0) == 1)
        #expect(ActiveDisplay.index(frames: frames, pointer: CGPoint(x: 2000, y: 1000), fallback: 2) == 0)
    }

    @Test func sharedEdgeSelectsExactlyOneDisplay() {
        #expect(ActiveDisplay.index(frames: frames, pointer: CGPoint(x: 0, y: 500)) == 0)
    }

    @Test func gapAndDisconnectedDisplayFallback() {
        #expect(ActiveDisplay.index(frames: frames, pointer: CGPoint(x: -100, y: -100), fallback: 1) == 1)
        #expect(ActiveDisplay.index(frames: [frames[0]], pointer: CGPoint(x: -1600, y: 500), fallback: 2) == 0)
        #expect(ActiveDisplay.index(frames: [], pointer: .zero) == nil)
    }
}
