import SwiftUI
import UIKit
import AVFoundation

final class OverlayWindow: UIWindow {
    static let shared: OverlayWindow = {
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            let w = OverlayWindow(windowScene: scene)
            w.windowLevel = UIWindow.Level.statusBar + 1
            w.backgroundColor = .clear
            w.isHidden = true
            w.isUserInteractionEnabled = true
            return w
        }
        let w = OverlayWindow(frame: UIScreen.main.bounds)
        w.windowLevel = UIWindow.Level.statusBar + 1
        w.backgroundColor = .clear
        w.isHidden = true
        w.isUserInteractionEnabled = true
        return w
    }()

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
    private var bgTask: UIBackgroundTaskIdentifier = .invalid
    private var audioPlayer: AVAudioPlayer?

    func show(recorder: TouchRecorder, player: MacroPlayer, recordedActions: Binding<[MacroAction]>) {
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
            self.keepAlive()
        }
    }

    func hide() {
        OverlayWindow.shared.hide()
        isShowing = false
        audioPlayer?.stop()
        if bgTask != .invalid {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
    }

    private func keepAlive() {
        // play silent audio to keep app alive
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: .mixWithOthers)
        try? session.setActive(true)
        // silent WAV: 0.1s at 44100Hz
        let sampleRate = 44100.0
        let duration = 0.1
        let numSamples = Int(sampleRate * duration)
        var bytes = Data(count: 44 + numSamples * 2)
        let header: [UInt8] = [
            0x52,0x49,0x46,0x46, // RIFF
            UInt8((36 + numSamples * 2) & 0xff),
            UInt8(((36 + numSamples * 2) >> 8) & 0xff),
            UInt8(((36 + numSamples * 2) >> 16) & 0xff),
            UInt8(((36 + numSamples * 2) >> 24) & 0xff),
            0x57,0x41,0x56,0x45, // WAVE
            0x66,0x6d,0x74,0x20, // fmt
            0x10,0x00,0x00,0x00, // chunk size 16
            0x01,0x00, // PCM
            0x02,0x00, // 2 channels
            UInt8(Int(sampleRate) & 0xff),
            UInt8((Int(sampleRate) >> 8) & 0xff),
            UInt8((Int(sampleRate) >> 16) & 0xff),
            UInt8((Int(sampleRate) >> 24) & 0xff),
            0x44,0xac,0x00,0x00, // byte rate
            0x04,0x00, // block align
            0x10,0x00, // bits per sample
            0x64,0x61,0x74,0x61, // data
            UInt8((numSamples * 2) & 0xff),
            UInt8(((numSamples * 2) >> 8) & 0xff),
            UInt8(((numSamples * 2) >> 16) & 0xff),
            UInt8(((numSamples * 2) >> 24) & 0xff),
        ]
        bytes.replaceSubrange(0..<44, with: header)
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory() + "silent.wav")
        try? bytes.write(to: tmp)
        audioPlayer = try? AVAudioPlayer(contentsOf: tmp)
        audioPlayer?.numberOfLoops = -1 // infinite loop
        audioPlayer?.volume = 0
        audioPlayer?.play()
    }
}
