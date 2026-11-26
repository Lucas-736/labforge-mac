import AppKit

/// Subtle native macOS system chimes for check-in / check-out.
///
/// Sounds are looked up with `NSSound(named:)`; a name missing on a given macOS version simply
/// plays nothing. Each sound is copied once so the shared system instance is never mutated.
@MainActor
final class SoundService {
    static let defaultVolume: Float = 0.45

    private var cache: [String: NSSound] = [:]

    func play(_ name: String, volume: Float = SoundService.defaultVolume) {
        guard let sound = sound(named: name) else { return }
        if sound.isPlaying { sound.stop() }
        sound.currentTime = 0
        sound.volume = volume
        sound.play()
    }

    private func sound(named name: String) -> NSSound? {
        if let cached = cache[name] { return cached }
        guard let system = NSSound(named: NSSound.Name(name)) else { return nil }
        let sound = (system.copy() as? NSSound) ?? system
        cache[name] = sound
        return sound
    }
}
