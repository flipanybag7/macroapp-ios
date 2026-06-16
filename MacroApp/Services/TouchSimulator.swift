import Foundation
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

    private(set) var canSimulateTouches = false

    private init() {
        #if targetEnvironment(simulator)
        return
        #endif
        loadIOKit()
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

    private func send(_ point: CGPoint, _ isDown: Bool, _ isUp: Bool) {
        guard let c = client, let cd = createDigitizerRaw, let dp = dispatchRaw else { return }
        let fn = unsafeBitCast(cd, to: CreateDigitizerC.self)
        let mask: UInt32 = isUp ? 0x01 : (0x01 | 0x02 | 0x04)
        guard let ev = fn(kCFAllocatorDefault, ts(), 3, 0, 2, mask, 0,
                          iofix(point.x), iofix(point.y), 0,
                          isDown ? iofix(1.0) : 0, 0,
                          !isUp, !isUp, 0) else { return }
        let dsp = unsafeBitCast(dp, to: DispatchC.self)
        if Thread.isMainThread {
            dsp(c, ev)
        } else {
            DispatchQueue.main.sync { dsp(c, ev) }
        }
    }

    func touchDown(at point: CGPoint, fingerId: Int32 = 0) { send(point, true, false) }
    func touchMove(to point: CGPoint, fingerId: Int32 = 0) { send(point, true, false) }
    func touchUp(at point: CGPoint, fingerId: Int32 = 0) { send(point, false, true) }

    func tap(at: CGPoint) { touchDown(at: at); usleep(60000); touchUp(at: at) }
    func longPress(at: CGPoint, duration: TimeInterval) { touchDown(at: at); usleep(UInt32(duration*1_000_000)); touchUp(at: at) }
    func swipe(from: CGPoint, to: CGPoint, duration: TimeInterval) {
        DispatchQueue.global(qos: .userInteractive).async {
            let s = max(5, Int(duration * 60))
            let d = useconds_t((duration / Double(s)) * 1_000_000)
            self.touchDown(at: from)
            for i in 1...s {
                usleep(d)
                let t = Double(i) / Double(s)
                self.touchMove(to: CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
            }
            usleep(40000)
            self.touchUp(at: to)
        }
    }
}
