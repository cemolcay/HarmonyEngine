import Foundation
import MusicTheory

public struct VoicedChord: Hashable, Codable, Sendable {
    public let chord: Chord
    /// The upper chord voices, sorted ascending, placed within the context's preferred register.
    public let upperVoices: [Pitch]
    /// The bass voice, placed within the context's bass register.
    public let bassVoice: Pitch

    /// All pitches sorted ascending, bass first.
    public var allPitches: [Pitch] { ([bassVoice] + upperVoices).sorted() }
    /// The highest upper voice.
    public var topPitch: Pitch { upperVoices[upperVoices.count - 1] }
    /// MIDI note numbers for all pitches (bass + upper voices), sorted ascending.
    public var midiNotes: [Int] { allPitches.map(\.midiNoteNumber) }

    public init?(chord: Chord, upperVoices: [Pitch], bassVoice: Pitch) {
        guard !upperVoices.isEmpty else { return nil }
        self.chord = chord
        self.upperVoices = upperVoices.sorted()
        self.bassVoice = bassVoice
    }
}

public protocol VoiceLeading {
    func voice(
        chord: Chord,
        previous: VoicedChord?,
        context: HarmonyContext,
        policy: InversionPolicy,
        role: HarmonyRole?
    ) throws -> VoicedChord
}

public extension VoiceLeading {
    func voice(
        chord: Chord,
        previous: VoicedChord?,
        context: HarmonyContext,
        policy: InversionPolicy
    ) throws -> VoicedChord {
        try voice(chord: chord, previous: previous, context: context, policy: policy, role: nil)
    }
}

public struct VoiceLeadingEngine: VoiceLeading {
    public init() {}

    public func voice(
        chord: Chord,
        previous: VoicedChord?,
        context: HarmonyContext,
        policy: InversionPolicy,
        role: HarmonyRole? = nil
    ) throws -> VoicedChord {
        let candidates = try makeCandidates(chord: chord, context: context, policy: policy)
        guard !candidates.isEmpty else {
            throw HarmonyEngineError.voicingOutOfRange
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
        case .rootPosition:       return chord.inversions.filter { $0.inversion == 0 }
        case .fixed(let inv):     return chord.inversions.filter { $0.inversion == inv }
        case .keepClose, .nearest: return chord.inversions
        }
    }

    private func candidateOctaves(for preferredRegister: PitchRange) -> ClosedRange<Int> {
        let minOctave = max(0, (preferredRegister.minMidi / 12) - 2)
        let maxOctave = preferredRegister.maxMidi / 12
        return minOctave...maxOctave
    }

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
            // Prefer brighter register: penalize voicings below MIDI 72 at the top voice.
            let brightness = max(0, 72 - candidate.voicedChord.topPitch.midiNoteNumber)
            return Double(brightness) * 0.5
        case .tonic:
            // Slight preference for root position to reinforce stability.
            return candidate.inversion != 0 ? 2.0 : 0.0
        case .passing:
            // Minimize bass movement when a previous chord exists.
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
