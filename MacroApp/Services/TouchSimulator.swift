import Foundation
import CoreGraphics
import Darwin

typealias IOHIDRef = UnsafeMutableRawPointer

private typealias CreateClientC = @convention(c) (CFAllocator?) -> IOHIDRef?
private typealias DispatchC = @convention(c) (IOHIDRef?, IOHIDRef?) -> Void
private typealias AppendC = @convention(c) (IOHIDRef?, IOHIDRef?) -> Void
private typealias CreateDigitizerC = @convention(c) (CFAllocator?, UInt64, UInt32, UInt32, UInt32, UInt32, UInt32, Int32, Int32, Int32, Int32, Int32, Bool, Bool, UInt32) -> IOHIDRef?

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

    private var createDigitizerRaw: UnsafeMutableRawPointer?
    private var appendRaw: UnsafeMutableRawPointer?
    private var dispatchRaw: UnsafeMutableRawPointer?

    private(set) var canSimulateTouches = false
    private var debugLog: [String] = []

    private init() {
        #if targetEnvironment(simulator)
        return
        #endif
        guard isJailbroken() else { return }
        loadIOKit()
    }

    private func isJailbroken() -> Bool {
        for p in ["/Applications/Cydia.app", "/Library/MobileSubstrate", "/bin/bash", "/etc/apt", "/var/jb", "/private/preboot/jb"] {
            if access(p, F_OK) == 0 { return true }
        }
        let t = "/var/mobile/Library/jbchk"
        do { try "." .write(toFile: t, atomically: true, encoding: .utf8); try FileManager.default.removeItem(atPath: t); return true } catch { }
        return false
    }

    private func loadIOKit() {
        guard let h = _dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else {
            debugLog.append("dlopen IOKit failed")
            return
        }
        handle = h

        guard let cc = _dlsym(h, "IOHIDEventSystemClientCreate") else { debugLog.append("no CreateClient"); return }
        let createClientFn = unsafeBitCast(cc, to: CreateClientC.self)
        guard let c = createClientFn(kCFAllocatorDefault) else { debugLog.append("CreateClient returned nil"); return }
        client = c

        guard let cd = _dlsym(h, "IOHIDEventCreateDigitizerEvent") else { debugLog.append("no CreateDigitizer"); return }
        createDigitizerRaw = cd

        guard let ap = _dlsym(h, "IOHIDEventAppendEvent") else { debugLog.append("no Append"); return }
        appendRaw = ap

        guard let dp = _dlsym(h, "IOHIDEventSystemClientDispatchEvent") else { debugLog.append("no Dispatch"); return }
        dispatchRaw = dp

        canSimulateTouches = true
        debugLog.append("IOKit loaded OK")
    }

    private func ts() -> UInt64 { _mach_absolute_time() }

    private func iofix(_ v: CGFloat) -> Int32 { Int32(v * 65536) }

    private func makeEvent(touch: Bool, point: CGPoint) -> IOHIDRef? {
        guard let p = createDigitizerRaw else { return nil }
        let fn = unsafeBitCast(p, to: CreateDigitizerC.self)
        let mask: UInt32 = 0x01 | 0x02 | 0x04
        return fn(kCFAllocatorDefault, ts(), 3, 0, 2, mask, 0,
                  iofix(point.x), iofix(point.y), 0,
                  touch ? iofix(1.0) : 0, 0,
                  touch, touch, 0)
    }

    private func dispatch(_ ev: IOHIDRef?) {
        guard let c = client, let ev = ev, let dp = dispatchRaw else { return }
        let dispatchFn = unsafeBitCast(dp, to: DispatchC.self)
        dispatchFn(c, ev)
    }

    private func makeParent() -> IOHIDRef? {
        nil
    }

    func touchDown(at point: CGPoint, fingerId: Int32 = 0) {
        guard canSimulateTouches else { return }
        dispatch(makeEvent(touch: true, point: point))
    }

    func touchMove(to point: CGPoint, fingerId: Int32 = 0) {
        guard canSimulateTouches else { return }
        dispatch(makeEvent(touch: true, point: point))
    }

    func touchUp(at point: CGPoint, fingerId: Int32 = 0) {
        guard canSimulateTouches else { return }
        dispatch(makeEvent(touch: false, point: point))
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
            touchMove(to: CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
        }
        usleep(40000)
        touchUp(at: end)
    }
}
