import Foundation
import MusicTheory
import HarmonyEngine

/// Generates whole progressions with a seeded beam search over `SuggestionEngine` rankings.
///
/// At each step, every kept progression is extended with its best suggestions (with the phrase position,
/// so the end moves to a cadence). A small seeded random value is added to each score for variety.
/// The same seed always gives the same progression.
public struct ProgressionGenerator: Sendable {
    public var engine: SuggestionEngine

    public init(engine: SuggestionEngine = SuggestionEngine()) {
        self.engine = engine
    }

    /// Generates a progression.
    ///
    /// - Parameters:
    ///   - length: The number of chords, including `start`.
    ///   - context: The key and scale.
    ///   - profile: The style.
    ///   - knobs: The user controls.
    ///   - seed: The random seed.
    ///   - start: Chords to begin with. They are part of the result.
    ///   - beamWidth: The number of progressions kept at each step, and the number of suggestions tried
    ///     for each one.
    ///   - temperature: The size of the random value added to each score (0 gives the best progression).
    /// - Returns: The chords of the progression. When the style ends phrases on a cadence
    ///   (`cadenceStrength` ≥ 0.5), the last chord is a root-position tonic chord when one is suggested.
    public func generate(
        length: Int,
        context: HarmonyContext,
        profile: StyleProfile,
        knobs: SuggestionKnobs = SuggestionKnobs(),
        seed: UInt64,
        start: [ChordSpec] = [],
        beamWidth: Int = 6,
        temperature: Double = 1
    ) -> [ChordSpec] {
        guard length > start.count else { return Array(start.prefix(max(length, 0))) }

        struct Beam {
            var specs: [ChordSpec]
            var score: Double
            var endsOnTonic: Bool
        }

        var random = SplitMix64(seed: seed)
        var beams = [Beam(specs: start, score: 0, endsOnTonic: false)]
        let endsOnCadence = profile.cadenceStrength >= 0.5

        for step in start.count..<length {
            var expanded = [Beam]()
            for beam in beams {
                let request = SuggestionRequest(
                    context: context,
                    profile: profile,
                    history: beam.specs,
                    position: PhrasePosition(step: step, length: length),
                    knobs: knobs,
                    limit: beamWidth,
                    maxPerRoot: 2
                )
                var suggestions = engine.suggestions(for: request)
                if endsOnCadence, step == length - 1 {
                    // The last step: ask for all suggestions, and keep the tonic chords.
                    var all = request
                    all.limit = .max
                    all.maxPerRoot = .max
                    let tonics = engine.suggestions(for: all).filter(Self.isTonic)
                    if !tonics.isEmpty { suggestions = Array(tonics.prefix(beamWidth)) }
                }
                for suggestion in suggestions {
                    let noise = random.nextUnitDouble() * temperature
                    let isTonic = Self.isTonic(suggestion)
                    expanded.append(Beam(
                        specs: beam.specs + [suggestion.spec],
                        score: beam.score + suggestion.score + noise,
                        endsOnTonic: isTonic
                    ))
                }
            }
            guard !expanded.isEmpty else { break }
            // Stable order for equal scores keeps the result deterministic.
            beams = Array(expanded.enumerated().sorted { lhs, rhs in
                if lhs.element.score != rhs.element.score { return lhs.element.score > rhs.element.score }
                return lhs.offset < rhs.offset
            }.map(\.element).prefix(beamWidth))
        }

        let cadential = endsOnCadence ? beams.first(where: \.endsOnTonic) : nil
        return (cadential ?? beams.first)?.specs ?? start
    }

    private static func isTonic(_ suggestion: Suggestion) -> Bool {
        guard case .degree(1, 0) = suggestion.spec.root else { return false }
        return suggestion.spec.bass == .root
    }
}

/// A small seeded random number generator (SplitMix64).
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A value in 0..<1.
    mutating func nextUnitDouble() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}
