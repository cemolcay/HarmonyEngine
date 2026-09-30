import Foundation
import MusicTheory
import HarmonyEngine

/// User controls that change the ranking. All values are 0–1.
public struct SuggestionKnobs: Hashable, Codable, Sendable {
    /// 0 prefers triads. 0.5 uses the style weights. 1 prefers extended chords.
    public var complexity: Double
    /// 0 turns chromatic chords off. 0.5 uses the style weights. 1 doubles them.
    public var chromaticism: Double
    /// 0 prefers minor and diminished chords. 0.5 is neutral. 1 prefers major chords.
    public var brightness: Double

    public init(complexity: Double = 0.5, chromaticism: Double = 0.5, brightness: Double = 0.5) {
        self.complexity = complexity
        self.chromaticism = chromaticism
        self.brightness = brightness
    }
}

/// The position of the suggested chord in a phrase.
public struct PhrasePosition: Hashable, Codable, Sendable {
    /// The 0-based index of the suggested chord in the phrase.
    public var step: Int
    /// The number of chords in the phrase.
    public var length: Int

    public init(step: Int, length: Int) {
        self.step = step
        self.length = length
    }

    var isLast: Bool { length > 1 && step == length - 1 }
    var isPenultimate: Bool { length > 2 && step == length - 2 }
}

/// The input of `SuggestionEngine`.
public struct SuggestionRequest: Hashable, Sendable {
    /// The key and scale.
    public var context: HarmonyContext
    /// The style.
    public var profile: StyleProfile
    /// The chords so far, oldest first. The last one is the current chord.
    public var history: [ChordSpec]
    /// The position of the suggested chord in the phrase, if known.
    public var position: PhrasePosition?
    /// The user controls.
    public var knobs: SuggestionKnobs
    /// The maximum number of suggestions.
    public var limit: Int
    /// The maximum number of suggestions on the same root. It keeps the list varied.
    public var maxPerRoot: Int

    public init(
        context: HarmonyContext,
        profile: StyleProfile,
        history: [ChordSpec] = [],
        position: PhrasePosition? = nil,
        knobs: SuggestionKnobs = SuggestionKnobs(),
        limit: Int = 24,
        maxPerRoot: Int = 4
    ) {
        self.context = context
        self.profile = profile
        self.history = history
        self.position = position
        self.knobs = knobs
        self.limit = limit
        self.maxPerRoot = maxPerRoot
    }
}

/// How a suggestion relates to the key.
public enum SuggestionCategory: String, Hashable, Codable, Sendable, CaseIterable {
    /// A diatonic triad or seventh chord.
    case diatonic
    /// A diatonic chord with extensions, a suspension, or added tones.
    case color
    /// A chord with notes outside the scale.
    case chromatic
}

/// Why a suggestion got a high score.
public enum SuggestionReason: Hashable, Sendable {
    /// It resolves the previous chord to its expected target degree.
    case resolves(to: Int)
    /// It prepares the next chord (for example ii/x before V/x, or V/x before x).
    case prepares(target: Int)
    /// It completes a cadence at the end of the phrase.
    case cadence
    /// It is a common move of the style.
    case styleMove
    /// It shares this many notes with the previous chord.
    case commonTones(Int)
    /// The voices move this many semitones in total (pitch-class distance).
    case smoothVoiceLeading(Int)
    /// The root moves by a fourth or a fifth.
    case strongRootMotion
    /// It is borrowed from a parallel scale.
    case borrowed(from: String)
}

/// A ranked chord suggestion.
public struct Suggestion: Hashable, Sendable {
    /// The chord, relative to the context.
    public let spec: ChordSpec
    /// The resolved chord.
    public let chord: Chord
    /// The Roman numeral and the chord symbol.
    public let name: ChordName
    /// The score. Higher is better. Only the order is meaningful.
    public let score: Double
    /// How the chord relates to the key.
    public let category: SuggestionCategory
    /// The main reasons for the score, strongest first.
    public let reasons: [SuggestionReason]
}

/// The weights of the score terms. The defaults work for all profiles.
public struct SuggestionWeights: Hashable, Codable, Sendable {
    /// Multiplies the log of the style transition weight.
    public var transition: Double = 2
    /// Multiplies the log of the flavor weight.
    public var flavor: Double = 1
    /// Multiplies the log of the device weight.
    public var device: Double = 1
    /// Multiplies the log of the root motion weight.
    public var rootMotion: Double = 1
    /// Subtracted for each semitone of pitch-class voice movement.
    public var voiceLeading: Double = 0.15
    /// Added for each common tone.
    public var commonTone: Double = 0.3
    /// Added when the chord resolves the previous chord. Subtracted (half) when it does not.
    public var resolution: Double = 3
    /// Multiplies the cadence bonus of the profile.
    public var cadence: Double = 2
    /// Multiplies the complexity preference.
    public var complexity: Double = 2
    /// The weight of a chromatic alteration (♭9, ♯9, ♯11, ♭13), before the chromaticism knob.
    public var alteration: Double = 0.3
    /// Multiplies the brightness preference.
    public var brightness: Double = 1
    /// Subtracted when the chord repeats the previous chord.
    public var repetition: Double = 2
    /// Subtracted when the chord makes a back-and-forth loop (A–B–A–B).
    public var recentRepetition: Double = 1.2

    public init() {}
}
