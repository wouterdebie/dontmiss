import AppKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}

guard CommandLine.arguments.count == 2 else {
    fail("Usage: swift scripts/require-stopped-app.swift /path/to/Don't Miss.app")
}
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
    .standardizedFileURL.resolvingSymlinksInPath()
for app in NSRunningApplication.runningApplications(withBundleIdentifier: "dev.wouter.dontmiss") where !app.isTerminated {
    guard let bundleURL = app.bundleURL else {
        fail("Cannot locate running Don't Miss process \(app.processIdentifier). Quit it before bundling.")
    }
    if bundleURL.standardizedFileURL.resolvingSymlinksInPath() == destination {
        fail("Refusing to replace running Don't Miss (PID \(app.processIdentifier)) at \(destination.path). Quit it first, or run the installed copy in Applications instead.")
    }
}
