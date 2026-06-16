import SwiftUI
import UIKit

final class OverlayWindow: UIWindow {
    static let shared = OverlayWindow()

    private init() {
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            super.init(windowScene: scene)
        } else {
            super.init(frame: UIScreen.main.bounds)
        }
        self.windowLevel = UIWindow.Level.statusBar + 1
        self.backgroundColor = .clear
        self.isHidden = true
        self.isUserInteractionEnabled = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func show<V: View>(with view: V) {
        let controller = UIHostingController(rootView: view)
        controller.view.backgroundColor = .clear
        rootViewController = controller
        isHidden = false
    }

    func hide() {
        isHidden = true
        rootViewController = nil
    }
}

struct FloatingOverlay: View {
    @ObservedObject var recorder: TouchRecorder
    @ObservedObject var player: MacroPlayer
    var onRecord: () -> Void
    var onStop: () -> Void
    var onPlay: () -> Void
    var onDismiss: () -> Void
    var savedCount: Int
    var jbOn: Bool { TouchSimulator.shared.canSimulateTouches }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if recorder.state == .recording {
                    Text("REC \(String(format: "%.1fs", recorder.elapsedTime))")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(6)
                } else if player.state == .playing {
                    Text("PLAY \(Int(player.progress * 100))%")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(6)
                } else {
                    Text(jbOn ? "JB:ON" : "JB:OFF")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(jbOn ? .green : .gray)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(6)
                }

                Spacer()

                if recorder.state == .recording {
                    Button(action: onStop) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.red)
                    }
                } else if player.state == .playing {
                    Button(action: onStop) {
                        Image(systemName: "pause.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.orange)
                    }
                } else {
                    Button(action: onRecord) {
                        Image(systemName: "record.circle")
                            .font(.system(size: 28))
                            .foregroundColor(.red)
                    }

                    if savedCount > 0 {
                        Button(action: onPlay) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.green)
                        }
                    }
                }

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .padding(.horizontal, 12)
            .padding(.top, 4)

            Spacer()
        }
    }
}

final class OverlayManager: ObservableObject {
    static let shared = OverlayManager()

    @Published var isShowing = false

    func show(recorder: TouchRecorder, player: MacroPlayer, recordedActions: Binding<[MacroAction]>) {
        guard !isShowing else { return }
        var recActions = recordedActions.wrappedValue

        DispatchQueue.main.async {
            OverlayWindow.shared.show(with: FloatingOverlay(
                recorder: recorder,
                player: player,
                onRecord: { recorder.startRecording() },
                onStop: {
                    if recorder.state == .recording {
                        recActions = recorder.stopRecording()
                        recordedActions.wrappedValue = recActions
                    } else {
                        player.stop()
                    }
                },
                onPlay: {
                    player.loadActions(recActions)
                    player.play { _, _ in }
                },
                onDismiss: { OverlayManager.shared.hide() },
                savedCount: recActions.count
            ))
            self.isShowing = true
        }
    }

    func hide() {
        OverlayWindow.shared.hide()
        isShowing = false
    }
}
