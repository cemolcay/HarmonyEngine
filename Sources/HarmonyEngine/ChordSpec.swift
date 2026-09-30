import Foundation
import MusicTheory

/// A secondary function that points at a target scale degree.
public enum AppliedFunction: String, Hashable, Codable, Sendable {
    /// Secondary dominant (V/x). The root is a perfect fifth above the target. Default type: dominant 7th.
    case dominant
    /// Secondary leading-tone chord (vii°/x). The root is a minor second below the target. Default type: diminished 7th.
    case leadingTone
    /// Tritone substitute of the secondary dominant (subV/x). The root is a minor second above the target.
    /// Default type: dominant 7th.
    case tritoneSubstitute
    /// Related ii of the secondary dominant (ii/x). The root is a major second above the target.
    /// Default type: minor 7th.
    case supertonic
}

/// The three common augmented sixth chords. Each one is built on the lowered sixth degree
/// and resolves to the dominant.
public enum AugmentedSixth: String, Hashable, Codable, Sendable {
    /// ♭6, 1, ♯4.
    case italian
    /// ♭6, 1, 2, ♯4.
    case french
    /// ♭6, 1, ♭3, ♯4.
    case german
}

/// Tells where the root of a `ChordSpec` comes from.
///
/// All cases are relative to the `HarmonyContext`, so a spec transposes with the key and scale.
public enum ChordRoot: Hashable, Codable, Sendable {
    /// A degree of the context scale (1-based), with an optional chromatic alteration in semitones.
    /// For example, `.degree(7, alteration: -1)` is ♭VII in a major key.
    case degree(Int, alteration: Int = 0)
    /// A degree (1-based) of a parallel scale on the context tonic (modal mixture).
    /// For example, `.borrowed(degree: 6, from: .minor)` is ♭VI in a major key.
    case borrowed(degree: Int, from: ScaleType)
    /// A secondary chord that points at a degree of the context scale. For example,
    /// `.applied(.dominant, of: 2)` is V/ii.
    case applied(AppliedFunction, of: Int)
    /// The Neapolitan chord: a major triad on the lowered second degree.
    case neapolitan
    /// An augmented sixth chord on the lowered sixth degree.
    case augmentedSixth(AugmentedSixth)
    /// A common-tone diminished seventh chord that embellishes the chord on the target degree.
    /// It shares its root with the target.
    case commonToneDiminished(of: Int)

    /// The scale degree that this chord normally resolves to, or `nil` if it has no expected resolution.
    public var resolutionTarget: Int? {
        switch self {
        case .degree, .borrowed:
            return nil
        case .applied(_, let target):
            return target
        case .neapolitan, .augmentedSixth:
            return 5
        case .commonToneDiminished(let target):
            return target
        }
    }

    /// Returns `true` when the root is a plain degree of the context scale with no alteration.
    public var isDiatonic: Bool {
        if case .degree(_, let alteration) = self { return alteration == 0 }
        return false
    }
}

/// Tells which note goes in the bass.
public enum ChordBass: Hashable, Codable, Sendable {
    /// The chord root.
    case root
    /// A chord tone. `0` is the root, `1` is the next chord tone, and so on.
    case inversion(Int)
    /// A degree of the context scale (1-based). Use it for slash chords and pedal points.
    case scaleDegree(Int)
}

/// Describes a chord relative to a `HarmonyContext`, including chromatic chords.
///
/// `ChordRecipe` can only express an absolute root or a diatonic degree. `ChordSpec` can also express
/// altered degrees (♭VII), borrowed chords, applied chords (V/x, vii°/x, subV/x, ii/x),
/// the Neapolitan, augmented sixths, and common-tone diminished chords.
///
/// Use `ChordBuilder.buildChord(spec:context:)` to resolve it, and `ChordNamer` to name it.
public struct ChordSpec: Hashable, Codable, Sendable {
    /// Where the root comes from.
    public var root: ChordRoot
    /// The chord quality. When `nil`, the builder uses the default type of the root:
    /// - `.degree` with no alteration and `.borrowed`: the diatonic triad of the source scale.
    /// - `.applied`, `.neapolitan`, `.augmentedSixth`, `.commonToneDiminished`: the type of that device.
    /// - `.degree` with an alteration: no default. The builder throws `missingChordType`.
    public var type: ChordType?
    /// The tension to add. Diatonic policies stack thirds from the source scale, so they apply only to
    /// `.degree` roots with no alteration and to `.borrowed` roots.
    public var tension: TensionPolicy
    /// The bass note.
    public var bass: ChordBass

    public init(
        root: ChordRoot,
        type: ChordType? = nil,
        tension: TensionPolicy = .none,
        bass: ChordBass = .root
    ) {
        self.root = root
        self.type = type
        self.tension = tension
        self.bass = bass
    }

    /// A diatonic chord on a degree of the context scale.
    public static func degree(_ degree: Int, type: ChordType? = nil, tension: TensionPolicy = .none) -> ChordSpec {
        ChordSpec(root: .degree(degree), type: type, tension: tension)
    }
}
