import Foundation
import UIKit
import Combine

enum RecordingState {
    case idle
    case recording
    case paused
}

final class TouchRecorder: ObservableObject {
    @Published var state: RecordingState = .idle
    @Published var actions: [MacroAction] = []
    @Published var elapsedTime: TimeInterval = 0

    private var startTime: Date?
    private var lastActionTime: Date?
    private var touchStartTime: Date?
    private var touchStartPoint: CGPoint?
    private var touchMoved = false
    private var timer: Timer?
    private var longPressTimer: Timer?
    private var longPressTriggered = false

    func startRecording() {
        actions.removeAll()
        state = .recording
        startTime = Date()
        lastActionTime = Date()
        longPressTriggered = false
        startElapsedTimer()
    }

    func stopRecording() -> [MacroAction] {
        state = .idle
        timer?.invalidate()
        timer = nil
        longPressTimer?.invalidate()
        longPressTimer = nil
        return actions
    }

    func pauseRecording() {
        state = .paused
        timer?.invalidate()
        longPressTimer?.invalidate()
    }

    func resumeRecording() {
        state = .recording
        startElapsedTimer()
    }

    func recordTouchBegan(at point: CGPoint) {
        guard state == .recording else { return }
        touchStartTime = Date()
        touchStartPoint = point
        touchMoved = false
        longPressTriggered = false

        longPressTimer?.invalidate()
        longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            guard let self = self, self.state == .recording else { return }
            self.longPressTriggered = true
        }
    }

    func recordTouchMoved(to point: CGPoint) {
        guard state == .recording, let start = touchStartPoint else { return }
        let dx = abs(point.x - start.x)
        let dy = abs(point.y - start.y)
        if dx > 10 || dy > 10 {
            touchMoved = true
            longPressTimer?.invalidate()
            longPressTimer = nil
        }
    }

    func recordTouchEnded(at point: CGPoint) {
        guard state == .recording, let start = touchStartPoint else { return }
        longPressTimer?.invalidate()
        longPressTimer = nil

        let delay = delaySinceLastAction()
        lastActionTime = Date()

        if longPressTriggered {
            let duration = Date().timeIntervalSince(touchStartTime ?? Date())
            let action = MacroAction.longPress(at: start, duration: duration, delay: delay)
            actions.append(action)
        } else if touchMoved {
            let duration = Date().timeIntervalSince(touchStartTime ?? Date())
            let action = MacroAction.swipe(from: start, to: point, duration: duration, delay: delay)
            actions.append(action)
        } else {
            let action = MacroAction.tap(at: point, delay: delay)
            actions.append(action)
        }

        touchStartPoint = nil
        touchStartTime = nil
        longPressTriggered = false
    }

    func recordScroll(delta: CGFloat) {
        guard state == .recording else { return }
        let delay = delaySinceLastAction()
        lastActionTime = Date()
        let action = MacroAction.scroll(delta: delta, delay: delay)
        actions.append(action)
    }

    func recordKeyPress(key: String) {
        guard state == .recording else { return }
        let delay = delaySinceLastAction()
        lastActionTime = Date()
        let action = MacroAction.keyPress(key, delay: delay)
        actions.append(action)
    }

    func addManualAction(_ action: MacroAction) {
        let delay = delaySinceLastAction()
        var actionWithDelay = action
        actionWithDelay = MacroAction(
            id: action.id,
            type: action.type,
            startPoint: action.startPoint,
            endPoint: action.endPoint,
            duration: action.duration,
            delay: delay,
            key: action.key,
            scrollDelta: action.scrollDelta
        )
        actions.append(actionWithDelay)
        lastActionTime = Date()
    }

    private func delaySinceLastAction() -> TimeInterval {
        guard let last = lastActionTime else {
            lastActionTime = Date()
            return 0
        }
        let delay = Date().timeIntervalSince(last)
        return max(0, round(delay * 1000) / 1000)
    }

    private func startElapsedTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let start = self.startTime else { return }
            self.elapsedTime = Date().timeIntervalSince(start)
        }
    }
}
