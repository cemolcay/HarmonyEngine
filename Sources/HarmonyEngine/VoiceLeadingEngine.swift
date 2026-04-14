import Foundation
import MusicTheory

public struct VoicedChord: Hashable, Codable, Sendable {
    public let chord: Chord
    public let pitches: [Pitch]
    public let bassPitch: Pitch
    public let topPitch: Pitch

    public init?(chord: Chord, pitches: [Pitch]) {
        let sortedPitches = pitches.sorted()
        guard let bassPitch = sortedPitches.first, let topPitch = sortedPitches.last else {
            return nil
        }
        self.chord = chord
        self.pitches = sortedPitches
        self.bassPitch = bassPitch
        self.topPitch = topPitch
    }
}

public protocol VoiceLeading {
    func voice(
        chord: Chord,
        previous: VoicedChord?,
        context: HarmonyContext,
        policy: InversionPolicy
    ) throws -> VoicedChord
}

public struct VoiceLeadingEngine: VoiceLeading {
    public init() {}

    public func voice(
        chord: Chord,
        previous: VoicedChord?,
        context: HarmonyContext,
        policy: InversionPolicy
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
                let lhsScore = score(candidate: lhs, previous: previous, context: context)
                let rhsScore = score(candidate: rhs, previous: previous, context: context)
                if lhsScore != rhsScore { return lhsScore < rhsScore }
                return nearestTieBreak(lhs: lhs, rhs: rhs)
            }.first!.voicedChord
        }
    }

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
                let upperVoices = inversion.pitches(octave: octave).sorted()
                guard upperVoices.allSatisfy({ context.preferredRegister.contains($0.midiNoteNumber) }) else {
                    continue
                }

                let bassPitch = bestBassPitch(for: upperVoices[0], context: context)
                let allPitches = [bassPitch] + upperVoices

                if let voicedChord = VoicedChord(chord: inversion, pitches: allPitches) {
                    candidates.append(
                        VoicingCandidate(
                            voicedChord: voicedChord,
                            inversion: inversion.inversion
                        )
                    )
                }
            }
        }

        return candidates
    }

    private func filteredInversions(for chord: Chord, policy: InversionPolicy) -> [Chord] {
        switch policy {
        case .rootPosition:
            return chord.inversions.filter { $0.inversion == 0 }
        case .fixed(let inversion):
            return chord.inversions.filter { $0.inversion == inversion }
        case .keepClose, .nearest:
            return chord.inversions
        }
    }

    private func candidateOctaves(for preferredRegister: PitchRange) -> ClosedRange<Int> {
        let minOctave = (preferredRegister.minMidi / 12) - 2
        let maxOctave = (preferredRegister.maxMidi / 12)
        return minOctave...maxOctave
    }

    private func bestBassPitch(for source: Pitch, context: HarmonyContext) -> Pitch {
        var candidates = [Pitch]()
        let midiClass = source.midiNoteNumber % 12

        for midi in context.bassRegister.minMidi...context.bassRegister.maxMidi {
            if ((midi % 12) + 12) % 12 == ((midiClass + 12) % 12) {
                candidates.append(Pitch(midiNote: midi, spelling: preferredSpelling(for: source.noteName)))
            }
        }

        guard !candidates.isEmpty else {
            return source
        }

        let targetMidi = Int(context.bassRegister.midpoint.rounded())
        return candidates.min {
            let lhsDistance = abs($0.midiNoteNumber - targetMidi)
            let rhsDistance = abs($1.midiNoteNumber - targetMidi)
            if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }
            return $0.midiNoteNumber < $1.midiNoteNumber
        }!
    }

    private func preferredSpelling(for noteName: NoteName) -> SpellingPreference {
        return noteName.accidental.semitones < 0 ? .flats : .sharps
    }

    private func keepCloseSort(lhs: VoicingCandidate, rhs: VoicingCandidate) -> Bool {
        let lhsBassPenalty = lhs.voicedChord.bassPitch.midiNoteNumber
        let rhsBassPenalty = rhs.voicedChord.bassPitch.midiNoteNumber

        if lhs.inversion != rhs.inversion { return lhs.inversion < rhs.inversion }
        if lhsBassPenalty != rhsBassPenalty { return lhsBassPenalty < rhsBassPenalty }
        return lhs.voicedChord.topPitch.midiNoteNumber < rhs.voicedChord.topPitch.midiNoteNumber
    }

    private func score(
        candidate: VoicingCandidate,
        previous: VoicedChord?,
        context: HarmonyContext
    ) -> Double {
        let bassPenalty = Double(context.bassRegister.distanceOutside(candidate.voicedChord.bassPitch.midiNoteNumber) * 4)

        guard let previous = previous else {
            return bassPenalty
        }

        let movement = zip(candidate.voicedChord.pitches, previous.pitches).reduce(0) { partial, pair in
            partial + abs(pair.0.midiNoteNumber - pair.1.midiNoteNumber)
        }

        let voiceCountPenalty = abs(candidate.voicedChord.pitches.count - previous.pitches.count) * 12
        let topLeap = abs(candidate.voicedChord.topPitch.midiNoteNumber - previous.topPitch.midiNoteNumber)
        return Double(movement + voiceCountPenalty) + (Double(topLeap) * 1.5) + bassPenalty
    }

    private func nearestTieBreak(lhs: VoicingCandidate, rhs: VoicingCandidate) -> Bool {
        if lhs.inversion != rhs.inversion { return lhs.inversion < rhs.inversion }
        if lhs.voicedChord.bassPitch.midiNoteNumber != rhs.voicedChord.bassPitch.midiNoteNumber {
            return lhs.voicedChord.bassPitch.midiNoteNumber < rhs.voicedChord.bassPitch.midiNoteNumber
        }
        return lhs.voicedChord.topPitch.midiNoteNumber < rhs.voicedChord.topPitch.midiNoteNumber
    }
}

private struct VoicingCandidate {
    let voicedChord: VoicedChord
    let inversion: Int
}

