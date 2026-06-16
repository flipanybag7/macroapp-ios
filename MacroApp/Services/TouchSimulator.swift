import Foundation
import CoreGraphics

@_silgen_name("dlopen")
internal func _dlopen(_ path: UnsafePointer<CChar>, _ mode: Int32) -> UnsafeMutableRawPointer?

@_silgen_name("dlsym")
internal func _dlsym(_ handle: UnsafeMutableRawPointer?, _ symbol: UnsafePointer<CChar>) -> UnsafeMutableRawPointer?

@_silgen_name("dlclose")
internal func _dlclose(_ handle: UnsafeMutableRawPointer?) -> Int32

struct GSEventRecord {
    var type: UInt32 = 0
    var subtype: UInt32 = 0
    var location: CGPoint = .zero
    var windowLocation: CGPoint = .zero
    var info0: Int32 = 0
    var info1: Int32 = 0
    var info2: Int32 = 0
    var info3: Int32 = 0
    var info4: Int32 = 0
    var info5: Int32 = 0
    var info6: Int32 = 0
    var info7: Int32 = 0
    var pressure: Float = 1.0
    var timestamp: Double = 0
}

final class TouchSimulator {
    static let shared = TouchSimulator()

    private let kGSHandEvent: UInt32 = 3001
    private let gsEventSubtypeDown: UInt32 = 1
    private let gsEventSubtypeMove: UInt32 = 2
    private let gsEventSubtypeUp: UInt32 = 3

    typealias GSSendEventFunc = @convention(c) (UnsafePointer<GSEventRecord>, UInt32) -> Void
    typealias GSCreatePurplePortFunc = @convention(c) () -> UInt32

    private var gsSendEvent: GSSendEventFunc?
    private var gsCreatePurplePort: GSCreatePurplePortFunc?
    private var gsAvailable: Bool = false

    var canSimulateTouches: Bool { gsAvailable }

    private init() {
        #if targetEnvironment(simulator)
        gsAvailable = false
        return
        #endif

        guard isDeviceJailbroken() else {
            gsAvailable = false
            return
        }

        loadGraphicsServices()
    }

    private func isDeviceJailbroken() -> Bool {
        let paths: [String] = [
            "/Applications/Cydia.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash",
            "/usr/sbin/sshd",
            "/etc/apt",
            "/var/lib/dpkg",
            "/var/jb",
            "/private/preboot/jb"
        ]

        for path in paths {
            if access(path, F_OK) == 0 {
                return true
            }
        }

        let testPath = "/var/mobile/Library/jb_test"
        do {
            try "jb".write(toFile: testPath, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(atPath: testPath)
            return true
        } catch {
            return false
        }
    }

    private func loadGraphicsServices() {
        let gsPaths = [
            "/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices",
            "/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices"
        ]

        for gsPath in gsPaths {
            guard let handle = _dlopen(gsPath, RTLD_NOW) else { continue }

            let sendSymbol = "GSSendEvent"
            let portSymbol = "GSCreatePurplePort"

            guard let sendPtr = _dlsym(handle, sendSymbol),
                  let portPtr = _dlsym(handle, portSymbol) else {
                _dlclose(handle)
                continue
            }

            gsSendEvent = unsafeBitCast(sendPtr, to: GSSendEventFunc.self)
            gsCreatePurplePort = unsafeBitCast(portPtr, to: GSCreatePurplePortFunc.self)
            gsAvailable = true
            return
        }
    }

    func touchDown(at point: CGPoint, fingerId: Int32 = 0) {
        guard gsAvailable else { return }
        sendHandEvent(at: point, subtype: gsEventSubtypeDown, fingerId: fingerId)
    }

    func touchMove(to point: CGPoint, fingerId: Int32 = 0) {
        guard gsAvailable else { return }
        sendHandEvent(at: point, subtype: gsEventSubtypeMove, fingerId: fingerId)
    }

    func touchUp(at point: CGPoint, fingerId: Int32 = 0) {
        guard gsAvailable else { return }
        sendHandEvent(at: point, subtype: gsEventSubtypeUp, fingerId: fingerId)
    }

    func tap(at point: CGPoint) {
        guard gsAvailable else { return }
        touchDown(at: point)
        usleep(50000)
        touchUp(at: point)
    }

    func longPress(at point: CGPoint, duration: TimeInterval) {
        guard gsAvailable else { return }
        touchDown(at: point)
        usleep(UInt32(duration * 1_000_000))
        touchUp(at: point)
    }

    func swipe(from start: CGPoint, to end: CGPoint, duration: TimeInterval) {
        guard gsAvailable else { return }
        let steps = max(5, Int(duration * 60))
        let stepDelay = useconds_t(duration / Double(steps) * 1_000_000)

        touchDown(at: start)
        for i in 1...steps {
            usleep(stepDelay)
            let t = Double(i) / Double(steps)
            let x = start.x + (end.x - start.x) * t
            let y = start.y + (end.y - start.y) * t
            touchMove(to: CGPoint(x: x, y: y))
        }
        usleep(30000)
        touchUp(at: end)
    }

    private func sendHandEvent(at point: CGPoint, subtype: UInt32, fingerId: Int32) {
        guard let sendEvent = gsSendEvent, let createPort = gsCreatePurplePort else { return }

        let port = createPort()
        var record = GSEventRecord()
        record.type = kGSHandEvent
        record.subtype = subtype
        record.location = point
        record.windowLocation = point
        record.pressure = (subtype == gsEventSubtypeUp) ? 0.0 : 1.0
        record.info0 = fingerId

        sendEvent(&record, port)
    }
}
