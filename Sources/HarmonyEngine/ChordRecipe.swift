import Foundation
import MusicTheory

public enum InversionPolicy: Hashable, Codable, Sendable {
    case rootPosition
    case keepClose
    case nearest
    case fixed(Int)
}

public enum TensionPolicy: Hashable, Codable, Sendable {
    case none
    case diatonicSeventh
    case diatonicExtensions(maxDegree: Int)
    case custom([Interval])
}

/// Describes harmonic intent without fixing the final voicing.
///
/// - `root`: use for absolute chords (e.g. always a G chord).
/// - `scaleDegree`: use for diatonic chords relative to the context's scale.
/// - `chordType`: when `nil`, the quality is inferred from the scale degree.
///   Only supported for heptatonic (7-note) scales. Requires `scaleDegree` to be set.
/// - `role`: optional harmonic function that biases tension and voicing defaults
///   when `tensionPolicy` is not explicitly set.
/// - `tensionPolicy`: when `nil`, the role provides the default (e.g. `.dominant` adds a
///   diatonic seventh). Pass `.none` explicitly to suppress role-based tension.
public struct ChordRecipe: Hashable, Codable, Sendable {
    public let root: NoteName?
    public let scaleDegree: Int?
    public let chordType: ChordType?
    public let role: HarmonyRole?
    public let inversionPolicy: InversionPolicy
    /// `nil` = defer to role default; `.none` = explicitly no tension.
    public let tensionPolicy: TensionPolicy?

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
