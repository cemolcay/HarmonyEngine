import XCTest
import MusicTheory
@testable import HarmonyEngine

final class HarmonyEngineTests: XCTestCase {

    // MARK: - ChordBuilder: degree resolution

    func testMajorDegreeResolutionUsesScaleNoteNames() throws {
        let context = HarmonyContext(tonic: .c, scale: Scale(type: .major, root: .c))
        let recipe = ChordRecipe(scaleDegree: 2)

        let chord = try ChordBuilder().buildChord(recipe: recipe, context: context)

        XCTAssertEqual(chord.root, .d)
        XCTAssertEqual(chord.type.symbol, "m")
    }

    func testMinorDegreeResolutionUsesCorrectSpelling() throws {
        let context = HarmonyContext(tonic: .a, scale: Scale(type: .minor, root: .a))
        let recipe = ChordRecipe(scaleDegree: 7)

        let chord = try ChordBuilder().buildChord(recipe: recipe, context: context)

        XCTAssertEqual(chord.root, .g)
        XCTAssertEqual(chord.type.symbol, "M")
    }

    func testCustomScaleContextCanResolveChordRecipeDegree() throws {
        let customScale = Scale(intervals: [.P1, .m2, .P4, .P5], root: .d, name: "Tetrachord")
        let context = HarmonyContext(tonic: .d, scale: customScale)
        let recipe = ChordRecipe(scaleDegree: 2, chordType: .minor)

        let chord = try ChordBuilder().buildChord(recipe: recipe, context: context)

        XCTAssertEqual(chord.root, .eb)
        XCTAssertEqual(chord.type.symbol, "m")
    }

    // MARK: - ChordBuilder: chord type resolution

    func testNilChordTypeInfersDiatonicQuality() throws {
        let context = HarmonyContext(tonic: .c, scale: Scale(type: .major, root: .c))
        let recipe = ChordRecipe(scaleDegree: 2) // no chordType → infer Dm

        let chord = try ChordBuilder().buildChord(recipe: recipe, context: context)

        XCTAssertEqual(chord.root, .d)
        XCTAssertEqual(chord.type.symbol, "m")
    }

    func testExplicitChordTypeOverridesInferredDiatonic() throws {
        let context = HarmonyContext(tonic: .c, scale: Scale(type: .major, root: .c))
        // Degree 2 in C major would infer Dm; explicit .major overrides the inference.
        let recipe = ChordRecipe(scaleDegree: 2, chordType: .major)

        let chord = try ChordBuilder().buildChord(recipe: recipe, context: context)

        XCTAssertEqual(chord.root, .d)
        XCTAssertEqual(chord.type.symbol, "M")
    }

    func testNonHeptatonicScaleRequiresExplicitChordType() throws {
        let customScale = Scale(intervals: [.P1, .m2, .P4, .P5], root: .d, name: "Tetrachord")
        let context = HarmonyContext(tonic: .d, scale: customScale)
        let recipe = ChordRecipe(scaleDegree: 1) // nil chordType, non-7-note scale

        XCTAssertThrowsError(try ChordBuilder().buildChord(recipe: recipe, context: context)) { error in
            XCTAssertEqual(error as? HarmonyEngineError, .unableToResolveChord)
        }
    }

    func testAbsoluteRootRecipeIgnoresScale() throws {
        let context = HarmonyContext(tonic: .c, scale: Scale(type: .major, root: .c))
        let recipe = ChordRecipe(root: .f, chordType: .minor)

        let chord = try ChordBuilder().buildChord(recipe: recipe, context: context)

        XCTAssertEqual(chord.root, .f)
        XCTAssertEqual(chord.type.symbol, "m")
    }

    // MARK: - ChordBuilder: tension policy

    func testDiatonicSeventhTensionBuildsSeventhChord() throws {
        let context = HarmonyContext(tonic: .c, scale: Scale(type: .major, root: .c))
        let recipe = ChordRecipe(scaleDegree: 5, chordType: .major, tensionPolicy: .diatonicSeventh)

        let chord = try ChordBuilder().buildChord(recipe: recipe, context: context)

        XCTAssertEqual(chord.root, .g)
        XCTAssertEqual(chord.type.symbol, "7")
    }

    // MARK: - ChordBuilder: role defaults

    func testDominantRoleAddsDiatonicSeventh() throws {
        let context = HarmonyContext(tonic: .c, scale: Scale(type: .major, root: .c))
        let recipe = ChordRecipe(scaleDegree: 5, role: .dominant)

        let chord = try ChordBuilder().buildChord(recipe: recipe, context: context)

        XCTAssertEqual(chord.root, .g)
        XCTAssertEqual(chord.type.symbol, "7")
    }

    func testColorRoleAddsNinthExtension() throws {
        let context = HarmonyContext(tonic: .c, scale: Scale(type: .major, root: .c))
        let recipe = ChordRecipe(scaleDegree: 1, role: .color)

        let chord = try ChordBuilder().buildChord(recipe: recipe, context: context)

        XCTAssertEqual(chord.root, .c)
        // Cmaj9 contains major 7th and major 9th on top of the triad
        XCTAssertTrue(chord.type.intervals.contains(.M7))
        XCTAssertTrue(chord.type.intervals.contains(.M9))
    }

    func testExplicitTensionPolicyWinsOverRoleDefault() throws {
        let context = HarmonyContext(tonic: .c, scale: Scale(type: .major, root: .c))
        // Dominant role would default to diatonicSeventh, but .none is explicit
        let recipe = ChordRecipe(scaleDegree: 5, role: .dominant, tensionPolicy: TensionPolicy.none)

        let chord = try ChordBuilder().buildChord(recipe: recipe, context: context)

        XCTAssertEqual(chord.root, .g)
        XCTAssertEqual(chord.type.symbol, "M") // triad only
    }

    // MARK: - VoiceLeadingEngine: determinism and register

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
        XCTAssertTrue((36...55).contains(second.bassVoice.midiNoteNumber))
        XCTAssertEqual(second.upperVoices.map(\.midiNoteNumber), [62, 65, 67, 71])
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

        XCTAssertTrue(voiced.upperVoices.allSatisfy { preferred.contains($0.midiNoteNumber) })
        XCTAssertTrue(bass.contains(voiced.bassVoice.midiNoteNumber))
    }

    // MARK: - VoiceLeadingEngine: VoicedChord structure

    func testVoicedChordSeparatesBassFromUpperVoices() throws {
        let context = HarmonyContext(tonic: .c, scale: Scale(type: .major, root: .c))

        let voiced = try VoiceLeadingEngine().voice(
            chord: Chord(type: .major, root: .c),
            previous: nil,
            context: context,
            policy: .rootPosition
        )

        XCTAssertTrue(context.bassRegister.contains(voiced.bassVoice.midiNoteNumber))
        XCTAssertTrue(voiced.upperVoices.allSatisfy { context.preferredRegister.contains($0.midiNoteNumber) })
        XCTAssertEqual(voiced.midiNotes, voiced.allPitches.map(\.midiNoteNumber))
        XCTAssertEqual(voiced.midiNotes, voiced.midiNotes.sorted())
    }

    func testMidiNotesIncludesBassAndUpperVoices() throws {
        let context = HarmonyContext(tonic: .c, scale: Scale(type: .major, root: .c))

        let voiced = try VoiceLeadingEngine().voice(
            chord: Chord(type: .major, root: .c),
            previous: nil,
            context: context,
            policy: .rootPosition
        )

        XCTAssertEqual(voiced.midiNotes.count, voiced.upperVoices.count + 1)
        XCTAssertTrue(voiced.midiNotes.contains(voiced.bassVoice.midiNoteNumber))
    }

    // MARK: - VoiceLeadingEngine: role-based voicing

    func testDominantRolePrefersBrighterVoicing() throws {
        let context = HarmonyContext(tonic: .c, scale: Scale(type: .major, root: .c))
        let engine = VoiceLeadingEngine()
        let chord = Chord(type: .dominant7, root: .g)

        let withRole = try engine.voice(chord: chord, previous: nil, context: context, policy: .nearest, role: .dominant)
        let noRole   = try engine.voice(chord: chord, previous: nil, context: context, policy: .nearest, role: nil)

        // Dominant role biases toward higher top voice; top note should be >= no-role result.
        XCTAssertGreaterThanOrEqual(withRole.topPitch.midiNoteNumber, noRole.topPitch.midiNoteNumber)
    }

    // MARK: - HarmonicPalette

    func testHarmonicPaletteDiatonicTriadsCMajor() throws {
        let context = HarmonyContext(tonic: .c, scale: Scale(type: .major, root: .c))
        let triads = try HarmonicPalette.diatonicTriads(in: context)

        XCTAssertEqual(triads.count, 7)
        // I = C major
        XCTAssertEqual(triads[0].root, .c)
        XCTAssertEqual(triads[0].type.symbol, "M")
        // II = D minor
        XCTAssertEqual(triads[1].root, .d)
        XCTAssertEqual(triads[1].type.symbol, "m")
        // V = G major
        XCTAssertEqual(triads[4].root, .g)
        XCTAssertEqual(triads[4].type.symbol, "M")
        // VII = B diminished
        XCTAssertEqual(triads[6].root, .b)
        XCTAssertEqual(triads[6].type.symbol, "dim")
    }

    func testHarmonicPaletteDiatonicSeventhsCMajor() throws {
        let context = HarmonyContext(tonic: .c, scale: Scale(type: .major, root: .c))
        let sevenths = try HarmonicPalette.diatonicSevenths(in: context)

        XCTAssertEqual(sevenths.count, 7)
        XCTAssertEqual(sevenths[0].root, .c)
        XCTAssertEqual(sevenths[0].type.symbol, "Maj7")
        XCTAssertEqual(sevenths[4].root, .g)
        XCTAssertEqual(sevenths[4].type.symbol, "7")
    }

    func testHarmonicPaletteChordsForDominantRole() throws {
        let context = HarmonyContext(tonic: .c, scale: Scale(type: .major, root: .c))
        let dominantChords = try HarmonicPalette.chords(for: .dominant, in: context)

        XCTAssertEqual(dominantChords.count, 2)
        XCTAssertEqual(dominantChords[0].root, .g)  // degree 5
        XCTAssertEqual(dominantChords[1].root, .b)  // degree 7
    }

    func testHarmonicPaletteChordsForTonicRole() throws {
        let context = HarmonyContext(tonic: .c, scale: Scale(type: .major, root: .c))
        let tonicChords = try HarmonicPalette.chords(for: .tonic, in: context)

        XCTAssertEqual(tonicChords.count, 3)
        XCTAssertEqual(tonicChords[0].root, .c)  // degree 1
        XCTAssertEqual(tonicChords[1].root, .e)  // degree 3
        XCTAssertEqual(tonicChords[2].root, .a)  // degree 6
    }

    func testHarmonicPaletteNonHeptatonicScaleReturnsAllDegrees() throws {
        let customScale = Scale(intervals: [.P1, .m2, .P4, .P5], root: .d, name: "Tetrachord")
        let context = HarmonyContext(tonic: .d, scale: customScale)
        // For non-7-note scales chords() returns all degrees regardless of role.
        // We must supply an explicit chordType via role-based recipes, but HarmonicPalette
        // will throw unableToResolveChord since inference requires a heptatonic scale.
        XCTAssertThrowsError(try HarmonicPalette.diatonicTriads(in: context))
    }
}
