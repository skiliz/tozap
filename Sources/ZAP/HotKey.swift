import Carbon.HIToolbox

/// Optional global push-to-talk shortcut (⌃⌥V) via the Carbon hot-key API, which reports both press
/// and release and needs no Accessibility or Input Monitoring permission.
final class PushToTalkHotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var onPress: (() -> Void)?
    private var onRelease: (() -> Void)?

    static let displayName = "⌃⌥V"

    /// Returns false when macOS refuses the shortcut (for example, another app already registered ⌃⌥V).
    @discardableResult
    func register(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) -> Bool {
        unregister()
        self.onPress = onPress
        self.onRelease = onRelease
        var events = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            let me = Unmanaged<PushToTalkHotKey>.fromOpaque(context).takeUnretainedValue()
            if GetEventKind(event) == UInt32(kEventHotKeyPressed) { me.onPress?() } else { me.onRelease?() }
            return noErr
        }, events.count, &events, Unmanaged.passUnretained(self).toOpaque(), &handler)
        let id = EventHotKeyID(signature: OSType(0x4652_5054), id: 1)  // 'FRPT'
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(controlKey | optionKey), id,
                                         GetApplicationEventTarget(), 0, &hotKey)
        return status == noErr
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
    }
}
