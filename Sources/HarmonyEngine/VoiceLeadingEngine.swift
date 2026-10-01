import Foundation
import MusicTheory

// MARK: - VoicingConstraints

/// Hard upper bounds on voice movement applied before candidate scoring.
///
/// Constraints are "best effort": if no candidate survives filtering, the engine
/// falls back to the unconstrained pool rather than throwing. This avoids hard
/// failures when a style profile sets tight limits that can't always be satisfied.
public struct VoicingConstraints: Hashable, Codable, Sendable {
    /// Maximum allowed semitone leap for the top upper voice between consecutive chords.
    /// `nil` means unconstrained.
    public var maxTopNoteLeap: Int?
    /// Maximum allowed semitone leap for the bass voice between consecutive chords.
    /// `nil` means unconstrained.
    public var maxBassLeap: Int?

    public init(maxTopNoteLeap: Int? = nil, maxBassLeap: Int? = nil) {
        self.maxTopNoteLeap = maxTopNoteLeap
        self.maxBassLeap = maxBassLeap
    }
}

// MARK: - VoicingOptions

/// The shape of the upper voices.
public enum VoicingStyle: String, Hashable, Codable, Sendable, CaseIterable {
    /// Chord tones stacked in chord-tone order, each one above the previous one.
    case close
    /// Close voicing with the second voice from the top one octave lower.
    case drop2
    /// Close voicing with the third voice from the top one octave lower. Needs 4 voices.
    case drop3
    /// Close voicing with the second and fourth voices from the top one octave lower. Needs 4 voices.
    case drop2and4
    /// Open voicing: every second voice from the bottom goes one octave higher.
    case spread
    /// Only the third (or suspension) and the seventh (or sixth). The bass plays the root.
    case shell
    /// Close voicing without the root. The bass plays the root.
    case rootless
}

/// Tells which note the bass voice plays.
public enum BassMode: String, Hashable, Codable, Sendable {
    /// The slash bass of the chord, or else the chord tone of its inversion.
    case chordBass
    /// Always the chord root, also when the upper voices are inverted.
    case root
}

/// Settings of `VoiceLeadingEngine`.
///
/// The defaults give the same result as the first engine version: close voicing, the bass follows the
/// inversion, and the bass pitch class is also in the upper voices.
public struct VoicingOptions: Hashable, Codable, Sendable {
    /// The shape of the upper voices.
    public var style: VoicingStyle
    /// The maximum number of upper voices. When a chord has more tones, the engine removes them in this
    /// order: the perfect 5th, the root, the 11th, the 9th. It always keeps at least 2 voices.
    public var maxVoices: Int?
    /// Which note the bass plays. `.shell` and `.rootless` voicings are usually used with `.root`.
    public var bassMode: BassMode
    /// When `false`, the upper voices do not play the bass pitch class (if 2 or more voices stay).
    public var doublesBassInUpperVoices: Bool
    /// A MIDI note that the top voice moves toward. Each semitone of distance adds 1 to the score.
    public var topVoiceTarget: Int?
    /// How strongly the voicing moves toward the middle of the preferred register.
    /// Each semitone between the average upper voice and the middle adds this value to the score.
    public var registerCenterWeight: Double

    public init(
        style: VoicingStyle = .close,
        maxVoices: Int? = nil,
        bassMode: BassMode = .chordBass,
        doublesBassInUpperVoices: Bool = true,
        topVoiceTarget: Int? = nil,
        registerCenterWeight: Double = 0
    ) {
        self.style = style
        self.maxVoices = maxVoices
        self.bassMode = bassMode
        self.doublesBassInUpperVoices = doublesBassInUpperVoices
        self.topVoiceTarget = topVoiceTarget
        self.registerCenterWeight = registerCenterWeight
    }
}

// MARK: - VoicedChord

/// The register-placed output of `VoiceLeadingEngine`.
///
/// Bass and upper voices are stored separately so the app can route them to different
/// MIDI channels, instruments, or synthesiser layers independently.
public struct VoicedChord: Hashable, Codable, Sendable {
    /// The source chord, including its inversion index.
    public let chord: Chord
    /// The upper chord voices, sorted ascending, placed within the context's preferred register.
    public let upperVoices: [Pitch]
    /// The bass voice, placed within the context's bass register.
    public let bassVoice: Pitch

    /// All pitches sorted ascending — bass first, then upper voices.
    public var allPitches: [Pitch] { ([bassVoice] + upperVoices).sorted() }
    /// The highest upper voice.
    public var topPitch: Pitch { upperVoices[upperVoices.count - 1] }
    /// MIDI note numbers for all pitches (bass + upper voices), sorted ascending.
    /// Pass directly to a sequencer or MIDI output.
    public var midiNotes: [Int] { allPitches.map(\.midiNoteNumber) }

    /// Creates a `VoicedChord`.
    /// - Returns: `nil` if `upperVoices` is empty.
    public init?(chord: Chord, upperVoices: [Pitch], bassVoice: Pitch) {
        guard !upperVoices.isEmpty else { return nil }
        self.chord = chord
        self.upperVoices = upperVoices.sorted()
        self.bassVoice = bassVoice
    }
}

// MARK: - VoiceLeading protocol

/// Converts a `Chord` into a register-specific `VoicedChord`.
public protocol VoiceLeading {
    /// Voices a chord, optionally minimising movement from a previous voicing.
    ///
    /// - Parameters:
    ///   - chord: The chord to voice.
    ///   - previous: The preceding `VoicedChord`, used to guide smooth voice leading.
    ///     Pass `nil` for the first chord in a sequence.
    ///   - context: The harmonic environment supplying register constraints.
    ///   - policy: Controls which inversion is selected.
    ///   - role: Optional harmonic function that biases voicing decisions.
    ///   - constraints: Optional hard limits on voice movement. Candidates that violate
    ///     these are filtered before scoring; if all are eliminated the full pool is used.
    /// - Returns: A `VoicedChord` placed within the context's register ranges.
    /// - Throws: `HarmonyEngineError.voicingOutOfRange` if no valid voicing exists.
    func voice(
        chord: Chord,
        previous: VoicedChord?,
        context: HarmonyContext,
        policy: InversionPolicy,
        role: HarmonyRole?,
        constraints: VoicingConstraints?
    ) throws -> VoicedChord
}

public extension VoiceLeading {
    /// Convenience overload omitting `constraints`, equivalent to passing `constraints: nil`.
    func voice(
        chord: Chord,
        previous: VoicedChord?,
        context: HarmonyContext,
        policy: InversionPolicy,
        role: HarmonyRole?
    ) throws -> VoicedChord {
        try voice(chord: chord, previous: previous, context: context, policy: policy, role: role, constraints: nil)
    }

    /// Convenience overload omitting `role` and `constraints`.
    func voice(
        chord: Chord,
        previous: VoicedChord?,
        context: HarmonyContext,
        policy: InversionPolicy
    ) throws -> VoicedChord {
        try voice(chord: chord, previous: previous, context: context, policy: policy, role: nil, constraints: nil)
    }

    /// Voices a sequence of recipes in order, threading each `VoicedChord` as the
    /// `previous` context for the next step.
    ///
    /// This is the primary entry point for building a voiced progression. The app
    /// retains full control over timing, velocity, and MIDI channel routing.
    ///
    /// - Parameters:
    ///   - recipes: Ordered list of chord recipes to build and voice.
    ///   - context: The shared harmonic environment for all steps.
    ///   - builder: The chord builder to use. Defaults to `ChordBuilder()`.
    ///   - constraints: Optional hard voice-movement limits applied to every step.
    /// - Returns: A `VoicedChord` for each recipe, in the same order.
    /// - Throws: Any error from `ChordBuilding` or `VoiceLeading`.
    func voice(
        recipes: [ChordRecipe],
        context: HarmonyContext,
        builder: ChordBuilding = ChordBuilder(),
        constraints: VoicingConstraints? = nil
    ) throws -> [VoicedChord] {
        var previous: VoicedChord?
        var result = [VoicedChord]()

        for recipe in recipes {
            let chord = try builder.buildChord(recipe: recipe, context: context)
            let voiced = try voice(
                chord: chord,
                previous: previous,
                context: context,
                policy: recipe.inversionPolicy,
                role: recipe.role,
                constraints: constraints
            )
            result.append(voiced)
            previous = voiced
        }

        return result
    }

    /// Voices a sequence of chord specs in order, threading each `VoicedChord` as the
    /// `previous` context for the next step.
    ///
    /// A spec with `bass: .inversion(k)` always uses inversion `k` (`.fixed(k)`). The other specs use `policy`.
    ///
    /// - Parameters:
    ///   - specs: Ordered list of chord specs to build and voice.
    ///   - context: The shared harmonic environment for all steps.
    ///   - policy: The inversion policy of the specs without a fixed inversion. Defaults to `.nearest`.
    ///   - builder: The chord builder to use. Defaults to `ChordBuilder()`.
    ///   - constraints: Optional hard voice-movement limits applied to every step.
    /// - Returns: A `VoicedChord` for each spec, in the same order.
    func voice(
        specs: [ChordSpec],
        context: HarmonyContext,
        policy: InversionPolicy = .nearest,
        builder: ChordBuilder = ChordBuilder(),
        constraints: VoicingConstraints? = nil
    ) throws -> [VoicedChord] {
        var previous: VoicedChord?
        var result = [VoicedChord]()

        for spec in specs {
            let chord = try builder.buildChord(spec: spec, context: context)
            let stepPolicy: InversionPolicy
            if case .inversion(let inversion) = spec.bass {
                stepPolicy = .fixed(inversion)
            } else {
                stepPolicy = policy
            }
            let voiced = try voice(
                chord: chord,
                previous: previous,
                context: context,
                policy: stepPolicy,
                role: nil,
                constraints: constraints
            )
            result.append(voiced)
            previous = voiced
        }

        return result
    }
}

// MARK: - VoiceLeadingEngine

/// Default implementation of `VoiceLeading`.
///
/// ## Algorithm
/// For each allowed inversion, the engine:
/// 1. Takes the chord tones from the inversion tone, and removes tones for the voicing style,
///    `maxVoices`, and `doublesBassInUpperVoices`.
/// 2. Stacks the tones in chord-tone order (each tone above the previous one), then applies the style
///    (for example drop 2).
/// 3. Places the shape in every octave that keeps all upper voices in the preferred register.
/// 4. Places the bass in the bass register, near the previous bass (or near the middle of the register
///    when there is no previous chord).
///
/// Each candidate gets a score. The score adds:
/// - the voice movement of the upper voices from the previous chord (`VoiceLeadingDistance`),
///   plus 3 for each voice that is added or removed,
/// - the top-voice leap (×1.5),
/// - the bass distance outside the bass register (×4 per semitone),
/// - the role bias (see `HarmonyRole`),
/// - the distance to `VoicingOptions.topVoiceTarget` and to the register middle (when set).
///
/// Hard `VoicingConstraints` are applied before scoring. If all candidates are eliminated,
/// the engine falls back to the unconstrained pool.
///
/// Selection by policy:
/// - `.nearest`: the lowest score from all inversions.
/// - `.rootPosition`, `.fixed`: the lowest score from the candidates of that inversion.
/// - `.keepClose`: the lowest inversion, then the lowest bass, then the lowest top voice.
///   It does not use the score.
///
/// Ties are broken by inversion index, then bass pitch, then top pitch.
public struct VoiceLeadingEngine: VoiceLeading, Sendable {
    /// The voicing settings.
    public var options: VoicingOptions

    public init(options: VoicingOptions = VoicingOptions()) {
        self.options = options
    }

    public func voice(
        chord: Chord,
        previous: VoicedChord?,
        context: HarmonyContext,
        policy: InversionPolicy,
        role: HarmonyRole? = nil,
        constraints: VoicingConstraints? = nil
    ) throws -> VoicedChord {
        let allCandidates = makeCandidates(chord: chord, previous: previous, context: context, policy: policy)
        guard !allCandidates.isEmpty else {
            throw HarmonyEngineError.voicingOutOfRange
        }

        // Apply hard constraints; fall back to full pool if all candidates are eliminated.
        let candidates: [VoicingCandidate]
        if let constraints = constraints, let previous = previous {
            let filtered = filter(candidates: allCandidates, by: constraints, previous: previous)
            candidates = filtered.isEmpty ? allCandidates : filtered
        } else {
            candidates = allCandidates
        }

        switch policy {
        case .keepClose:
            return candidates.sorted(by: tieBreak).first!.voicedChord
        case .rootPosition, .fixed, .nearest:
            let scored = candidates.map { ($0, score(candidate: $0, previous: previous, context: context, role: role)) }
            return scored.min { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                return tieBreak(lhs: lhs.0, rhs: rhs.0)
            }!.0.voicedChord
        }
    }

    // MARK: - Constraint filtering

    private func filter(
        candidates: [VoicingCandidate],
        by constraints: VoicingConstraints,
        previous: VoicedChord
    ) -> [VoicingCandidate] {
        candidates.filter { candidate in
            if let maxTopLeap = constraints.maxTopNoteLeap {
                let leap = abs(candidate.voicedChord.topPitch.midiNoteNumber - previous.topPitch.midiNoteNumber)
                guard leap <= maxTopLeap else { return false }
            }
            if let maxBassLeap = constraints.maxBassLeap {
                let leap = abs(candidate.voicedChord.bassVoice.midiNoteNumber - previous.bassVoice.midiNoteNumber)
                guard leap <= maxBassLeap else { return false }
            }
            return true
        }
    }

    // MARK: - Candidate generation

    private func makeCandidates(
        chord: Chord,
        previous: VoicedChord?,
        context: HarmonyContext,
        policy: InversionPolicy
    ) -> [VoicingCandidate] {
        var candidates = [VoicingCandidate]()

        for inverted in filteredInversions(for: chord, policy: policy) {
            let (tones, bassNote) = upperTonesAndBass(for: inverted)
            guard !tones.isEmpty else { continue }
            let shape = applyStyle(to: stack(tones))
            let bassVoice = bestBassPitch(for: bassNote, previous: previous, context: context)

            for shift in octaveShifts(for: shape, in: context.preferredRegister) {
                let voices = shape.map { Pitch(noteName: $0.noteName, octave: $0.octave + shift) }
                if let voicedChord = VoicedChord(chord: inverted, upperVoices: voices, bassVoice: bassVoice) {
                    candidates.append(VoicingCandidate(voicedChord: voicedChord, inversion: inverted.inversion))
                }
            }
        }

        return candidates
    }

    private func filteredInversions(for chord: Chord, policy: InversionPolicy) -> [Chord] {
        switch policy {
        case .rootPosition:        return chord.inversions.filter { $0.inversion == 0 }
        case .fixed(let inv):      return chord.inversions.filter { $0.inversion == inv }
        case .keepClose, .nearest: return chord.inversions
        }
    }

    /// The upper chord tones in voicing order (from the inversion tone), and the bass note.
    private func upperTonesAndBass(for chord: Chord) -> ([(note: NoteName, interval: Interval)], NoteName) {
        let rootPosition = Array(zip(chord.noteNames, chord.type.intervals)).map { (note: $0.0, interval: $0.1) }
        guard !rootPosition.isEmpty else { return ([], chord.root) }
        let inversion = min(max(chord.inversion, 0), rootPosition.count - 1)
        var tones = Array(rootPosition[inversion...] + rootPosition[..<inversion])

        let bassNote: NoteName
        if let slash = chord.bass {
            bassNote = slash
        } else if options.bassMode == .root {
            bassNote = chord.root
        } else {
            bassNote = tones[0].note
        }

        // Style omissions.
        switch options.style {
        case .shell:
            let hasSeventh = tones.contains { $0.interval.degree == 7 }
            let shell = tones.filter { tone in
                switch tone.interval.degree {
                case 3, 7: return true
                case 2, 4: return !tones.contains { $0.interval.degree == 3 }
                case 6:    return !hasSeventh
                default:   return false
                }
            }
            if shell.count >= 2 { tones = shell }
        case .rootless:
            if tones.count > 2 { tones.removeAll { $0.interval == .P1 } }
        case .close, .drop2, .drop3, .drop2and4, .spread:
            break
        }

        // Voice count limit.
        if let maxVoices = options.maxVoices {
            for omitted in [Interval.P5, .P1, .P11, .M9] where tones.count > max(maxVoices, 2) {
                tones.removeAll { $0.interval == omitted }
            }
        }

        // Bass doubling.
        if !options.doublesBassInUpperVoices {
            let withoutBass = tones.filter { $0.note.pitchClass != bassNote.pitchClass }
            if withoutBass.count >= 2 { tones = withoutBass }
        }

        return (tones, bassNote)
    }

    /// Stacks the tones in order, each one in the nearest octave above the previous one.
    private func stack(_ tones: [(note: NoteName, interval: Interval)]) -> [Pitch] {
        var pitches = [Pitch]()
        for tone in tones {
            guard let previous = pitches.last else {
                pitches.append(Pitch(noteName: tone.note, octave: 4))
                continue
            }
            var candidate = Pitch(noteName: tone.note, octave: previous.octave)
            while candidate.midiNoteNumber <= previous.midiNoteNumber {
                candidate = Pitch(noteName: tone.note, octave: candidate.octave + 1)
            }
            pitches.append(candidate)
        }
        return pitches
    }

    /// Applies the style to a stacked (ascending) voicing, and sorts the result.
    private func applyStyle(to stacked: [Pitch]) -> [Pitch] {
        var voices = stacked
        let count = voices.count

        func move(_ index: Int, octaves: Int) {
            guard voices.indices.contains(index) else { return }
            voices[index] = Pitch(noteName: voices[index].noteName, octave: voices[index].octave + octaves)
        }

        switch options.style {
        case .close, .shell, .rootless:
            break
        case .drop2:
            if count >= 3 { move(count - 2, octaves: -1) }
        case .drop3:
            if count >= 4 { move(count - 3, octaves: -1) }
        case .drop2and4:
            if count >= 4 {
                move(count - 2, octaves: -1)
                move(count - 4, octaves: -1)
            }
        case .spread:
            for index in stride(from: 1, to: count, by: 2) { move(index, octaves: 1) }
        }
        return voices.sorted()
    }

    /// The octave shifts that keep every voice of the shape in the register.
    private func octaveShifts(for shape: [Pitch], in register: PitchRange) -> [Int] {
        guard let lowest = shape.first?.midiNoteNumber, let highest = shape.last?.midiNoteNumber else { return [] }
        return (-10...10).filter { shift in
            register.contains(lowest + shift * 12) && register.contains(highest + shift * 12)
        }
    }

    /// Places the bass note in the bass register: near the previous bass, or else near the middle
    /// of the register. When the register has no pitch of that note, it uses the nearest pitch outside it.
    private func bestBassPitch(for note: NoteName, previous: VoicedChord?, context: HarmonyContext) -> Pitch {
        let register = context.bassRegister
        let target = previous?.bassVoice.midiNoteNumber ?? Int(register.midpoint.rounded())
        let pitches = (-1...9).map { Pitch(noteName: note, octave: $0) }
        let inRegister = pitches.filter { register.contains($0.midiNoteNumber) }
        let pool = inRegister.isEmpty ? pitches : inRegister

        return pool.min {
            let ld = abs($0.midiNoteNumber - target)
            let rd = abs($1.midiNoteNumber - target)
            return ld != rd ? ld < rd : $0.midiNoteNumber < $1.midiNoteNumber
        }!
    }

    // MARK: - Scoring

    private func score(
        candidate: VoicingCandidate,
        previous: VoicedChord?,
        context: HarmonyContext,
        role: HarmonyRole?
    ) -> Double {
        let voiced = candidate.voicedChord
        var score = Double(context.bassRegister.distanceOutside(voiced.bassVoice.midiNoteNumber) * 4)
        score += roleBasedPenalty(candidate: candidate, previous: previous, role: role)

        if let previous {
            let movement = VoiceLeadingDistance.between(
                previous.upperVoices.map(\.midiNoteNumber),
                voiced.upperVoices.map(\.midiNoteNumber)
            )
            let voiceCountPenalty = abs(voiced.upperVoices.count - previous.upperVoices.count) * 3
            let topLeap = abs(voiced.topPitch.midiNoteNumber - previous.topPitch.midiNoteNumber)
            score += Double(movement + voiceCountPenalty) + Double(topLeap) * 1.5
        }

        if let target = options.topVoiceTarget {
            score += Double(abs(voiced.topPitch.midiNoteNumber - target))
        }

        if options.registerCenterWeight > 0 {
            let voices = voiced.upperVoices.map(\.midiNoteNumber)
            let center = Double(voices.reduce(0, +)) / Double(voices.count)
            score += abs(center - context.preferredRegister.midpoint) * options.registerCenterWeight
        }

        return score
    }

    private func roleBasedPenalty(
        candidate: VoicingCandidate,
        previous: VoicedChord?,
        role: HarmonyRole?
    ) -> Double {
        guard let role = role else { return 0 }
        switch role {
        case .dominant:
            // Prefer brighter register: penalise voicings below MIDI 72 at the top voice.
            let brightness = max(0, 72 - candidate.voicedChord.topPitch.midiNoteNumber)
            return Double(brightness) * 0.5
        case .tonic:
            // Slight preference for root position to reinforce stability.
            return candidate.inversion != 0 ? 2.0 : 0.0
        case .passing:
            // Minimise bass movement when a previous chord exists.
            guard let previous = previous else { return 0 }
            return Double(abs(candidate.voicedChord.bassVoice.midiNoteNumber - previous.bassVoice.midiNoteNumber)) * 2.0
        default:
            return 0
        }
    }

    // MARK: - Sorting helpers

    private func tieBreak(lhs: VoicingCandidate, rhs: VoicingCandidate) -> Bool {
        if lhs.inversion != rhs.inversion { return lhs.inversion < rhs.inversion }
        let lb = lhs.voicedChord.bassVoice.midiNoteNumber
        let rb = rhs.voicedChord.bassVoice.midiNoteNumber
        if lb != rb { return lb < rb }
        return lhs.voicedChord.topPitch.midiNoteNumber < rhs.voicedChord.topPitch.midiNoteNumber
    }
}

private struct VoicingCandidate {
    let voicedChord: VoicedChord
    let inversion: Int
}
