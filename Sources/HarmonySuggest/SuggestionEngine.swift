import Foundation
import MusicTheory
import HarmonyEngine

/// Ranks the next chord for a style.
///
/// ## Score
/// Each candidate gets a sum of terms. The weights come from `SuggestionWeights` and the style profile:
/// - **Style**: the log of the style transition weight from the current degree (or the opening weight),
///   and the log of the flavor weight. A chromatic device uses the log of its weight, scaled by the
///   chromaticism knob, and the transition weight toward its target (half strength).
/// - **Voice leading**: fewer semitones of pitch-class movement and more common tones score higher.
/// - **Root motion**: the log of the profile root-motion weight.
/// - **Resolution**: when the current chord has an expected resolution (V/x → x, ii/x → V/x, N6 → V,
///   CT°7 → its chord, I64 → V), a chord that resolves it gets a bonus, and the others get half of it
///   as a penalty.
/// - **Cadence**: at the end of a phrase, the tonic after a dominant scores higher, and a dominant scores
///   higher on the step before. The first step prefers the tonic.
/// - **Knobs**: below 0.5 the complexity knob prefers simple chords, above 0.5 extended chords.
///   The brightness knob prefers minor chords below 0.5 and major chords above 0.5.
/// - **Repetition**: repeating the current chord, or making a back-and-forth loop (A–B–A–B), is a penalty.
///
/// The ranking is deterministic. Ties keep the generation order (degree, then flavor).
public struct SuggestionEngine: Sendable {
    public var weights: SuggestionWeights
    public var builder: ChordBuilder

    public init(weights: SuggestionWeights = SuggestionWeights(), builder: ChordBuilder = ChordBuilder()) {
        self.weights = weights
        self.builder = builder
    }

    /// Returns the ranked suggestions, best first.
    public func suggestions(for request: SuggestionRequest) -> [Suggestion] {
        let context = request.context
        let generator = CandidateGenerator(builder: builder)
        let current = request.history.last
        let currentChord = current.flatMap { try? builder.buildChord(spec: $0, context: context) }
        let currentDegree = current.flatMap { spec in currentChord.map { functionalDegree(of: spec, chord: $0, context: context) } }
        // The chord that would make a back-and-forth loop: A–B–A → B.
        let history = request.history
        var loopSounds = Set<SoundKey>()
        if history.count >= 3, history[history.count - 1] == history[history.count - 3],
           let chord = try? builder.buildChord(spec: history[history.count - 2], context: context) {
            loopSounds.insert(SoundKey(chord))
        }

        let candidates = generator.candidates(context: context, profile: request.profile, current: current, knobs: request.knobs)
        var scored = [(candidate: Candidate, score: Double, reasons: [(SuggestionReason, Double)])]()

        for candidate in candidates {
            guard let (score, reasons) = score(
                candidate,
                request: request,
                current: current,
                currentChord: currentChord,
                currentDegree: currentDegree,
                loopSounds: loopSounds
            ) else { continue }
            scored.append((candidate, score, reasons))
        }

        // Stable sort: higher score first, generation order for ties.
        let ranked = scored.enumerated().sorted { lhs, rhs in
            if lhs.element.score != rhs.element.score { return lhs.element.score > rhs.element.score }
            return lhs.offset < rhs.offset
        }.map(\.element)

        let namer = ChordNamer(builder: builder)
        var perRoot = [Int: Int]()
        var result = [Suggestion]()
        for item in ranked {
            guard result.count < request.limit else { break }
            let root = item.candidate.chord.root.pitchClass
            guard perRoot[root, default: 0] < request.maxPerRoot,
                  let name = try? namer.name(spec: item.candidate.spec, context: context) else { continue }
            perRoot[root, default: 0] += 1
            let reasons = item.reasons.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.prefix(3).map(\.0)
            result.append(Suggestion(
                spec: item.candidate.spec,
                chord: item.candidate.chord,
                name: name,
                score: item.score,
                category: item.candidate.category,
                reasons: reasons
            ))
        }
        return result
    }

    // MARK: - Score

    private func score(
        _ candidate: Candidate,
        request: SuggestionRequest,
        current: ChordSpec?,
        currentChord: Chord?,
        currentDegree: Int?,
        loopSounds: Set<SoundKey>
    ) -> (Double, [(SuggestionReason, Double)])? {
        let profile = request.profile
        let context = request.context
        let knobs = request.knobs
        let degree = functionalDegree(of: candidate.spec, chord: candidate.chord, context: context)
        var score = 0.0
        var reasons = [(SuggestionReason, Double)]()

        // A chord that resolves the current chord (V/x → x) follows the resolution, not the style table.
        let expectation = current.flatMap(expectedResolution(of:))
        let resolves = expectation?.matches(candidate.spec, degree) ?? false

        func styleWeight(to degree: Int) -> Double {
            guard let currentDegree else { return profile.openingWeights[degree] ?? 0.1 }
            return profile.transitionWeight(from: currentDegree, to: degree)
        }

        // Style.
        switch candidate.source {
        case .diatonic(let flavor), .altered(let flavor):
            let transition = resolves ? 1 : styleWeight(to: degree)
            score += weights.transition * log(max(transition, 0.01))
            score += weights.flavor * log(max(profile.flavors[flavor] ?? 0, 0.01))
            if transition >= 0.6, !resolves { reasons.append((.styleMove, transition)) }
            if case .altered = candidate.source {
                let chromatic = weights.alteration * knobs.chromaticism * 2
                guard chromatic > 0 else { return nil }
                score += weights.device * log(chromatic)
            }
        case .device(let device, let weight, let flavor):
            // Applied and other chromatic chords rarely open a progression.
            var isBorrowed = false
            if case .borrowed = device { isBorrowed = true }
            let opening = current == nil && !isBorrowed ? 0.3 : 1
            let chromatic = weight * knobs.chromaticism * 2 * opening
            guard chromatic > 0 else { return nil }
            score += weights.device * log(chromatic)
            if let flavor {
                score += weights.flavor * log(max(profile.flavors[flavor] ?? 0, 0.01))
            }
            if let target = candidate.spec.root.resolutionTarget, candidate.spec.root != .neapolitan,
               !isAugmentedSixth(candidate.spec) {
                // Approach: prefer devices whose target is a likely next move.
                let approach = styleWeight(to: target)
                score += weights.transition * 0.5 * log(max(approach, 0.01))
                if approach >= 0.6 { reasons.append((.prepares(target: target), approach)) }
            } else {
                score += weights.transition * log(max(resolves ? 1 : styleWeight(to: degree), 0.01))
            }
            if case .borrowed(_, let scaleType) = device {
                reasons.append((.borrowed(from: scaleType.description), 0.1))
            }
        }

        // Voice leading and root motion, measured on the triad cores. Otherwise larger chords would
        // score higher only because they share more notes.
        if let currentChord {
            let metrics = TransitionMetrics(from: Self.core(of: currentChord), to: Self.core(of: candidate.chord), scale: context.scale)
            score -= weights.voiceLeading * Double(metrics.voiceLeadingDistance)
            score += weights.commonTone * Double(metrics.commonTones)
            let rootMotion = profile.rootMotionWeights[metrics.rootMotionClass] ?? 0.5
            score += weights.rootMotion * log(max(rootMotion, 0.01))
            if metrics.commonTones >= 2 { reasons.append((.commonTones(metrics.commonTones), Double(metrics.commonTones) * 0.2)) }
            if metrics.voiceLeadingDistance <= 3 { reasons.append((.smoothVoiceLeading(metrics.voiceLeadingDistance), 0.3)) }
            if metrics.rootMotionClass == 5 { reasons.append((.strongRootMotion, 0.4)) }
        }

        // Resolution.
        if let expectation {
            if resolves {
                score += weights.resolution
                reasons.append((.resolves(to: expectation.degree), weights.resolution))
            } else {
                score -= weights.resolution / 2
            }
        }

        // Cadence.
        if let position = request.position {
            let isTonic = degree == 1 && isRootPositionDiatonic(candidate.spec)
            if position.isLast, isTonic {
                let afterDominant = current.map { isDominantFunction($0, context: context) } ?? false
                let bonus = profile.cadenceStrength * weights.cadence * (afterDominant ? 1 : 0.5)
                score += bonus
                reasons.append((.cadence, bonus))
            } else if position.isPenultimate, isDominantFunction(candidate.spec, context: context) {
                score += profile.cadenceStrength * weights.cadence * 0.75
            } else if position.step == 0, isTonic {
                score += profile.cadenceStrength * weights.cadence * 0.5
            }
        }

        // Knobs. At 0.5 they have no effect.
        score += weights.complexity * (Self.complexity(of: candidate.chord.type) - 0.5) * (knobs.complexity - 0.5) * 4
        score += weights.brightness * (Self.brightness(of: candidate.chord.type) - 0.5) * (knobs.brightness - 0.5) * 4

        // Repetition.
        let sound = SoundKey(candidate.chord)
        if let currentChord, SoundKey(currentChord) == sound {
            score -= weights.repetition
        } else if loopSounds.contains(sound) {
            score -= weights.recentRepetition
        }

        return (score, reasons)
    }

    // MARK: - Harmonic roles

    /// The Roman numeral degree (1–7) of a chord, by letter distance from the scale root.
    /// Applied dominant chords count as 5, the Neapolitan as 2, augmented sixths as 6, and a
    /// common-tone diminished chord as the degree it embellishes.
    func functionalDegree(of spec: ChordSpec, chord: Chord, context: HarmonyContext) -> Int {
        switch spec.root {
        case .degree, .borrowed:
            if isCadentialSixFour(spec) { return 5 }
            return context.scale.root.letter.diatonicDistance(to: chord.root.letter) + 1
        case .applied:
            return 5
        case .neapolitan:
            return 2
        case .augmentedSixth:
            return 6
        case .commonToneDiminished(let target):
            return target
        }
    }

    private struct Expectation {
        let degree: Int
        let matches: (ChordSpec, Int) -> Bool
    }

    private func expectedResolution(of spec: ChordSpec) -> Expectation? {
        if isCadentialSixFour(spec) {
            return Expectation(degree: 5) { spec, degree in degree == 5 && !self.isCadentialSixFour(spec) }
        }
        switch spec.root {
        case .applied(.supertonic, let target):
            return Expectation(degree: target) { spec, _ in
                spec.root == .applied(.dominant, of: target) || spec.root == .applied(.tritoneSubstitute, of: target)
            }
        case .applied(_, let target), .commonToneDiminished(let target):
            return Expectation(degree: target) { spec, degree in
                degree == target && self.isPlainDegree(spec)
            }
        case .neapolitan, .augmentedSixth:
            return Expectation(degree: 5) { spec, degree in degree == 5 && (self.isPlainDegree(spec) || self.isCadentialSixFour(spec)) }
        case .degree, .borrowed:
            return nil
        }
    }

    private func isPlainDegree(_ spec: ChordSpec) -> Bool {
        switch spec.root {
        case .degree, .borrowed: return !isCadentialSixFour(spec)
        default: return false
        }
    }

    private func isCadentialSixFour(_ spec: ChordSpec) -> Bool {
        spec.root == .degree(1) && spec.bass == .inversion(2)
    }

    private func isAugmentedSixth(_ spec: ChordSpec) -> Bool {
        if case .augmentedSixth = spec.root { return true }
        return false
    }

    private func isRootPositionDiatonic(_ spec: ChordSpec) -> Bool {
        spec.bass == .root && isPlainDegree(spec)
    }

    private func isDominantFunction(_ spec: ChordSpec, context: HarmonyContext) -> Bool {
        if isCadentialSixFour(spec) { return true }
        switch spec.root {
        case .applied(let function, let target):
            return target == 1 && function != .supertonic
        case .degree, .borrowed:
            guard let chord = try? builder.buildChord(spec: spec, context: context) else { return false }
            let degree = functionalDegree(of: spec, chord: chord, context: context)
            return degree == 5 || degree == 7
        default:
            return false
        }
    }

    // MARK: - Chord measures

    /// The chord with only its root, third (or suspension), and fifth.
    static func core(of chord: Chord) -> Chord {
        let coreComponents: Set<ChordComponent> = [
            .majorSecond, .minorThird, .majorThird, .perfectFourth, .diminishedFifth, .perfectFifth, .augmentedFifth,
        ]
        let components = chord.type.components.intersection(coreComponents)
        guard let type = ChordType(components: components) else { return chord }
        return Chord(type: type, root: chord.root)
    }

    /// The complexity of a chord type (0–1): 0 for triads, 0.5 for seventh chords, more for extensions
    /// and alterations.
    static func complexity(of type: ChordType) -> Double {
        let components = type.components
        let hasThird = components.contains(.minorThird) || components.contains(.majorThird)
        let hasSeventh = components.contains(.minorSeventh) || components.contains(.majorSeventh)
            || components.contains(.diminishedSeventh)
        var value = 0.0
        if !hasThird { value += 0.25 }
        if hasSeventh { value = max(value, 0.5) }
        if components.contains(.majorSixth), !hasSeventh { value += 0.35 }
        let extensions = [ChordComponent.ninth, .eleventh, .thirteenth].filter { components.contains($0) }.count
        value += hasSeventh ? Double(extensions) * 0.15 : Double(extensions) * 0.35
        let alterations = [ChordComponent.flatNinth, .sharpNinth, .sharpEleventh, .flatThirteenth].filter { components.contains($0) }.count
        value += Double(alterations) * 0.1
        return min(value, 1)
    }

    /// The brightness of a chord type (0–1): 1 for major, 0.6 for suspended or augmented, 0.3 for minor,
    /// 0 for diminished.
    static func brightness(of type: ChordType) -> Double {
        let components = type.components
        if components.contains(.minorThird) {
            return components.contains(.diminishedFifth) ? 0 : 0.3
        }
        if components.contains(.majorThird) {
            return components.contains(.augmentedFifth) ? 0.6 : 1
        }
        return 0.6
    }
}
