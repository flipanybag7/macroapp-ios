import SwiftUI

struct MacroEditView: View {
    let macro: MacroFile
    let onSave: () -> Void

    @State private var actions: [MacroAction]
    @State private var name: String
    @State private var showAddAction = false
    @Environment(\.dismiss) private var dismiss

    init(macro: MacroFile, onSave: @escaping () -> Void) {
        self.macro = macro
        self.onSave = onSave
        _name = State(initialValue: macro.name)
        _actions = State(initialValue: macro.actions)
    }

    var body: some View {
        NavigationView {
            List {
                ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                    HStack {
                        Image(systemName: icon(action.type))
                            .foregroundColor(color(action.type))
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(label(action))
                                .font(.subheadline)
                                .foregroundColor(.white)
                            Text(String(format: "Delay: %.2fs", action.delay))
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        Text("#\(index + 1)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .listRowBackground(Color(white: 0.1))
                }
                .onDelete { indexSet in
                    actions.remove(atOffsets: indexSet)
                }
            }
            .listStyle(.plain)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Edit \(name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Button(action: { showAddAction = true }) {
                            Image(systemName: "plus")
                        }
                        Button(action: save) {
                            Text("Save")
                                .font(.headline)
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddAction) {
                AddActionView { action in
                    actions.append(action)
                    showAddAction = false
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func save() {
        var updated = macro
        updated.name = name
        updated.actions = actions
        try? MacroFileStore.save(updated)
        onSave()
        dismiss()
    }

    private func icon(_ type: MacroActionType) -> String {
        switch type {
        case .tap: return "hand.point.up.fill"
        case .swipe: return "hand.draw.fill"
        case .longPress: return "hand.tap.fill"
        case .keyPress: return "keyboard.fill"
        case .wait: return "clock.fill"
        case .scroll: return "arrow.up.arrow.down"
        }
    }

    private func color(_ type: MacroActionType) -> Color {
        switch type {
        case .tap: return .blue
        case .swipe: return .orange
        case .longPress: return .red
        case .keyPress: return .purple
        case .wait: return .gray
        case .scroll: return .green
        }
    }

    private func label(_ action: MacroAction) -> String {
        switch action.type {
        case .tap:
            if let p = action.startPoint { return "Tap at (\(Int(p.x)), \(Int(p.y)))" }
            return "Tap"
        case .swipe:
            if let s = action.startPoint, let e = action.endPoint {
                return "Swipe (\(Int(s.x)),\(Int(s.y))) -> (\(Int(e.x)),\(Int(e.y)))"
            }
            return "Swipe"
        case .longPress:
            if let p = action.startPoint { return "Long press at (\(Int(p.x)), \(Int(p.y))) for \(String(format: "%.1f", action.duration))s" }
            return "Long press"
        case .keyPress:
            return "Key: \(action.key ?? "?")"
        case .wait:
            return "Wait \(String(format: "%.1f", action.duration))s"
        case .scroll:
            return "Scroll \(Int(action.scrollDelta ?? 0))"
        }
    }
}

struct AddActionView: View {
    let onAdd: (MacroAction) -> Void

    @State private var selectedType: MacroActionType = .tap
    @State private var xText = "200"
    @State private var yText = "400"
    @State private var x2Text = "200"
    @State private var y2Text = "100"
    @State private var durationText = "0.5"
    @State private var delayText = "0.5"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Picker("Type", selection: $selectedType) {
                    ForEach(MacroActionType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.menu)

                switch selectedType {
                case .tap, .longPress:
                    HStack { Text("X"); TextField("200", text: $xText).keyboardType(.numberPad) }
                    HStack { Text("Y"); TextField("400", text: $yText).keyboardType(.numberPad) }
                    if selectedType == .longPress {
                        HStack { Text("Duration"); TextField("1.0", text: $durationText).keyboardType(.decimalPad) }
                    }
                case .swipe:
                    HStack { Text("Start X"); TextField("200", text: $xText).keyboardType(.numberPad) }
                    HStack { Text("Start Y"); TextField("600", text: $yText).keyboardType(.numberPad) }
                    HStack { Text("End X"); TextField("200", text: $x2Text).keyboardType(.numberPad) }
                    HStack { Text("End Y"); TextField("100", text: $y2Text).keyboardType(.numberPad) }
                    HStack { Text("Duration"); TextField("0.5", text: $durationText).keyboardType(.decimalPad) }
                case .wait:
                    HStack { Text("Duration"); TextField("1.0", text: $durationText).keyboardType(.decimalPad) }
                case .scroll:
                    HStack { Text("Delta (negative=up)"); TextField("-200", text: $xText).keyboardType(.numberPad) }
                case .keyPress:
                    HStack { Text("Key"); TextField("a", text: $xText) }
                }

                HStack { Text("Delay before"); TextField("0.5", text: $delayText).keyboardType(.decimalPad) }
            }
            .navigationTitle("Add Action")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        let action = buildAction()
                        onAdd(action)
                        dismiss()
                    }
                }
            }
        }
    }

    private func buildAction() -> MacroAction {
        let x = Double(xText) ?? 200
        let y = Double(yText) ?? 400
        let x2 = Double(x2Text) ?? 200
        let y2 = Double(y2Text) ?? 100
        let dur = Double(durationText) ?? 0.5
        let del = Double(delayText) ?? 0.5

        switch selectedType {
        case .tap:
            return .tap(at: CGPoint(x: x, y: y), delay: del)
        case .swipe:
            return .swipe(from: CGPoint(x: x, y: y), to: CGPoint(x: x2, y: y2), duration: dur, delay: del)
        case .longPress:
            return .longPress(at: CGPoint(x: x, y: y), duration: dur, delay: del)
        case .wait:
            return .wait(dur)
        case .scroll:
            return .scroll(delta: CGFloat(x), delay: del)
        case .keyPress:
            return .keyPress(xText.isEmpty ? "a" : xText, delay: del)
        }
    }
}
