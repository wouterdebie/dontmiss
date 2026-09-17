import AppKit
import DontMissCore

@MainActor
enum AgendaPreview {
    static func meetings(now: Date) -> [Meeting] {
        let guests = [
            MeetingGuest(name: "Alex Rivera", email: "alex@example.invalid", response: "accepted", isOrganizer: true),
            MeetingGuest(name: "Sam Parker", email: "sam@example.invalid", response: "tentative"),
            MeetingGuest(name: "You", email: "preview@example.invalid", response: "accepted", isSelf: true)
        ]
        let titles = ["Product check-in", "A longer design review title that should wrap comfortably",
                      "Planning session", "Weekly team sync", "Coffee with Alex", "Project retrospective"]
        let offsets: [TimeInterval] = [1800, 5400, 86400, 100800, 172800, 345600]
        return zip(titles, offsets).enumerated().map { index, item in
            Meeting(eventID: "preview-\(index)", calendarID: "preview", calendarName: index == 4 ? "Personal" : "Work",
                    title: item.0, start: now.addingTimeInterval(item.1),
                    end: now.addingTimeInterval(item.1 + 1800),
                    joinURL: index == 4 ? nil : URL(string: "https://meet.google.com/abc-defg-hij"),
                    calendarURL: URL(string: "https://calendar.google.com/calendar/u/0/r"),
                    location: index == 4 ? "The coffee shop" : "Online",
                    notes: "Review this week's progress and agree on next steps.\n\nBring questions and ideas for the next release.",
                    organizer: guests.first, guests: guests, isRecurring: index == 0 || index == 3)
        }
    }

    static func save(view: NSView, to url: URL) throws {
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw PreviewError.capture
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let captured = bitmap.cgImage,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: bitmap.pixelsWide, height: bitmap.pixelsHigh,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw PreviewError.capture
        }
        // NSView capture excludes the window background; composite it for a faithful preview.
        var background = NSColor.windowBackgroundColor.cgColor
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            background = NSColor.windowBackgroundColor.cgColor
        }
        let bounds = CGRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        context.setFillColor(background)
        context.fill(bounds)
        context.draw(captured, in: bounds)
        guard let image = context.makeImage(),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw PreviewError.capture
        }
        try data.write(to: url, options: .atomic)
    }

    enum PreviewError: LocalizedError {
        case capture
        var errorDescription: String? { "Could not capture the native agenda preview." }
    }
}
