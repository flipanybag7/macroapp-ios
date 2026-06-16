import Foundation
import Darwin

@_silgen_name("posix_spawn")
func _posix_spawn(_ pid: UnsafeMutablePointer<pid_t>?, _ path: UnsafePointer<CChar>, _ fa: UnsafeMutablePointer<posix_spawn_file_actions_t>?, _ attr: UnsafeMutablePointer<posix_spawnattr_t>?, _ argv: UnsafePointer<UnsafeMutablePointer<CChar>?>?, _ envp: UnsafePointer<UnsafeMutablePointer<CChar>?>?) -> Int32

final class TouchSimulator {
    static let shared = TouchSimulator()
    private let path = "/tmp/.th"
    private var ready = false
    private(set) var canSimulateTouches = false

    private init() {
        #if targetEnvironment(simulator)
        return
        #endif
        DispatchQueue.global(qos: .background).async { self.setup() }
    }

    private func setup() {
        guard !helperBinaryB64.isEmpty, let data = Data(base64Encoded: helperBinaryB64) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
        spawn("/var/jb/usr/bin/chmod", "755", path)
        ready = access(path, X_OK) == 0
        canSimulateTouches = ready
    }

    private func spawn(_ cmd: String, _ args: String...) {
        var pid: pid_t = 0
        let a = ([cmd] + args).map { strdup($0) }; defer { a.forEach { free($0) } }
        var argv = a + [nil]
        _ = _posix_spawn(&pid, cmd, nil, nil, &argv, nil)
    }

    func touchDown(at point: CGPoint, fingerId: Int32 = 0) { spawn("/var/jb/usr/bin/sudo", path, "0", "\(point.x)", "\(point.y)", "\(fingerId)") }
    func touchMove(to point: CGPoint, fingerId: Int32 = 0) { spawn("/var/jb/usr/bin/sudo", path, "1", "\(point.x)", "\(point.y)", "\(fingerId)") }
    func touchUp(at point: CGPoint, fingerId: Int32 = 0) { spawn("/var/jb/usr/bin/sudo", path, "2", "\(point.x)", "\(point.y)", "\(fingerId)") }

    func tap(at: CGPoint) { touchDown(at: at); usleep(60000); touchUp(at: at) }
    func longPress(at: CGPoint, duration: TimeInterval) { touchDown(at: at); usleep(UInt32(duration*1_000_000)); touchUp(at: at) }
    func swipe(from: CGPoint, to: CGPoint, duration: TimeInterval) {
        let s = max(5, Int(duration*60)); let d = useconds_t(duration/Double(s)*1_000_000)
        touchDown(at: from)
        for i in 1...s { usleep(d); let t=Double(i)/Double(s); touchMove(to: CGPoint(x:from.x+(to.x-from.x)*t, y:from.y+(to.y-from.y)*t)) }
        usleep(40000); touchUp(at: to)
    }
}
