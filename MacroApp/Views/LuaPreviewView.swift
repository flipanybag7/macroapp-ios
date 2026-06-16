import SwiftUI

struct LuaPreviewView: View {
    let actions: [MacroAction]
    let macroName: String

    @State private var copied = false
    @Environment(\.dismiss) private var dismiss

    private var luaCode: String {
        let macro = MacroFile(name: macroName, actions: actions)
        return macro.luaScript
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollView {
                    Text(luaCode)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .background(Color(white: 0.06))

                VStack(spacing: 8) {
                    Text("AutoTouch-compatible Lua script")
                        .font(.caption)
                        .foregroundColor(.gray)

                    HStack(spacing: 16) {
                        Button(action: {
                            UIPasteboard.general.string = luaCode
                            copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                copied = false
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                Text(copied ? "Copied!" : "Copy")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(copied ? Color.green.opacity(0.3) : Color.blue.opacity(0.3))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }

                        Button(action: saveToFiles) {
                            HStack(spacing: 6) {
                                Image(systemName: "square.and.arrow.down")
                                Text("Save")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.green.opacity(0.3))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 12)
                .background(Color(white: 0.1))
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("\(macroName).lua")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func saveToFiles() {
        let macro = MacroFile(name: macroName, actions: actions)
        try? MacroFileStore.saveLua(macro)
    }
}
