import Foundation

public enum HarmonyEngineError: Error, Equatable, Sendable {
    case invalidScaleDegree(Int)
    case missingChordSource
    case invalidPitchRange(minMidi: Int, maxMidi: Int)
    case invalidProgressionStep(bar: Int, beat: Double, durationBeats: Double)
    case overlappingProgressionSteps
    case voicingOutOfRange
    case unableToResolveChord
}

