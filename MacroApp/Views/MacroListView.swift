import SwiftUI

struct MacroListView: View {
    @State private var macros: [MacroFile] = MacroFileStore.loadAll()
    @State private var selectedMacro: MacroFile?
    @State private var showPlayView = false
    @State private var showDeleteAlert = false
    @State private var macroToDelete: MacroFile?
    @State private var showLuaSheet = false
    @State private var luaMacro: MacroFile?
    @State private var showRenameAlert = false
    @State private var macroToRename: MacroFile?
    @State private var renameText = ""
    @State private var showEditSheet = false

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                if macros.isEmpty {
                    emptyState
                } else {
                    macroList
                }
            }
            .navigationTitle("Macros")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: importFromClipboard) {
                            Label("Import from clipboard", systemImage: "doc.on.clipboard")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showPlayView) {
                if let macro = selectedMacro {
                    MacroPlaybackView(macro: macro)
                }
            }
            .sheet(isPresented: $showLuaSheet) {
                if let macro = luaMacro {
                    LuaPreviewView(actions: macro.actions, macroName: macro.name)
                }
            }
            .sheet(isPresented: $showEditSheet) {
                if let macro = selectedMacro {
                    MacroEditView(macro: macro) {
                        refreshMacros()
                    }
                }
            }
            .alert("Rename Macro", isPresented: $showRenameAlert) {
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) { }
                Button("Save") {
                    if let m = macroToRename {
                        var updated = m
                        updated.name = renameText.isEmpty ? "Untitled" : renameText
                        try? MacroFileStore.save(updated)
                        refreshMacros()
                    }
                }
            } message: {
                Text("Enter a new name")
            }
            .alert("Delete Macro", isPresented: $showDeleteAlert, presenting: macroToDelete) { macro in
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteMacro(macro)
                }
            } message: { macro in
                Text("Delete '\(macro.name)'? This cannot be undone.")
            }
            .onAppear {
                refreshMacros()
            }
        }
        .navigationViewStyle(.stack)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.fill")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            Text("No macros saved yet")
                .font(.title3)
                .foregroundColor(.white)
            Text("Record a macro from the Record tab to save it here")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
    }

    private var macroList: some View {
        List {
            ForEach(macros) { macro in
                macroRow(macro)
                    .listRowBackground(Color(white: 0.1))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            macroToDelete = macro
                            showDeleteAlert = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            luaMacro = macro
                            showLuaSheet = true
                        } label: {
                            Label("Lua", systemImage: "doc.text")
                        }
                        .tint(.orange)
                        Button {
                            macroToRename = macro
                            renameText = macro.name
                            showRenameAlert = true
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
            }
        }
        .listStyle(.plain)
        .onAppear {
            UITableView.appearance().backgroundColor = .black
        }
    }

    private func macroRow(_ macro: MacroFile) -> some View {
        Button {
            selectedMacro = macro
            showPlayView = true
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(macro.name)
                            .font(.headline)
                            .foregroundColor(.white)

                        Text("\(macro.actionCount) actions · \(String(format: "%.1f", macro.duration))s")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }

                    Spacer()

                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundColor(.green)
                }

                actionTypeChips(for: macro)
            }
            .padding(.vertical, 4)
        }
        .contextMenu {
            Button {
                selectedMacro = macro
                showEditSheet = true
            } label: {
                Label("Edit Actions", systemImage: "slider.horizontal.3")
            }
            Button {
                macroToRename = macro
                renameText = macro.name
                showRenameAlert = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button {
                luaMacro = macro
                showLuaSheet = true
            } label: {
                Label("View Lua", systemImage: "doc.text")
            }
            Divider()
            Button(role: .destructive) {
                macroToDelete = macro
                showDeleteAlert = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func actionTypeChips(for macro: MacroFile) -> some View {
        let types = Array(Set(macro.actions.map { $0.type })).prefix(4)
        return HStack(spacing: 4) {
            ForEach(Array(types), id: \.self) { type in
                Text(type.rawValue)
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(chipColor(type).opacity(0.3))
                    .foregroundColor(chipColor(type))
                    .cornerRadius(4)
            }
            if macro.actions.count > 4 {
                Text("+\(macro.actions.count - 4)")
                    .font(.system(size: 9))
                    .foregroundColor(.gray)
            }
        }
    }

    private func chipColor(_ type: MacroActionType) -> Color {
        switch type {
        case .tap: return .blue
        case .swipe: return .orange
        case .longPress: return .red
        case .keyPress: return .purple
        case .wait: return .gray
        case .scroll: return .green
        }
    }

    private func deleteMacro(_ macro: MacroFile) {
        try? MacroFileStore.delete(macro)
        refreshMacros()
    }

    private func refreshMacros() {
        macros = MacroFileStore.loadAll()
    }

    private func importFromClipboard() {
        guard let text = UIPasteboard.general.string else { return }
        let actions = LuaEngine.shared.parseScript(text)
        if !actions.isEmpty {
            let macro = MacroFile(name: "Imported Macro", actions: actions)
            try? MacroFileStore.save(macro)
            refreshMacros()
        }
    }
}
