import Foundation
import CoreGraphics

public enum ActiveDisplay {
    public static func index(frames: [CGRect], pointer: CGPoint, fallback: Int? = nil) -> Int? {
        if let index = frames.firstIndex(where: { $0.contains(pointer) }) { return index }
        if let fallback, frames.indices.contains(fallback) { return fallback }
        return frames.isEmpty ? nil : 0
    }
}
