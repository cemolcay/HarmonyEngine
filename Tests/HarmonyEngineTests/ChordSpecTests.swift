import XCTest
import MusicTheory
@testable import HarmonyEngine

final class ChordSpecTests: XCTestCase {

    private let cMajor = HarmonyContext(tonic: .c, scale: Scale(type: .major, root: .c))
    private let aMinor = HarmonyContext(tonic: .a, scale: Scale(type: .minor, root: .a))
    private let builder = ChordBuilder()
    private let namer = ChordNamer()

    private static let heptatonicScales: [ScaleType] = [
        .major, .minor, .dorian, .phrygian, .lydian, .mixolydian, .locrian,
        .harmonicMinor, .melodicMinor, .harmonicMajor, .lydianDominant, .phrygianDominant,
    ]

    private func pitchClasses(_ chord: Chord) -> Set<Int> {
        ScaleFit.pitchClasses(of: chord)
    }

    private func name(_ spec: ChordSpec, in context: HarmonyContext) throws -> ChordName {
        try namer.name(spec: spec, context: context)
    }

    // MARK: - Diatonic chords in every scale and key

    func testDiatonicTriadsAndSeventhsFitEveryHeptatonicScaleInEveryKey() throws {
        for scaleType in Self.heptatonicScales {
            for root in NoteName.chromaticWithFlats {
                let context = HarmonyContext(tonic: root, scale: Scale(type: scaleType, root: root))
                for degree in 1...7 {
                    for tension in [TensionPolicy.none, .diatonicSeventh] {
                        let chord = try builder.buildChord(spec: .degree(degree, tension: tension), context: context)
                        XCTAssertTrue(
                            ScaleFit.isDiatonic(chord, in: context.scale),
                            "\(root) \(scaleType) degree \(degree) \(tension): \(chord.notation)"
                        )
                        XCTAssertEqual(chord.root, context.scale.noteNames[degree - 1])
                    }
                }
            }
        }
    }

    func testMinorSeventhDegreeUsesCorrectOctave() throws {
        // The octave of the stacked third was wrong for G in A minor (B5 instead of B4).
        let chord = try builder.buildChord(spec: .degree(7, tension: .diatonicSeventh), context: aMinor)
        XCTAssertEqual(chord.root, .g)
        XCTAssertEqual(chord.type, .dominant7)
    }

    // MARK: - Avoid notes

    func testDiatonicThirteenthOmitsAvoidNotes() throws {
        let tonic = try builder.buildChord(spec: .degree(1, tension: .diatonicExtensions(maxDegree: 13)), context: cMajor)
        XCTAssertTrue(tonic.type.components.contains(.thirteenth))
        XCTAssertFalse(tonic.type.components.contains(.eleventh), "The natural 11 clashes with the major 3rd")

        let mediant = try builder.buildChord(spec: .degree(3, tension: .diatonicExtensions(maxDegree: 13)), context: cMajor)
        XCTAssertFalse(mediant.type.components.contains(.flatNinth))
        XCTAssertFalse(mediant.type.components.contains(.flatThirteenth))
        XCTAssertTrue(mediant.type.components.contains(.eleventh))

        let harmonicMinor = HarmonyContext(tonic: .a, scale: Scale(type: .harmonicMinor, root: .a))
        let dominant = try builder.buildChord(spec: .degree(5, tension: .diatonicExtensions(maxDegree: 13)), context: harmonicMinor)
        XCTAssertTrue(dominant.type.components.contains(.flatNinth), "♭9 is a valid tension on a dominant 7th")
        XCTAssertTrue(dominant.type.components.contains(.flatThirteenth))
    }

    func testKeepAvoidNotesPolicyKeepsEleventh() throws {
        let chord = try ChordBuilder(avoidNotes: .keep)
            .buildChord(spec: .degree(1, tension: .diatonicExtensions(maxDegree: 11)), context: cMajor)
        XCTAssertTrue(chord.type.components.contains(.eleventh))
    }

    // MARK: - Chromatic roots

    func testBorrowedChordsFromParallelMinor() throws {
        let flatSeven = ChordSpec(root: .borrowed(degree: 7, from: .minor))
        XCTAssertEqual(try builder.buildChord(spec: flatSeven, context: cMajor), Chord(type: .major, root: .bb))
        XCTAssertEqual(try name(flatSeven, in: cMajor).roman, "♭VII")

        let flatSix = ChordSpec(root: .borrowed(degree: 6, from: .minor))
        XCTAssertEqual(try name(flatSix, in: cMajor).roman, "♭VI")

        let minorFour = ChordSpec(root: .borrowed(degree: 4, from: .minor))
        XCTAssertEqual(try builder.buildChord(spec: minorFour, context: cMajor), Chord(type: .minor, root: .f))
        XCTAssertEqual(try name(minorFour, in: cMajor).roman, "iv")
    }

    func testAlteredDegreeNeedsExplicitType() throws {
        let spec = ChordSpec(root: .degree(7, alteration: -1))
        XCTAssertThrowsError(try builder.buildChord(spec: spec, context: cMajor)) { error in
            XCTAssertEqual(error as? HarmonyEngineError, .missingChordType)
        }

        let typed = ChordSpec(root: .degree(7, alteration: -1), type: .major)
        XCTAssertEqual(try builder.buildChord(spec: typed, context: cMajor), Chord(type: .major, root: .bb))
    }

    func testAppliedChords() throws {
        let fiveOfTwo = ChordSpec(root: .applied(.dominant, of: 2))
        XCTAssertEqual(try builder.buildChord(spec: fiveOfTwo, context: cMajor), Chord(type: .dominant7, root: .a))
        XCTAssertEqual(try name(fiveOfTwo, in: cMajor).roman, "V7/ii")
        XCTAssertEqual(fiveOfTwo.root.resolutionTarget, 2)

        let sevenOfFive = ChordSpec(root: .applied(.leadingTone, of: 5))
        XCTAssertEqual(try builder.buildChord(spec: sevenOfFive, context: cMajor), Chord(type: .diminished7, root: .fs))
        XCTAssertEqual(try name(sevenOfFive, in: cMajor).roman, "vii°7/V")

        let subFiveOfOne = ChordSpec(root: .applied(.tritoneSubstitute, of: 1))
        XCTAssertEqual(try builder.buildChord(spec: subFiveOfOne, context: cMajor), Chord(type: .dominant7, root: .db))
        XCTAssertEqual(try name(subFiveOfOne, in: cMajor).roman, "subV7/I")

        let twoOfFive = ChordSpec(root: .applied(.supertonic, of: 5))
        XCTAssertEqual(try builder.buildChord(spec: twoOfFive, context: cMajor), Chord(type: .minor7, root: .a))
        XCTAssertEqual(try name(twoOfFive, in: cMajor).roman, "ii7/V")

        // The related ii of a minor target is half-diminished.
        let twoOfTwo = ChordSpec(root: .applied(.supertonic, of: 2))
        XCTAssertEqual(try builder.buildChord(spec: twoOfTwo, context: cMajor), Chord(type: .halfDiminished7, root: .e))
        XCTAssertEqual(try name(twoOfTwo, in: cMajor).roman, "iiø7/ii")
    }

    func testNeapolitanAugmentedSixthsAndCommonToneDiminished() throws {
        let neapolitan = ChordSpec(root: .neapolitan, bass: .inversion(1))
        let neapolitanChord = try builder.buildChord(spec: neapolitan, context: cMajor)
        XCTAssertEqual(neapolitanChord.root, .db)
        XCTAssertEqual(neapolitanChord.inversion, 1)
        XCTAssertEqual(try name(neapolitan, in: cMajor).roman, "N6")
        XCTAssertEqual(neapolitan.root.resolutionTarget, 5)

        XCTAssertEqual(pitchClasses(try builder.buildChord(spec: ChordSpec(root: .augmentedSixth(.italian)), context: cMajor)), [8, 0, 6])
        XCTAssertEqual(pitchClasses(try builder.buildChord(spec: ChordSpec(root: .augmentedSixth(.french)), context: cMajor)), [8, 0, 2, 6])
        XCTAssertEqual(pitchClasses(try builder.buildChord(spec: ChordSpec(root: .augmentedSixth(.german)), context: cMajor)), [8, 0, 3, 6])
        XCTAssertEqual(try name(ChordSpec(root: .augmentedSixth(.german)), in: cMajor).roman, "Ger+6")

        let commonTone = ChordSpec(root: .commonToneDiminished(of: 1))
        XCTAssertEqual(pitchClasses(try builder.buildChord(spec: commonTone, context: cMajor)), [0, 3, 6, 9])
        XCTAssertEqual(try name(commonTone, in: cMajor).roman, "CT°7/I")
    }

    func testDiatonicTensionOnChromaticRootThrows() {
        let spec = ChordSpec(root: .applied(.dominant, of: 5), tension: .diatonicSeventh)
        XCTAssertThrowsError(try builder.buildChord(spec: spec, context: cMajor)) { error in
            XCTAssertEqual(error as? HarmonyEngineError, .unableToResolveChord)
        }
    }

    func testSlashBassAndInvalidInversion() throws {
        let slash = ChordSpec(root: .degree(1), bass: .scaleDegree(3))
        let chord = try builder.buildChord(spec: slash, context: cMajor)
        XCTAssertEqual(chord.bass, .e)
        let voiced = try VoiceLeadingEngine().voice(chord: chord, previous: nil, context: cMajor, policy: .nearest)
        XCTAssertEqual(voiced.bassVoice.noteName, .e)

        XCTAssertThrowsError(try builder.buildChord(spec: ChordSpec(root: .degree(1), bass: .inversion(3)), context: cMajor)) { error in
            XCTAssertEqual(error as? HarmonyEngineError, .invalidInversion(3))
        }
    }

    // MARK: - Names

    func testDiatonicRomanNumerals() throws {
        let triads = try (1...7).map { try name(.degree($0), in: cMajor).roman }
        XCTAssertEqual(triads, ["I", "ii", "iii", "IV", "V", "vi", "vii°"])

        let sevenths = try (1...7).map { try name(.degree($0, tension: .diatonicSeventh), in: cMajor).roman }
        XCTAssertEqual(sevenths, ["Imaj7", "ii7", "iii7", "IVmaj7", "V7", "vi7", "viiø7"])

        let minorTriads = try (1...7).map { try name(.degree($0), in: aMinor).roman }
        XCTAssertEqual(minorTriads, ["i", "ii°", "III", "iv", "v", "VI", "VII"])

        let harmonicMinor = HarmonyContext(tonic: .a, scale: Scale(type: .harmonicMinor, root: .a))
        XCTAssertEqual(try name(.degree(5, tension: .diatonicSeventh), in: harmonicMinor).roman, "V7")
        XCTAssertEqual(try name(.degree(3), in: harmonicMinor).roman, "III+")
    }

    func testInversionFiguresAndExtensions() throws {
        XCTAssertEqual(try name(ChordSpec(root: .degree(1), bass: .inversion(2)), in: cMajor).roman, "I64")
        XCTAssertEqual(try name(ChordSpec(root: .degree(5), tension: .diatonicSeventh, bass: .inversion(1)), in: cMajor).roman, "V65")
        XCTAssertEqual(try name(.degree(1, tension: .diatonicExtensions(maxDegree: 9)), in: cMajor).roman, "Imaj9")
        XCTAssertEqual(
            try name(ChordSpec(root: .degree(1), tension: .diatonicExtensions(maxDegree: 9), bass: .inversion(1)), in: cMajor).roman,
            "Imaj9",
            "Extended chords do not get a figure"
        )
    }

    func testChordSymbols() throws {
        XCTAssertEqual(try name(ChordSpec(root: .applied(.dominant, of: 2)), in: cMajor).symbol, "A7")
        XCTAssertEqual(try name(ChordSpec(root: .borrowed(degree: 7, from: .minor)), in: cMajor).symbol, Chord(type: .major, root: .bb).notation)
    }

    // MARK: - Golden progressions

    func testCreedenceProgressionInC() throws {
        let specs = [ChordSpec.degree(1), ChordSpec(root: .borrowed(degree: 7, from: .minor)), .degree(4)]
        let chords = try specs.map { try builder.buildChord(spec: $0, context: cMajor) }
        XCTAssertEqual(chords, [Chord(type: .major, root: .c), Chord(type: .major, root: .bb), Chord(type: .major, root: .f)])
    }

    func testAndalusianCadenceInAMinor() throws {
        let specs = [ChordSpec.degree(1), .degree(7), .degree(6), .degree(5, type: .major)]
        let chords = try specs.map { try builder.buildChord(spec: $0, context: aMinor) }
        XCTAssertEqual(chords, [
            Chord(type: .minor, root: .a), Chord(type: .major, root: .g),
            Chord(type: .major, root: .f), Chord(type: .major, root: .e),
        ])
        XCTAssertEqual(try specs.map { try name($0, in: aMinor).roman }, ["i", "VII", "VI", "V"])
    }

    func testColtraneChangesInC() throws {
        let specs = [
            ChordSpec.degree(1, type: .major7),
            ChordSpec(root: .borrowed(degree: 3, from: .minor), type: .dominant7),
            ChordSpec(root: .borrowed(degree: 6, from: .minor), type: .major7),
        ]
        let chords = try specs.map { try builder.buildChord(spec: $0, context: cMajor) }
        XCTAssertEqual(chords.map(\.root), [.c, .eb, .ab])
        XCTAssertEqual(try specs.map { try name($0, in: cMajor).roman }, ["Imaj7", "♭III7", "♭VImaj7"])
    }

    // MARK: - Non-heptatonic scales

    func testPentatonicInferenceAndNumerals() throws {
        let pentatonic = HarmonyContext(tonic: .c, scale: Scale(type: .pentatonicMajor, root: .c))
        let sixth = try builder.buildChord(spec: .degree(5), context: pentatonic)
        XCTAssertEqual(sixth, Chord(type: .minor, root: .a))
        XCTAssertEqual(try name(.degree(5), in: pentatonic).roman, "vi")

        // D has no third in C major pentatonic, so there is no fallback.
        XCTAssertThrowsError(try builder.buildChord(spec: .degree(2), context: pentatonic))
    }

    // MARK: - Metrics

    func testTransitionMetrics() throws {
        let tonic = Chord(type: .major, root: .c)
        let dominant = Chord(type: .dominant7, root: .g)
        let metrics = TransitionMetrics(from: tonic, to: dominant, scale: cMajor.scale)
        XCTAssertEqual(metrics.rootMotion, 7)
        XCTAssertEqual(metrics.rootMotionClass, 5)
        XCTAssertEqual(metrics.commonTones, 1)
        XCTAssertEqual(metrics.tension, 1)
        XCTAssertEqual(metrics.tensionChange, 1)
        XCTAssertEqual(metrics.outsideNotes, 0)
        XCTAssertEqual(metrics.voiceLeadingDistance, 4)

        let applied = try builder.buildChord(spec: ChordSpec(root: .applied(.dominant, of: 2)), context: cMajor)
        XCTAssertEqual(TransitionMetrics(from: tonic, to: applied, scale: cMajor.scale).outsideNotes, 1)
    }

    func testVoiceLeadingDistance() {
        XCTAssertEqual(VoiceLeadingDistance.between([60, 64, 67], [59, 65, 67]), 2)
        XCTAssertEqual(VoiceLeadingDistance.between([60, 64, 67], [60, 64, 67, 70]), 3)
        XCTAssertEqual(VoiceLeadingDistance.between([60, 64, 67, 70], [60, 64, 67]), 3)
    }
}
