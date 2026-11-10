import Carbon.HIToolbox

/// A system-wide hotkey. Carbon's API is still the one that needs no permissions.
@MainActor
final class HotKey {
    private let action: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action

        // Register first: a handler installed before a failed registration would outlive this object.
        let hotKeyID = EventHotKeyID(signature: OSType(0x5243_5354), id: 1) // "RCST"
        let registerStatus = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef
        )
        guard registerStatus == noErr else { return nil }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
                // Carbon delivers application-target events on the main thread.
                MainActor.assumeIsolated { hotKey.action() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        guard installStatus == noErr else {
            if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
            return nil
        }
    }
}
