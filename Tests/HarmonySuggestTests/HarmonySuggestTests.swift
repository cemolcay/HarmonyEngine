import XCTest
import MusicTheory
import HarmonyEngine
@testable import HarmonySuggest

final class HarmonySuggestTests: XCTestCase {

    private let engine = SuggestionEngine()
    private let cMajor = HarmonyContext(tonic: .c, scale: Scale(type: .major, root: .c))
    private let aMinor = HarmonyContext(tonic: .a, scale: Scale(type: .minor, root: .a))

    private func suggestions(
        _ profile: StyleProfile,
        in context: HarmonyContext? = nil,
        after history: [ChordSpec] = [],
        position: PhrasePosition? = nil,
        knobs: SuggestionKnobs = SuggestionKnobs(),
        limit: Int = 24
    ) -> [Suggestion] {
        engine.suggestions(for: SuggestionRequest(
            context: context ?? cMajor,
            profile: profile,
            history: history,
            position: position,
            knobs: knobs,
            limit: limit
        ))
    }

    // MARK: - Profiles

    func testAllHarmoniccStylesArePresent() {
        XCTAssertEqual(StyleProfile.all.count, 32)
        XCTAssertEqual(Set(StyleProfile.all.map(\.id)).count, 32)
        XCTAssertEqual(StyleProfile.named("rAndB")?.name, "R&B")
        XCTAssertEqual(StyleProfile.named("general")?.name, "General")
        XCTAssertNil(StyleProfile.named("unknown"))
    }

    func testProfileCodableRoundTrip() throws {
        for profile in StyleProfile.all {
            let data = try JSONEncoder().encode(profile)
            XCTAssertEqual(try JSONDecoder().decode(StyleProfile.self, from: data), profile, profile.id)
        }
    }

    // MARK: - Properties over all styles, scales, and keys

    func testSuggestionsAreValidForEveryStyleScaleAndKey() throws {
        let scales: [ScaleType] = [.major, .minor, .dorian, .mixolydian, .harmonicMinor, .pentatonicMajor]
        let roots: [NoteName] = [.c, .fs, .bb]
        for profile in StyleProfile.all {
            for scaleType in scales {
                for root in roots {
                    let context = HarmonyContext(tonic: root, scale: Scale(type: scaleType, root: root))
                    for history in [[], [ChordSpec.degree(1)]] {
                        let list = suggestions(profile, in: context, after: history, limit: 40)
                        let label = "\(profile.id) \(root) \(scaleType) after \(history.count)"
                        XCTAssertFalse(list.isEmpty, label)

                        // Diatonic and color chords use only scale notes. Chromatic chords do not.
                        for suggestion in list {
                            let fits = ScaleFit.isDiatonic(suggestion.chord, in: context.scale)
                            XCTAssertEqual(fits, suggestion.category != .chromatic, "\(label): \(suggestion.name.symbol)")
                        }

                        // No two suggestions sound the same.
                        let sounds = list.map { SoundKey($0.chord) }
                        XCTAssertEqual(Set(sounds).count, sounds.count, label)

                        // The ranking is sorted.
                        XCTAssertEqual(list.map(\.score), list.map(\.score).sorted(by: >), label)
                    }
                }
            }
        }
    }

    func testRankingIsDeterministic() {
        let history: [ChordSpec] = [.degree(1), .degree(4, tension: .diatonicSeventh)]
        XCTAssertEqual(suggestions(.jazz, after: history), suggestions(.jazz, after: history))
    }

    // MARK: - Harmonic behavior

    func testAppliedDominantResolvesToItsTarget() {
        let top = suggestions(.general, after: [.degree(1), ChordSpec(root: .applied(.dominant, of: 2))]).first
        XCTAssertEqual(top?.chord.root, .d)
        XCTAssertEqual(top?.reasons.first, .resolves(to: 2))
    }

    func testRelatedTwoPreparesItsDominant() {
        let top = suggestions(.jazz, after: [.degree(1, tension: .diatonicSeventh), ChordSpec(root: .applied(.supertonic, of: 2))]).first
        XCTAssertEqual(top?.spec.root, .applied(.dominant, of: 2))
    }

    func testNeapolitanResolvesToDominant() {
        let top = suggestions(.romantic, in: aMinor, after: [.degree(1), ChordSpec(root: .neapolitan, bass: .inversion(1))]).first
        XCTAssertEqual(top?.chord.root, .e)
    }

    func testDominantMovesToTonicInCommonPractice() {
        for profile in [StyleProfile.general, .classical, .baroque, .pop] {
            let list = suggestions(profile, after: [.degree(4), .degree(5)])
            XCTAssertEqual(list.first?.chord.root, .c, profile.id)
        }
    }

    func testTwoFiveInJazz() {
        let top = suggestions(.jazz, after: [.degree(2, tension: .diatonicSeventh)]).first
        XCTAssertEqual(top?.chord, Chord(type: .dominant7, root: .g))
    }

    func testCadenceAtTheEndOfAPhrase() {
        let top = suggestions(.classical, after: [.degree(4), .degree(5)], position: PhrasePosition(step: 2, length: 3)).first
        XCTAssertEqual(top?.chord, Chord(type: .major, root: .c))
        XCTAssertTrue(top?.reasons.contains(.cadence) ?? false)
    }

    func testMinorKeysOfferTheHarmonicMinorDominant() {
        let list = suggestions(.general, in: aMinor, after: [.degree(1), .degree(4)])
        XCTAssertTrue(list.contains { $0.chord == Chord(type: .major, root: .e) })
        XCTAssertTrue(list.contains { $0.chord == Chord(type: .dominant7, root: .e) })
    }

    func testBluesUsesDominantSevenths() {
        let list = suggestions(.blues, after: [ChordSpec(root: .degree(1), type: .dominant7)])
        let top3 = list.prefix(3).map(\.chord)
        XCTAssertTrue(top3.contains(Chord(type: .dominant7, root: .f)), "\(top3)")
    }

    func testRockOffersBorrowedChords() {
        let list = suggestions(.rock, after: [.degree(1)], limit: 40)
        let flatSix = list.first { $0.chord == Chord(type: .major, root: .ab) }
        XCTAssertNotNil(flatSix)
        XCTAssertEqual(flatSix?.name.roman, "♭VI")
        XCTAssertEqual(flatSix?.category, .chromatic)
    }

    func testRepeatingTheCurrentChordIsNotFirst() {
        for profile in StyleProfile.all {
            let top = suggestions(profile, after: [.degree(1)]).first
            XCTAssertNotEqual(top?.chord, Chord(type: .major, root: .c), profile.id)
        }
    }

    // MARK: - Knobs

    func testZeroChromaticismRemovesChromaticChords() {
        for profile in StyleProfile.all {
            let list = suggestions(profile, after: [.degree(1)], knobs: SuggestionKnobs(chromaticism: 0), limit: 60)
            XCTAssertFalse(list.contains { $0.category == .chromatic }, profile.id)
        }
    }

    func testComplexityKnob() {
        func averageComplexity(_ profile: StyleProfile, _ complexity: Double) -> Double {
            let top = suggestions(profile, after: [.degree(1)], knobs: SuggestionKnobs(complexity: complexity)).prefix(5)
            return top.map { SuggestionEngine.complexity(of: $0.chord.type) }.reduce(0, +) / Double(top.count)
        }
        for profile in [StyleProfile.jazz, .general, .pop] {
            let simple = averageComplexity(profile, 0)
            let neutral = averageComplexity(profile, 0.5)
            let complex = averageComplexity(profile, 1)
            XCTAssertLessThan(simple, neutral, profile.id)
            XCTAssertLessThan(neutral, complex, profile.id)
        }
    }

    func testBrightnessKnob() {
        let history: [ChordSpec] = [.degree(1)]
        func majorShare(_ brightness: Double) -> Int {
            suggestions(.pop, after: history, knobs: SuggestionKnobs(brightness: brightness)).prefix(6)
                .filter { $0.chord.type.components.contains(.majorThird) }.count
        }
        XCTAssertGreaterThan(majorShare(1), majorShare(0))
    }

    // MARK: - Progression generator

    func testGeneratorIsDeterministicAndEndsOnTonic() throws {
        let generator = ProgressionGenerator()
        for profile in [StyleProfile.general, .pop, .jazz, .classical, .blues, .rock] {
            for seed in [UInt64(1), 7, 42] {
                let first = generator.generate(length: 8, context: cMajor, profile: profile, seed: seed)
                let second = generator.generate(length: 8, context: cMajor, profile: profile, seed: seed)
                XCTAssertEqual(first, second, profile.id)
                XCTAssertEqual(first.count, 8, profile.id)
                let last = try XCTUnwrap(first.last)
                XCTAssertEqual(try ChordBuilder().buildChord(spec: last, context: cMajor).root, .c, "\(profile.id) seed \(seed)")
            }
        }
    }

    func testGeneratorSeedsGiveVariety() {
        let generator = ProgressionGenerator()
        let progressions = Set((0..<10).map {
            generator.generate(length: 8, context: cMajor, profile: .general, seed: UInt64($0), temperature: 2)
        })
        XCTAssertGreaterThan(progressions.count, 1)
    }

    func testGeneratorKeepsStartChords() {
        let start: [ChordSpec] = [.degree(6), .degree(4)]
        let progression = ProgressionGenerator().generate(length: 4, context: cMajor, profile: .pop, seed: 3, start: start)
        XCTAssertEqual(Array(progression.prefix(2)), start)
        XCTAssertEqual(progression.count, 4)
    }

    func testGeneratorWorksInEveryStyleAndMinorKey() {
        let generator = ProgressionGenerator()
        for profile in StyleProfile.all {
            let progression = generator.generate(length: 6, context: aMinor, profile: profile, seed: 5)
            XCTAssertEqual(progression.count, 6, profile.id)
            XCTAssertTrue(progression.allSatisfy { (try? ChordBuilder().buildChord(spec: $0, context: aMinor)) != nil }, profile.id)
        }
    }
}
