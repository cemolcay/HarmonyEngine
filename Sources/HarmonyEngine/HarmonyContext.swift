import Foundation
import MusicTheory

public struct PitchRange: Hashable, Codable, Sendable {
    public let minMidi: Int
    public let maxMidi: Int

    public static let defaultPreferred = try! PitchRange(minMidi: 60, maxMidi: 84)
    public static let defaultBass = try! PitchRange(minMidi: 36, maxMidi: 55)

    public init(minMidi: Int, maxMidi: Int) throws {
        guard minMidi <= maxMidi else {
            throw HarmonyEngineError.invalidPitchRange(minMidi: minMidi, maxMidi: maxMidi)
        }
        self.minMidi = minMidi
        self.maxMidi = maxMidi
    }

    public func contains(_ midiNote: Int) -> Bool {
        return midiNote >= minMidi && midiNote <= maxMidi
    }

    public func distanceOutside(_ midiNote: Int) -> Int {
        if midiNote < minMidi {
            return minMidi - midiNote
        }
        if midiNote > maxMidi {
            return midiNote - maxMidi
        }
        return 0
    }

    public var midpoint: Double {
        return Double(minMidi + maxMidi) / 2.0
    }
}

public struct HarmonyContext: Hashable, Codable, Sendable {
    public let tonic: NoteName
    public let scale: Scale
    public let tempo: Tempo?
    public let preferredRegister: PitchRange
    public let bassRegister: PitchRange

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

public enum HarmonyRole: String, Codable, Hashable, Sendable {
    case tonic
    case predominant
    case dominant
    case color
    case passing
}

