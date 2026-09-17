import AppKit
import SwiftUI

enum ReminderPalette {
    static let cyan = Color(red: 0x7D / 255.0, green: 1, blue: 0xF0 / 255.0)
    static let blue = Color(red: 0x57 / 255.0, green: 0xB8 / 255.0, blue: 1)
    static let purple = Color(red: 0xA4 / 255.0, green: 0x5C / 255.0, blue: 1)
    static let text = Color(red: 0.93, green: 0.95, blue: 1)
    static let secondaryText = Color(red: 0.72, green: 0.78, blue: 0.89)
    static let ink = Color(red: 0x0A / 255.0, green: 0x10 / 255.0, blue: 0x20 / 255.0)

    static func accent(for scheme: ColorScheme) -> Color {
        scheme == .dark ? blue : Color(red: 0x17 / 255.0, green: 0x64 / 255.0, blue: 0xB5 / 255.0)
    }

    static func gradient(for scheme: ColorScheme) -> LinearGradient {
        let colors = scheme == .dark ? [cyan, blue, purple] : [
            Color(red: 0, green: 0x75 / 255.0, blue: 0x7D / 255.0),
            accent(for: scheme),
            Color(red: 0x73 / 255.0, green: 0x37 / 255.0, blue: 0xBE / 255.0)
        ]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct AppIconView: View {
    let size: CGFloat

    private static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let image = NSImage(contentsOf: url), image.isValid else {
            NSLog("Don't Miss: missing or invalid AppIcon.icns. Run the bundled app; using a system bell instead.")
            return nil
        }
        image.isTemplate = false
        return image
    }()

    var body: some View {
        Group {
            if let image = Self.image {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            } else {
                Image(systemName: "bell.fill")
                    .font(.system(size: size * 0.6))
                    .foregroundStyle(ReminderPalette.blue)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    static func checkResource() -> Bool {
        guard let image, !image.isTemplate,
              image.representations.contains(where: { $0.pixelsWide == 1024 && $0.pixelsHigh == 1024 }) else {
            print("FAIL: in-app icon must load the full-color, high-resolution AppIcon.icns.")
            return false
        }
        return true
    }
}
