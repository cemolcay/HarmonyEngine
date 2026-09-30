import Foundation
import MusicTheory
import HarmonyEngine

/// A way to build a diatonic chord on a scale degree.
public enum ChordFlavor: String, Hashable, Codable, Sendable, CaseIterable {
    /// The diatonic triad.
    case triad
    /// The diatonic seventh chord when it is a dominant 7th (for example V7). Other seventh chords use `seventh`.
    case dominantSeventh
    /// The diatonic seventh chord.
    case seventh
    /// The diatonic ninth chord (avoid notes removed).
    case ninth
    /// The diatonic eleventh chord (avoid notes removed).
    case eleventh
    /// The diatonic thirteenth chord (avoid notes removed).
    case thirteenth
    /// Root, major 2nd, perfect 5th.
    case sus2
    /// Root, perfect 4th, perfect 5th.
    case sus4
    /// Root, perfect 4th, perfect 5th, minor 7th.
    case sevenSus4
    /// The diatonic triad with a major 6th.
    case six
    /// The diatonic triad with a major 9th.
    case add9
    /// The diatonic triad with a major 6th and a major 9th.
    case sixNine
    /// A dominant 7th on every degree with a major triad, also when the 7th is not in the scale
    /// (I7, IV7, V7 of the blues). It is chromatic when the 7th is outside the scale.
    case bluesSeventh
}

/// A chromatic tension added to dominant-quality chords (major 3rd and minor 7th).
/// `sharpEleventh` is also added to major 7th chords.
public enum AlterationTension: String, Hashable, Codable, Sendable, CaseIterable {
    case flatNinth
    case sharpNinth
    case sharpEleventh
    case flatThirteenth

    var component: ChordComponent {
        switch self {
        case .flatNinth:      return .flatNinth
        case .sharpNinth:     return .sharpNinth
        case .sharpEleventh:  return .sharpEleventh
        case .flatThirteenth: return .flatThirteenth
        }
    }

    /// The natural tension that this alteration replaces.
    var replaces: ChordComponent {
        switch self {
        case .flatNinth, .sharpNinth: return .ninth
        case .sharpEleventh:          return .eleventh
        case .flatThirteenth:         return .thirteenth
        }
    }
}

/// A chromatic chord device.
public enum ChromaticDevice: Hashable, Codable, Sendable {
    /// V/x.
    case appliedDominant(target: Int)
    /// vii°7/x.
    case appliedLeadingTone(target: Int)
    /// subV/x.
    case tritoneSubstitute(target: Int)
    /// ii/x, the related ii of V/x.
    case relatedSupertonic(target: Int)
    /// A degree of a parallel scale on the tonic.
    case borrowed(degree: Int, from: ScaleType)
    /// ♭II (first inversion).
    case neapolitan
    /// It+6, Fr+6, Ger+6.
    case augmentedSixth(AugmentedSixth)
    /// A °7 on the root of the current chord that returns to it.
    case commonToneDiminished
    /// I64 before V.
    case cadentialSixFour
}

/// A weighted move from one scale degree to another.
public struct DegreeTransition: Hashable, Codable, Sendable {
    public var from: Int
    public var to: Int
    public var weight: Double

    public init(from: Int, to: Int, weight: Double) {
        self.from = from
        self.to = to
        self.weight = weight
    }
}

/// A weighted chromatic device.
public struct DeviceWeight: Hashable, Codable, Sendable {
    public var device: ChromaticDevice
    public var weight: Double

    public init(_ device: ChromaticDevice, weight: Double) {
        self.device = device
        self.weight = weight
    }
}

/// The harmonic taste of a musical style, as data.
///
/// All weights are in the range 0–1. A weight of 0 turns an item off.
/// Degrees are numbered 1–7 by letter distance from the scale root (the Roman numeral), so the same profile
/// works in every key and scale.
public struct StyleProfile: Hashable, Codable, Sendable, Identifiable {
    /// A stable identifier, for example `"jazz"` or `"rAndB"`.
    public var id: String
    /// The display name.
    public var name: String
    /// Weights of the moves between degrees. Moves that are not in the list use `defaultTransitionWeight`.
    public var transitions: [DegreeTransition]
    /// The weight of a move that is not in `transitions`.
    public var defaultTransitionWeight: Double
    /// The weight of each degree as the first chord.
    public var openingWeights: [Int: Double]
    /// The weight of each chord flavor. Flavors that are not in the dictionary are off.
    public var flavors: [ChordFlavor: Double]
    /// The alterations to add to dominant-quality chords.
    public var alterations: [AlterationTension]
    /// The chromatic devices and their weights.
    public var devices: [DeviceWeight]
    /// Weights of root motion by interval class (0–6). 5 is a fourth or a fifth.
    public var rootMotionWeights: [Int: Double]
    /// How strongly the end of a phrase moves to a cadence (0–1).
    public var cadenceStrength: Double
    /// The default voicing of the style.
    public var voicing: VoicingOptions

    public init(
        id: String,
        name: String,
        transitions: [DegreeTransition],
        defaultTransitionWeight: Double = 0.08,
        openingWeights: [Int: Double] = StyleProfile.defaultOpeningWeights,
        flavors: [ChordFlavor: Double],
        alterations: [AlterationTension] = [],
        devices: [DeviceWeight] = [],
        rootMotionWeights: [Int: Double] = StyleProfile.defaultRootMotionWeights,
        cadenceStrength: Double = 1,
        voicing: VoicingOptions = VoicingOptions()
    ) {
        self.id = id
        self.name = name
        self.transitions = transitions
        self.defaultTransitionWeight = defaultTransitionWeight
        self.openingWeights = openingWeights
        self.flavors = flavors
        self.alterations = alterations
        self.devices = devices
        self.rootMotionWeights = rootMotionWeights
        self.cadenceStrength = cadenceStrength
        self.voicing = voicing
    }

    /// Opening weights that prefer the tonic.
    public static let defaultOpeningWeights: [Int: Double] = [1: 1, 2: 0.3, 3: 0.2, 4: 0.5, 5: 0.3, 6: 0.5, 7: 0.1]

    /// Root motion weights of common-practice harmony: fourths and fifths first, then steps and thirds.
    public static let defaultRootMotionWeights: [Int: Double] = [0: 0.3, 1: 0.4, 2: 0.8, 3: 0.7, 4: 0.7, 5: 1, 6: 0.3]

    /// The weight of a move between two degrees.
    public func transitionWeight(from: Int, to: Int) -> Double {
        transitions.first { $0.from == from && $0.to == to }?.weight ?? defaultTransitionWeight
    }

    /// The weight of a device, or 0 when the profile does not use it.
    public func weight(of device: ChromaticDevice) -> Double {
        devices.first { $0.device == device }?.weight ?? 0
    }
}
