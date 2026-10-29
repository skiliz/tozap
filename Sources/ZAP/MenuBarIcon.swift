import AppKit
import Observation
import ZAPKit

/// The menu bar icon: the approved slim remote silhouette (body, D-pad ring with select button, middle and
/// bottom buttons) with small status lights inside it, like LEDs on a real remote:
///   middle button — connection: green dot (confirmed recently), red dot with a dimmed remote (confirmed
///                   failure), amber ring (reconnecting, gently blinking), gray (preview: filled; not checked or
///                   not recent: hollow);
///                   red with a ring while the microphone records;
///   bottom button — blue while macOS shows the screen on the TV;
///   D-pad         — a brief fill when the TV accepts a command.
/// The silhouette is drawn in the label colour of the menu bar it sits in (vector, redrawn for each appearance),
/// so it reads on light and dark menu bars; colour is never the only signal (tooltip, VoiceOver, shape).
enum MenuBarIcon {
    struct State: Hashable {
        var link: MenuBarStatus.Link
        var listening: Bool
        var command: Bool
        var mirroring: Bool
        /// Reconnecting blink step, 0…3 (always 0 when still).
        var phase: Int
    }

    static let size = NSSize(width: 18, height: 18)

    @MainActor private static var cache: [State: NSImage] = [:]

    @MainActor
    static func image(_ state: State) -> NSImage {
        if let cached = cache[state] { return cached }
        let image = NSImage(size: size, flipped: false) { _ in
            draw(state)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "to.zap"
        cache[state] = image
        return image
    }

    private static func circle(_ center: CGPoint, _ radius: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
    }

    /// Geometry in points on an 18 × 18 canvas (origin bottom-left). Dynamic colours resolve against the
    /// appearance being drawn, i.e. the menu bar's.
    private static func draw(_ state: State) {
        let dimmed = state.link == .unreachable && !state.listening
        let ink = dimmed ? NSColor.labelColor.withAlphaComponent(0.45) : NSColor.labelColor

        // Body.
        let body = NSBezierPath(roundedRect: NSRect(x: 4.9, y: 0.9, width: 8.2, height: 16.2), xRadius: 3.9, yRadius: 3.9)
        body.lineWidth = 1.25
        ink.setStroke()
        body.stroke()

        // D-pad ring and select button; filled for a moment when a command was accepted.
        let pad = CGPoint(x: 9, y: 12.25)
        ink.setFill()
        if state.command {
            let pressed = circle(pad, 2.85)
            pressed.append(circle(pad, 0.95))
            pressed.windingRule = .evenOdd
            pressed.fill()
        } else {
            let ring = circle(pad, 2.3)
            ring.lineWidth = 1.05
            ring.stroke()
            circle(pad, 0.85).fill()
        }

        // Middle button: microphone while recording, otherwise the connection light.
        let middle = CGPoint(x: 9, y: 6.8)
        if state.listening {
            NSColor.systemRed.setFill()
            circle(middle, 1.45).fill()
            NSColor.systemRed.setStroke()
            let ring = circle(middle, 2.0)
            ring.lineWidth = 0.75
            ring.stroke()
        } else {
            switch state.link {
            case .connected:
                NSColor.systemGreen.setFill()
                circle(middle, 1.45).fill()
            case .unreachable:
                NSColor.systemRed.setFill()
                circle(middle, 1.45).fill()
            case .reconnecting:
                let alpha: [CGFloat] = [1, 0.75, 0.45, 0.75]
                let amber = NSColor.systemOrange.withAlphaComponent(alpha[max(0, min(state.phase, 3))])
                amber.setStroke()
                let ring = circle(middle, 1.5)
                ring.lineWidth = 0.9
                ring.stroke()
                amber.setFill()
                circle(middle, 0.6).fill()
            case .preview:
                NSColor.secondaryLabelColor.setFill()
                circle(middle, 1.3).fill()
            case .unknown:
                NSColor.secondaryLabelColor.setStroke()
                let hollow = circle(middle, 1.15)
                hollow.lineWidth = 0.8
                hollow.stroke()
            }
        }

        // Bottom ("…") button: blue while the screen is shown on the TV.
        let bottom = CGPoint(x: 9, y: 2.9)
        if state.mirroring {
            NSColor.systemBlue.setFill()
            circle(bottom, 1.15).fill()
        } else {
            ink.setFill()
            circle(bottom, 0.8).fill()
        }
    }
}

/// Puts the status description on the menu bar button itself (tooltip and VoiceOver value). SwiftUI's
/// MenuBarExtra owns the button, so it is looked up among the app's status bar windows; if it can't be found,
/// nothing else is affected.
@MainActor
enum MenuBarStatusText {
    private static weak var button: NSStatusBarButton?

    /// Re-applies on every change of the menu bar state (Observation, no timer).
    static func track(_ model: RemoteModel) {
        withObservationTracking {
            apply(model.menuBarDescription, image: MenuBarIcon.image(model.menuBarState))
        } onChange: {
            Task { @MainActor in track(model) }
        }
    }

    /// The image is also set here, on the button itself, so AppKit draws the vector image with the menu bar's
    /// own appearance even if SwiftUI rendered the label differently.
    private static func apply(_ text: String, image: NSImage) {
        guard let button = button ?? find() else { return }
        self.button = button
        if button.image !== image { button.image = image }
        button.toolTip = text
        button.setAccessibilityValue(text)
    }

#if ZAP_DEVTOOLS
    /// For the developer demo: draws the menu bar button exactly as AppKit renders it (its image, in its own
    /// appearance) into a PNG — in-process, without screen recording.
    static func snapshot(to url: URL) {
        guard let button = button ?? find(), button.bounds.width > 0, button.bounds.height > 0,
              let rep = button.bitmapImageRepForCachingDisplay(in: button.bounds) else { return }
        button.cacheDisplay(in: button.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// For the developer demo log: is the button showing ZAP's colour image, and in which appearance?
    static func debugSummary(expected: NSImage) -> String {
        guard let button = button ?? find() else { return "status item button not found" }
        let image = button.image
        return "button found, image is to.zap's: \(image === expected), template: \(image?.isTemplate ?? false), "
            + "appearance: \(button.effectiveAppearance.name.rawValue)"
    }
#endif

    private static func find() -> NSStatusBarButton? {
        for window in NSApp.windows where String(describing: type(of: window)).contains("StatusBar") {
            if let found = window.contentView.flatMap(search) { return found }
        }
        return nil
    }

    private static func search(_ view: NSView) -> NSStatusBarButton? {
        if let button = view as? NSStatusBarButton { return button }
        for subview in view.subviews {
            if let found = search(subview) { return found }
        }
        return nil
    }
}
