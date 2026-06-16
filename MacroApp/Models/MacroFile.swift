import Foundation

struct MacroFile: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var actions: [MacroAction]
    var createdAt: Date
    var modifiedAt: Date
    var screenSize: CGSize
    var duration: TimeInterval {
        actions.reduce(0) { $0 + $1.delay + $1.duration }
    }

    init(
        id: UUID = UUID(),
        name: String,
        actions: [MacroAction] = [],
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        screenSize: CGSize = CGSize(width: 393, height: 852)
    ) {
        self.id = id
        self.name = name
        self.actions = actions
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.screenSize = screenSize
    }

    var luaScript: String {
        LuaScriptGenerator.generate(from: self)
    }

    var actionCount: Int {
        actions.count
    }
}

struct MacroFileStore {
    static let documentsDirectory: URL = {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }()

    static let macrosDirectory: URL = {
        let dir = documentsDirectory.appendingPathComponent("Macros")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }()

    static func save(_ macro: MacroFile) throws {
        var mutable = macro
        mutable.modifiedAt = Date()
        let data = try JSONEncoder().encode(mutable)
        let url = macrosDirectory.appendingPathComponent("\(mutable.id.uuidString).json")
        try data.write(to: url)
    }

    static func loadAll() -> [MacroFile] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: macrosDirectory,
            includingPropertiesForKeys: nil
        ) else { return [] }

        return contents
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> MacroFile? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(MacroFile.self, from: data)
            }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    static func delete(_ macro: MacroFile) throws {
        let url = macrosDirectory.appendingPathComponent("\(macro.id.uuidString).json")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    static func saveLua(_ macro: MacroFile) throws {
        let luaDir = macrosDirectory.appendingPathComponent("lua_scripts")
        if !FileManager.default.fileExists(atPath: luaDir.path) {
            try FileManager.default.createDirectory(at: luaDir, withIntermediateDirectories: true)
        }
        let url = luaDir.appendingPathComponent("\(macro.name).lua")
        try macro.luaScript.write(to: url, atomically: true, encoding: .utf8)
    }
}
