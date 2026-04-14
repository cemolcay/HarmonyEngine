import Foundation

public struct ProgressionStep: Hashable, Codable, Sendable {
    public let bar: Int
    public let beat: Double
    public let durationBeats: Double
    public let role: HarmonyRole?
    public let scaleDegree: Int?
    public let chordRecipe: ChordRecipe?

    public init(
        bar: Int,
        beat: Double,
        durationBeats: Double,
        role: HarmonyRole? = nil,
        scaleDegree: Int? = nil,
        chordRecipe: ChordRecipe? = nil
    ) {
        self.bar = bar
        self.beat = beat
        self.durationBeats = durationBeats
        self.role = role
        self.scaleDegree = scaleDegree
        self.chordRecipe = chordRecipe
    }
}

public struct Progression: Hashable, Codable, Sendable {
    public let steps: [ProgressionStep]
    public let loopLengthBars: Int

    public init(steps: [ProgressionStep], loopLengthBars: Int) throws {
        let sortedSteps = steps.sorted {
            if $0.bar != $1.bar { return $0.bar < $1.bar }
            return $0.beat < $1.beat
        }

        for step in sortedSteps {
            guard step.bar >= 1, step.beat >= 0, step.durationBeats > 0 else {
                throw HarmonyEngineError.invalidProgressionStep(
                    bar: step.bar,
                    beat: step.beat,
                    durationBeats: step.durationBeats
                )
            }
        }

        for pair in zip(sortedSteps, sortedSteps.dropFirst()) {
            let currentEnd = Progression.absoluteBeat(for: pair.0) + pair.0.durationBeats
            let nextStart = Progression.absoluteBeat(for: pair.1)
            guard nextStart >= currentEnd else {
                throw HarmonyEngineError.overlappingProgressionSteps
            }
        }

        self.steps = sortedSteps
        self.loopLengthBars = loopLengthBars
    }

    internal static func absoluteBeat(for step: ProgressionStep, beatsPerBar: Int = 4) -> Double {
        return (Double(step.bar - 1) * Double(beatsPerBar)) + step.beat
    }
}

