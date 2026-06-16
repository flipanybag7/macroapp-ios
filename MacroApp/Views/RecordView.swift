import SwiftUI

struct RecordView: View {
    @StateObject private var recorder = TouchRecorder()
    @StateObject private var player = MacroPlayer()
    @State private var macroName = ""
    @State private var showSaveAlert = false
    @State private var showNamePrompt = false
    @State private var recordedActions: [MacroAction] = []
    @State private var highlightActionId: UUID?
    @State private var showLuaPreview = false
    @State private var gestureActive = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                canvasView
                controlBar
                actionTimeline
            }
            .background(Color.black)

            if showNamePrompt {
                namePromptOverlay
            }
        }
        .sheet(isPresented: $showLuaPreview) {
            LuaPreviewView(actions: recordedActions, macroName: macroName)
        }
    }

    private var canvasView: some View {
        GeometryReader { geometry in
            ZStack {
                Color(white: 0.08).ignoresSafeArea()

                VStack(spacing: 16) {
                    Image(systemName: recorder.state == .recording ? "record.circle.fill" : "hand.draw.fill")
                        .font(.system(size: 48))
                        .foregroundColor(recorder.state == .recording ? .red : .gray)
                        .opacity(recorder.state == .recording ? 1 : 0.5)

                    Text(statusText)
                        .font(.title3)
                        .foregroundColor(.white)
                        .fontWeight(.medium)

                    if recorder.state == .recording {
                        Text("\(recorder.actions.count) actions recorded")
                            .font(.subheadline)
                            .foregroundColor(.gray)

                        Text(timeString(from: recorder.elapsedTime))
                            .font(.system(size: 36, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }

                    if recorder.state == .idle && !recordedActions.isEmpty {
                        Text("\(recordedActions.count) actions · \(String(format: "%.1f", totalDuration))s")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }

                    if player.state == .playing {
                        VStack(spacing: 8) {
                            ProgressView(value: player.progress)
                                .tint(.green)
                                .padding(.horizontal, 40)

                            Text("Playing action \(player.currentActionIndex + 1) of \(recordedActions.count)")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                    }

                    if player.state == .completed {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.green)
                        Text("Playback complete")
                            .font(.headline)
                            .foregroundColor(.green)
                    }
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !gestureActive {
                            gestureActive = true
                            recorder.recordTouchBegan(at: value.startLocation)
                        }
                        recorder.recordTouchMoved(to: value.location)
                    }
                    .onEnded { value in
                        gestureActive = false
                        recorder.recordTouchEnded(at: value.location)
                    }
            )

            if recorder.state == .recording {
                ForEach(recorder.actions.indices, id: \.self) { index in
                    let action = recorder.actions[index]
                    if let point = action.startPoint {
                        Circle()
                            .fill(actionColor(action.type).opacity(0.6))
                            .frame(width: 24, height: 24)
                            .overlay(
                                Text("\(index + 1)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                            )
                            .position(point)
                            .allowsHitTesting(false)
                    }
                }
            }

            if player.state == .playing || player.state == .paused {
                ForEach(Array(highlightedActions.enumerated()), id: \.offset) { index, action in
                    if let point = action.startPoint {
                        Circle()
                            .stroke(index == 0 ? Color.green : Color.white.opacity(0.3), lineWidth: index == 0 ? 3 : 1)
                            .frame(width: 30, height: 30)
                            .position(point)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    private var highlightedActions: [MacroAction] {
        guard player.currentActionIndex < recordedActions.count else { return [] }
        return [recordedActions[player.currentActionIndex]]
    }

    private func actionColor(_ type: MacroActionType) -> Color {
        switch type {
        case .tap: return .blue
        case .swipe: return .orange
        case .longPress: return .red
        case .keyPress: return .purple
        case .wait: return .gray
        case .scroll: return .green
        }
    }

    private var controlBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 24) {
                Button(action: toggleRecording) {
                    HStack(spacing: 8) {
                        Image(systemName: recorder.state == .recording ? "stop.circle.fill" : "record.circle")
                            .font(.title2)
                        Text(recorder.state == .recording ? "Stop" : "Record")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(recorder.state == .recording ? Color.red : Color.red.opacity(0.3))
                    .foregroundColor(.white)
                    .cornerRadius(14)
                }
                .disabled(player.state == .playing)

                Button(action: togglePlayback) {
                    HStack(spacing: 8) {
                        Image(systemName: playIcon)
                            .font(.title2)
                        Text(playLabel)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(playBackground)
                    .foregroundColor(.white)
                    .cornerRadius(14)
                }
                .disabled(recordedActions.isEmpty || recorder.state == .recording)
            }
            .padding(.horizontal, 16)

            HStack(spacing: 16) {
                Button(action: { showNamePrompt = true }) {
                    Label("Save", systemImage: "square.and.arrow.down")
                        .font(.subheadline)
                }
                .disabled(recordedActions.isEmpty)

                Button(action: { showLuaPreview = true }) {
                    Label("Lua", systemImage: "doc.text")
                        .font(.subheadline)
                }
                .disabled(recordedActions.isEmpty)

                Button(action: clearActions) {
                    Label("Clear", systemImage: "trash")
                        .font(.subheadline)
                }
                .disabled(recordedActions.isEmpty)

                Spacer()

                Text("\(recordedActions.count) actions")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 16)
            .foregroundColor(.white)
        }
        .padding(.vertical, 12)
        .background(Color(white: 0.12))
    }

    private var actionTimeline: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                if recordedActions.isEmpty {
                    Text("Recorded actions will appear here")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.horizontal, 16)
                } else {
                    HStack(spacing: 6) {
                        ForEach(Array(recordedActions.enumerated()), id: \.offset) { index, action in
                            actionTimelineCard(action, index: index)
                                .id(index)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
            .frame(height: 70)
            .background(Color(white: 0.06))
            .onChange(of: player.currentActionIndex) { newValue in
                withAnimation {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    private func actionTimelineCard(_ action: MacroAction, index: Int) -> some View {
        let isActive = index == player.currentActionIndex && player.state == .playing

        return VStack(spacing: 2) {
            Image(systemName: actionTypeIcon(action.type))
                .font(.system(size: 14))
            Text("\(index + 1)")
                .font(.system(size: 9))
            Text(String(format: "%.1fs", action.delay))
                .font(.system(size: 8))
                .foregroundColor(.gray)
        }
        .frame(width: 56, height: 52)
        .background(isActive ? Color.green.opacity(0.3) : Color(white: 0.18))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.green : Color.clear, lineWidth: 2)
        )
        .cornerRadius(8)
        .onTapGesture {
            highlightActionId = action.id
        }
    }

    private func actionTypeIcon(_ type: MacroActionType) -> String {
        switch type {
        case .tap: return "hand.point.up.fill"
        case .swipe: return "hand.draw.fill"
        case .longPress: return "hand.tap.fill"
        case .keyPress: return "keyboard.fill"
        case .wait: return "clock.fill"
        case .scroll: return "arrow.up.arrow.down"
        }
    }

    private var namePromptOverlay: some View {
        Color.black.opacity(0.6).ignoresSafeArea()
            .overlay(
                VStack(spacing: 16) {
                    Text("Save Macro")
                        .font(.headline)
                        .foregroundColor(.white)

                    TextField("Macro name", text: $macroName)
                        .textFieldStyle(.plain)
                        .padding()
                        .background(Color(white: 0.2))
                        .cornerRadius(10)
                        .foregroundColor(.white)

                    HStack(spacing: 16) {
                        Button("Cancel") {
                            showNamePrompt = false
                        }
                        .foregroundColor(.gray)

                        Button("Save") {
                            saveMacro()
                            showNamePrompt = false
                        }
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                    }
                }
                .padding(24)
                .background(Color(white: 0.15))
                .cornerRadius(16)
                .padding(40)
            )
            .onTapGesture { }
    }

    private var statusText: String {
        switch recorder.state {
        case .idle:
            return player.state == .playing ? "Playing..." : "Tap canvas to begin"
        case .recording:
            return "Recording..."
        case .paused:
            return "Paused"
        }
    }

    private var playIcon: String {
        switch player.state {
        case .idle, .completed: return "play.circle"
        case .playing: return "pause.circle"
        case .paused: return "play.circle.fill"
        }
    }

    private var playLabel: String {
        switch player.state {
        case .idle, .completed: return "Play"
        case .playing: return "Pause"
        case .paused: return "Resume"
        }
    }

    private var playBackground: Color {
        switch player.state {
        case .playing: return .orange
        default: return .green.opacity(0.4)
        }
    }

    private var totalDuration: TimeInterval {
        recordedActions.reduce(0) { $0 + $1.delay + $1.duration }
    }

    private func toggleRecording() {
        switch recorder.state {
        case .idle:
            recorder.startRecording()
            player.stop()
        case .recording:
            recordedActions = recorder.stopRecording()
        case .paused:
            recorder.resumeRecording()
        }
    }

    private func togglePlayback() {
        switch player.state {
        case .idle, .completed:
            player.loadActions(recordedActions)
            player.play { action, index in
                withAnimation {
                    highlightActionId = action.id
                }
            }
        case .playing:
            player.pause()
        case .paused:
            player.resume()
        }
    }

    private func clearActions() {
        recordedActions.removeAll()
        player.stop()
        player.loadActions([])
    }

    private func saveMacro() {
        let name = macroName.isEmpty ? "Untitled Macro" : macroName
        var macro = MacroFile(name: name, actions: recordedActions)
        try? MacroFileStore.save(macro)
        macroName = ""
    }

    private func timeString(from interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        let centiseconds = Int((interval - Double(Int(interval))) * 100)
        return String(format: "%02d:%02d.%02d", minutes, seconds, centiseconds)
    }
}
