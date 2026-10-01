import XCTest
import MusicTheory
import HarmonyEngine
@testable import HarmonySuggest

/// Prints rankings for manual review. Runs only when `HARMONY_SUGGEST_DUMP=1`.
final class SuggestionDumpTests: XCTestCase {

    func testDumpRankings() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HARMONY_SUGGEST_DUMP"] == "1")
        let engine = SuggestionEngine()
        let cMajor = HarmonyContext(tonic: .c, scale: Scale(type: .major, root: .c))
        let aMinor = HarmonyContext(tonic: .a, scale: Scale(type: .minor, root: .a))

        let cases: [(String, HarmonyContext, StyleProfile, [ChordSpec], PhrasePosition?)] = [
            ("general, start", cMajor, .general, [], nil),
            ("general after I", cMajor, .general, [.degree(1)], nil),
            ("general after V7", cMajor, .general, [.degree(1), .degree(5, tension: .diatonicSeventh)], nil),
            ("general after V7/ii", cMajor, .general, [.degree(1), ChordSpec(root: .applied(.dominant, of: 2))], nil),
            ("pop after I", cMajor, .pop, [.degree(1)], nil),
            ("rock after I", cMajor, .rock, [.degree(1)], nil),
            ("jazz after ii7", cMajor, .jazz, [.degree(2, tension: .diatonicSeventh)], nil),
            ("jazz after Imaj7", cMajor, .jazz, [.degree(1, tension: .diatonicSeventh)], nil),
            ("classical after V, last step", cMajor, .classical, [.degree(4), .degree(5)], PhrasePosition(step: 2, length: 3)),
            ("general A minor after i", aMinor, .general, [.degree(1)], nil),
            ("romantic A minor after iv", aMinor, .romantic, [.degree(1), .degree(4)], nil),
        ]

        for (title, context, profile, history, position) in cases {
            let request = SuggestionRequest(context: context, profile: profile, history: history, position: position, limit: 12)
            let list = engine.suggestions(for: request)
                .map { "\($0.name.roman) \($0.name.symbol) [\($0.category.rawValue)] \(String(format: "%.2f", $0.score))" }
            print("== \(title):\n  " + list.joined(separator: "\n  "))
        }

        let generator = ProgressionGenerator()
        for profile in [StyleProfile.general, .pop, .jazz, .classical, .blues, .cinematic] {
            for seed in [UInt64(1), 2, 3] {
                let specs = generator.generate(length: 8, context: cMajor, profile: profile, seed: seed)
                let names = specs.map { (try? ChordNamer().name(spec: $0, context: cMajor).symbol) ?? "?" }
                print("-- \(profile.id) seed \(seed): \(names.joined(separator: " "))")
            }
        }
    }
}
