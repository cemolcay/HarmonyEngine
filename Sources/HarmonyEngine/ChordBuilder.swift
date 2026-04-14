import Foundation
import MusicTheory

public protocol ChordBuilding {
    func buildChord(step: ProgressionStep, context: HarmonyContext) throws -> Chord
}

public struct ChordBuilder: ChordBuilding {
    public init() {}

    public func buildChord(step: ProgressionStep, context: HarmonyContext) throws -> Chord {
        if let recipe = step.chordRecipe {
            let root = try resolveRoot(recipe: recipe, context: context)
            let chordType = try applyTensionPolicy(
                recipe.tensionPolicy,
                to: recipe.chordType,
                root: root,
                scaleDegree: recipe.scaleDegree,
                context: context
            )
            return Chord(type: chordType, root: root)
        }

        guard let scaleDegree = step.scaleDegree else {
            throw HarmonyEngineError.missingChordSource
        }

        let root = try noteName(for: scaleDegree, in: context.scale)
        let chordType = try diatonicChordType(scaleDegree: scaleDegree, scale: context.scale, stackSize: 3)
        return Chord(type: chordType, root: root)
    }

    private func resolveRoot(recipe: ChordRecipe, context: HarmonyContext) throws -> NoteName {
        if let root = recipe.root {
            return root
        }
        if let scaleDegree = recipe.scaleDegree {
            return try noteName(for: scaleDegree, in: context.scale)
        }
        throw HarmonyEngineError.missingChordSource
    }

    private func noteName(for scaleDegree: Int, in scale: Scale) throws -> NoteName {
        let noteNames = scale.noteNames
        guard scaleDegree >= 1, scaleDegree <= noteNames.count else {
            throw HarmonyEngineError.invalidScaleDegree(scaleDegree)
        }
        return noteNames[scaleDegree - 1]
    }

    private func diatonicChordType(scaleDegree: Int, scale: Scale, stackSize: Int) throws -> ChordType {
        let intervals = try diatonicIntervals(scaleDegree: scaleDegree, scale: scale, stackSize: stackSize)
        switch ChordType.from(intervals: intervals) {
        case let .success(chordType):
            return chordType
        case .failure:
            throw HarmonyEngineError.unableToResolveChord
        }
    }

    private func diatonicIntervals(scaleDegree: Int, scale: Scale, stackSize: Int) throws -> [Interval] {
        let noteNames = scale.noteNames
        guard scaleDegree >= 1, scaleDegree <= noteNames.count else {
            throw HarmonyEngineError.invalidScaleDegree(scaleDegree)
        }

        let rootIndex = scaleDegree - 1
        let root = noteNames[rootIndex]
        let rootPitch = Pitch(noteName: root, octave: 4)
        var intervals = [Interval.P1]

        if stackSize <= 1 {
            return intervals
        }

        for stackIndex in 1..<stackSize {
            let targetIndex = rootIndex + (stackIndex * 2)
            let target = noteNames[targetIndex % noteNames.count]
            let octaveOffset = octaveDiffUp(from: root.letter, steps: stackIndex * 2)
            let targetPitch = Pitch(noteName: target, octave: rootPitch.octave + octaveOffset)
            let interval = rootPitch.interval(to: targetPitch)

            intervals.append(interval)
        }

        return intervals
    }

    private func applyTensionPolicy(
        _ policy: TensionPolicy,
        to baseChordType: ChordType,
        root: NoteName,
        scaleDegree: Int?,
        context: HarmonyContext
    ) throws -> ChordType {
        switch policy {
        case .none:
            return baseChordType
        case .custom(let intervals):
            return try rebuildChordType(baseIntervals: baseChordType.intervals, extraIntervals: intervals)
        case .diatonicSeventh:
            guard let scaleDegree = scaleDegree else {
                return baseChordType
            }
            let extra = try diatonicIntervals(scaleDegree: scaleDegree, scale: context.scale, stackSize: 4)
            return try rebuildChordType(baseIntervals: baseChordType.intervals, extraIntervals: extra)
        case .diatonicExtensions(let maxDegree):
            guard let scaleDegree = scaleDegree else {
                return baseChordType
            }
            let stackSize: Int
            switch maxDegree {
            case ..<7:
                return baseChordType
            case 7..<9:
                stackSize = 4
            case 9..<11:
                stackSize = 5
            case 11..<13:
                stackSize = 6
            default:
                stackSize = 7
            }
            let extra = try diatonicIntervals(scaleDegree: scaleDegree, scale: context.scale, stackSize: stackSize)
            return try rebuildChordType(baseIntervals: baseChordType.intervals, extraIntervals: extra)
        }
    }

    private func rebuildChordType(baseIntervals: [Interval], extraIntervals: [Interval]) throws -> ChordType {
        let merged = Array(Set(baseIntervals + extraIntervals)).sorted()
        switch ChordType.from(intervals: merged) {
        case let .success(chordType):
            return chordType
        case .failure:
            throw HarmonyEngineError.unableToResolveChord
        }
    }
    private func octaveDiffUp(from letter: LetterName, steps: Int) -> Int {
        var diff = 0
        var current = letter
        for _ in 0..<steps {
            let next = current.advanced(by: 1)
            if current == .b && next == .c {
                diff += 1
            }
            current = next
        }
        return diff
    }
}
