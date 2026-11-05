import AVFoundation
import Foundation

/// Audio du chrono de repos.
///
/// 1. *Keep-alive* : pendant un repos, si l'app passe en arrière-plan, un flux silencieux mixé
///    (`.mixWithOthers`, n'interrompt pas la musique) garde le processus actif pour pouvoir, à 00:00,
///    déclencher l'alerte de la Live Activity (expansion de la Dynamic Island).
/// 2. *Bip de fin* : court signal sonore qui baisse temporairement la musique (`.duckOthers`)
///    au lieu de la couper.
@MainActor
final class AudioCueService {
    static let shared = AudioCueService()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var isKeepingAlive = false

    var keepAliveEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "audio.keepAlive") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "audio.keepAlive") }
    }

    var chimeEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "audio.chime") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "audio.chime") }
    }

    private init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func startKeepAlive() {
        guard keepAliveEnabled, !isKeepingAlive else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            try startEngineIfNeeded()
            player.scheduleBuffer(silence(seconds: 1), at: nil, options: .loops, completionHandler: nil)
            player.play()
            isKeepingAlive = true
        } catch {
            print("⚠️ Keep-alive audio : \(error)")
        }
    }

    func stopKeepAlive() {
        guard isKeepingAlive else { return }
        player.stop()
        engine.stop()
        isKeepingAlive = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Triple bip, musique baissée (duck) puis rétablie.
    func playRestEndChime() {
        guard chimeEnabled else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)
            try startEngineIfNeeded()
            player.stop()
            player.scheduleBuffer(chime(), at: nil, options: [], completionHandler: { @Sendable in
                Task { @MainActor in AudioCueService.shared.chimeFinished() }
            })
            player.play()
        } catch {
            print("⚠️ Bip : \(error)")
        }
    }

    private func chimeFinished() {
        player.stop()
        engine.stop()
        isKeepingAlive = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startEngineIfNeeded() throws {
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
    }

    private func silence(seconds: Double) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(format.sampleRate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames // déjà initialisé à zéro
        return buffer
    }

    private func chime() -> AVAudioPCMBuffer {
        let sampleRate = format.sampleRate
        let beep = 0.12, gap = 0.08
        let tones: [Double] = [880, 880, 1320]
        let total = Double(tones.count) * (beep + gap)
        let frames = AVAudioFrameCount(sampleRate * total)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let data = buffer.floatChannelData![0]
        for i in 0..<Int(frames) {
            let t = Double(i) / sampleRate
            let slot = Int(t / (beep + gap))
            let local = t - Double(slot) * (beep + gap)
            guard slot < tones.count, local < beep else { data[i] = 0; continue }
            let envelope = min(1, local / 0.01) * min(1, (beep - local) / 0.03)
            data[i] = Float(sin(2 * .pi * tones[slot] * t) * 0.45 * envelope)
        }
        return buffer
    }
}
