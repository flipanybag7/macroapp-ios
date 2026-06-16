import Foundation
import Network

final class TouchSimulator {
    static let shared = TouchSimulator()

    private var connection: NWConnection?
    private var queue = DispatchQueue(label: "zxtouch.tcp")
    private var isConnected = false
    private var connectionReady = false
    private var pending: [Data] = []

    private let port: UInt16 = 6000
    private let taskTouch: Int = 10

    private(set) var canSimulateTouches = false

    private init() {
        #if targetEnvironment(simulator)
        return
        #endif
        connect()
    }

    private func connect() {
        let host = NWEndpoint.Host("127.0.0.1")
        connection = NWConnection(host: host, port: NWEndpoint.Port(rawValue: port)!, using: .tcp)

        connection?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.connectionReady = true
                self?.canSimulateTouches = true
                self?.flushPending()
            case .failed, .cancelled:
                self?.canSimulateTouches = false
                self?.connectionReady = false
            default:
                break
            }
        }
        connection?.start(queue: queue)
    }

    private func flushPending() {
        for data in pending {
            sendRaw(data)
        }
        pending.removeAll()
    }

    private func sendRaw(_ data: Data) {
        guard let conn = connection, connectionReady else {
            pending.append(data)
            return
        }
        conn.send(content: data, completion: .contentProcessed({ _ in }))
    }

    private func sendCommand(_ taskType: Int, _ data: String) {
        let msg = "\(taskType);;\(data)\r\n"
        guard let raw = msg.data(using: .utf8) else { return }
        sendRaw(raw)
    }

    private func formatCoord(_ val: CGFloat) -> String {
        let scaled = Int(val * 10)
        return String(format: "%05d", scaled)
    }

    private func buildTouchData(type: Int, finger: Int, x: CGFloat, y: CGFloat) -> String {
        "1\(type)\(String(format: "%02d", finger))\(formatCoord(x))\(formatCoord(y))"
    }

    func touchDown(at point: CGPoint, fingerId: Int32 = 0) {
        sendCommand(taskTouch, buildTouchData(type: 1, finger: Int(fingerId), x: point.x, y: point.y))
    }

    func touchMove(to point: CGPoint, fingerId: Int32 = 0) {
        sendCommand(taskTouch, buildTouchData(type: 2, finger: Int(fingerId), x: point.x, y: point.y))
    }

    func touchUp(at point: CGPoint, fingerId: Int32 = 0) {
        sendCommand(taskTouch, buildTouchData(type: 3, finger: Int(fingerId), x: point.x, y: point.y))
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
