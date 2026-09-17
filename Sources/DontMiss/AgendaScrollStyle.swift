import AppKit
import SwiftUI

struct AgendaScrollStyle: NSViewRepresentable {
    func makeNSView(context: Context) -> ScrollStyleView { ScrollStyleView() }

    func updateNSView(_ nsView: ScrollStyleView, context: Context) { nsView.applyStyle() }

    final class ScrollStyleView: NSView {
        private weak var scrollView: NSScrollView?
        private var styleObservation: NSKeyValueObservation?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyStyle()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            applyStyle()
        }

        func applyStyle() {
            guard let enclosingScrollView else { return }
            if scrollView !== enclosingScrollView {
                scrollView = enclosingScrollView
                // SwiftUI can reset this property after configuring its scroll view.
                styleObservation = enclosingScrollView.observe(\.scrollerStyle, options: [.new]) { [weak self] _, change in
                    guard change.newValue != .overlay else { return }
                    MainActor.assumeIsolated { self?.enforceStyle() }
                }
            }
            enforceStyle()
        }

        private func enforceStyle() {
            guard let scrollView else { return }
            if scrollView.scrollerStyle != .overlay { scrollView.scrollerStyle = .overlay }
            if scrollView.verticalScroller?.controlSize != .small { scrollView.verticalScroller?.controlSize = .small }
        }
    }
}
