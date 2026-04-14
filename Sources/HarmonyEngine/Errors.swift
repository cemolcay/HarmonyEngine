import Foundation

public enum HarmonyEngineError: Error, Equatable, Sendable {
    case invalidScaleDegree(Int)
    case missingChordSource
    case invalidPitchRange(minMidi: Int, maxMidi: Int)
    case voicingOutOfRange
    case unableToResolveChord
}
