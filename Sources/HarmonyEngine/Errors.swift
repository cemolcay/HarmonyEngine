import Foundation

/// Errors thrown by `HarmonyEngine` services.
///
/// No silent fallbacks are used — every failure to resolve harmonic intent surfaces as one of
/// these cases so the caller can handle it explicitly.
public enum HarmonyEngineError: Error, Equatable, Sendable {
    /// The requested scale degree is outside the valid range for the scale (1…N).
    case invalidScaleDegree(Int)
    /// A `ChordRecipe` was provided with neither a `root` nor a `scaleDegree`.
    case missingChordSource
    /// A `PitchRange` was constructed with `minMidi > maxMidi`.
    case invalidPitchRange(minMidi: Int, maxMidi: Int)
    /// No candidate voicing could be placed within the context's register constraints.
    case voicingOutOfRange
    /// The chord type could not be inferred or rebuilt from the given intervals.
    case unableToResolveChord
}
