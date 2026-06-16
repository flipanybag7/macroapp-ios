import Foundation
import CoreGraphics

enum MacroActionType: String, Codable, CaseIterable {
    case tap
    case longPress
    case swipe
    case keyPress
    case wait
    case scroll
}

struct MacroAction: Identifiable, Codable, Equatable {
    let id: UUID
    let type: MacroActionType
    let startPoint: CGPoint?
    let endPoint: CGPoint?
    let duration: TimeInterval
    let delay: TimeInterval
    let key: String?
    let scrollDelta: CGFloat?

    init(
        id: UUID = UUID(),
        type: MacroActionType,
        startPoint: CGPoint? = nil,
        endPoint: CGPoint? = nil,
        duration: TimeInterval = 0,
        delay: TimeInterval = 0,
        key: String? = nil,
        scrollDelta: CGFloat? = nil
    ) {
        self.id = id
        self.type = type
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.duration = duration
        self.delay = delay
        self.key = key
        self.scrollDelta = scrollDelta
    }

    static func tap(at point: CGPoint, delay: TimeInterval = 0) -> MacroAction {
        MacroAction(type: .tap, startPoint: point, delay: delay)
    }

    static func longPress(at point: CGPoint, duration: TimeInterval, delay: TimeInterval = 0) -> MacroAction {
        MacroAction(type: .longPress, startPoint: point, duration: duration, delay: delay)
    }

    static func swipe(from start: CGPoint, to end: CGPoint, duration: TimeInterval, delay: TimeInterval = 0) -> MacroAction {
        MacroAction(type: .swipe, startPoint: start, endPoint: end, duration: duration, delay: delay)
    }

    static func keyPress(_ key: String, delay: TimeInterval = 0) -> MacroAction {
        MacroAction(type: .keyPress, delay: delay, key: key)
    }

    static func wait(_ duration: TimeInterval) -> MacroAction {
        MacroAction(type: .wait, duration: duration, delay: duration)
    }

    static func scroll(delta: CGFloat, delay: TimeInterval = 0) -> MacroAction {
        MacroAction(type: .scroll, delay: delay, scrollDelta: delta)
    }
}
