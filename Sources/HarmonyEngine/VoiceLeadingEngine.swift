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
}

// MARK: - VoiceLeadingEngine

/// Default implementation of `VoiceLeading`.
///
/// ## Algorithm
/// For each inversion of the chord, pitches are placed across candidate octaves within the
/// preferred register. Each valid voicing is scored by:
/// - Total semitone movement across upper voices from the previous chord.
/// - Top-voice leap (weighted ×1.5).
/// - Bass distance outside the bass register (weighted ×4 per semitone).
/// - Role-based bias (see `HarmonyRole`).
///
/// Hard `VoicingConstraints` are applied before scoring: candidates that violate
/// `maxTopNoteLeap` or `maxBassLeap` are removed from the pool. If all candidates
/// are eliminated, the engine falls back to the unconstrained pool.
///
/// The lowest-scoring candidate is selected. Ties are broken by inversion index, then bass
/// pitch, then top pitch.
public struct VoiceLeadingEngine: VoiceLeading {
    public init() {}

    public func voice(
        chord: Chord,
        previous: VoicedChord?,
        context: HarmonyContext,
        policy: InversionPolicy,
        role: HarmonyRole? = nil,
        constraints: VoicingConstraints? = nil
    ) throws -> VoicedChord {
        let allCandidates = try makeCandidates(chord: chord, context: context, policy: policy)
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
        case .rootPosition, .fixed:
            return candidates[0].voicedChord
        case .keepClose:
            return candidates.sorted(by: keepCloseSort).first!.voicedChord
        case .nearest:
            return candidates.sorted { lhs, rhs in
                let lhsScore = score(candidate: lhs, previous: previous, context: context, role: role)
                let rhsScore = score(candidate: rhs, previous: previous, context: context, role: role)
                if lhsScore != rhsScore { return lhsScore < rhsScore }
                return nearestTieBreak(lhs: lhs, rhs: rhs)
            }.first!.voicedChord
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
        context: HarmonyContext,
        policy: InversionPolicy
    ) throws -> [VoicingCandidate] {
        let inversions = filteredInversions(for: chord, policy: policy)
        let octaveRange = candidateOctaves(for: context.preferredRegister)
        var candidates = [VoicingCandidate]()

        for inversion in inversions {
            for octave in octaveRange {
                let voicePitches = inversion.pitches(octave: octave).sorted()
                guard voicePitches.allSatisfy({ context.preferredRegister.contains($0.midiNoteNumber) }) else {
                    continue
                }

                let bassVoice = bestBassPitch(for: voicePitches[0], context: context)

                if let voicedChord = VoicedChord(chord: inversion, upperVoices: voicePitches, bassVoice: bassVoice) {
                    candidates.append(
                        VoicingCandidate(voicedChord: voicedChord, inversion: inversion.inversion)
                    )
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

    private func candidateOctaves(for preferredRegister: PitchRange) -> ClosedRange<Int> {
        let minOctave = max(0, (preferredRegister.minMidi / 12) - 2)
        let maxOctave = preferredRegister.maxMidi / 12
        return minOctave...maxOctave
    }

    /// Finds the pitch in the bass register whose pitch class matches `source`,
    /// placing it closest to the register's midpoint.
    private func bestBassPitch(for source: Pitch, context: HarmonyContext) -> Pitch {
        let midiClass = ((source.midiNoteNumber % 12) + 12) % 12
        var candidates = [Pitch]()

        for midi in context.bassRegister.minMidi...context.bassRegister.maxMidi {
            if ((midi % 12) + 12) % 12 == midiClass {
                candidates.append(Pitch(midiNote: midi, spelling: preferredSpelling(for: source.noteName)))
            }
        }

        guard !candidates.isEmpty else { return source }

        let targetMidi = Int(context.bassRegister.midpoint.rounded())
        return candidates.min {
            let ld = abs($0.midiNoteNumber - targetMidi)
            let rd = abs($1.midiNoteNumber - targetMidi)
            return ld != rd ? ld < rd : $0.midiNoteNumber < $1.midiNoteNumber
        }!
    }

    private func preferredSpelling(for noteName: NoteName) -> SpellingPreference {
        noteName.accidental.semitones < 0 ? .flats : .sharps
    }

    // MARK: - Scoring

    private func score(
        candidate: VoicingCandidate,
        previous: VoicedChord?,
        context: HarmonyContext,
        role: HarmonyRole?
    ) -> Double {
        let bassPenalty = Double(context.bassRegister.distanceOutside(candidate.voicedChord.bassVoice.midiNoteNumber) * 4)
        let rolePenalty = roleBasedPenalty(candidate: candidate, previous: previous, role: role)

        guard let previous = previous else {
            return bassPenalty + rolePenalty
        }

        let movement = zip(candidate.voicedChord.upperVoices, previous.upperVoices).reduce(0) { acc, pair in
            acc + abs(pair.0.midiNoteNumber - pair.1.midiNoteNumber)
        }
        let voiceCountPenalty = abs(candidate.voicedChord.upperVoices.count - previous.upperVoices.count) * 12
        let topLeap = abs(candidate.voicedChord.topPitch.midiNoteNumber - previous.topPitch.midiNoteNumber)

        return Double(movement + voiceCountPenalty) + (Double(topLeap) * 1.5) + bassPenalty + rolePenalty
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

    private func keepCloseSort(lhs: VoicingCandidate, rhs: VoicingCandidate) -> Bool {
        if lhs.inversion != rhs.inversion { return lhs.inversion < rhs.inversion }
        let lb = lhs.voicedChord.bassVoice.midiNoteNumber
        let rb = rhs.voicedChord.bassVoice.midiNoteNumber
        if lb != rb { return lb < rb }
        return lhs.voicedChord.topPitch.midiNoteNumber < rhs.voicedChord.topPitch.midiNoteNumber
    }

    private func nearestTieBreak(lhs: VoicingCandidate, rhs: VoicingCandidate) -> Bool {
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
