import SwiftUI

struct LuaEditorView: View {
    @State private var scriptText = ""
    @State private var scriptName = ""
    @State private var isRunning = false
    @State private var output = ""
    @State private var scripts: [URL] = []
    @State private var selectedScriptURL: URL?
    @State private var showSaveAlert = false
    @State private var showDeleteAlert = false
    @State private var scriptToDelete: URL?

    private let templateScript = """
    -- MacroApp Lua Script
    -- Write your automation script here

    function main()
        -- Example: Tap at center of screen
        usleep(500000)
        touchDown(0, 200, 400)
        usleep(50000)
        touchUp(0, 200, 400)

        -- Example: Swipe up
        usleep(1000000)
        touchDown(0, 200, 600)
        for i = 1, 20 do
            usleep(8000)
            local y = math.floor(600 - (200 * i / 20))
            touchMove(0, 200, y)
        end
        usleep(50000)
        touchUp(0, 200, 400)

        -- Example: Long press
        usleep(1000000)
        touchDown(0, 200, 300)
        usleep(1000000)
        touchUp(0, 200, 300)

        -- Example: Scroll
        usleep(500000)
        scroll(-200)
    end

    main()
    """

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if !scripts.isEmpty {
                    scriptSelector
                }

                ZStack(alignment: .topLeading) {
                    if scriptText.isEmpty {
                        Text("Write or paste Lua script here...")
                            .foregroundColor(.gray)
                            .padding(.horizontal, 12)
                            .padding(.top, 12)
                    }

                    TextEditor(text: $scriptText)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(.white)
                        .background(Color(white: 0.06))
                }

                if !output.isEmpty {
                    outputConsole
                }

                actionBar
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Lua Editor")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button(action: loadTemplate) {
                            Text("New")
                        }
                        Button(action: { showSaveAlert = true }) {
                            Text("Save")
                        }
                    }
                }
            }
            .alert("Save Script", isPresented: $showSaveAlert) {
                TextField("script.lua", text: $scriptName)
                Button("Cancel", role: .cancel) { }
                Button("Save") {
                    saveScript()
                }
            } message: {
                Text("Enter a name for the Lua script")
            }
            .alert("Delete Script", isPresented: $showDeleteAlert, presenting: scriptToDelete) { url in
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    try? LuaEngine.shared.deleteScript(at: url)
                    refreshScripts()
                }
            } message: { url in
                Text("Delete '\(url.lastPathComponent)'?")
            }
            .onAppear {
                refreshScripts()
                if scriptText.isEmpty {
                    scriptText = templateScript
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var scriptSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(scripts, id: \.self) { url in
                    Button {
                        loadScript(from: url)
                    } label: {
                        Text(url.deletingPathExtension().lastPathComponent)
                            .font(.caption)
                            .fontWeight(selectedScriptURL == url ? .bold : .regular)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedScriptURL == url ? Color.blue.opacity(0.3) : Color(white: 0.18))
                            .foregroundColor(selectedScriptURL == url ? .white : .gray)
                            .cornerRadius(16)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            scriptToDelete = url
                            showDeleteAlert = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(white: 0.1))
    }

    private var outputConsole: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider().background(Color.gray.opacity(0.3))
            HStack {
                Text("Output")
                    .font(.caption)
                    .foregroundColor(.gray)
                Spacer()
                Button("Clear") {
                    output = ""
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)

            ScrollView {
                Text(output)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }
            .frame(maxHeight: 120)
            .background(Color(white: 0.04))
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button(action: runScript) {
                HStack(spacing: 6) {
                    Image(systemName: isRunning ? "stop.fill" : "play.fill")
                        .font(.subheadline)
                    Text(isRunning ? "Stop" : "Run")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isRunning ? Color.red.opacity(0.4) : Color.green.opacity(0.4))
                .foregroundColor(.white)
                .cornerRadius(10)
            }

            Button(action: { UIPasteboard.general.string = scriptText }) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.doc")
                        .font(.subheadline)
                    Text("Copy")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.blue.opacity(0.3))
                .foregroundColor(.white)
                .cornerRadius(10)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(white: 0.12))
    }

    private func runScript() {
        if isRunning {
            LuaEngine.shared.isRunning = false
            isRunning = false
            return
        }

        isRunning = true
        output = "Running...\n"

        LuaEngine.shared.runScript(scriptText) { actions in
            output += "Parsed \(actions.count) actions\n"
            for (i, action) in actions.enumerated() {
                output += "  [\(i + 1)] \(action.type.rawValue)"
                if let p = action.startPoint {
                    output += " at (\(Int(p.x)), \(Int(p.y)))"
                }
                output += " delay: \(String(format: "%.2f", action.delay))s\n"
            }

            if TouchSimulator.shared.canSimulateTouches {
                output += "\nRunning on device...\n"
                let player = MacroPlayer()
                player.loadActions(actions)
                player.play { _, _ in }
            } else {
                output += "\n(JB not detected -- script parsed only)\n"
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                output += "Done!\n"
                isRunning = false
            }
        }
    }

    private func loadTemplate() {
        scriptText = templateScript
        selectedScriptURL = nil
    }

    private func loadScript(from url: URL) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        scriptText = content
        selectedScriptURL = url
    }

    private func saveScript() {
        let name = scriptName.isEmpty ? "script.lua" : (scriptName.hasSuffix(".lua") ? scriptName : "\(scriptName).lua")
        try? LuaEngine.shared.saveScript(scriptText, named: name)
        scriptName = ""
        refreshScripts()
    }

    private func refreshScripts() {
        scripts = LuaEngine.shared.listScripts()
    }
}
