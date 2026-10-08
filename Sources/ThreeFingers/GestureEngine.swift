import AppKit
import CMultitouch
import CoreGraphics
import os

/// Turns raw multitouch frames into middle clicks.
///
/// * 3-finger **tap**: a touch session that goes 0 → 3 → 0 fingers, lasts < 180 ms and in which no
///   finger moves more than 2% of the trackpad's size. Swipes, drags and Mission Control gestures fail
///   the duration or displacement test and are ignored.
/// * 3-finger **click**: while exactly 3 fingers rest on the trackpad, the physical left click is
///   rewritten in-flight (event tap) into a middle click, so no stray left click leaks through.
///
/// Multitouch frames arrive on a private framework thread; the event tap and UI run on the main thread.
/// Shared state is guarded by an unfair lock.
final class GestureEngine: @unchecked Sendable {
    static let shared = GestureEngine()

    static let requiredFingers = 3
    static let maxTapDuration: Double = 0.180      // seconds
    static let maxDisplacement: Float = 0.02       // fraction of the trackpad (normalized 0...1 coordinates)
    static let debounceInterval: Double = 0.250    // seconds

    private static let touchingStates: Set<Int32> = [
        Int32(MTTouchStateMakeTouch.rawValue),
        Int32(MTTouchStateTouching.rawValue),
    ]

    private struct Session {
        var start: Double
        var peakFingers = 0
        var origins: [Int32: MTPoint] = [:]
        var maxDisplacement: Float = 0
        var physicalClick = false
    }

    private struct State {
        var enabled = false
        var sessions: [Int: Session] = [:]      // keyed by device pointer
        var fingersDown: [Int: Int] = [:]       // keyed by device pointer
        var lastFire: Double = -.infinity
        var convertingClick = false
    }

    private let log = Logger(subsystem: "com.3fingers.app", category: "GestureEngine")
    private let state = OSAllocatedUnfairLock(initialState: State())

    // Main-thread only.
    private var multitouch: Multitouch?
    private var eventTap: CFMachPort?

    private init() {}

    // MARK: - Lifecycle (main thread)

    var isEnabled: Bool { state.withLock { $0.enabled } }
    var hasEventTap: Bool { eventTap != nil }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            if multitouch == nil {
                multitouch = Multitouch(callback: contactFrameCallback)
            }
            state.withLock { $0.enabled = true }
            multitouch?.startAll()
            installEventTapIfNeeded()
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
        } else {
            state.withLock {
                $0.enabled = false
                $0.sessions.removeAll()
                $0.fingersDown.removeAll()
                $0.convertingClick = false
            }
            multitouch?.stopAll()
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        }
        log.notice("Engine \(enabled ? "enabled" : "disabled", privacy: .public)")
    }

    /// Re-enumerates trackpads. Needed after sleep/wake, when devices stop delivering frames.
    func restartDevices() {
        guard isEnabled else { return }
        state.withLock {
            $0.sessions.removeAll()
            $0.fingersDown.removeAll()
        }
        multitouch?.restart()
    }

    /// Creates the event tap used for 3-finger physical clicks. Requires Accessibility permission,
    /// so it is retried by the app delegate until permission is granted.
    @discardableResult
    func installEventTapIfNeeded() -> Bool {
        if eventTap != nil { return true }
        let mask = (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: eventTapCallback,
            userInfo: nil
        ) else {
            log.error("Could not create event tap (Accessibility permission missing?)")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: isEnabled)
        eventTap = tap
        log.notice("Event tap installed")
        return true
    }

    // MARK: - Multitouch frames (framework thread)

    fileprivate func process(device: MTDeviceRef?, touches: UnsafePointer<MTTouch>?, count: Int, timestamp: Double) {
        let key = Int(bitPattern: device)
        let contacts: [MTTouch] = touches.map {
            UnsafeBufferPointer(start: $0, count: count).filter { Self.touchingStates.contains($0.state) }
        } ?? []

        let shouldFire: Bool = state.withLock { s in
            guard s.enabled else { return false }
            s.fingersDown[key] = contacts.count

            guard var session = s.sessions[key] ?? (contacts.isEmpty ? nil : Session(start: timestamp)) else {
                return false
            }
            session.peakFingers = max(session.peakFingers, contacts.count)
            for contact in contacts {
                let p = contact.normalized.position
                if let origin = session.origins[contact.pathIndex] {
                    let d = hypotf(p.x - origin.x, p.y - origin.y)
                    session.maxDisplacement = max(session.maxDisplacement, d)
                } else {
                    session.origins[contact.pathIndex] = p
                }
            }

            guard contacts.isEmpty else {
                s.sessions[key] = session
                return false
            }
            s.sessions[key] = nil
            return evaluate(session, end: timestamp, lastFire: &s.lastFire)
        }

        if shouldFire { postMiddleClick() }
    }

    /// Decides whether a finished touch session was a 3-finger tap. Called with the lock held.
    private func evaluate(_ session: Session, end: Double, lastFire: inout Double) -> Bool {
        // 1- and 2-finger sessions are ordinary pointer use; don't log them.
        guard session.peakFingers >= Self.requiredFingers else { return false }

        let duration = end - session.start
        let ms = Int(duration * 1000)
        let disp = session.maxDisplacement

        if session.peakFingers > Self.requiredFingers {
            log.info("Rejected: \(session.peakFingers) fingers")
            return false
        }
        if session.physicalClick {
            log.debug("Skipped tap: session already produced a physical 3-finger click")
            return false
        }
        if duration >= Self.maxTapDuration {
            log.info("Rejected: duration \(ms) ms ≥ \(Int(Self.maxTapDuration * 1000)) ms")
            return false
        }
        if disp >= Self.maxDisplacement {
            log.info("Rejected: displacement \(disp, format: .fixed(precision: 4)) ≥ \(Self.maxDisplacement)")
            return false
        }
        let now = ProcessInfo.processInfo.systemUptime
        let sinceLast = now - lastFire
        if sinceLast < Self.debounceInterval {
            log.info("Rejected: debounced (\(Int(sinceLast * 1000)) ms since last click)")
            return false
        }
        lastFire = now
        log.notice("3-finger tap → middle click (\(ms) ms, displacement \(disp, format: .fixed(precision: 4)))")
        return true
    }

    private func postMiddleClick() {
        let location = CGEvent(source: nil)?.location ?? .zero
        let source = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.otherMouseDown, .otherMouseUp] {
            let event = CGEvent(mouseEventSource: source, mouseType: type,
                                mouseCursorPosition: location, mouseButton: .center)
            event?.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Event tap (main thread)

    fileprivate func handle(type: CGEventType, event: CGEvent) -> CGEvent {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap, isEnabled { CGEvent.tapEnable(tap: eventTap, enable: true) }
            log.notice("Event tap re-enabled after \(type == .tapDisabledByTimeout ? "timeout" : "user input", privacy: .public)")

        case .leftMouseDown:
            let convert = state.withLock { s -> Bool in
                guard s.enabled, s.fingersDown.values.contains(Self.requiredFingers) else { return false }
                s.convertingClick = true
                s.lastFire = ProcessInfo.processInfo.systemUptime
                for key in s.sessions.keys { s.sessions[key]?.physicalClick = true }
                return true
            }
            if convert {
                rewriteAsMiddle(event, type: .otherMouseDown)
                log.notice("3-finger click → middle click")
            }

        case .leftMouseDragged:
            if state.withLock({ $0.convertingClick }) {
                rewriteAsMiddle(event, type: .otherMouseDragged)
            }

        case .leftMouseUp:
            let wasConverting = state.withLock { s -> Bool in
                defer { s.convertingClick = false }
                return s.convertingClick
            }
            if wasConverting { rewriteAsMiddle(event, type: .otherMouseUp) }

        default:
            break
        }
        return event
    }

    private func rewriteAsMiddle(_ event: CGEvent, type: CGEventType) {
        event.type = type
        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(CGMouseButton.center.rawValue))
    }
}

// C function pointers cannot capture context, so both callbacks route through the singleton.

private let contactFrameCallback: MTContactCallbackFunction = { device, touches, count, timestamp, _ in
    GestureEngine.shared.process(device: device, touches: touches, count: Int(count), timestamp: timestamp)
    return 0
}

private let eventTapCallback: CGEventTapCallBack = { _, type, event, _ in
    Unmanaged.passUnretained(GestureEngine.shared.handle(type: type, event: event))
}
