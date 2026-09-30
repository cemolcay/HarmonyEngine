import XCTest
import MusicTheory
@testable import HarmonyEngine

final class VoicingTests: XCTestCase {

    private let context = HarmonyContext(tonic: .c, scale: Scale(type: .major, root: .c))

    private func upper(
        _ chord: Chord,
        policy: InversionPolicy = .rootPosition,
        previous: VoicedChord? = nil,
        options: VoicingOptions
    ) throws -> [Int] {
        try VoiceLeadingEngine(options: options)
            .voice(chord: chord, previous: previous, context: context, policy: policy)
            .upperVoices.map(\.midiNoteNumber)
    }

    // MARK: - Styles

    func testCloseAndDrop2() throws {
        let g7 = Chord(type: .dominant7, root: .g)
        XCTAssertEqual(try upper(g7, options: VoicingOptions(style: .close)), [67, 71, 74, 77])
        XCTAssertEqual(try upper(g7, options: VoicingOptions(style: .drop2)), [62, 67, 71, 77])
    }

    func testSpreadTriad() throws {
        XCTAssertEqual(try upper(Chord(type: .major, root: .c), options: VoicingOptions(style: .spread)), [60, 67, 76])
    }

    func testShellVoicingKeepsThirdAndSeventhWithRootInBass() throws {
        let voiced = try VoiceLeadingEngine(options: VoicingOptions(style: .shell, bassMode: .root))
            .voice(chord: Chord(type: .dominant7, root: .g), previous: nil, context: context, policy: .rootPosition)
        XCTAssertEqual(Set(voiced.upperVoices.map(\.noteName)), [.b, .f])
        XCTAssertEqual(voiced.bassVoice.noteName, .g)
    }

    func testRootlessVoicing() throws {
        let cmaj9 = Chord(type: .major9, root: .c)
        let voiced = try VoiceLeadingEngine(options: VoicingOptions(style: .rootless, bassMode: .root))
            .voice(chord: cmaj9, previous: nil, context: context, policy: .rootPosition)
        XCTAssertEqual(voiced.upperVoices.map(\.noteName), [.e, .g, .b, .d])
        XCTAssertEqual(voiced.bassVoice.noteName, .c)
    }

    // MARK: - Omissions and bass

    func testMaxVoicesRemovesFifthFirst() throws {
        let voiced = try VoiceLeadingEngine(options: VoicingOptions(maxVoices: 3))
            .voice(chord: Chord(type: .dominant7, root: .g), previous: nil, context: context, policy: .rootPosition)
        XCTAssertEqual(voiced.upperVoices.map(\.noteName), [.g, .b, .f])
    }

    func testNoBassDoubling() throws {
        XCTAssertEqual(
            try upper(Chord(type: .major, root: .c), options: VoicingOptions(doublesBassInUpperVoices: false)),
            [64, 67]
        )
    }

    func testRootBassModeUnderInvertedUpperVoices() throws {
        let voiced = try VoiceLeadingEngine(options: VoicingOptions(bassMode: .root))
            .voice(chord: Chord(type: .major, root: .c), previous: nil, context: context, policy: .fixed(1))
        XCTAssertEqual(voiced.upperVoices.map(\.noteName), [.e, .g, .c])
        XCTAssertEqual(voiced.bassVoice.noteName, .c)
    }

    func testBassMovesToNearestPitchOfPreviousBass() throws {
        let engine = VoiceLeadingEngine()
        let tonic = try engine.voice(chord: Chord(type: .major, root: .c), previous: nil, context: context, policy: .rootPosition)
        XCTAssertEqual(tonic.bassVoice.midiNoteNumber, 48)
        let subdominant = try engine.voice(chord: Chord(type: .major, root: .f), previous: tonic, context: context, policy: .rootPosition)
        XCTAssertEqual(subdominant.bassVoice.midiNoteNumber, 53, "F3 is 5 semitones from C3; F2 is 7")
    }

    // MARK: - Targets

    func testTopVoiceTarget() throws {
        let top = try upper(Chord(type: .major, root: .c), policy: .nearest, options: VoicingOptions(topVoiceTarget: 72)).last
        XCTAssertEqual(top, 72)
    }

    func testRegisterCenterWeight() throws {
        XCTAssertEqual(
            try upper(Chord(type: .major, root: .c), policy: .nearest, options: VoicingOptions(registerCenterWeight: 1)),
            [67, 72, 76]
        )
    }

    func testFixedPolicyUsesPreviousVoicing() throws {
        let engine = VoiceLeadingEngine()
        let high = try engine.voice(chord: Chord(type: .major, root: .c), previous: nil, context: context, policy: .rootPosition)
        let highC = try VoicedChord(
            chord: high.chord,
            upperVoices: [72, 76, 79].map { Pitch(midiNote: $0) },
            bassVoice: high.bassVoice
        ).unwrap()
        // Root position F after C5–E5–G5: F5–A5–C6 moves 15 semitones, F4–A4–C5 moves 21.
        // The first engine version always took the lowest octave (F4–A4–C5).
        let next = try engine.voice(chord: Chord(type: .major, root: .f), previous: highC, context: context, policy: .rootPosition)
        XCTAssertEqual(next.upperVoices.map(\.midiNoteNumber), [77, 81, 84])
    }

    // MARK: - Invariants

    func testVoicingInvariantsForAllStylesAndInversions() throws {
        let chords = [
            Chord(type: .major, root: .d), Chord(type: .minor7, root: .a),
            Chord(type: .dominant9, root: .g), Chord(type: .halfDiminished7, root: .b),
        ]
        for style in VoicingStyle.allCases {
            let engine = VoiceLeadingEngine(options: VoicingOptions(style: style))
            let wideContext = HarmonyContext(
                tonic: .c,
                scale: Scale(type: .major, root: .c),
                preferredRegister: try PitchRange(minMidi: 48, maxMidi: 90)
            )
            for chord in chords {
                for inversion in 0..<chord.noteNames.count {
                    let voiced = try engine.voice(chord: chord, previous: nil, context: wideContext, policy: .fixed(inversion))
                    XCTAssertTrue(voiced.upperVoices.allSatisfy { wideContext.preferredRegister.contains($0.midiNoteNumber) })
                    XCTAssertTrue(wideContext.bassRegister.contains(voiced.bassVoice.midiNoteNumber))
                    // The bass plays the inversion tone.
                    XCTAssertEqual(voiced.bassVoice.noteName, chord.noteNames[inversion], "\(style) \(chord) inv \(inversion)")
                    // The upper voices use only chord tones.
                    let chordPitchClasses = Set(chord.noteNames.map(\.pitchClass))
                    XCTAssertTrue(voiced.upperVoices.allSatisfy { chordPitchClasses.contains($0.noteName.pitchClass) })
                }
            }
        }
    }

    func testSpecPipelineIsDeterministicAndHonorsInversion() throws {
        let specs = [
            ChordSpec.degree(2, tension: .diatonicSeventh),
            ChordSpec(root: .degree(5), tension: .diatonicSeventh, bass: .inversion(1)),
            ChordSpec(root: .applied(.dominant, of: 2)),
            ChordSpec.degree(1),
        ]
        let engine = VoiceLeadingEngine(options: VoicingOptions(style: .drop2))
        let first = try engine.voice(specs: specs, context: context)
        let second = try engine.voice(specs: specs, context: context)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first[1].chord.inversion, 1)
        XCTAssertEqual(first[1].bassVoice.noteName, .b)
    }
}

private extension Optional {
    func unwrap(file: StaticString = #filePath, line: UInt = #line) throws -> Wrapped {
        try XCTUnwrap(self, file: file, line: line)
    }
}
