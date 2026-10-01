import Foundation
import MusicTheory

/// Checks how well a chord fits a scale.
public enum ScaleFit {
    /// The pitch classes (0–11) of the chord, including a slash bass.
    public static func pitchClasses(of chord: Chord) -> Set<Int> {
        var pitchClasses = Set(chord.noteNames.map(\.pitchClass))
        if let bass = chord.bass { pitchClasses.insert(bass.pitchClass) }
        return pitchClasses
    }

    /// The pitch classes of the chord that are not in the scale.
    public static func outsidePitchClasses(of chord: Chord, in scale: Scale) -> Set<Int> {
        pitchClasses(of: chord).subtracting(scale.noteNames.map(\.pitchClass))
    }

    /// Returns `true` when every note of the chord is in the scale.
    public static func isDiatonic(_ chord: Chord, in scale: Scale) -> Bool {
        outsidePitchClasses(of: chord, in: scale).isEmpty
    }
}

/// The distance in semitones that the voices move from one chord to the next.
public enum VoiceLeadingDistance {
    /// The total voice movement between two voicings, in semitones.
    ///
    /// - Same voice count: the sum of the moves of the sorted voices (the best move without voice crossing).
    /// - Different voice counts: the smallest total move when a voice can split into two voices or two voices
    ///   can merge into one, without voice crossing.
    public static func between(_ source: [Int], _ target: [Int]) -> Int {
        let a = source.sorted()
        let b = target.sorted()
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        if a.count == b.count {
            return zip(a, b).reduce(0) { $0 + abs($1.0 - $1.1) }
        }

        // Dynamic programming over the two sorted voice lists.
        var cost = Array(repeating: Array(repeating: Int.max, count: b.count), count: a.count)
        for i in a.indices {
            for j in b.indices {
                let move = abs(a[i] - b[j])
                if i == 0, j == 0 {
                    cost[i][j] = move
                    continue
                }
                var best = Int.max
                if i > 0 { best = min(best, cost[i - 1][j]) }
                if j > 0 { best = min(best, cost[i][j - 1]) }
                if i > 0, j > 0 { best = min(best, cost[i - 1][j - 1]) }
                cost[i][j] = best + move
            }
        }
        return cost[a.count - 1][b.count - 1]
    }

    /// The pitch-class distance from one chord to the next.
    ///
    /// For each note of `target`, it takes the smallest move (0–6 semitones) from any note of `source`,
    /// and adds them. It does not depend on the register.
    public static func between(_ source: Set<Int>, _ target: Set<Int>) -> Int {
        guard !source.isEmpty else { return 0 }
        return target.reduce(0) { total, pitchClass in
            total + source.map { circularDistance($0, pitchClass) }.min()!
        }
    }

    static func circularDistance(_ a: Int, _ b: Int) -> Int {
        let difference = abs(a - b) % 12
        return min(difference, 12 - difference)
    }
}
