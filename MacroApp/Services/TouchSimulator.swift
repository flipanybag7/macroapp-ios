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
private typealias CreateFingerC = @convention(c) (CFAllocator?, UInt64, UInt32, UInt32, UInt32, Int32, Int32, Int32, Int32, Int32, Bool, Bool, UInt32) -> IOHIDRef?
private typealias AppendEventC = @convention(c) (IOHIDRef?, IOHIDRef?) -> Void

final class TouchSimulator {
    static let shared = TouchSimulator()
    private var client: IOHIDRef?
    private var createDigitizerRaw: UnsafeMutableRawPointer?
    private var createFingerRaw: UnsafeMutableRawPointer?
    private var appendRaw: UnsafeMutableRawPointer?
    private var dispatchRaw: UnsafeMutableRawPointer?
    private(set) var canSimulateTouches = false

    private init() {
        #if targetEnvironment(simulator)
        return
        #endif
        loadIOKit()
    }

    private func loadIOKit() {
        guard let h = _dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else {
            print("🔴 IOKit dlopen failed")
            return
        }
        guard let cc = _dlsym(h, "IOHIDEventSystemClientCreate"),
              let cd = _dlsym(h, "IOHIDEventCreateDigitizerEvent"),
              let cf = _dlsym(h, "IOHIDEventCreateDigitizerFingerEvent"),
              let ap = _dlsym(h, "IOHIDEventAppendEvent"),
              let dp = _dlsym(h, "IOHIDEventSystemClientDispatchEvent") else {
            print("🔴 dlsym failed")
            return
        }
        let fn = unsafeBitCast(cc, to: CreateClientC.self)
        guard let c = fn(kCFAllocatorDefault) else {
            print("🔴 CreateClient returned nil")
            return
        }
        client = c
        createDigitizerRaw = cd
        createFingerRaw = cf
        appendRaw = ap
        dispatchRaw = dp
        canSimulateTouches = true
        print("🟢 IOKit loaded OK, client: \(c)")
    }

    private func ts() -> UInt64 { _mach_absolute_time() }
    private func iofix(_ v: CGFloat) -> Int32 { Int32(v * 65536) }

    private func send(_ point: CGPoint, _ isDown: Bool, _ isUp: Bool) {
        print("🔵 send x:\(point.x) y:\(point.y) down:\(isDown) up:\(isUp)")
        guard let c = client, let cd = createDigitizerRaw, let cf = createFingerRaw,
              let ap = appendRaw, let dp = dispatchRaw else {
            print("🔴 send() guard failed — missing one of: client=\(client != nil) cd=\(createDigitizerRaw != nil) cf=\(createFingerRaw != nil) ap=\(appendRaw != nil) dp=\(dispatchRaw != nil)")
            return
        }

        let time = ts()
        let ix = iofix(point.x)
        let iy = iofix(point.y)
        let pr = isDown ? iofix(1.0) : 0
        let touch = !isUp
        let digMask: UInt32 = touch ? 0x07 : 0x01

        let createDig = unsafeBitCast(cd, to: CreateDigitizerC.self)
        guard let digEvent = createDig(kCFAllocatorDefault, time, 3, 0, 2, 1, 0,
                                       0, 0, 0, 0, 0, true, false, 0) else {
            print("🔴 digEvent is nil")
            return
        }

        let createFinger = unsafeBitCast(cf, to: CreateFingerC.self)
        guard let fingerEvent = createFinger(kCFAllocatorDefault, time, 0, 2, digMask,
                                             ix, iy, 0, pr, 0, touch, touch, 0) else {
            print("🔴 fingerEvent is nil")
            return
        }

        let append = unsafeBitCast(ap, to: AppendEventC.self)
        append(digEvent, fingerEvent)

        let dsp = unsafeBitCast(dp, to: DispatchC.self)
        if Thread.isMainThread { dsp(c, digEvent) }
        else { DispatchQueue.main.sync { dsp(c, digEvent) } }
        print("✅ dispatched")
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
            print("🟡 swipe from \(from) to \(to) steps=\(s)")
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
