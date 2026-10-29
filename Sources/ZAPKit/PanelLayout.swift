import CoreGraphics

/// Sizing rules for the menu bar panel, kept separate from SwiftUI so they can be unit-tested.
public enum PanelLayout {
    public static let width: CGFloat = 304
    /// Header, paddings and the gap macOS leaves under the menu bar.
    public static let chrome: CGFloat = 104
    /// Below this the panel scrolls rather than shrinking controls.
    public static let minimumScrollHeight: CGFloat = 240

    /// Height available to the scrolling page content on a screen whose visible frame
    /// (menu bar and Dock excluded) is `visibleHeight` points tall.
    public static func maxScrollHeight(visibleHeight: CGFloat) -> CGFloat {
        max(minimumScrollHeight, visibleHeight - chrome)
    }

    /// The page area: its natural height, capped so the whole panel stays on screen.
    public static func scrollHeight(content: CGFloat, visibleHeight: CGFloat) -> CGFloat {
        min(content, maxScrollHeight(visibleHeight: visibleHeight))
    }
}
