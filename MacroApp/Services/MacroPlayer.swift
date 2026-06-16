import Foundation
import UIKit
import Combine

enum PlaybackState {
    case idle
    case playing
    case paused
    case completed
}

final class MacroPlayer: ObservableObject {
    @Published var state: PlaybackState = .idle
    @Published var currentActionIndex: Int = 0
    @Published var progress: Double = 0

    private var actions: [MacroAction] = []
    private var currentIndex = 0
    private var isCancelled = false
    private var onActionExecuted: ((MacroAction, Int) -> Void)?

    var totalActions: Int { actions.count }
    var isPlaying: Bool { state == .playing }
    var isPaused: Bool { state == .paused }

    func loadActions(_ actions: [MacroAction]) {
        self.actions = actions
        self.currentIndex = 0
        self.progress = 0
        self.state = .idle
    }

    func play(onActionExecuted: @escaping (MacroAction, Int) -> Void) {
        guard !actions.isEmpty else {
            state = .completed
            return
        }
        isCancelled = false
        state = .playing
        currentIndex = 0
        progress = 0
        self.onActionExecuted = onActionExecuted
        executeNextAction()
    }

    func pause() {
        guard state == .playing else { return }
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        state = .playing
        executeNextAction()
    }

    func stop() {
        isCancelled = true
        state = .idle
        currentIndex = 0
        progress = 0
        onActionExecuted = nil
    }

    private func executeNextAction() {
        guard !isCancelled, state == .playing, currentIndex < actions.count else {
            if !isCancelled {
                state = .completed
                progress = 1.0
            }
            return
        }

        let action = actions[currentIndex]
        currentActionIndex = currentIndex
        progress = Double(currentIndex) / Double(max(1, actions.count))
        onActionExecuted?(action, currentIndex)

        currentIndex += 1

        let totalDelay = action.delay + action.duration + 0.05

        DispatchQueue.main.asyncAfter(deadline: .now() + totalDelay) { [weak self] in
            self?.executeNextAction()
        }
    }

    func executeFromLua(_ script: String) -> [MacroAction] {
        return LuaEngine.shared.parseScript(script)
    }
}
