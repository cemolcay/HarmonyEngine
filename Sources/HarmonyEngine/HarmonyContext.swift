import Foundation
import MusicTheory

/// An inclusive MIDI note range used to constrain voice placement.
///
/// Used by `HarmonyContext` to define where upper voices and the bass voice
/// are allowed to be placed. All bounds are inclusive.
public struct PitchRange: Hashable, Codable, Sendable {
    /// The lowest allowed MIDI note number (inclusive).
    public let minMidi: Int
    /// The highest allowed MIDI note number (inclusive).
    public let maxMidi: Int

    /// Default upper-voice register: MIDI 60 (C4) through 84 (C6).
    public static let defaultPreferred = try! PitchRange(minMidi: 60, maxMidi: 84)
    /// Default bass register: MIDI 36 (C2) through 55 (G3).
    public static let defaultBass = try! PitchRange(minMidi: 36, maxMidi: 55)

    /// Creates a `PitchRange`.
    /// - Throws: `HarmonyEngineError.invalidPitchRange` if `minMidi > maxMidi`.
    public init(minMidi: Int, maxMidi: Int) throws {
        guard minMidi <= maxMidi else {
            throw HarmonyEngineError.invalidPitchRange(minMidi: minMidi, maxMidi: maxMidi)
        }
        self.minMidi = minMidi
        self.maxMidi = maxMidi
    }

    /// Returns `true` if `midiNote` falls within the range (inclusive).
    public func contains(_ midiNote: Int) -> Bool {
        midiNote >= minMidi && midiNote <= maxMidi
    }

    /// Returns the number of semitones by which `midiNote` falls outside the range,
    /// or `0` if it is within the range.
    public func distanceOutside(_ midiNote: Int) -> Int {
        if midiNote < minMidi { return minMidi - midiNote }
        if midiNote > maxMidi { return midiNote - maxMidi }
        return 0
    }

    /// The arithmetic midpoint of the range.
    public var midpoint: Double {
        Double(minMidi + maxMidi) / 2.0
    }
}

/// The harmonic environment shared by all engine services.
///
/// `HarmonyContext` binds together the key, scale, optional tempo, and register
/// constraints used to build and voice chords. Pass the same context through
/// `ChordBuilder`, `VoiceLeadingEngine`, and `HarmonicPalette` for consistent results.
public struct HarmonyContext: Hashable, Codable, Sendable {
    /// The tonal centre. May differ from `scale.root` in modal or borrowed-chord contexts.
    public let tonic: NoteName
    /// The active pitch collection used for degree resolution and diatonic inference.
    public let scale: Scale
    /// Optional tempo. Used by the app for timing; informational within the engine.
    public let tempo: Tempo?
    /// The MIDI register that upper voices must fall within. Defaults to MIDI 60–84.
    public let preferredRegister: PitchRange
    /// The MIDI register that the bass voice must fall within. Defaults to MIDI 36–55.
    public let bassRegister: PitchRange

    /// Creates a `HarmonyContext`.
    /// - Parameters:
    ///   - tonic: The tonal centre of the harmonic environment.
    ///   - scale: The active scale used for degree-to-note resolution.
    ///   - tempo: Optional tempo; not used internally but available to callers.
    ///   - preferredRegister: Upper-voice placement range. Defaults to MIDI 60–84.
    ///   - bassRegister: Bass-voice placement range. Defaults to MIDI 36–55.
    public init(
        tonic: NoteName,
        scale: Scale,
        tempo: Tempo? = nil,
        preferredRegister: PitchRange = .defaultPreferred,
        bassRegister: PitchRange = .defaultBass
    ) {
        self.tonic = tonic
        self.scale = scale
        self.tempo = tempo
        self.preferredRegister = preferredRegister
        self.bassRegister = bassRegister
    }
}

/// The conventional harmonic function of a chord within its key.
///
/// `HarmonyRole` acts as an intent signal rather than a strict rule.
/// `ChordBuilder` uses it to apply tension defaults when `tensionPolicy` is unset.
/// `VoiceLeadingEngine` uses it to bias inversion and register selection.
public enum HarmonyRole: String, Codable, Hashable, Sendable {
    /// Stable, home-base function. Biases toward root position in voice leading.
    case tonic
    /// Pre-dominant function (e.g. II, IV). No automatic bias applied.
    case predominant
    /// Tension-seeking function (e.g. V, VII). Adds a diatonic seventh by default;
    /// biases toward a brighter register in voice leading.
    case dominant
    /// Coloristic or non-functional chord. Adds diatonic extensions up to the 9th by default.
    case color
    /// Transitional chord. Minimises bass movement in voice leading.
    case passing
}
