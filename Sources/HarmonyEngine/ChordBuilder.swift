import Foundation
import MusicTheory

/// Resolves a `ChordRecipe` into a `Chord` within a `HarmonyContext`.
public protocol ChordBuilding {
    /// Builds a `Chord` from the given recipe and harmonic context.
    ///
    /// - Parameters:
    ///   - recipe: Describes the desired root, chord quality, and tension.
    ///   - context: The harmonic environment providing scale and tonic.
    /// - Returns: A fully resolved `Chord`.
    /// - Throws: `HarmonyEngineError` if the root or chord type cannot be determined.
    func buildChord(recipe: ChordRecipe, context: HarmonyContext) throws -> Chord
}

/// Default implementation of `ChordBuilding`.
///
/// Resolution order:
/// 1. Root — from `recipe.root`, or derived from `recipe.scaleDegree` via the scale.
/// 2. Base chord type — from `recipe.chordType`, or inferred diatonically when `nil`
///    (heptatonic scales only).
/// 3. Effective tension — explicit `recipe.tensionPolicy` wins; role provides the default
///    when `tensionPolicy` is `nil`.
/// 4. Final chord type — base type with tension intervals merged in.
public struct ChordBuilder: ChordBuilding {
    public init() {}

    public func buildChord(recipe: ChordRecipe, context: HarmonyContext) throws -> Chord {
        let root = try resolveRoot(recipe: recipe, context: context)
        let baseChordType = try resolveChordType(recipe: recipe, context: context)
        let effectiveTension = effectiveTensionPolicy(recipe: recipe)
        let chordType = try applyTensionPolicy(
            effectiveTension,
            to: baseChordType,
            scaleDegree: recipe.scaleDegree,
            context: context
        )
        return Chord(type: chordType, root: root)
    }

    // MARK: - Root resolution

    private func resolveRoot(recipe: ChordRecipe, context: HarmonyContext) throws -> NoteName {
        if let root = recipe.root { return root }
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

    // MARK: - Chord type resolution

    /// Returns the explicit chord type, or infers the diatonic quality from the scale.
    /// Inference is only supported for heptatonic (7-note) scales and requires `scaleDegree`.
    /// For non-heptatonic scales, quality is inferred from pitch-class presence in the scale.
    private func resolveChordType(recipe: ChordRecipe, context: HarmonyContext) throws -> ChordType {
        if let chordType = recipe.chordType { return chordType }
        guard let scaleDegree = recipe.scaleDegree else {
            throw HarmonyEngineError.missingChordSource
        }
        guard scaleDegree >= 1, scaleDegree <= context.scale.noteNames.count else {
            throw HarmonyEngineError.invalidScaleDegree(scaleDegree)
        }
        guard context.scale.noteNames.count == 7 else {
            return inferChordType(scaleDegree: scaleDegree, scale: context.scale)
        }
        return try diatonicChordType(scaleDegree: scaleDegree, scale: context.scale, stackSize: 3)
    }

    /// Infers a chord type for non-heptatonic scales by checking which intervals
    /// are present in the scale above the given root degree.
    private func inferChordType(scaleDegree: Int, scale: Scale) -> ChordType {
        let root = scale.noteNames[scaleDegree - 1]
        let pcs = Set(scale.noteNames.map(\.pitchClass))
        let r = root.pitchClass
        let hasMin3 = pcs.contains((r + 3) % 12)
        let hasMaj3 = pcs.contains((r + 4) % 12)
        let hasDim5 = pcs.contains((r + 6) % 12) && !pcs.contains((r + 7) % 12)
        let hasP5   = pcs.contains((r + 7) % 12)
        var components = Set<ChordComponent>()
        if hasMin3      { components.insert(.minorThird) }
        else if hasMaj3 { components.insert(.majorThird) }
        if hasDim5      { components.insert(.diminishedFifth) }
        else if hasP5   { components.insert(.perfectFifth) }
        return ChordType(components: components) ?? (hasMin3 ? .minor : .major)
    }

    // MARK: - Tension policy

    /// Resolves the effective tension policy.
    /// An explicit `tensionPolicy` in the recipe always wins (even `TensionPolicy.none`).
    /// When `tensionPolicy` is `nil`, the role provides the default.
    /// Falls back to `.none` when neither is set.
    private func effectiveTensionPolicy(recipe: ChordRecipe) -> TensionPolicy {
        if let explicit = recipe.tensionPolicy { return explicit }
        guard let role = recipe.role, recipe.scaleDegree != nil else { return .none }
        switch role {
        case .dominant: return .diatonicSeventh
        case .color:    return .diatonicExtensions(maxDegree: 9)
        default:        return .none
        }
    }

    private func applyTensionPolicy(
        _ policy: TensionPolicy,
        to baseChordType: ChordType,
        scaleDegree: Int?,
        context: HarmonyContext
    ) throws -> ChordType {
        switch policy {
        case .none:
            return baseChordType
        case .custom(let intervals):
            return try rebuildChordType(baseIntervals: baseChordType.intervals, extraIntervals: intervals)
        case .diatonicSeventh:
            guard let scaleDegree = scaleDegree,
                  context.scale.noteNames.count == 7 else { return baseChordType }
            let extra = try diatonicIntervals(scaleDegree: scaleDegree, scale: context.scale, stackSize: 4)
            return try rebuildChordType(baseIntervals: baseChordType.intervals, extraIntervals: extra)
        case .diatonicExtensions(let maxDegree):
            guard let scaleDegree = scaleDegree,
                  context.scale.noteNames.count == 7 else { return baseChordType }
            let stackSize: Int
            switch maxDegree {
            case ..<7:    return baseChordType
            case 7..<9:   stackSize = 4
            case 9..<11:  stackSize = 5
            case 11..<13: stackSize = 6
            default:      stackSize = 7
            }
            let extra = try diatonicIntervals(scaleDegree: scaleDegree, scale: context.scale, stackSize: stackSize)
            return try rebuildChordType(baseIntervals: baseChordType.intervals, extraIntervals: extra)
        }
    }

    private func rebuildChordType(baseIntervals: [Interval], extraIntervals: [Interval]) throws -> ChordType {
        let merged = Array(Set(baseIntervals + extraIntervals)).sorted()
        switch ChordType.from(intervals: merged) {
        case let .success(chordType): return chordType
        case .failure:                throw HarmonyEngineError.unableToResolveChord
        }
    }

    // MARK: - Diatonic interval stacking

    private func diatonicChordType(scaleDegree: Int, scale: Scale, stackSize: Int) throws -> ChordType {
        let intervals = try diatonicIntervals(scaleDegree: scaleDegree, scale: scale, stackSize: stackSize)
        switch ChordType.from(intervals: intervals) {
        case let .success(chordType): return chordType
        case .failure:                throw HarmonyEngineError.unableToResolveChord
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
        var floorMidi = rootPitch.midiNoteNumber

        for stackIndex in 1..<stackSize {
            let targetIndex = rootIndex + (stackIndex * 2)
            let target = noteNames[targetIndex % noteNames.count]
            // Start from an octave estimate based on full scale-cycle wraps, then
            // bump up until the target sits strictly above the previous voice.
            // This is correct for any scale size, not just heptatonic.
            var octave = rootPitch.octave + (targetIndex / noteNames.count)
            var candidate = Pitch(noteName: target, octave: octave)
            while candidate.midiNoteNumber <= floorMidi {
                octave += 1
                candidate = Pitch(noteName: target, octave: octave)
            }
            floorMidi = candidate.midiNoteNumber
            intervals.append(rootPitch.interval(to: candidate))
        }

        return intervals
    }
}
