import SwiftUI

struct MacroPlaybackView: View {
    let macro: MacroFile
    @StateObject private var player = MacroPlayer()
    @State private var highlightIndex: Int = -1
    @State private var showLua = false
    @State private var touchAnimating = false
    @State private var tapPosition: CGPoint?
    @State private var animationWorkItem: DispatchWorkItem?
    @Environment(\.dismiss) private var dismiss

    private var jbStatusText: String {
        if TouchSimulator.shared.canSimulateTouches {
            return "JB: real touches ON"
        } else {
            return "JB not detected · visual only"
        }
    }

    private var jbStatusColor: Color {
        TouchSimulator.shared.canSimulateTouches ? .green : .gray
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                canvasArea
                playbackControls
                actionList
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(macro.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showLua = true } label: {
                        Image(systemName: "doc.text")
                    }
                }
            }
            .sheet(isPresented: $showLua) {
                LuaPreviewView(actions: macro.actions, macroName: macro.name)
            }
            .onDisappear {
                player.stop()
                animationWorkItem?.cancel()
            }
        }
        .navigationViewStyle(.stack)
    }

    private var canvasArea: some View {
        GeometryReader { geo in
            ZStack {
                Color(white: 0.08)

                VStack(spacing: 16) {
                    if player.state == .idle {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)

                        Text("\(macro.actionCount) actions")
                            .font(.title3)
                            .foregroundColor(.white)

                        Text("\(String(format: "%.1f", macro.duration))s total")
                            .font(.subheadline)
                            .foregroundColor(.gray)

                        if macro.actionCount > 0 {
                            Text("Press play to replay this macro")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .padding(.top, 4)
                        }
                    }

                    if player.state == .playing || player.state == .paused {
                        VStack(spacing: 12) {
                            Text(player.state == .playing ? "Playing..." : "Paused")
                                .font(.headline)
                                .foregroundColor(player.state == .playing ? .green : .orange)

                            ProgressView(value: player.progress)
                                .tint(.green)
                                .padding(.horizontal, 40)

                            Text("\(player.currentActionIndex + 1) / \(macro.actionCount)")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }

                    if player.state == .completed {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.green)
                            Text("Done!")
                                .font(.title3)
                                .foregroundColor(.green)
                        }
                    }
                }

                ForEach(Array(macro.actions.enumerated()), id: \.offset) { index, action in
                    if let point = action.startPoint {
                        Circle()
                            .fill(actionDotColor(action.type, index: index))
                            .frame(width: 12, height: 12)
                            .position(scalePoint(point, to: geo.size))
                            .opacity(highlightIndex == index ? 1 : 0.3)
                            .animation(.easeInOut(duration: 0.2), value: highlightIndex)
                            .allowsHitTesting(false)
                    }

                    if action.type == .swipe, let start = action.startPoint, let end = action.endPoint {
                        Path { path in
                            path.move(to: scalePoint(start, to: geo.size))
                            path.addLine(to: scalePoint(end, to: geo.size))
                        }
                        .stroke(
                            highlightIndex == index ? Color.orange : Color.orange.opacity(0.2),
                            style: StrokeStyle(lineWidth: highlightIndex == index ? 2 : 1, dash: [6, 4])
                        )
                        .allowsHitTesting(false)
                    }
                }

                if let pos = tapPosition {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 30, height: 30)
                        .position(pos)
                        .opacity(touchAnimating ? 0.8 : 0)
                        .scaleEffect(touchAnimating ? 1.3 : 1.0)
                        .animation(.easeOut(duration: 0.2), value: touchAnimating)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private func scalePoint(_ point: CGPoint, to size: CGSize) -> CGPoint {
        let scaleX = size.width / macro.screenSize.width
        let scaleY = size.height / macro.screenSize.height
        return CGPoint(x: point.x * scaleX, y: point.y * scaleY)
    }

    private func actionDotColor(_ type: MacroActionType, index: Int) -> Color {
        if highlightIndex == index { return .yellow }
        switch type {
        case .tap: return .blue
        case .swipe: return .orange
        case .longPress: return .red
        case .keyPress: return .purple
        case .wait: return .gray
        case .scroll: return .green
        }
    }

    private var playbackControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 24) {
                Button(action: playFromStart) {
                    HStack(spacing: 8) {
                        Image(systemName: "backward.end.fill")
                        Text("Restart")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue.opacity(0.3))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }

                Button(action: togglePlayback) {
                    HStack(spacing: 8) {
                        Image(systemName: playbackIcon)
                            .font(.title3)
                        Text(playbackLabel)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(playbackBackground)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }

                Button(action: { loopPlayback() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "repeat")
                        Text("Loop")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.gray.opacity(0.2))
                    .foregroundColor(.gray)
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal, 16)

            HStack {
                Button(action: stepForward) {
                    Label("Step", systemImage: "forward.frame.fill")
                        .font(.subheadline)
                }
                .disabled(player.state != .paused)

                Spacer()

                Button(action: { showLua = true }) {
                    Label("View Lua", systemImage: "chevron.left.slash.chevron.right")
                        .font(.subheadline)
                }

                Text(jbStatusText)
                    .font(.system(size: 9))
                    .foregroundColor(jbStatusColor)
            }
            .padding(.horizontal, 16)
            .foregroundColor(.white)
        }
        .padding(.vertical, 12)
        .background(Color(white: 0.12))
    }

    private var actionList: some View {
        List {
            if macro.actions.isEmpty {
                Text("No actions recorded")
                    .foregroundColor(.gray)
                    .listRowBackground(Color(white: 0.1))
            } else {
                ForEach(Array(macro.actions.enumerated()), id: \.offset) { index, action in
                    HStack {
                        Image(systemName: actionIcon(action.type))
                            .foregroundColor(actionListDotColor(action.type))
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(actionTypeLabel(action))
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
                    .listRowBackground(
                        highlightIndex == index
                            ? Color.green.opacity(0.15)
                            : Color(white: 0.1)
                    )
                }
            }
        }
        .listStyle(.plain)
    }

    private func actionIcon(_ type: MacroActionType) -> String {
        switch type {
        case .tap: return "hand.point.up.fill"
        case .swipe: return "hand.draw.fill"
        case .longPress: return "hand.tap.fill"
        case .keyPress: return "keyboard.fill"
        case .wait: return "clock.fill"
        case .scroll: return "arrow.up.arrow.down"
        }
    }

    private func actionListDotColor(_ type: MacroActionType) -> Color {
        switch type {
        case .tap: return .blue
        case .swipe: return .orange
        case .longPress: return .red
        case .keyPress: return .purple
        case .wait: return .gray
        case .scroll: return .green
        }
    }

    private func actionTypeLabel(_ action: MacroAction) -> String {
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

    private var playbackIcon: String {
        switch player.state {
        case .idle, .completed: return "play.fill"
        case .playing: return "pause.fill"
        case .paused: return "play.fill"
        }
    }

    private var playbackLabel: String {
        switch player.state {
        case .idle, .completed: return "Play"
        case .playing: return "Pause"
        case .paused: return "Resume"
        }
    }

    private var playbackBackground: Color {
        switch player.state {
        case .idle, .completed: return .green.opacity(0.4)
        case .playing: return .orange
        case .paused: return .green
        }
    }

    private func togglePlayback() {
        switch player.state {
        case .idle, .completed:
            playFromStart()
        case .playing:
            player.pause()
        case .paused:
            player.resume()
        }
    }

    private func playFromStart() {
        highlightIndex = -1
        animationWorkItem?.cancel()
        touchAnimating = false
        player.loadActions(macro.actions)
        player.play { action, index in
            withAnimation {
                highlightIndex = index
            }
            if let point = action.startPoint {
                withAnimation {
                    tapPosition = point
                    touchAnimating = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation {
                        touchAnimating = false
                    }
                }
            }
        }
    }

    private func loopPlayback() {
        if player.state == .completed || player.state == .idle {
            playFromStart()
        }
    }

    private func stepForward() {
        guard player.currentActionIndex + 1 < macro.actions.count else { return }
        highlightIndex = player.currentActionIndex + 1
    }
}
