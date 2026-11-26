import Carbon
import Foundation

/// Permissionless system-wide `⌃⌥⌘L` hotkey via Carbon `RegisterEventHotKey`.
///
/// Carbon hotkeys are delivered through the application event target on the main thread and do
/// not require Accessibility permission (unlike `NSEvent.addGlobalMonitorForEvents`).
///
/// The C callback is a non-capturing closure; the service is handed over as an unretained
/// `userData` pointer. Because the pointer is unretained, the owner must call `unregister()` /
/// `shutdown()` before releasing the service — the view model does this in `shutdown()`.
@MainActor
final class GlobalHotKeyService {

    static let shortcutLabel = "⌃⌥⌘L"

    /// `'LBFG'`
    nonisolated private static let signature: OSType = 0x4C42_4647
    nonisolated private static let identifier: UInt32 = 1

    private(set) var isRegistered = false

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var handler: (@MainActor () -> Void)?

    /// Registers `⌃⌥⌘L`. Calling again while registered just swaps the handler.
    /// Returns `false` if the shortcut could not be registered (e.g. taken by another app).
    @discardableResult
    func register(handler: @escaping @MainActor () -> Void) -> Bool {
        self.handler = handler
        if isRegistered { return true }

        let target = GetApplicationEventTarget()
        var installedHandler: EventHandlerRef?
        let userData = Unmanaged.passUnretained(self).toOpaque()

        let installStatus = Self.installHandler(on: target, userData: userData, installedHandler: &installedHandler)

        guard installStatus == noErr, let installedHandler else {
            self.handler = nil
            return false
        }

        var registeredRef: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(UInt32(kVK_ANSI_L),
                                                 UInt32(controlKey | optionKey | cmdKey),
                                                 EventHotKeyID(signature: Self.signature, id: Self.identifier),
                                                 target, UInt32(kEventHotKeyExclusive), &registeredRef)
        guard registerStatus == noErr, let registeredRef else {
            RemoveEventHandler(installedHandler)
            self.handler = nil
            return false
        }

        eventHandlerRef = installedHandler
        hotKeyRef = registeredRef
        isRegistered = true
        return true
    }

    nonisolated private static func installHandler(on target: EventTargetRef?, userData: UnsafeMutableRawPointer,
                                                   installedHandler: inout EventHandlerRef?) -> OSStatus {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        return InstallEventHandler(target, { _, event, userData -> OSStatus in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hotKeyID)
            guard status == noErr,
                  hotKeyID.signature == GlobalHotKeyService.signature,
                  hotKeyID.id == GlobalHotKeyService.identifier else {
                return OSStatus(eventNotHandledErr)
            }
            // Carbon dispatches application-target events on the main thread.
            let address = UInt(bitPattern: userData)
            MainActor.assumeIsolated {
                guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
                Unmanaged<GlobalHotKeyService>.fromOpaque(pointer).takeUnretainedValue().fire()
            }
            return noErr
        }, 1, &eventType, userData, &installedHandler)
    }

    /// Unregisters the hotkey and removes the event handler. Safe to call repeatedly.
    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
        handler = nil
        isRegistered = false
    }

    func shutdown() {
        unregister()
    }

    private func fire() {
        handler?()
    }
}
