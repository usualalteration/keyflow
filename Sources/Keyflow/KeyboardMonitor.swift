import Foundation
import CoreGraphics

/// Global, listen-only keyboard timing tap.
///
/// PRIVACY: this class never reads key codes, characters or modifier state. The only things that
/// leave the event callback are "a key went down / up" and the time it happened.
final class KeyboardMonitor {
    var onKeyDown: ((Double) -> Void)?
    var onKeyUp: ((Double) -> Void)?
    private(set) var isActive = false

    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?

    var hasAccess: Bool { CGPreflightListenEventAccess() }

    func requestAccess() { _ = CGRequestListenEventAccess() }

    @discardableResult
    func start() -> Bool {
        if isActive { return true }
        guard CGPreflightListenEventAccess() else {
            _ = CGRequestListenEventAccess()
            return false
        }
        final class Flag { var ok = false }
        let flag = Flag()
        let sem = DispatchSemaphore(value: 0)

        let thread = Thread { [unowned self] in
            let mask: CGEventMask = (1 << UInt64(CGEventType.keyDown.rawValue))
                                  | (1 << UInt64(CGEventType.keyUp.rawValue))
            guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                              place: .headInsertEventTap,
                                              options: .listenOnly,
                                              eventsOfInterest: mask,
                                              callback: keyboardTapCallback,
                                              userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
                sem.signal()
                return
            }
            self.tap = tap
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            let rl = CFRunLoopGetCurrent()
            self.runLoop = rl
            CFRunLoopAddSource(rl, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            flag.ok = true
            sem.signal()
            CFRunLoopRun()
            CFRunLoopRemoveSource(rl, source, .commonModes)
        }
        thread.name = "KEYFLOW.KeyboardTap"
        thread.qualityOfService = .userInteractive
        thread.start()
        _ = sem.wait(timeout: .now() + 1.0)
        isActive = flag.ok
        return isActive
    }

    func stop() {
        guard isActive else { return }
        if let tap = tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let rl = runLoop { CFRunLoopStop(rl) }
        tap = nil
        runLoop = nil
        isActive = false
    }

    /// Called on the tap thread.
    func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .keyDown:
            // Ignore OS key auto-repeat: only physical presses are musical events.
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                onKeyDown?(ProcessInfo.processInfo.systemUptime)
            }
        case .keyUp:
            onKeyUp?(ProcessInfo.processInfo.systemUptime)
        default:
            break
        }
    }
}

private func keyboardTapCallback(proxy: CGEventTapProxy,
                                 type: CGEventType,
                                 event: CGEvent,
                                 refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let refcon = refcon {
        Unmanaged<KeyboardMonitor>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event)
    }
    return Unmanaged.passUnretained(event)
}
