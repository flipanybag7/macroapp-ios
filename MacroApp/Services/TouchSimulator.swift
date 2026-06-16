import Foundation
import Darwin

@_silgen_name("posix_spawn")
func _posix_spawn(_ pid: UnsafeMutablePointer<pid_t>?, _ path: UnsafePointer<CChar>, _ fileActions: UnsafeMutablePointer<posix_spawn_file_actions_t>?, _ attrp: UnsafeMutablePointer<posix_spawnattr_t>?, _ argv: UnsafePointer<UnsafeMutablePointer<CChar>?>?, _ envp: UnsafePointer<UnsafeMutablePointer<CChar>?>?) -> Int32

final class TouchSimulator {
    static let shared = TouchSimulator()

    private var helperPath = "/tmp/touch_helper"
    private var helperReady = false

    private(set) var canSimulateTouches = false

    private init() {
        #if targetEnvironment(simulator)
        return
        #endif
        guard isJailbroken() else { return }
        setupHelper()
    }

    private func isJailbroken() -> Bool {
        for p in ["/Applications/Cydia.app","/Library/MobileSubstrate","/bin/bash","/etc/apt","/var/jb","/private/preboot/jb"] {
            if access(p, F_OK) == 0 { return true }
        }
        do {
            try ".".write(toFile: "/var/mobile/Library/jbchk", atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(atPath: "/var/mobile/Library/jbchk")
            return true
        } catch { return false }
    }

    private func setupHelper() {
        // try to find or install the helper
        if access("/tmp/touch_helper", X_OK) == 0 {
            helperReady = true
            canSimulateTouches = true
            return
        }

        // copy from bundle if available
        if let bundled = Bundle.main.url(forResource: "touch_helper", withExtension: nil) {
            try? FileManager.default.removeItem(atPath: "/tmp/touch_helper")
            do {
                try FileManager.default.copyItem(at: bundled, to: URL(fileURLWithPath: "/tmp/touch_helper"))
                spawn("/var/jb/usr/bin/chmod", ["755", "/tmp/touch_helper"])
                spawn("/var/jb/usr/bin/ldid", ["-S", "/tmp/touch_helper"])
                helperReady = true
                canSimulateTouches = true
                return
            } catch { }
        }

        // if all else fails, try the previously compiled one
        if access("/tmp/th", X_OK) == 0 {
            helperPath = "/tmp/th"
            helperReady = true
            canSimulateTouches = true
            return
        }
    }

    private func spawn(_ launchPath: String, _ args: [String]) -> Int32 {
        var pid: pid_t = 0
        let cargs = ([launchPath] + args).map { strdup($0) }
        defer { cargs.forEach { free($0) } }
        var argv = cargs + [nil]
        return _posix_spawn(&pid, launchPath, nil, nil, argv, nil)
    }

    @discardableResult
    private func run(_ args: String...) -> Bool {
        guard helperReady else { return false }
        let ret = spawn("/var/jb/usr/bin/sudo", [helperPath] + args)
        return ret == 0
    }

    func touchDown(at point: CGPoint, fingerId: Int32 = 0) {
        run("0", "\(point.x)", "\(point.y)", "\(fingerId)")
    }

    func touchMove(to point: CGPoint, fingerId: Int32 = 0) {
        run("1", "\(point.x)", "\(point.y)", "\(fingerId)")
    }

    func touchUp(at point: CGPoint, fingerId: Int32 = 0) {
        run("2", "\(point.x)", "\(point.y)", "\(fingerId)")
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
