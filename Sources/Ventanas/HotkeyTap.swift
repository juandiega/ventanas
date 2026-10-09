import AppKit

/// Intercepts the keyboard at session level. The handler returns `true` to swallow the event.
@MainActor
final class HotkeyTap {
    private let handler: (CGEventType, CGEvent) -> Bool
    private var tap: CFMachPort?

    init(handler: @escaping (CGEventType, CGEvent) -> Bool) {
        self.handler = handler
    }

    func start() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let swallow = MainActor.assumeIsolated {
                Unmanaged<HotkeyTap>.fromOpaque(refcon).takeUnretainedValue().process(type, event)
            }
            return swallow ? nil : Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func process(_ type: CGEventType, _ event: CGEvent) -> Bool {
        // macOS disables the tap if it takes too long; turn it back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        return handler(type, event)
    }
}
