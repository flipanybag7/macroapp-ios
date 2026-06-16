import Foundation
import Darwin

@_silgen_name("posix_spawn")
func _posix_spawn(_ pid: UnsafeMutablePointer<pid_t>?, _ path: UnsafePointer<CChar>, _ fileActions: UnsafeMutablePointer<posix_spawn_file_actions_t>?, _ attrp: UnsafeMutablePointer<posix_spawnattr_t>?, _ argv: UnsafePointer<UnsafeMutablePointer<CChar>?>?, _ envp: UnsafePointer<UnsafeMutablePointer<CChar>?>?) -> Int32

let helperBinary: [UInt8] = []

final class TouchSimulator {
    static let shared = TouchSimulator()

    private let path = "/tmp/touch_helper"
    private var ready = false
    private(set) var canSimulateTouches = false

    private init() {
        #if targetEnvironment(simulator)
        return
        #endif
        DispatchQueue.global(qos: .background).async { self.setup() }
    }

    private func spawn(_ p: String, _ args: [String]) -> Int32 {
        var pid: pid_t = 0
        let a = ([p] + args).map { strdup($0) }
        defer { a.forEach { free($0) } }
        var argv = a + [nil]
        return _posix_spawn(&pid, p, nil, nil, &argv, nil)
    }

    private func setup() {
        guard !helperBinary.isEmpty else { return }
        if access(path, X_OK) != 0 {
            let data = Data(helperBinary)
            try? data.write(to: URL(fileURLWithPath: path))
            spawn("/var/jb/usr/bin/chmod", ["755", path])
            spawn("/var/jb/usr/bin/ldid", ["-S", path])
        }
        ready = access(path, X_OK) == 0
        canSimulateTouches = ready
    }

    private func run(_ args: String...) {
        guard ready else { return }
        spawn("/var/jb/usr/bin/sudo", [path] + args)
    }

    func touchDown(at point: CGPoint, fingerId: Int32 = 0) { run("0", "\(point.x)", "\(point.y)", "\(fingerId)") }
    func touchMove(to point: CGPoint, fingerId: Int32 = 0) { run("1", "\(point.x)", "\(point.y)", "\(fingerId)") }
    func touchUp(at point: CGPoint, fingerId: Int32 = 0) { run("2", "\(point.x)", "\(point.y)", "\(fingerId)") }

    func tap(at: CGPoint) { touchDown(at: at); usleep(60000); touchUp(at: at) }
    func longPress(at: CGPoint, duration: TimeInterval) { touchDown(at: at); usleep(UInt32(duration*1_000_000)); touchUp(at: at) }
    func swipe(from: CGPoint, to: CGPoint, duration: TimeInterval) {
        let s = max(5, Int(duration*60))
        let d = useconds_t(duration/Double(s)*1_000_000)
        touchDown(at: from)
        for i in 1...s { usleep(d); let t=Double(i)/Double(s); touchMove(to: CGPoint(x:from.x+(to.x-from.x)*t, y:from.y+(to.y-from.y)*t)) }
        usleep(40000); touchUp(at: to)
    }
}
