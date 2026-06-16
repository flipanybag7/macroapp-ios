import Foundation
import CoreGraphics
import Darwin

typealias IOHIDRef = UnsafeMutableRawPointer

private typealias CreateClientC = @convention(c) (CFAllocator?) -> IOHIDRef
private typealias DispatchC = @convention(c) (IOHIDRef, IOHIDRef) -> Void
private typealias AppendC = @convention(c) (IOHIDRef, IOHIDRef) -> Void
private typealias CreateFingerC = @convention(c) (CFAllocator?, UInt64, UInt32, UInt32, UInt32, Int32, Int32, Int32, Int32, Int32, Bool, Bool, UInt32) -> IOHIDRef
private typealias CreateDigitizerC = @convention(c) (CFAllocator?, UInt64, UInt32, UInt32, UInt32, UInt32, UInt32, Int32, Int32, Int32, Int32, Int32, Bool, Bool, UInt32) -> IOHIDRef

@_silgen_name("dlopen")
private func _dlopen(_ path: UnsafePointer<CChar>, _ mode: Int32) -> UnsafeMutableRawPointer?

@_silgen_name("dlsym")
private func _dlsym(_ handle: UnsafeMutableRawPointer?, _ symbol: UnsafePointer<CChar>) -> UnsafeMutableRawPointer?

@_silgen_name("mach_absolute_time")
private func _mach_absolute_time() -> UInt64

final class TouchSimulator {
    static let shared = TouchSimulator()

    private var handle: UnsafeMutableRawPointer?
    private var client: IOHIDRef?

    private var createDigitizerPtr: UnsafeMutableRawPointer?
    private var createFingerPtr: UnsafeMutableRawPointer?
    private var appendEventPtr: UnsafeMutableRawPointer?
    private var dispatchEventPtr: UnsafeMutableRawPointer?

    private(set) var canSimulateTouches = false

    private init() {
        #if targetEnvironment(simulator)
        return
        #endif

        guard isJailbroken() else { return }
        loadIOKit()
    }

    private func isJailbroken() -> Bool {
        let paths = [
            "/Applications/Cydia.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash",
            "/etc/apt",
            "/var/jb",
            "/private/preboot/jb"
        ]
        for p in paths {
            if access(p, F_OK) == 0 { return true }
        }
        let t = "/var/mobile/Library/jbchk"
        do {
            try "." .write(toFile: t, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(atPath: t)
            return true
        } catch { }
        return false
    }

    private func loadIOKit() {
        guard let h = _dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else {
            return
        }
        handle = h

        let syms: [(String, UnsafeMutableRawPointer?)] = [
            ("IOHIDEventSystemClientCreate", nil),
            ("IOHIDEventSystemClientDispatchEvent", nil),
            ("IOHIDEventAppendEvent", nil),
            ("IOHIDEventCreateDigitizerFingerEvent", nil),
            ("IOHIDEventCreateDigitizerEvent", nil),
        ]

        var resolved: [String: UnsafeMutableRawPointer] = [:]
        for (name, _) in syms {
            if let ptr = _dlsym(h, name) {
                resolved[name] = ptr
            } else {
                return
            }
        }

        guard let createClientRaw = resolved["IOHIDEventSystemClientCreate"] else { return }
        let createClient = unsafeBitCast(createClientRaw, to: CreateClientC.self)
        guard let c = createClient(kCFAllocatorDefault) else { return }

        client = c
        createDigitizerPtr = resolved["IOHIDEventCreateDigitizerEvent"]
        createFingerPtr = resolved["IOHIDEventCreateDigitizerFingerEvent"]
        appendEventPtr = resolved["IOHIDEventAppendEvent"]
        dispatchEventPtr = resolved["IOHIDEventSystemClientDispatchEvent"]
        canSimulateTouches = true
    }

    private func iofix(_ v: CGFloat) -> Int32 { Int32(v * 65536) }
    private func ts() -> UInt64 { _mach_absolute_time() }

    private func parentEvent() -> IOHIDRef? {
        guard let p = createDigitizerPtr else { return nil }
        let fn = unsafeBitCast(p, to: CreateDigitizerC.self)
        return fn(kCFAllocatorDefault, ts(), 3, 0, 2, 0x01, 0, 0, 0, 0, 0, 0, true, false, 0)
    }

    private func fingerEvent(at point: CGPoint, touch: Bool, range: Bool) -> IOHIDRef? {
        guard let p = createFingerPtr else { return nil }
        let fn = unsafeBitCast(p, to: CreateFingerC.self)
        return fn(kCFAllocatorDefault, ts(), 0, 2, 0x01|0x02|0x04,
                  iofix(point.x), iofix(point.y), 0,
                  iofix(touch ? 30 : 0), 0, range, touch, 0)
    }

    private func post(_ finger: IOHIDRef) {
        guard let c = client, let parent = parentEvent(),
              let app = appendEventPtr, let dsp = dispatchEventPtr else { return }
        let append = unsafeBitCast(app, to: AppendC.self)
        append(parent, finger)
        let dispatch = unsafeBitCast(dsp, to: DispatchC.self)
        dispatch(c, parent)
    }

    func touchDown(at point: CGPoint, fingerId: Int32 = 0) {
        guard canSimulateTouches, let ev = fingerEvent(at: point, touch: true, range: true) else { return }
        post(ev)
    }

    func touchMove(to point: CGPoint, fingerId: Int32 = 0) {
        guard canSimulateTouches, let ev = fingerEvent(at: point, touch: true, range: true) else { return }
        post(ev)
    }

    func touchUp(at point: CGPoint, fingerId: Int32 = 0) {
        guard canSimulateTouches, let ev = fingerEvent(at: point, touch: false, range: false) else { return }
        post(ev)
    }

    func tap(at point: CGPoint) {
        guard canSimulateTouches else { return }
        touchDown(at: point)
        usleep(60000)
        touchUp(at: point)
    }

    func longPress(at point: CGPoint, duration: TimeInterval) {
        guard canSimulateTouches else { return }
        touchDown(at: point)
        usleep(UInt32(duration * 1_000_000))
        touchUp(at: point)
    }

    func swipe(from start: CGPoint, to end: CGPoint, duration: TimeInterval) {
        guard canSimulateTouches else { return }
        let steps = max(5, Int(duration * 60))
        let step = useconds_t(duration / Double(steps) * 1_000_000)
        touchDown(at: start)
        for i in 1...steps {
            usleep(step)
            let t = Double(i) / Double(steps)
            let x = start.x + (end.x - start.x) * t
            let y = start.y + (end.y - start.y) * t
            touchMove(to: CGPoint(x: x, y: y))
        }
        usleep(40000)
        touchUp(at: end)
    }
}
