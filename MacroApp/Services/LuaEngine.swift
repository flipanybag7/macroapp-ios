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

    private func executeScript(_ raw: String) -> [MacroAction] {
        var actions: [MacroAction] = []
        var variables: [String: Double] = [:]

        let lines = raw.components(separatedBy: .newlines)

        for (lineNum, line) in lines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespaces)

            if t.isEmpty || t.hasPrefix("--") { continue }

            DispatchQueue.main.async { [weak self] in
                self?.currentLine = lineNum + 1
            }

            if t.hasPrefix("local ") {
                if let (name, val) = parseAssignment(t) {
                    variables[name] = val
                }
                continue
            }

            if t.hasPrefix("usleep("), let num = extractParenNum(t) {
                let sec = num / 1_000_000
                Thread.sleep(forTimeInterval: sec)
                continue
            }

            if let (fn, args) = parseCall(t) {
                let vals = args.map { evalExpr($0, vars: variables) }
                if fn == "touchDown", vals.count >= 3 {
                    let pt = CGPoint(x: vals[1], y: vals[2])
                    actions.append(.tap(at: pt, delay: 0))
                } else if fn == "touchMove", vals.count >= 3 {
                    // tracked via the touchDown that started it
                } else if fn == "touchUp", vals.count >= 3 {
                    // tracked via the touchDown that started it
                }
                continue
            }

            if t.hasPrefix("for ") {
                let (iterVar, from, to, body) = parseFor(t, remainingLines: Array(lines[(lineNum + 1)...]))
                if let iv = iterVar {
                    for i in Int(from)...Int(to) {
                        variables[iv] = Double(i)
                        let subActions = executeScript(body.joined(separator: "\n"))
                        actions.append(contentsOf: subActions)
                    }
                    break
                }
            }
        }

        return actions
    }

    func parseScript(_ script: String) -> [MacroAction] {
        return executeScript(script)
    }

    // --- helpers ---

    private func parseAssignment(_ line: String) -> (String, Double)? {
        let cleaned = line
            .replacingOccurrences(of: "local ", with: "")
            .trimmingCharacters(in: .whitespaces)
        let parts = cleaned.components(separatedBy: "=").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { return nil }
        let name = parts[0]
        let expr = parts[1]
        let val = evalExpr(expr, vars: [:])
        return (name, val)
    }

    private func evalExpr(_ expr: String, vars: [String: Double]) -> Double {
        let e = expr.trimmingCharacters(in: .whitespaces)

        // math.random(a, b)
        if e.hasPrefix("math.random("), e.hasSuffix(")") {
            let inner = String(e.dropFirst("math.random(".count).dropLast(1))
            let nums = inner.components(separatedBy: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if nums.count == 2 {
                return Double(Int.random(in: Int(nums[0])...Int(nums[1])))
            }
        }

        // simple arithmetic: a + b, a - b, a * b, a / b
        if e.contains("+") {
            let parts = e.components(separatedBy: "+")
            return parts.reduce(0) { $0 + (Double($1.trimmingCharacters(in: .whitespaces)) ?? vars[$1.trimmingCharacters(in: .whitespaces)] ?? 0) }
        }
        if e.contains("-"), !e.hasPrefix("-") {
            let parts = e.components(separatedBy: "-")
            if parts.count == 2 {
                let a = Double(parts[0].trimmingCharacters(in: .whitespaces)) ?? vars[parts[0].trimmingCharacters(in: .whitespaces)] ?? 0
                let b = Double(parts[1].trimmingCharacters(in: .whitespaces)) ?? vars[parts[1].trimmingCharacters(in: .whitespaces)] ?? 0
                return a - b
            }
        }
        if e.contains("*") {
            let parts = e.components(separatedBy: "*")
            return parts.reduce(1) { $0 * (Double($1.trimmingCharacters(in: .whitespaces)) ?? vars[$1.trimmingCharacters(in: .whitespaces)] ?? 1) }
        }
        if e.contains("/"), !e.hasPrefix("/") {
            let parts = e.components(separatedBy: "/")
            if parts.count == 2 {
                let a = Double(parts[0].trimmingCharacters(in: .whitespaces)) ?? vars[parts[0].trimmingCharacters(in: .whitespaces)] ?? 0
                let b = Double(parts[1].trimmingCharacters(in: .whitespaces)) ?? vars[parts[1].trimmingCharacters(in: .whitespaces)] ?? 1
                return b != 0 ? a / b : 0
            }
        }

        // variable lookup
        if let v = vars[e] { return v }
        // plain number
        return Double(e) ?? 0
    }

    private func extractParenNum(_ s: String) -> Double? {
        guard let start = s.firstIndex(of: "("), let end = s.lastIndex(of: ")"), start < end else { return nil }
        let inside = String(s[s.index(after: start)..<end]).trimmingCharacters(in: .whitespaces)
        return Double(inside)
    }

    private func parseCall(_ line: String) -> (String, [String])? {
        guard let paren = line.firstIndex(of: "("), line.hasSuffix(")") else { return nil }
        let fn = String(line[..<paren]).trimmingCharacters(in: .whitespaces)
        let argsRaw = String(line[line.index(after: paren)..<line.index(before: line.endIndex)])
        let args = argsRaw.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return (fn, args)
    }

    private func parseFor(_ line: String, remainingLines: [String]) -> (String?, Double, Double, [String]) {
        let parts = line.components(separatedBy: "=")
        guard parts.count == 2 else { return (nil, 0, 0, []) }

        let left = parts[0].replacingOccurrences(of: "for ", with: "").trimmingCharacters(in: .whitespaces)
        let comps = left.components(separatedBy: ",")
        guard comps.count == 2 else { return (nil, 0, 0, []) }
        let iterVar = comps[0].trimmingCharacters(in: .whitespaces)

        let right = parts[1].trimmingCharacters(in: .whitespaces)
        let rangeParts = right.components(separatedBy: " ")
        guard rangeParts.count >= 3, rangeParts[1] == "do" else { return (nil, 0, 0, []) }

        let from = Double(rangeParts[0]) ?? 0
        var to: Double = 0
        if let endIdx = rangeParts[2].firstIndex(of: ")") {
            to = Double(String(rangeParts[2][..<endIdx])) ?? 0
        } else {
            to = Double(rangeParts[2]) ?? 0
        }

        var body: [String] = []
        var depth = 1
        for rline in remainingLines {
            let rt = rline.trimmingCharacters(in: .whitespaces)
            if rt == "end" || rt.hasPrefix("end ") {
                depth -= 1
                if depth == 0 { break }
            }
            if rt.hasPrefix("for ") { depth += 1 }
            body.append(rline)
        }
        return (iterVar, from, to, body)
    }

    func runWithSimulation(_ script: String) {
        _executeWithInject(script)
    }

    private func _executeWithInject(_ raw: String) {
        var variables: [String: Double] = [:]
        let lines = raw.components(separatedBy: .newlines)

        for (lineNum, line) in lines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("--") { continue }

            DispatchQueue.main.async { [weak self] in
                self?.currentLine = lineNum + 1
            }

            if t.hasPrefix("local ") {
                if let (name, val) = parseAssignment(t) {
                    variables[name] = val
                }
                continue
            }

            if t.hasPrefix("usleep("), let num = extractParenNum(t) {
                Thread.sleep(forTimeInterval: num / 1_000_000)
                continue
            }

            if let (fn, args) = parseCall(t) {
                let vals = args.map { evalExpr($0, vars: variables) }
                if fn == "touchDown", vals.count >= 3 {
                    TouchSimulator.shared.touchDown(at: CGPoint(x: vals[1], y: vals[2]), fingerId: Int32(vals[0]))
                } else if fn == "touchMove", vals.count >= 3 {
                    TouchSimulator.shared.touchMove(to: CGPoint(x: vals[1], y: vals[2]), fingerId: Int32(vals[0]))
                } else if fn == "touchUp", vals.count >= 3 {
                    TouchSimulator.shared.touchUp(at: CGPoint(x: vals[1], y: vals[2]), fingerId: Int32(vals[0]))
                }
                continue
            }

            if t.hasPrefix("for ") {
                let (iterVar, from, to, body) = parseFor(t, remainingLines: Array(lines[(lineNum + 1)...]))
                if let iv = iterVar {
                    for i in Int(from)...Int(to) {
                        variables[iv] = Double(i)
                        _executeWithInject(body.joined(separator: "\n"))
                    }
                    break
                }
            }
        }
    }
}
