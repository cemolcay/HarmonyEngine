import Foundation
import MusicTheory

/// Controls which inversion of a chord the voice-leading engine selects.
public enum InversionPolicy: Hashable, Codable, Sendable {
    /// Always use root position (inversion 0).
    case rootPosition
    /// Prefer the lowest inversion that places all voices within the preferred register cleanly.
    case keepClose
    /// Choose the inversion that minimises total semitone movement from the previous `VoicedChord`.
    /// Falls back to the lowest inversion when there is no previous chord.
    case nearest
    /// Force a specific inversion index.
    case fixed(Int)
}

/// Controls which tensions are added on top of the base chord type.
public enum TensionPolicy: Hashable, Codable, Sendable {
    /// No tension — use the chord type exactly as given.
    case none
    /// Add the diatonic seventh derived from the context's scale.
    case diatonicSeventh
    /// Stack diatonic thirds up to the given scale degree (7, 9, 11, or 13).
    case diatonicExtensions(maxDegree: Int)
    /// Merge a specific set of intervals into the chord type.
    case custom([Interval])
}

/// Describes harmonic intent without fixing the final voicing.
///
/// A `ChordRecipe` is the primary input to `ChordBuilder`. It separates *what chord to use*
/// from *how to voice it* — voicing is handled later by `VoiceLeadingEngine`.
///
/// ## Source precedence
/// Provide either `root` (absolute) or `scaleDegree` (diatonic). `root` takes priority if both
/// are set.
///
/// ## Chord type inference
/// When `chordType` is `nil`, `ChordBuilder` infers the diatonic quality from the scale degree.
/// This requires a heptatonic (7-note) scale and a `scaleDegree`.
///
/// ## Tension precedence
/// An explicit `tensionPolicy` always wins. Pass `TensionPolicy.none` to suppress any
/// role-based tension default. Leave `tensionPolicy` as `nil` to let the `role` decide.
public struct ChordRecipe: Hashable, Codable, Sendable {
    /// Absolute root note. Takes priority over `scaleDegree` when resolving the root.
    public let root: NoteName?
    /// Scale degree (1-based). Used to derive the root from the context's scale and,
    /// when `chordType` is `nil`, to infer the diatonic chord quality.
    public let scaleDegree: Int?
    /// The chord quality to use. When `nil`, the quality is inferred from the scale degree.
    /// Inference requires a heptatonic scale and a non-nil `scaleDegree`.
    public let chordType: ChordType?
    /// The harmonic function of this chord. Provides defaults for `tensionPolicy`
    /// and voicing bias when those are not set explicitly.
    public let role: HarmonyRole?
    /// How the voice-leading engine selects an inversion. Defaults to `.nearest`.
    public let inversionPolicy: InversionPolicy
    /// The tension to apply after resolving the base chord type.
    /// - `nil`: defer to the `role` default (e.g. `.dominant` adds a diatonic seventh).
    /// - `TensionPolicy.none`: explicitly suppress all tension, even when a role is set.
    public let tensionPolicy: TensionPolicy?

    /// Creates a `ChordRecipe`.
    /// - Parameters:
    ///   - root: Absolute root note. Mutually exclusive with `scaleDegree` for root resolution;
    ///     `root` takes priority when both are provided.
    ///   - scaleDegree: 1-based scale degree. Used for diatonic root and chord-type resolution.
    ///   - chordType: Explicit chord quality. Pass `nil` to infer from the scale degree.
    ///   - role: Harmonic function. Provides tension and voicing defaults.
    ///   - inversionPolicy: Inversion selection strategy. Defaults to `.nearest`.
    ///   - tensionPolicy: Tension to apply. `nil` defers to the role; `TensionPolicy.none`
    ///     suppresses tension regardless of role.
    public init(
        root: NoteName? = nil,
        scaleDegree: Int? = nil,
        chordType: ChordType? = nil,
        role: HarmonyRole? = nil,
        inversionPolicy: InversionPolicy = .nearest,
        tensionPolicy: TensionPolicy? = nil
    ) {
        self.root = root
        self.scaleDegree = scaleDegree
        self.chordType = chordType
        self.role = role
        self.inversionPolicy = inversionPolicy
        self.tensionPolicy = tensionPolicy
    }
}
