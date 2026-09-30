import Foundation
import MusicTheory

/// Measures that describe the move from one chord to the next.
///
/// A suggestion or style layer can combine these values into a score. The values themselves do not
/// contain style rules.
public struct TransitionMetrics: Hashable, Sendable {
    /// The ascending root motion in semitones (0–11). For example, 7 is a move up a fifth (down a fourth).
    public let rootMotion: Int
    /// The number of pitch classes that both chords have.
    public let commonTones: Int
    /// The voice movement in semitones. It uses the real voices when the metrics come from voicings,
    /// and the pitch-class distance (`VoiceLeadingDistance.between(_:_:)` on sets) when they come from chords.
    public let voiceLeadingDistance: Int
    /// The tension of the target chord: the number of note pairs that make a semitone, a major 7th,
    /// or a tritone.
    public let tension: Int
    /// The tension of the target chord minus the tension of the source chord.
    public let tensionChange: Int
    /// The number of target chord pitch classes that are not in the scale.
    public let outsideNotes: Int

    /// The root motion as an interval class (0–6). Up a fifth and down a fifth are both 5.
    public var rootMotionClass: Int {
        min(rootMotion, 12 - rootMotion)
    }

    /// Creates the metrics from two chords. The voice-leading distance uses pitch classes.
    public init(from source: Chord, to target: Chord, scale: Scale) {
        let sourcePitchClasses = ScaleFit.pitchClasses(of: source)
        let targetPitchClasses = ScaleFit.pitchClasses(of: target)
        self.init(
            source: source,
            target: target,
            sourcePitchClasses: sourcePitchClasses,
            targetPitchClasses: targetPitchClasses,
            voiceLeadingDistance: VoiceLeadingDistance.between(sourcePitchClasses, targetPitchClasses),
            scale: scale
        )
    }

    /// Creates the metrics from two voicings. The voice-leading distance uses the upper voices and the bass.
    public init(from source: VoicedChord, to target: VoicedChord, scale: Scale) {
        let upperDistance = VoiceLeadingDistance.between(
            source.upperVoices.map(\.midiNoteNumber),
            target.upperVoices.map(\.midiNoteNumber)
        )
        let bassDistance = abs(source.bassVoice.midiNoteNumber - target.bassVoice.midiNoteNumber)
        self.init(
            source: source.chord,
            target: target.chord,
            sourcePitchClasses: Set(source.midiNotes.map { $0 % 12 }),
            targetPitchClasses: Set(target.midiNotes.map { $0 % 12 }),
            voiceLeadingDistance: upperDistance + bassDistance,
            scale: scale
        )
    }

    private init(
        source: Chord,
        target: Chord,
        sourcePitchClasses: Set<Int>,
        targetPitchClasses: Set<Int>,
        voiceLeadingDistance: Int,
        scale: Scale
    ) {
        self.rootMotion = ((target.root.pitchClass - source.root.pitchClass) % 12 + 12) % 12
        self.commonTones = sourcePitchClasses.intersection(targetPitchClasses).count
        self.voiceLeadingDistance = voiceLeadingDistance
        let targetTension = TransitionMetrics.tension(of: targetPitchClasses)
        self.tension = targetTension
        self.tensionChange = targetTension - TransitionMetrics.tension(of: sourcePitchClasses)
        self.outsideNotes = targetPitchClasses.subtracting(scale.noteNames.map(\.pitchClass)).count
    }

    /// The number of pitch-class pairs that make interval class 1 (semitone or major 7th) or 6 (tritone).
    public static func tension(of pitchClasses: Set<Int>) -> Int {
        let sorted = pitchClasses.sorted()
        var count = 0
        for i in sorted.indices {
            for j in sorted.indices where j > i {
                let intervalClass = VoiceLeadingDistance.circularDistance(sorted[i], sorted[j])
                if intervalClass == 1 || intervalClass == 6 { count += 1 }
            }
        }
        return count
    }
}
