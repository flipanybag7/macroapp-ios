import Foundation
import CoreGraphics
import Darwin

typealias IOHIDRef = UnsafeMutableRawPointer

private typealias CreateClientC = @convention(c) (CFAllocator?) -> IOHIDRef?
private typealias DispatchC = @convention(c) (IOHIDRef?, IOHIDRef?) -> Void
private typealias ScheduleC = @convention(c) (IOHIDRef?, CFRunLoop?, CFString?) -> Void
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
    private var dispatchRaw: UnsafeMutableRawPointer?
    private var scheduleRaw: UnsafeMutableRawPointer?
    private var eventQueue = DispatchQueue(label: "touchsim.hid", qos: .userInteractive)
    private var queueInitialized = false

    private(set) var canSimulateTouches = false

    private init() {
        #if targetEnvironment(simulator)
        return
        #endif
        guard isJailbroken() else { return }
        setupEventQueue()
    }

    private func isJailbroken() -> Bool {
        for p in ["/Applications/Cydia.app","/Library/MobileSubstrate","/bin/bash","/etc/apt","/var/jb","/private/preboot/jb"] {
            if access(p, F_OK) == 0 { return true }
        }
        let t = "/var/mobile/Library/jbchk"
        do { try "." .write(toFile: t, atomically: true, encoding: .utf8); try FileManager.default.removeItem(atPath: t); return true } catch { }
        return false
    }

    private func setupEventQueue() {
        eventQueue.async { [weak self] in
            guard let self = self else { return }

            guard let h = _dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else { return }
            self.handle = h

            guard let cc = _dlsym(h, "IOHIDEventSystemClientCreate"),
                  let cd = _dlsym(h, "IOHIDEventCreateDigitizerEvent"),
                  let dp = _dlsym(h, "IOHIDEventSystemClientDispatchEvent"),
                  let sc = _dlsym(h, "IOHIDEventSystemClientScheduleWithRunLoop") else { return }

            let createClientFn = unsafeBitCast(cc, to: CreateClientC.self)
            guard let c = createClientFn(kCFAllocatorDefault) else { return }

            self.client = c
            self.createDigitizerRaw = cd
            self.dispatchRaw = dp
            self.scheduleRaw = sc

            // schedule on this queue's run loop
            let scheduleFn = unsafeBitCast(sc, to: ScheduleC.self)
            scheduleFn(c, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

            self.canSimulateTouches = true
            self.queueInitialized = true

            // keep run loop alive
            while self.canSimulateTouches {
                CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 1.0, true)
            }
        }
    }

    private func ts() -> UInt64 { _mach_absolute_time() }

    private func iofix(_ v: CGFloat) -> Int32 { Int32(v * 65536) }

    private func makeEvent(touch: Bool, point: CGPoint) -> IOHIDRef? {
        guard let p = createDigitizerRaw else { return nil }
        let fn = unsafeBitCast(p, to: CreateDigitizerC.self)
        return fn(kCFAllocatorDefault, ts(), 3, 0, 2, 0x01|0x02|0x04, 0,
                  iofix(point.x), iofix(point.y), 0,
                  touch ? iofix(1.0) : 0, 0,
                  touch, touch, 0)
    }

    private func enqueue(_ work: @escaping () -> Void) {
        eventQueue.sync {
            guard self.queueInitialized, self.canSimulateTouches else { return }
            work()
        }
    }

    func touchDown(at point: CGPoint, fingerId: Int32 = 0) {
        enqueue {
            guard let ev = self.makeEvent(touch: true, point: point),
                  let c = self.client, let dp = self.dispatchRaw else { return }
            let fn = unsafeBitCast(dp, to: DispatchC.self)
            fn(c, ev)
        }
    }

    func touchMove(to point: CGPoint, fingerId: Int32 = 0) {
        enqueue {
            guard let ev = self.makeEvent(touch: true, point: point),
                  let c = self.client, let dp = self.dispatchRaw else { return }
            let fn = unsafeBitCast(dp, to: DispatchC.self)
            fn(c, ev)
        }
    }

    func touchUp(at point: CGPoint, fingerId: Int32 = 0) {
        enqueue {
            guard let ev = self.makeEvent(touch: false, point: point),
                  let c = self.client, let dp = self.dispatchRaw else { return }
            let fn = unsafeBitCast(dp, to: DispatchC.self)
            fn(c, ev)
        }
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
