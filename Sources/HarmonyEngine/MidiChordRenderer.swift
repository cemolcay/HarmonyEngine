import Foundation
import MusicTheory

public struct MidiChordEvent: Hashable, Codable, Sendable {
    public let note: Int
    public let velocity: Int
    public let startBeat: Double
    public let durationBeats: Double
    public let channel: Int

    public init(note: Int, velocity: Int, startBeat: Double, durationBeats: Double, channel: Int) {
        self.note = note
        self.velocity = velocity
        self.startBeat = startBeat
        self.durationBeats = durationBeats
        self.channel = channel
    }
}

public protocol MidiRendering {
    func render(progression: Progression, in context: HarmonyContext) throws -> [MidiChordEvent]
}

public struct MidiChordRenderer: MidiRendering {
    public let chordBuilder: ChordBuilding
    public let voiceLeading: VoiceLeading
    public let velocity: Int
    public let channel: Int

    public init(
        chordBuilder: ChordBuilding = ChordBuilder(),
        voiceLeading: VoiceLeading = VoiceLeadingEngine(),
        velocity: Int = 100,
        channel: Int = 0
    ) {
        self.chordBuilder = chordBuilder
        self.voiceLeading = voiceLeading
        self.velocity = velocity
        self.channel = channel
    }

    public func voice(progression: Progression, in context: HarmonyContext) throws -> [VoicedChord] {
        var previous: VoicedChord?
        var voicedChords = [VoicedChord]()

        for step in progression.steps {
            let chord = try chordBuilder.buildChord(step: step, context: context)
            let policy = step.chordRecipe?.inversionPolicy ?? .nearest
            let voicedChord = try voiceLeading.voice(
                chord: chord,
                previous: previous,
                context: context,
                policy: policy
            )
            voicedChords.append(voicedChord)
            previous = voicedChord
        }

        return voicedChords
    }

    public func render(progression: Progression, in context: HarmonyContext) throws -> [MidiChordEvent] {
        let voicedChords = try voice(progression: progression, in: context)
        let beatsPerBar = context.tempo?.timeSignature.beats ?? 4
        var events = [MidiChordEvent]()

        for pair in zip(progression.steps, voicedChords) {
            let startBeat = Progression.absoluteBeat(for: pair.0, beatsPerBar: beatsPerBar)
            let chordEvents = pair.1.pitches.map { pitch in
                MidiChordEvent(
                    note: pitch.midiNoteNumber,
                    velocity: velocity,
                    startBeat: startBeat,
                    durationBeats: pair.0.durationBeats,
                    channel: channel
                )
            }
            events.append(contentsOf: chordEvents)
        }

        return events.sorted {
            if $0.startBeat != $1.startBeat { return $0.startBeat < $1.startBeat }
            if $0.note != $1.note { return $0.note < $1.note }
            return $0.channel < $1.channel
        }
    }
}

