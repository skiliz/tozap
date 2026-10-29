import AppKit
import Observation
import SwiftUI

/// to.zap's design tokens: neutral graphite, no decorative colour. The only colours are functional:
/// a small green "connected" dot, red while the microphone records, and warning/error.
enum DS {
    enum Palette {
        static let panel = Color(white: 0.07)                 // near-black graphite
        static let surface = Color(white: 0.135)              // dark charcoal
        static let surfaceHover = Color(white: 0.165)
        static let surfacePressed = Color(white: 0.21)
        static let notch = Color.black
        static let border = Color.white.opacity(0.075)
        static let borderStrong = Color.white.opacity(0.22)
        static let textPrimary = Color.white.opacity(0.94)
        static let textSecondary = Color(red: 0.69, green: 0.705, blue: 0.73)   // cool-neutral gray
        static let textTertiary = Color(white: 0.62)
        static let connected = Color(red: 0.29, green: 0.78, blue: 0.40)
        static let recording = Color(red: 1.0, green: 0.27, blue: 0.24)
        static let warning = Color(red: 0.98, green: 0.70, blue: 0.26)
        static let error = Color(red: 1.0, green: 0.38, blue: 0.35)

        /// Borders that strengthen with Increase Contrast.
        @MainActor static var cardBorder: Color { AccessibilityPrefs.shared.increaseContrast ? borderStrong : border }
        @MainActor static var capsuleStroke: Color {
            AccessibilityPrefs.shared.increaseContrast ? Color.white.opacity(0.35) : Color.white.opacity(0.07)
        }
    }

    enum Radius {
        static let tile: CGFloat = 12
        static let card: CGFloat = 12
        static let row: CGFloat = 8
    }

    enum Size {
        static let notchHeight: CGFloat = 32
        static let notchMinWidth: CGFloat = 164
        static let header: CGFloat = 32
        static let tileHeight: CGFloat = 62
        static let tileIcon: CGFloat = 26
        static let media: CGFloat = 40
        static let dpad: CGFloat = 172
        static let ok: CGFloat = 64
        static let round: CGFloat = 40
        static let pill: CGFloat = 46
        static let settingsButton: CGFloat = 26
    }

    /// The Settings window: neutral dark graphite, a quiet gray selection, no blue chips or glows.
    enum Settings {
        static let windowBackground = Color(red: 0.071, green: 0.075, blue: 0.082)
        static let panel = Color(red: 0.102, green: 0.106, blue: 0.118)
        static let group = Color.white.opacity(0.045)
        static let groupHover = Color.white.opacity(0.075)
        static let groupPressed = Color.white.opacity(0.11)
        static let selection = Color.white.opacity(0.105)
        static let hover = Color.white.opacity(0.05)
        /// The approved switches are green; used only for "on" switches and the selected radio.
        static let on = Color(red: 0.22, green: 0.66, blue: 0.36)
        static let danger = Color(red: 1.0, green: 0.42, blue: 0.38)
        static let dangerFill = Color(red: 1.0, green: 0.30, blue: 0.26).opacity(0.11)
        static let dangerFillHover = Color(red: 1.0, green: 0.30, blue: 0.26).opacity(0.17)

        static let sidebarWidth: CGFloat = 206
        static let panelRadius: CGFloat = 14
        static let groupRadius: CGFloat = 10
        static let rowMinHeight: CGFloat = 54
        static let contentPadding: CGFloat = 28

        @MainActor static var divider: Color {
            AccessibilityPrefs.shared.increaseContrast ? Color.white.opacity(0.22) : Color.white.opacity(0.075)
        }
        @MainActor static var panelStroke: Color {
            AccessibilityPrefs.shared.increaseContrast ? Color.white.opacity(0.3) : Color.white.opacity(0.06)
        }
    }

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let section: CGFloat = 14
        static let panel: CGFloat = 14
    }

    /// One rhythm for every animation; Reduce Motion swaps movement for short crossfades.
    enum Motion {
        static let press = Animation.easeOut(duration: 0.1)
        static func small(_ reduce: Bool) -> Animation {
            reduce ? .easeInOut(duration: 0.15) : .spring(response: 0.22, dampingFraction: 1)
        }
        static func capsule(_ reduce: Bool) -> Animation {
            reduce ? .easeInOut(duration: 0.18) : .spring(response: 0.32, dampingFraction: 1)
        }
        static func pressScale(_ pressed: Bool, _ reduce: Bool) -> CGFloat { pressed && !reduce ? 0.97 : 1 }
    }
}

/// The system's accessibility display options, kept current while to.zap runs.
@MainActor
@Observable
final class AccessibilityPrefs {
    static let shared = AccessibilityPrefs()
    private(set) var reduceMotion = false
    private(set) var reduceTransparency = false
    private(set) var increaseContrast = false

    /// System Reduce Motion, or to.zap's own "Animation feedback" turned off: movement becomes a fade.
    var motionReduced: Bool { reduceMotion || !AppPreferences.shared.animationFeedback }

    private init() {
        refresh()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { AccessibilityPrefs.shared.refresh() }
        }
    }

    func refresh() {
        let workspace = NSWorkspace.shared
#if ZAP_DEVTOOLS
        reduceMotion = workspace.accessibilityDisplayShouldReduceMotion
            || UserDefaults.standard.bool(forKey: "debugReduceMotion")
#else
        reduceMotion = workspace.accessibilityDisplayShouldReduceMotion
#endif
        reduceTransparency = workspace.accessibilityDisplayShouldReduceTransparency
        increaseContrast = workspace.accessibilityDisplayShouldIncreaseContrast
    }
}

/// Hover tracking for a single control (a reference type, since the toolchain lacks SwiftUI's @State macro).
final class HoverState: ObservableObject {
    @Published var isHovering = false
}

/// The one surface used by every remote control: opaque smoked graphite with a soft top light and a hairline
/// edge. Deliberately not translucent, so the desktop never tints the remote (no green or blue cast).
struct GraphiteSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    var pressed = false
    var hovering = false
    var raised = false

    func body(content: Content) -> some View {
        let contrast = AccessibilityPrefs.shared.increaseContrast
        let base: Double = pressed ? 0.205 : (hovering ? 0.17 : (raised ? 0.16 : 0.135))
        let fill = LinearGradient(colors: [Color(white: base + 0.03), Color(white: base - 0.012)],
                                  startPoint: .top, endPoint: .bottom)
        let edge = LinearGradient(colors: [Color.white.opacity(contrast ? 0.36 : 0.12),
                                           Color.white.opacity(contrast ? 0.24 : 0.035)],
                                  startPoint: .top, endPoint: .bottom)
        content
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(edge, lineWidth: 1))
    }
}

extension View {
    func graphiteSurface<S: InsettableShape>(_ shape: S, pressed: Bool = false, hovering: Bool = false,
                                             raised: Bool = false) -> some View {
        modifier(GraphiteSurface(shape: shape, pressed: pressed, hovering: hovering, raised: raised))
    }
}

/// Section label used in Settings.
struct SectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(DS.Palette.textSecondary)
            .accessibilityAddTraits(.isHeader)
    }
}
