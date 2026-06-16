import Foundation
import Darwin

@_silgen_name("posix_spawn")
func _posix_spawn(_ pid: UnsafeMutablePointer<pid_t>?, _ path: UnsafePointer<CChar>, _ fileActions: UnsafeMutablePointer<posix_spawn_file_actions_t>?, _ attrp: UnsafeMutablePointer<posix_spawnattr_t>?, _ argv: UnsafePointer<UnsafeMutablePointer<CChar>?>?, _ envp: UnsafePointer<UnsafeMutablePointer<CChar>?>?) -> Int32

final class TouchSimulator {
    static let shared = TouchSimulator()

    private let helperPath = "/tmp/touch_helper"
    private var helperReady = false

    private(set) var canSimulateTouches = false

    private init() {
        #if targetEnvironment(simulator)
        return
        #endif
        DispatchQueue.global(qos: .background).async { self.trySetup() }
    }

    private func trySetup() {
        // Already exists?
        if access(helperPath, X_OK) == 0 {
            helperReady = true
            canSimulateTouches = true
            return
        }
        // Use fallback from earlier compile
        if access("/tmp/th", X_OK) == 0 {
            helperReady = true
            canSimulateTouches = true
            _helperPath = "/tmp/th"
            return
        }
        // Try to copy from bundle, and if that fails, compile on-device
        if compileHelper() {
            helperReady = true
            canSimulateTouches = true
        }
    }

    private var _helperPath = "/tmp/touch_helper"
    private var effectivePath: String { _helperPath }

    private func spawn(_ path: String, _ args: [String]) -> Int32 {
        var pid: pid_t = 0
        let cargs = ([path] + args).map { strdup($0) }
        defer { cargs.forEach { free($0) } }
        let argv = cargs + [nil]
        return _posix_spawn(&pid, path, nil, nil, argv, nil)
    }

    private func compileHelper() -> Bool {
        let sdk = "/var/jb/usr/share/SDKs/iPhoneOS.sdk"
        let src = "/tmp/th.c"

        let code = """
        #include <CoreFoundation/CoreFoundation.h>
        #include <mach/mach_time.h>
        #include <stdlib.h>
        #include <unistd.h>
        typedef void* IOHIDSystemRef; typedef void* IOHIDRef;
        extern IOHIDSystemRef IOHIDEventSystemClientCreate(CFAllocatorRef);
        extern IOHIDRef IOHIDEventCreateDigitizerFingerEvent(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t, int32_t, int32_t, int32_t, int32_t, int32_t, int, int, uint32_t);
        extern IOHIDRef IOHIDEventCreateDigitizerEvent(CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, int32_t, int32_t, int32_t, int32_t, int32_t, int, int, uint32_t);
        extern void IOHIDEventAppendEvent(IOHIDRef, IOHIDRef);
        extern void IOHIDEventSystemClientDispatchEvent(IOHIDSystemRef, IOHIDRef);
        int main(int c, char** v) { if(c!=5) return 1; int t=atoi(v[1]); float x=atof(v[2]),y=atof(v[3]); uint64_t mt=mach_absolute_time();
        #define F(p) ((int32_t)((p)*65536))
        IOHIDSystemRef cl=IOHIDEventSystemClientCreate(NULL); if(!cl) return 2;
        IOHIDRef p=IOHIDEventCreateDigitizerEvent(NULL,mt,3,0,2,1,0,0,0,0,0,0,1,0,0);
        IOHIDRef e=IOHIDEventCreateDigitizerFingerEvent(NULL,mt,0,2,(t==2?1:7),F(x),F(y),0,F(t==2?0:1),0,t!=2,t!=2,0);
        IOHIDEventAppendEvent(p,e); IOHIDEventSystemClientDispatchEvent(cl,p); CFRelease(e);CFRelease(p);CFRelease(cl); return 0; }
        """

        try? code.write(toFile: src, atomically: true, encoding: .utf8)

        let clangPath = "/var/jb/usr/bin/clang"
        guard access(clangPath, X_OK) == 0 else { return false }

        try? FileManager.default.removeItem(atPath: helperPath)
        let r1 = spawn(clangPath, ["-isysroot", sdk, "-framework", "IOKit", "-framework", "CoreFoundation", "-o", helperPath, src])
        if r1 != 0 { return false }

        let r2 = spawn("/var/jb/usr/bin/ldid", ["-S", helperPath])
        if r2 != 0 {
            // try without signing
        }

        return access(helperPath, X_OK) == 0
    }

    @discardableResult
    private func run(_ args: String...) -> Bool {
        guard helperReady else { return false }
        let ret = spawn("/var/jb/usr/bin/sudo", [effectivePath] + args)
        return ret == 0
    }

    func touchDown(at point: CGPoint, fingerId: Int32 = 0) { run("0", "\(point.x)", "\(point.y)", "\(fingerId)") }
    func touchMove(to point: CGPoint, fingerId: Int32 = 0) { run("1", "\(point.x)", "\(point.y)", "\(fingerId)") }
    func touchUp(at point: CGPoint, fingerId: Int32 = 0) { run("2", "\(point.x)", "\(point.y)", "\(fingerId)") }

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
