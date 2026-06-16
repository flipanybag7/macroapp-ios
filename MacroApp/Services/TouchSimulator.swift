import Foundation
import CoreGraphics
import Darwin

@_silgen_name("dlopen")
private func _dlopen(_ path: UnsafePointer<CChar>, _ mode: Int32) -> UnsafeMutableRawPointer?
@_silgen_name("dlsym")
private func _dlsym(_ handle: UnsafeMutableRawPointer?, _ symbol: UnsafePointer<CChar>) -> UnsafeMutableRawPointer?
@_silgen_name("mach_absolute_time")
private func _mach_absolute_time() -> UInt64

typealias IOHIDRef = UnsafeMutableRawPointer

private typealias CreateClientC = @convention(c) (CFAllocator?) -> IOHIDRef?
private typealias DispatchC = @convention(c) (IOHIDRef?, IOHIDRef?) -> Void
private typealias CreateDigitizerC = @convention(c) (CFAllocator?, UInt64, UInt32, UInt32, UInt32, UInt32, UInt32, Int32, Int32, Int32, Int32, Int32, Bool, Bool, UInt32) -> IOHIDRef?

final class TouchSimulator {
    static let shared = TouchSimulator()

    private var handle: UnsafeMutableRawPointer?
    private var client: IOHIDRef?
    private var createDigitizerRaw: UnsafeMutableRawPointer?
    private var dispatchRaw: UnsafeMutableRawPointer?
    private let serialQueue = DispatchQueue(label: "zxt.iolib")

    private(set) var canSimulateTouches = false

    private init() {
        #if targetEnvironment(simulator)
        return
        #endif
        guard isJailbroken() else { return }
        loadIOKit()
    }

    private func isJailbroken() -> Bool {
        for p in ["/Applications/Cydia.app","/Library/MobileSubstrate","/bin/bash","/etc/apt","/var/jb","/private/preboot/jb"] {
            if access(p, F_OK) == 0 { return true }
        }
        do {
            try "." .write(toFile: "/var/mobile/Library/jbchk", atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(atPath: "/var/mobile/Library/jbchk")
            return true
        } catch { return false }
    }

    private func loadIOKit() {
        guard let h = _dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else { return }
        handle = h

        guard let cc = _dlsym(h, "IOHIDEventSystemClientCreate"),
              let cd = _dlsym(h, "IOHIDEventCreateDigitizerEvent"),
              let dp = _dlsym(h, "IOHIDEventSystemClientDispatchEvent") else { return }

        let fn = unsafeBitCast(cc, to: CreateClientC.self)
        guard let c = fn(kCFAllocatorDefault) else { return }
        client = c
        createDigitizerRaw = cd
        dispatchRaw = dp
        canSimulateTouches = true
    }

    private func ts() -> UInt64 { _mach_absolute_time() }
    private func iofix(_ v: CGFloat) -> Int32 { Int32(v * 65536) }

    private func sendEvent(point: CGPoint, isDown: Bool, isUp: Bool) {
        guard let p = createDigitizerRaw, let c = client, let dp = dispatchRaw else { return }
        let fn = unsafeBitCast(p, to: CreateDigitizerC.self)
        let dsp = unsafeBitCast(dp, to: DispatchC.self)

        let mask: UInt32 = isUp ? 0x01 : (0x01 | 0x02 | 0x04)
        guard let ev = fn(kCFAllocatorDefault, ts(), 3, 0, 2, mask, 0,
                          iofix(point.x), iofix(point.y), 0,
                          isDown ? iofix(1.0) : 0, 0,
                          true,       // range always true
                          !isUp,      // touch = false on up
                          0) else { return }
        serialQueue.sync { dsp(c, ev) }
    }

    func touchDown(at point: CGPoint, fingerId: Int32 = 0) {
        guard canSimulateTouches else { return }
        sendEvent(point: point, isDown: true, isUp: false)
    }

    func touchMove(to point: CGPoint, fingerId: Int32 = 0) {
        guard canSimulateTouches else { return }
        sendEvent(point: point, isDown: true, isUp: false)
    }

    func touchUp(at point: CGPoint, fingerId: Int32 = 0) {
        guard canSimulateTouches else { return }
        sendEvent(point: point, isDown: false, isUp: true)
    }

    func tap(at point: CGPoint) {
        touchDown(at: point)
        usleep(60000)
        touchUp(at: point)
    }

    func longPress(at point: CGPoint, duration: TimeInterval) {
        touchDown(at: point)
        usleep(UInt32(duration * 1_000_000))
        touchUp(at: point)
    }

    func swipe(from start: CGPoint, to end: CGPoint, duration: TimeInterval) {
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
