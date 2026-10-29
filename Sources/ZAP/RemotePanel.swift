import Observation
import SwiftUI
import ZAPKit

// View state that SwiftUI would normally keep in @State lives in @Observable models or @StateObject
// holders: the installed toolchain lacks SwiftUI's @State macro plugin.

/// Measured sizes that keep the panel on screen (see `PanelLayout`).
@MainActor
@Observable
final class PanelMetrics {
    static let shared = PanelMetrics()
    var contentHeight: CGFloat = 0
    /// Visible height of the screen the panel is on. A hidden developer default can simulate small screens.
    var visibleHeight: CGFloat = 800

    var scrollHeight: CGFloat {
#if ZAP_DEVTOOLS
        let simulated = CGFloat(UserDefaults.standard.double(forKey: "debugVisibleHeight"))  // small-screen checks
        if simulated > 0 { return PanelLayout.scrollHeight(content: contentHeight, visibleHeight: simulated) }
#endif
        return PanelLayout.scrollHeight(content: contentHeight, visibleHeight: visibleHeight)
    }

    var isScrolling: Bool { contentHeight > scrollHeight + 1 }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Reports the visible height of whichever screen hosts the panel, and again when displays change.
private struct ScreenReader: NSViewRepresentable {
    let onChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ReaderView, context: Context) { view.onChange = onChange }

    final class ReaderView: NSView {
        var onChange: ((CGFloat) -> Void)?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            report()
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: NSWindow.didChangeScreenNotification, object: window,
                                                queue: .main) { [weak self] _ in self?.report() })
            observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                object: nil, queue: .main) { [weak self] _ in self?.report() })
        }

        private func report() {
            if let height = (window?.screen ?? NSScreen.main)?.visibleFrame.height { onChange?(height) }
        }
    }
}

/// The panel's window is dark on its own; the app itself keeps the system appearance so the menu bar icon
/// follows the real menu bar.
private struct DarkWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> DarkView { DarkView() }
    func updateNSView(_ view: DarkView, context: Context) {}

    final class DarkView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - Panel

struct RemotePanel: View {
    let model: RemoteModel
    let metrics = PanelMetrics.shared
    let prefs = AccessibilityPrefs.shared

    var body: some View {
        VStack(spacing: DS.Space.m) {
            Header(model: model)
            ScrollView(.vertical) {
                Group {
                    switch model.page {
                    case .remote: RemotePage(model: model)
                    case .pairing: PairingPage(model: model)
                    case .chooseApp: AppChooser(model: model)
                    }
                }
                .padding(.bottom, 2)
                .transition(.opacity)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                })
            }
            .scrollIndicators(.automatic)
            .contentMargins(.trailing, metrics.isScrolling ? 10 : 0, for: .scrollContent)
            .frame(height: metrics.scrollHeight)
            .onPreferenceChange(ContentHeightKey.self) { metrics.contentHeight = $0 }
        }
        .padding(DS.Space.panel)
        .frame(width: PanelLayout.width)
        .background(DS.Palette.panel.opacity(prefs.reduceTransparency ? 1 : 0.94))
        .foregroundStyle(DS.Palette.textPrimary)
        .tint(Color(white: 0.45))
        .background(ScreenReader { metrics.visibleHeight = $0 })
        .background(DarkWindow())
        .animation(DS.Motion.small(prefs.motionReduced), value: model.page)
        .onAppear { model.panelVisible(true) }
        .onDisappear { model.panelVisible(false) }
    }
}

private struct Header: View {
    let model: RemoteModel

    var body: some View {
        let onRemote = model.page == .remote
        // On the remote the gear opens the Settings window; on a sub-page the same spot closes it.
        let showsClose = !onRemote && model.isPaired
        HStack(spacing: DS.Space.s) {
            Color.clear.frame(width: DS.Size.settingsButton, height: DS.Size.settingsButton)
            Spacer(minLength: 0)
            StatusCapsule(model: model)
            Spacer(minLength: 0)
            Button {
                if showsClose {
                    if model.page == .chooseApp { model.cancelChoosing() } else { model.cancelPairing() }
                } else {
                    model.openSettings()
                }
            } label: {
                Image(systemName: showsClose ? "xmark" : "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.Palette.textSecondary)
                    .frame(width: DS.Size.settingsButton, height: DS.Size.settingsButton)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .contentShape(.focusEffect, Circle())
            .help(showsClose ? "Close (Esc)" : "Settings (⌘,)")
            .accessibilityLabel(showsClose ? "Close" : "Settings")
        }
        .frame(height: DS.Size.header)
    }
}

// MARK: - Status capsule (the internal notch)

/// A black capsule embedded in the panel header. It hugs its text, truncates long text, and shows the TV's
/// name or, briefly, what just happened.
private struct StatusCapsule: View {
    let model: RemoteModel

    var body: some View {
        let content = model.capsuleContent
        let reduce = AccessibilityPrefs.shared.motionReduced
        HStack(spacing: 7) {
            Leading(content: content, model: model)
                .id(leadingKey(content))
                .transition(reduce ? .opacity : .opacity.combined(with: .scale(scale: 0.85)))
            VStack(alignment: .leading, spacing: 0) {
                Text(text(content))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .contentTransition(.opacity)
                if let detail = detail(content) {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(DS.Palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            if case .listening = content {
                LevelMeter(level: model.voice.level, animated: !reduce)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .frame(minWidth: DS.Size.notchMinWidth, minHeight: DS.Size.notchHeight)
        .background(Capsule().fill(DS.Palette.notch))
        .overlay(Capsule().strokeBorder(DS.Palette.capsuleStroke))
        .frame(maxWidth: 212)
        .layoutPriority(1)
        .animation(DS.Motion.capsule(reduce), value: content)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(content))
        .accessibilityAddTraits(.updatesFrequently)
        .help(text(content))
    }

    private func leadingKey(_ content: RemoteModel.CapsuleContent) -> String {
        switch content {
        case .device(_, let link, let connection): return "device-\(link)-\(connection == .checking)"
        case .listening: return "listening"
        case .voiceBusy: return "voice-busy"
        case .mirroringSetup: return "mirroring-setup"
        case .event(let event): return "event-\(event)"
        case .mirroring: return "mirroring"
        case .nowPlaying(let playing): return "playing-\(playing.appID ?? "")"
        }
    }

    private func text(_ content: RemoteModel.CapsuleContent) -> String {
        switch content {
        case .device(let name, let link, let connection):
            switch link {
            case .connected, .unknown: return name
            case .reconnecting: return connection == .searching ? "Searching…" : "Reconnecting…"
            case .unreachable: return connection == .pairingRequired ? "Pair again" : "Device unavailable"
            case .preview: return "\(name) · Preview"
            }
        case .listening(let alexa): return alexa ? "Listening · Alexa" : "Listening…"
        case .voiceBusy(let text), .mirroringSetup(let text): return text
        case .event(let event): return event.text
        case .mirroring: return "Mirroring to TV"
        case .nowPlaying(let playing): return playing.title
        }
    }

    /// Second line, only for verified Now Playing metadata (app and episode/artist as reported).
    private func detail(_ content: RemoteModel.CapsuleContent) -> String? {
        guard case .nowPlaying(let playing) = content else { return nil }
        let parts = [playing.appName, playing.detail].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The name alone would hide the state, which the dot shows by colour and shape.
    private func spoken(_ content: RemoteModel.CapsuleContent) -> String {
        switch content {
        case let .device(name, link, connection) where model.isPaired:
            switch link {
            case .connected: return "\(name), connected"
            case .unknown: return connection == .checking ? "\(name), checking the connection" : "\(name), connection not checked recently"
            case .preview: return "\(name), offline preview"
            case .reconnecting, .unreachable: return text(content)
            }
        case .mirroring:
            return "Mirroring to the TV"
        case .nowPlaying(let playing):
            return (["Now playing", playing.title] + [playing.appName, playing.detail].compactMap { $0 }).joined(separator: ", ")
        default:
            return text(content)
        }
    }

    private struct Leading: View {
        let content: RemoteModel.CapsuleContent
        let model: RemoteModel

        var body: some View {
            switch content {
            case .device(_, let link, let connection):
                switch link {
                case .connected:
                    Dot(color: DS.Palette.connected)
                case .unknown where connection == .checking, .reconnecting:
                    ProgressView().controlSize(.mini).tint(DS.Palette.textSecondary).frame(width: 12, height: 12)
                case .unknown:
                    // Not confirmed recently: a hollow dot, never a green one.
                    Circle().strokeBorder(DS.Palette.textTertiary, lineWidth: 1.2).frame(width: 7, height: 7)
                case .unreachable:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10)).foregroundStyle(DS.Palette.warning)
                case .preview:
                    Dot(color: DS.Palette.textTertiary)
                }
            case .nowPlaying(let playing):
                AppIcon(appId: playing.appID, size: 14)
            case .listening:
                Image(systemName: "mic.fill").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.Palette.recording)
            case .voiceBusy:
                Image(systemName: "mic").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.Palette.textSecondary)
            case .mirroringSetup:
                ProgressView().controlSize(.mini).tint(DS.Palette.textSecondary).frame(width: 12, height: 12)
            case .mirroring:
                Image(systemName: "airplayvideo").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .systemBlue))
            case .event(let event):
                switch event {
                case .appOpened(_, let appId):
                    AppIcon(appId: appId, size: 14)
                case .reconnected:
                    Dot(color: DS.Palette.connected)
                case .receiverReady:
                    Image(systemName: "airplayvideo").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.Palette.textSecondary)
                case .voice(_, let failed):
                    Image(systemName: failed ? "mic.slash" : "waveform")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(failed ? DS.Palette.warning : DS.Palette.textSecondary)
                case .notice(_, let warning):
                    Image(systemName: warning ? "exclamationmark.circle.fill" : "info.circle.fill")
                        .font(.system(size: 11)).foregroundStyle(warning ? DS.Palette.warning : DS.Palette.textSecondary)
                }
            }
        }
    }

    private struct Dot: View {
        let color: Color
        var body: some View { Circle().fill(color).frame(width: 7, height: 7) }
    }
}

/// Three bars driven by the real microphone level; still when there's no sound.
private struct LevelMeter: View {
    let level: Float
    let animated: Bool

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(DS.Palette.recording.opacity(0.85))
                    .frame(width: 2.5, height: height(index))
            }
        }
        .frame(height: 12)
        .animation(animated ? .easeOut(duration: 0.08) : nil, value: level)
        .accessibilityHidden(true)
    }

    private func height(_ index: Int) -> CGFloat {
        let weights: [CGFloat] = [0.6, 1, 0.75]
        return 3 + 9 * CGFloat(min(max(level, 0), 1)) * weights[index]
    }
}

/// The TV's own icon for an app when available (Settings → Advanced), otherwise a neutral symbol.
struct AppIcon: View {
    let appId: String?
    /// Height; Fire TV app artwork is landscape, so the slot is wider than tall.
    var size: CGFloat = 26

    var body: some View {
        Group {
            if let image = AppIconStore.shared.image(for: appId) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: max(2, size * 0.14), style: .continuous))
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: size * 0.62, weight: .regular))
                    .foregroundStyle(DS.Palette.textSecondary)
            }
        }
        .frame(width: size * 1.6, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Button styles

/// Graphite surface with hover, press and disabled states (Liquid Glass on macOS 26+).
private struct SurfaceButtonStyle<S: InsettableShape>: ButtonStyle {
    let shape: S
    var raised = false

    func makeBody(configuration: Configuration) -> some View {
        SurfaceButton(label: configuration.label, pressed: configuration.isPressed, shape: shape, raised: raised)
    }
}

private struct SurfaceButton<Label: View, S: InsettableShape>: View {
    let label: Label
    let pressed: Bool
    let shape: S
    let raised: Bool
    @StateObject private var hover = HoverState()
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let reduce = AccessibilityPrefs.shared.motionReduced
        label
            .graphiteSurface(shape, pressed: pressed && isEnabled, hovering: hover.isHovering && isEnabled,
                             raised: raised)
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(shape)
            .contentShape(.focusEffect, shape)
            .scaleEffect(DS.Motion.pressScale(pressed && isEnabled, reduce))
            .animation(DS.Motion.press, value: pressed)
            .animation(DS.Motion.small(reduce), value: hover.isHovering)
            .onHover { hover.isHovering = $0 }
    }
}

/// Press and release come from the native button's mouse tracking (reliable in the menu bar panel),
/// so holding a key repeats on the TV. The button's own action stays empty to avoid double sends.
private struct HoldButtonStyle<S: InsettableShape>: ButtonStyle {
    let shape: S
    var raised = false
    let onPress: () -> Void
    let onRelease: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        SurfaceButton(label: configuration.label, pressed: configuration.isPressed, shape: shape, raised: raised)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { onPress() } else { onRelease() }
            }
    }
}

/// Press/release reporting without a surface (the D-pad wedges draw their own highlight).
private struct PressReportStyle: ButtonStyle {
    let onPress: () -> Void
    let onRelease: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.onChange(of: configuration.isPressed) { _, pressed in
            if pressed { onPress() } else { onRelease() }
        }
    }
}

/// Row highlight for lists inside a card.
private struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RowButton(label: configuration.label, pressed: configuration.isPressed)
    }
}

private struct RowButton<Label: View>: View {
    let label: Label
    let pressed: Bool
    @StateObject private var hover = HoverState()
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        label
            .background(Color.white.opacity(!isEnabled ? 0 : (pressed ? 0.09 : (hover.isHovering ? 0.05 : 0))))
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(Rectangle())
            .contentShape(.focusEffect, Rectangle())
            .onHover { hover.isHovering = $0 }
    }
}

// MARK: - Remote page

private struct RemotePage: View {
    let model: RemoteModel

    var body: some View {
        VStack(spacing: DS.Space.section) {
            QuickActionsRow(model: model)
            MediaRow(model: model)
            DPad(model: model)
            NavRow(model: model)
            ActionPills(model: model)
        }
        .disabled(!model.isPaired)
    }
}

private struct QuickActionsRow: View {
    let model: RemoteModel

    var body: some View {
        let store = model.quickActions
        VStack(alignment: .leading, spacing: 7) {
            Text("Quick Apps")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.Palette.textSecondary)
                .padding(.leading, 2)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: DS.Space.s) {
                ForEach(Array(store.visibleItems.enumerated()), id: \.element.id) { index, item in
                    QuickTile(model: model, item: item, index: index)
                }
                if store.canAdd {
                Button { model.beginChoosing(replacing: nil) } label: {
                    TileLabel(title: "Add") {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(DS.Palette.textSecondary)
                            .frame(height: DS.Size.tileIcon)
                    }
                }
                .buttonStyle(SurfaceButtonStyle(shape: RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)))
                .help("Add an app shortcut")
                .accessibilityLabel("Add a shortcut")
                }
            }
        }
    }
}

private struct QuickTile: View {
    let model: RemoteModel
    let item: QuickAction
    let index: Int

    var body: some View {
        let missing = model.isMissing(item)
        let store = model.quickActions
        let shown = store.visibleItems
        Button { model.openQuickAction(item) } label: {
            TileLabel(title: item.name) {
                AppIcon(appId: item.appId, size: DS.Size.tileIcon)
                    .overlay(alignment: .topTrailing) {
                        if missing {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(DS.Palette.warning)
                                .background(Circle().fill(Color.black))
                                .offset(x: 2, y: -4)
                        }
                    }
            }
            .opacity(missing ? 0.6 : 1)
        }
        .buttonStyle(SurfaceButtonStyle(shape: RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)))
        .help(missing ? "\(item.name) isn't in this TV's app list — click to choose another app"
              : "Open \(item.name)\(index < 4 ? " (\(index + 1))" : "")")
        .accessibilityLabel(missing ? "\(item.name), not on this TV" : "Open \(item.name)")
        .contextMenu {
            Button("Replace…") {
                if let position = store.items.firstIndex(of: item) { model.beginChoosing(replacing: position) }
            }
            Button("Move Left") {
                if index > 0 { store.move(item.id, to: shown[index - 1].id) }
            }
            .disabled(index == 0)
            Button("Move Right") {
                if index < shown.count - 1 { store.move(item.id, to: shown[index + 1].id) }
            }
            .disabled(index == shown.count - 1)
            Divider()
            Button("Hide from Remote") { store.setEnabled(item.id, false) }
            Button("Remove") {
                if let position = store.items.firstIndex(of: item) { store.remove(at: position) }
            }
            Divider()
            Button("Edit Apps…") { model.openSettings(.apps) }
        }
    }
}

private struct TileLabel<Icon: View>: View {
    let title: String
    @ViewBuilder let icon: Icon

    var body: some View {
        VStack(spacing: 5) {
            icon
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DS.Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, minHeight: DS.Size.tileHeight)
    }
}

private struct MediaRow: View {
    let model: RemoteModel

    var body: some View {
        HStack(spacing: 30) {
            MediaKey(model: model, command: .rewind, symbol: "backward.fill", help: "Rewind ([)")
            MediaKey(model: model, command: .playPause, symbol: "playpause.fill", help: "Play / Pause (Space)")
            MediaKey(model: model, command: .forward, symbol: "forward.fill", help: "Fast-forward (])")
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MediaKey: View {
    let model: RemoteModel
    let command: MediaCommand
    let symbol: String
    let help: String

    var body: some View {
        Button { model.send(.media(command)) } label: {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(DS.Palette.textSecondary)
                .frame(width: DS.Size.media, height: DS.Size.media)
        }
        .buttonStyle(SurfaceButtonStyle(shape: Circle()))
        .help(help)
        .accessibilityLabel(command.label)
    }
}

/// A quarter of the D-pad ring. The whole wedge is the arrow's hit area, so the ring has no dead zones.
private struct RingWedge: Shape {
    let direction: Angle   // 0° = right, 90° = down
    let inner: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        func point(_ radius: CGFloat, _ angle: Double) -> CGPoint {
            CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }
        let start = direction.radians - .pi / 4
        let steps = 16
        var path = Path()
        for step in 0...steps {
            let angle = start + Double(step) / Double(steps) * .pi / 2
            if step == 0 { path.move(to: point(outer, angle)) } else { path.addLine(to: point(outer, angle)) }
        }
        for step in (0...steps).reversed() {
            path.addLine(to: point(inner, start + Double(step) / Double(steps) * .pi / 2))
        }
        path.closeSubpath()
        return path
    }
}

/// One continuous circular surface; four wedge-shaped arrows; a raised OK in the middle.
private struct DPad: View {
    let model: RemoteModel

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.clear)
                .graphiteSurface(Circle())
            ArrowKey(key: .up, model: model, direction: .degrees(-90))
            ArrowKey(key: .down, model: model, direction: .degrees(90))
            ArrowKey(key: .left, model: model, direction: .degrees(180))
            ArrowKey(key: .right, model: model, direction: .degrees(0))
            OKKey(model: model)
        }
        .frame(width: DS.Size.dpad, height: DS.Size.dpad)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Direction pad")
    }
}

private struct ArrowKey: View {
    let key: NavKey
    let model: RemoteModel
    let direction: Angle

    var body: some View {
        let pressed = model.pressedKeys.contains(key)
        let wedge = RingWedge(direction: direction, inner: DS.Size.ok / 2 + 2)
        let distance = DS.Size.dpad * 0.335
        Button { model.keyActivated(key) } label: {
            ZStack {
                wedge.fill(Color.white.opacity(pressed ? 0.07 : 0))
                Image(systemName: key.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(pressed ? DS.Palette.textPrimary : DS.Palette.textSecondary)
                    .offset(x: distance * cos(direction.radians), y: distance * sin(direction.radians))
            }
            .frame(width: DS.Size.dpad, height: DS.Size.dpad)
            .contentShape(wedge)
            .animation(DS.Motion.press, value: pressed)
        }
        .buttonStyle(PressReportStyle(onPress: { model.keyPressBegan(key) }, onRelease: { model.keyPressEnded(key) }))
        .contentShape(.focusEffect, wedge)
        .help("\(key.label) — arrow key; hold to repeat")
        .accessibilityLabel(key.label)
        .accessibilityAction { model.send(.key(key)) }
    }
}

private struct OKKey: View {
    let model: RemoteModel

    var body: some View {
        Button { model.keyActivated(.select) } label: {
            Text("OK")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DS.Palette.textPrimary)
                .frame(width: DS.Size.ok, height: DS.Size.ok)
        }
        .buttonStyle(HoldButtonStyle(shape: Circle(), raised: true,
                                     onPress: { model.keyPressBegan(.select) },
                                     onRelease: { model.keyPressEnded(.select) }))
        .help("OK (Return)")
        .accessibilityLabel("OK")
        .accessibilityAction { model.send(.key(.select)) }
    }
}

private struct NavRow: View {
    let model: RemoteModel

    var body: some View {
        HStack(spacing: 30) {
            NavButton(model: model, key: .back, title: "Back", help: "Back (Esc)")
            NavButton(model: model, key: .home, title: "Home", help: "Home (H)", prominent: true)
            NavButton(model: model, key: .menu, title: "Menu", help: "Menu (M)")
        }
        .frame(maxWidth: .infinity)
    }
}

private struct NavButton: View {
    let model: RemoteModel
    let key: NavKey
    let title: String
    let help: String
    var prominent = false

    var body: some View {
        VStack(spacing: 5) {
            Button { model.keyActivated(key) } label: {
                Image(systemName: key == .home ? "house.fill" : key.symbol)
                    .font(.system(size: prominent ? 14.5 : 13, weight: prominent ? .semibold : .medium))
                    .foregroundStyle(prominent ? DS.Palette.textPrimary : DS.Palette.textSecondary)
                    .frame(width: DS.Size.round, height: DS.Size.round)
            }
            .buttonStyle(HoldButtonStyle(shape: Circle(), raised: prominent,
                                         onPress: { model.keyPressBegan(key) }, onRelease: { model.keyPressEnded(key) }))
            .help(help)
            .accessibilityLabel(title)
            .accessibilityAction { model.send(.key(key)) }
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DS.Palette.textTertiary)
                .accessibilityHidden(true)
        }
    }
}

private struct ActionPills: View {
    let model: RemoteModel

    var body: some View {
        HStack(spacing: DS.Space.s) {
            VoicePill(voice: model.voice)
            MirrorPill(model: model)
        }
    }
}

private struct PillLabel: View {
    let symbol: String
    let title: String
    let subtitle: String
    var symbolColor: Color = DS.Palette.textPrimary

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(symbolColor)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(DS.Palette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: DS.Size.pill)
    }
}

private struct VoicePill: View {
    let voice: VoiceController

    var body: some View {
        let active = voice.isCapturing  // red only while the microphone really records
        let shape = Capsule()
        Button { voice.keyboardActivated() } label: {
            PillLabel(symbol: active ? "mic.fill" : "mic",
                      title: "Voice",
                      subtitle: active ? "Release to send" : (voice.mode == .local ? "Apple Speech" : "Alexa"),
                      symbolColor: active ? DS.Palette.recording : DS.Palette.textPrimary)
                .overlay(shape.strokeBorder(DS.Palette.recording.opacity(active ? 0.55 : 0)))
                .background(shape.fill(DS.Palette.recording.opacity(active ? 0.12 : 0)))
        }
        .buttonStyle(HoldButtonStyle(shape: shape, onPress: { voice.pushToTalkBegan() },
                                     onRelease: { voice.pushToTalkEnded() }))
        .help("Hold to talk (or hold V). \(voice.modeDescription)")
        .accessibilityLabel(active ? "Microphone on" : "Voice, \(voice.mode == .local ? "Apple Speech" : "Alexa")")
        .accessibilityHint(active ? "Activate again to stop listening" : "Activate to start listening, then again to stop")
        .accessibilityAction {
            if voice.isActive { voice.pushToTalkEnded() } else { voice.pushToTalkBegan() }
        }
    }
}

private struct MirrorPill: View {
    let model: RemoteModel

    var body: some View {
        Button { model.startMirroring() } label: {
            PillLabel(symbol: "airplayvideo", title: "Mirror", subtitle: subtitle)
        }
        .buttonStyle(SurfaceButtonStyle(shape: Capsule()))
        .help(mirrorHelp)
        .accessibilityLabel("Mirror, \(subtitle)")
    }

    private var mirrorHelp: String {
        switch model.mirroring.stage {
        case .guide:
            return "Opens System Settings → Displays, which lists AirPlay displays to mirror or extend to"
        case .notFound:
            return "No AirPlay receiver found on the TV. Install AirPlay Server on the TV, keep the Mac on the same network, then press Mirror again"
        default:
            return "Opens the AirPlay receiver on the TV, then choose it in Control Center → Screen Mirroring"
        }
    }

    private var subtitle: String {
        switch model.mirroring.stage {
        case .idle: return "Screen to TV"
        case .searching: return "Searching…"
        case .guide: return "Receiver ready"
        case .notFound: return "No receiver"
        }
    }
}

// MARK: - App chooser

private struct AppChooser: View {
    let model: RemoteModel

    var body: some View {
        let store = model.quickActions
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Text(model.choosingForID == nil ? "Add a Shortcut" : "Replace Shortcut")
                .font(.system(size: 15, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            if let message = model.chooserMessage {
                Label(message, systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Palette.warning)
            }
            if model.apps.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading the apps installed on your TV…").font(.system(size: 11))
                        .foregroundStyle(DS.Palette.textSecondary)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.apps.enumerated()), id: \.element.id) { index, app in
                        let added = store.items.contains { $0.appId == app.appId }
                        if index > 0 { Rectangle().fill(DS.Palette.border).frame(height: 1).padding(.leading, 50) }
                        Button { model.choose(app) } label: {
                            HStack(spacing: 10) {
                                AppIcon(appId: app.appId, size: 20)
                                Text(shortAppName(app.name)).font(.system(size: 12)).lineLimit(1)
                                Spacer()
                                if added {
                                    Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(DS.Palette.textTertiary)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                        }
                        .buttonStyle(RowButtonStyle())
                        .disabled(added)
                        .help(app.name)
                        .accessibilityLabel(added ? "\(shortAppName(app.name)), already a shortcut" : shortAppName(app.name))
                    }
                }
                .background(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).fill(DS.Palette.surface.opacity(0.7)))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).strokeBorder(DS.Palette.cardBorder))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            }
        }
    }
}

// MARK: - Panel card

/// A titled card inside the menu bar panel (pairing).
struct PanelCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(title: title).padding(.leading, 2)
            VStack(alignment: .leading, spacing: 10) { content }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).fill(DS.Palette.surface.opacity(0.7)))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).strokeBorder(DS.Palette.cardBorder))
        }
    }
}

// MARK: - Pairing / onboarding

struct PairingPage: View {
    let model: RemoteModel

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pair with your Fire TV").font(.system(size: 15, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Your Mac and the Fire TV must be on the same network. The TV shows a PIN to confirm.")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Palette.textSecondary)
            }
            PanelCard(title: "Fire TVs on this network") {
                if model.discovering {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Searching…").font(.system(size: 11)).foregroundStyle(DS.Palette.textSecondary)
                    }
                } else if model.discovered.isEmpty {
                    Text("None found yet.").font(.system(size: 11)).foregroundStyle(DS.Palette.textSecondary)
                }
                ForEach(model.discovered) { tv in
                    let selected = model.selectedTVID == tv.id && model.manualHost.isEmpty
                    Button {
                        model.selectedTVID = tv.id
                        model.manualHost = ""
                    } label: {
                        HStack {
                            Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(selected ? DS.Palette.textPrimary : DS.Palette.textTertiary)
                            Text(tv.name).lineLimit(1)
                            Spacer()
                        }
                        .font(.system(size: 12))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                    }
                    .buttonStyle(SurfaceButtonStyle(shape: RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
                Button("Search Again") { Task { await model.discoverTVs() } }
                    .controlSize(.small)
                    .disabled(model.discovering)
                DisclosureGroup("Enter its address instead") {
                    TextField("e.g. 192.168.1.20", text: Binding(get: { model.manualHost }, set: { model.manualHost = $0 }))
                        .textFieldStyle(.roundedBorder)
                        .padding(.top, 4)
                }
                .font(.system(size: 11))
            }
            if let message = model.pairingMessage {
                Label(message.text, systemImage: message.isError ? "exclamationmark.triangle.fill" : "info.circle")
                    .font(.system(size: 11.5))
                    .foregroundStyle(message.isError ? DS.Palette.warning : DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            Button { Task { await model.requestPIN() } } label: {
                Text(model.awaitingPIN ? "Show a New PIN" : "Show PIN on TV")
                    .font(.system(size: 12.5, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(SurfaceButtonStyle(shape: Capsule(), raised: true))
            .disabled(model.pairingBusy)
            if model.awaitingPIN {
                HStack {
                    TextField("PIN", text: Binding(get: { model.pairingPIN }, set: { model.pairingPIN = $0 }))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    Button("Pair") { Task { await model.submitPIN() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.pairingPIN.filter(\.isNumber).count < 4 || model.pairingBusy)
                    if model.pairingBusy { ProgressView().controlSize(.small) }
                }
            }
        }
        .onAppear {
            if model.discovered.isEmpty { Task { await model.discoverTVs() } }
        }
    }
}
