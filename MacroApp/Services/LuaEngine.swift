import Foundation
import UIKit

final class LuaEngine: ObservableObject {
    static let shared = LuaEngine()

    @Published var isRunning = false
    @Published var output: String = ""
    @Published var currentLine: Int = 0

    private var scriptsDir: URL {
        MacroFileStore.macrosDirectory.appendingPathComponent("lua_scripts")
    }

    private init() {
        if !FileManager.default.fileExists(atPath: scriptsDir.path) {
            try? FileManager.default.createDirectory(at: scriptsDir, withIntermediateDirectories: true)
        }
    }

    func runScript(_ script: String, completion: @escaping ([MacroAction]) -> Void) {
        isRunning = true
        output = ""

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let actions = self?.executeScript(script) ?? []
            DispatchQueue.main.async {
                self?.isRunning = false
                completion(actions)
            }
        }
    }

    func runScriptFile(named name: String) -> [MacroAction] {
        let url = scriptsDir.appendingPathComponent(name)
        guard let script = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return executeScript(script)
    }

    func saveScript(_ script: String, named name: String) throws {
        let url = scriptsDir.appendingPathComponent(name)
        try script.write(to: url, atomically: true, encoding: .utf8)
    }

    func listScripts() -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: scriptsDir,
            includingPropertiesForKeys: [.creationDateKey]
        ) else { return [] }
        return contents
            .filter { $0.pathExtension == "lua" }
            .sorted { u1, u2 in
                let d1 = (try? u1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
                let d2 = (try? u2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
                return d1 > d2
            }
    }

    func deleteScript(at url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func executeScript(_ script: String) -> [MacroAction] {
        var actions: [MacroAction] = []
        let lines = script.components(separatedBy: .newlines)

        for (lineNum, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            DispatchQueue.main.async { [weak self] in
                self?.currentLine = lineNum + 1
            }

            if trimmed.hasPrefix("usleep(") {
                let microseconds = extractNumber(from: trimmed, prefix: "usleep(")
                let seconds = microseconds / 1_000_000
                Thread.sleep(forTimeInterval: seconds)
                continue
            }

            if trimmed.hasPrefix("touchDown(") {
                let parts = trimmed
                    .replacingOccurrences(of: "touchDown(", with: "")
                    .replacingOccurrences(of: ")", with: "")
                    .components(separatedBy: ",")
                    .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                if parts.count >= 3 {
                    let point = CGPoint(x: parts[1], y: parts[2])
                    actions.append(.tap(at: point, delay: 0))
                }
            }
        }

        return actions
    }

    func parseScript(_ script: String) -> [MacroAction] {
        return LuaScriptGenerator.parseFromLua(script)
    }

    private func extractNumber(from str: String, prefix: String) -> Double {
        let numStr = str
            .replacingOccurrences(of: prefix, with: "")
            .replacingOccurrences(of: ")", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Double(numStr) ?? 0
    }

    func runWithSimulation(_ script: String) {
        let actions = parseScript(script)
        guard !actions.isEmpty else { return }

        isRunning = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            for (index, action) in actions.enumerated() {
                guard self?.isRunning == true else { break }

                DispatchQueue.main.async {
                    self?.currentLine = index + 1
                }

                Thread.sleep(forTimeInterval: action.delay)

                switch action.type {
                case .tap:
                    if let point = action.startPoint {
                        self?.simulateTap(at: point)
                    }
                case .swipe:
                    if let start = action.startPoint, let end = action.endPoint {
                        self?.simulateSwipe(from: start, to: end, duration: action.duration)
                    }
                case .longPress:
                    if let point = action.startPoint {
                        self?.simulateLongPress(at: point, duration: action.duration)
                    }
                case .wait:
                    Thread.sleep(forTimeInterval: action.duration)
                case .scroll:
                    self?.simulateScroll(delta: action.scrollDelta ?? 0)
                case .keyPress:
                    break
                }
            }

            DispatchQueue.main.async {
                self?.isRunning = false
            }
        }
    }

    private func simulateTap(at point: CGPoint) {
        DispatchQueue.main.async {
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first?.windows
                .first(where: { $0.isKeyWindow }) else { return }

            let touch = UITouch()
            let event = UIEvent()
            window.hitTest(point, with: event)?.touchesBegan([touch], with: event)
            window.hitTest(point, with: event)?.touchesEnded([touch], with: event)
        }
    }

    private func simulateSwipe(from: CGPoint, to: CGPoint, duration: TimeInterval) {
        let steps = max(5, Int(duration * 60))
        let stepDelay = duration / Double(steps)

        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let x = from.x + (to.x - from.x) * t
            let y = from.y + (to.y - from.y) * t
            let point = CGPoint(x: x, y: y)

            DispatchQueue.main.async {
                guard let window = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first?.windows
                    .first(where: { $0.isKeyWindow }) else { return }
                window.bringSubviewToFront(window)
            }

            Thread.sleep(forTimeInterval: stepDelay)
        }
    }

    private func simulateLongPress(at point: CGPoint, duration: TimeInterval) {
        DispatchQueue.main.async {
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first?.windows
                .first(where: { $0.isKeyWindow }) else { return }
            let touch = UITouch()
            let event = UIEvent()
            window.hitTest(point, with: event)?.touchesBegan([touch], with: event)
        }

        Thread.sleep(forTimeInterval: duration)

        DispatchQueue.main.async {
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first?.windows
                .first(where: { $0.isKeyWindow }) else { return }
            let touch = UITouch()
            let event = UIEvent()
            window.hitTest(point, with: event)?.touchesEnded([touch], with: event)
        }
    }

    private func simulateScroll(delta: CGFloat) {
        DispatchQueue.main.async {
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first?.windows
                .first(where: { $0.isKeyWindow }) else { return }

            let center = CGPoint(x: window.bounds.midX, y: window.bounds.midY)
            window.hitTest(center, with: nil)?.layer?.position = CGPoint(
                x: center.x,
                y: center.y + delta
            )
        }
    }
}
