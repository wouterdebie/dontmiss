import AppKit

@MainActor
enum MenuBarIcon {
    static let regular = load("DontMissTemplate")
    static let attention = load("DontMissAttentionTemplate")

    private static func load(_ name: String) -> NSImage? {
        guard let image = NSImage(named: name), image.isValid else {
            NSLog("Don't Miss: missing menu-bar image %@. Run the bundled app; using a system bell instead.", name)
            return nil
        }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }

    static func checkResources() -> Bool {
        for (name, image) in [("DontMissTemplate", regular), ("DontMissAttentionTemplate", attention)] {
            guard let image, image.isTemplate, image.size == NSSize(width: 18, height: 18) else {
                print("FAIL: menu-bar template \(name) did not load correctly.")
                return false
            }
            for (suffix, pixels) in [("", 18), ("@2x", 36), ("@3x", 54)] {
                guard let url = Bundle.main.url(forResource: name + suffix, withExtension: "png") else {
                    print("FAIL: missing menu-bar resource \(name)\(suffix).png")
                    return false
                }
                do {
                    let data = try Data(contentsOf: url)
                    guard let bitmap = NSBitmapImageRep(data: data),
                          bitmap.pixelsWide == pixels, bitmap.pixelsHigh == pixels, bitmap.hasAlpha else {
                        print("FAIL: invalid menu-bar dimensions/alpha for \(name)\(suffix).png")
                        return false
                    }
                } catch {
                    print("FAIL: could not read \(name)\(suffix).png: \(error.localizedDescription)")
                    return false
                }
            }
        }
        return true
    }
}
