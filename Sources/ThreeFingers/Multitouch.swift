import CMultitouch
import Foundation
import os

/// Runtime bridge to the private MultitouchSupport.framework.
///
/// The framework is opened with `dlopen` and its C entry points are resolved with `dlsym`,
/// so nothing private is referenced at link time.
final class Multitouch {
    private typealias CreateListFn = @convention(c) () -> Unmanaged<CFArray>?
    private typealias RegisterFn = @convention(c) (MTDeviceRef?, MTContactCallbackFunction?) -> Void
    private typealias StartFn = @convention(c) (MTDeviceRef?, Int32) -> Int32
    private typealias StopFn = @convention(c) (MTDeviceRef?) -> Void

    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"

    private let log = Logger(subsystem: "com.3fingers.app", category: "GestureEngine")
    private let createList: CreateListFn
    private let register: RegisterFn
    private let unregister: RegisterFn
    private let start: StartFn
    private let stop: StopFn

    private let callback: MTContactCallbackFunction
    private var devices: CFArray?

    init?(callback: MTContactCallbackFunction) {
        guard let handle = dlopen(Self.frameworkPath, RTLD_NOW) else {
            Logger(subsystem: "com.3fingers.app", category: "GestureEngine")
                .error("dlopen MultitouchSupport failed: \(String(cString: dlerror()), privacy: .public)")
            return nil
        }
        func sym<T>(_ name: String, as _: T.Type) -> T? {
            guard let ptr = dlsym(handle, name) else { return nil }
            return unsafeBitCast(ptr, to: T.self)
        }
        guard
            let createList = sym("MTDeviceCreateList", as: CreateListFn.self),
            let register = sym("MTRegisterContactFrameCallback", as: RegisterFn.self),
            let unregister = sym("MTUnregisterContactFrameCallback", as: RegisterFn.self),
            let start = sym("MTDeviceStart", as: StartFn.self),
            let stop = sym("MTDeviceStop", as: StopFn.self)
        else {
            Logger(subsystem: "com.3fingers.app", category: "GestureEngine")
                .error("MultitouchSupport symbols missing")
            return nil
        }
        self.createList = createList
        self.register = register
        self.unregister = unregister
        self.start = start
        self.stop = stop
        self.callback = callback
    }

    var isRunning: Bool { devices != nil }

    func startAll() {
        guard devices == nil else { return }
        guard let list = createList()?.takeRetainedValue() else {
            log.error("MTDeviceCreateList returned nil")
            return
        }
        let count = CFArrayGetCount(list)
        for i in 0..<count {
            let device = UnsafeMutableRawPointer(mutating: CFArrayGetValueAtIndex(list, i))
            register(device, callback)
            _ = start(device, 0)
        }
        devices = list
        log.notice("Listening on \(count) multitouch device(s)")
    }

    func stopAll() {
        guard let list = devices else { return }
        for i in 0..<CFArrayGetCount(list) {
            let device = UnsafeMutableRawPointer(mutating: CFArrayGetValueAtIndex(list, i))
            unregister(device, callback)
            stop(device)
        }
        devices = nil
        log.notice("Stopped multitouch devices")
    }

    /// Re-enumerates devices (e.g. after wake, or when a Magic Trackpad connects).
    func restart() {
        stopAll()
        startAll()
    }
}
