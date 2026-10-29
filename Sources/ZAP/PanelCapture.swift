#if ZAP_DEVTOOLS
// Developer builds only (`ZAP_DEVTOOLS=1 scripts/build.sh`); not part of the public app.
import AppKit
import ScreenCaptureKit
import SwiftUI
import os

/// Developer tool for the README screenshots: captures to.zap's own panel window. Since macOS 14.4 a process
/// may capture its own windows without Screen Recording permission (`SCShareableContent.currentProcess`).
/// Reachable only through the hidden automation URLs.
@MainActor
enum PanelCapture {
    private static let log = Logger(subsystem: "local.tozap.app", category: "capture")

    private static var preview: NSPanel?

    /// Developer layout check: the same panel views in an ordinary window, so they can be captured
    /// without someone clicking the menu bar. Not used for the published screenshots.
    static func showPreview(_ show: Bool) {
        preview?.close()
        preview = nil
        guard show else { return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 304, height: 600),
                            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isReleasedWhenClosed = false
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.state = .active
        let host = NSHostingView(rootView: RemotePanel(model: RemoteModel.shared))
        host.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            host.topAnchor.constraint(equalTo: effect.topAnchor, constant: 8),
            host.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        panel.contentView = effect
        panel.setContentSize(host.fittingSize)
        if let screen = NSScreen.main {
            panel.setFrameTopLeftPoint(NSPoint(x: screen.visibleFrame.maxX - 340, y: screen.visibleFrame.maxY - 8))
        }
        panel.orderFrontRegardless()
        preview = panel
    }

    static func capture(to url: URL) async {
        guard #available(macOS 14.4, *) else { return }
        guard let panel = NSApp.windows.first(where: {
            $0.isVisible && $0.frame.height > 120 && !String(describing: type(of: $0)).contains("StatusBar")
        }) else {
            log.error("capture: the panel is not open")
            return
        }
        do {
            let content = try await SCShareableContent.currentProcess
            guard let window = content.windows.first(where: { $0.windowID == CGWindowID(panel.windowNumber) }) else {
                log.error("capture: panel window not shareable")
                return
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            config.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
            config.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
            config.showsCursor = false
            config.ignoreShadowsSingleWindow = true
            config.captureResolution = .best
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
            log.notice("captured \(image.width)x\(image.height) to \(url.lastPathComponent, privacy: .public)")
        } catch {
            log.error("capture failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
#endif
