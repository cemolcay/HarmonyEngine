import XCTest
import MusicTheory
@testable import HarmonyEngine

final class HarmonyEngineTests: XCTestCase {
    func testMajorDegreeResolutionUsesScaleNoteNames() throws {
        let context = HarmonyContext(
            tonic: .c,
            scale: Scale(type: .major, root: .c)
        )
        let step = ProgressionStep(bar: 1, beat: 0, durationBeats: 4, scaleDegree: 2)

        let chord = try ChordBuilder().buildChord(step: step, context: context)

        XCTAssertEqual(chord.root, .d)
        XCTAssertEqual(chord.type.symbol, "m")
    }

    func testMinorDegreeResolutionUsesCorrectSpelling() throws {
        let context = HarmonyContext(
            tonic: .a,
            scale: Scale(type: .minor, root: .a)
        )
        let step = ProgressionStep(bar: 1, beat: 0, durationBeats: 4, scaleDegree: 7)

        let chord = try ChordBuilder().buildChord(step: step, context: context)

        XCTAssertEqual(chord.root, .g)
        XCTAssertEqual(chord.type.symbol, "M")
    }

    func testCustomScaleContextCanResolveChordRecipeDegree() throws {
        let customScale = Scale(intervals: [.P1, .m2, .P4, .P5], root: .d, name: "Tetrachord")
        let context = HarmonyContext(tonic: .d, scale: customScale)
        let recipe = ChordRecipe(scaleDegree: 2, chordType: .minor)
        let step = ProgressionStep(bar: 1, beat: 0, durationBeats: 2, chordRecipe: recipe)

        let chord = try ChordBuilder().buildChord(step: step, context: context)

        XCTAssertEqual(chord.root, .eb)
        XCTAssertEqual(chord.type.symbol, "m")
    }

    func testChordRecipeWinsOverStepDegree() throws {
        let context = HarmonyContext(tonic: .c, scale: Scale(type: .major, root: .c))
        let recipe = ChordRecipe(scaleDegree: 5, chordType: .dominant7)
        let step = ProgressionStep(bar: 1, beat: 0, durationBeats: 4, scaleDegree: 1, chordRecipe: recipe)

        let chord = try ChordBuilder().buildChord(step: step, context: context)

        XCTAssertEqual(chord.root, .g)
        XCTAssertEqual(chord.type.symbol, "7")
    }

    func testDiatonicSeventhTensionBuildsSeventhChord() throws {
        let context = HarmonyContext(tonic: .c, scale: Scale(type: .major, root: .c))
        let recipe = ChordRecipe(
            scaleDegree: 5,
            chordType: .major,
            tensionPolicy: .diatonicSeventh
        )
        let step = ProgressionStep(bar: 1, beat: 0, durationBeats: 4, chordRecipe: recipe)

        let chord = try ChordBuilder().buildChord(step: step, context: context)

        XCTAssertEqual(chord.root, .g)
        XCTAssertEqual(chord.type.symbol, "7")
    }

    func testNearestVoiceLeadingIsDeterministic() throws {
        let context = HarmonyContext(tonic: .c, scale: Scale(type: .major, root: .c))
        let engine = VoiceLeadingEngine()
        let first = try engine.voice(
            chord: Chord(type: .major7, root: .c),
            previous: nil,
            context: context,
            policy: .nearest
        )
        let second = try engine.voice(
            chord: Chord(type: .dominant7, root: .g),
            previous: first,
            context: context,
            policy: .nearest
        )
        let repeatSecond = try engine.voice(
            chord: Chord(type: .dominant7, root: .g),
            previous: first,
            context: context,
            policy: .nearest
        )

        XCTAssertEqual(second, repeatSecond)
        XCTAssertTrue((36...55).contains(second.bassPitch.midiNoteNumber))
        XCTAssertEqual(Array(second.pitches.dropFirst()).map(\.midiNoteNumber), [62, 65, 67, 71])
    }

    func testVoicingKeepsUpperVoicesInPreferredRegister() throws {
        let preferred = try PitchRange(minMidi: 60, maxMidi: 72)
        let bass = try PitchRange(minMidi: 36, maxMidi: 48)
        let context = HarmonyContext(
            tonic: .c,
            scale: Scale(type: .major, root: .c),
            preferredRegister: preferred,
            bassRegister: bass
        )

        let voiced = try VoiceLeadingEngine().voice(
            chord: Chord(type: .major7, root: .f),
            previous: nil,
            context: context,
            policy: .keepClose
        )

        XCTAssertTrue(preferred.contains(voiced.pitches[1].midiNoteNumber))
        XCTAssertTrue(preferred.contains(voiced.topPitch.midiNoteNumber))
        XCTAssertTrue(bass.contains(voiced.bassPitch.midiNoteNumber))
    }

    func testMidiRenderingOrdersEventsByBeatAndNote() throws {
        let context = HarmonyContext(
            tonic: .c,
            scale: Scale(type: .major, root: .c),
            tempo: Tempo(timeSignature: TimeSignature(beats: 4, beatUnit: 4), bpm: 120)
        )
        let progression = try Progression(
            steps: [
                ProgressionStep(
                    bar: 1,
                    beat: 0,
                    durationBeats: 4,
                    chordRecipe: ChordRecipe(scaleDegree: 1, chordType: .major7)
                ),
                ProgressionStep(
                    bar: 2,
                    beat: 0,
                    durationBeats: 4,
                    chordRecipe: ChordRecipe(scaleDegree: 5, chordType: .dominant7)
                ),
            ],
            loopLengthBars: 2
        )

        let events = try MidiChordRenderer().render(progression: progression, in: context)

        XCTAssertEqual(events.first?.startBeat, 0)
        XCTAssertEqual(events.last?.startBeat, 4)
        XCTAssertEqual(events.prefix(5).map(\.note), events.prefix(5).map(\.note).sorted())
        XCTAssertEqual(events.suffix(5).map(\.note), events.suffix(5).map(\.note).sorted())
        XCTAssertEqual(events.first?.velocity, 100)
        XCTAssertEqual(events.first?.channel, 0)
    }

    func testProgressionRejectsOverlaps() throws {
        XCTAssertThrowsError(
            try Progression(
                steps: [
                    ProgressionStep(bar: 1, beat: 0, durationBeats: 3, scaleDegree: 1),
                    ProgressionStep(bar: 1, beat: 2, durationBeats: 2, scaleDegree: 4),
                ],
                loopLengthBars: 1
            )
        ) { error in
            XCTAssertEqual(error as? HarmonyEngineError, .overlappingProgressionSteps)
        }
    }
}
