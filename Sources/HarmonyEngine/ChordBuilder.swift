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

/// Controls what happens to avoid notes when diatonic extensions are stacked.
public enum AvoidNotePolicy: Hashable, Codable, Sendable {
    /// Keep every stacked extension.
    case keep
    /// Remove the common avoid notes:
    /// - the natural 11th over a major 3rd,
    /// - the ♭9th over a chord that is not a dominant 7th,
    /// - the ♭13th over a chord with a perfect 5th that is not a dominant 7th.
    case omit
}

/// Default implementation of `ChordBuilding`.
///
/// Resolution order:
/// 1. Root — from `recipe.root`, or derived from `recipe.scaleDegree` via the scale.
/// 2. Base chord type — from `recipe.chordType`, or inferred diatonically when `nil`.
/// 3. Effective tension — explicit `recipe.tensionPolicy` wins; role provides the default
///    when `tensionPolicy` is `nil`.
/// 4. Final chord type — base type with tension intervals merged in.
///
/// The builder also resolves a `ChordSpec` (see `buildChord(spec:context:)`).
public struct ChordBuilder: ChordBuilding, Sendable {
    /// What to do with avoid notes when `TensionPolicy.diatonicExtensions` stacks thirds.
    public var avoidNotes: AvoidNotePolicy

    public init(avoidNotes: AvoidNotePolicy = .omit) {
        self.avoidNotes = avoidNotes
    }

    public func buildChord(recipe: ChordRecipe, context: HarmonyContext) throws -> Chord {
        let root = try resolveRoot(recipe: recipe, context: context)
        let baseChordType = try resolveChordType(recipe: recipe, context: context)
        let effectiveTension = effectiveTensionPolicy(recipe: recipe)
        let chordType = try applyTensionPolicy(
            effectiveTension,
            to: baseChordType,
            scaleDegree: recipe.scaleDegree,
            scale: context.scale,
            failsWithoutScaleDegree: false
        )
        return Chord(type: chordType, root: root)
    }

    /// Builds a `Chord` from a `ChordSpec`.
    ///
    /// - Throws:
    ///   - `invalidScaleDegree` when a degree is outside the scale.
    ///   - `missingChordType` when the spec has an altered degree and no type.
    ///   - `unableToResolveChord` when a diatonic tension is asked for a chromatic root, or when
    ///     the type cannot be built.
    ///   - `invalidInversion` when the bass inversion is not a chord tone index.
    public func buildChord(spec: ChordSpec, context: HarmonyContext) throws -> Chord {
        let resolved = try resolveRoot(spec.root, context: context)
        let baseType = try spec.type ?? defaultChordType(for: spec.root, resolved: resolved, context: context)
        let chordType = try applyTensionPolicy(
            spec.tension,
            to: baseType,
            scaleDegree: resolved.sourceDegree,
            scale: resolved.sourceScale,
            failsWithoutScaleDegree: true
        )

        var chord = Chord(type: chordType, root: resolved.root)
        switch spec.bass {
        case .root:
            break
        case .inversion(let inversion):
            guard inversion >= 0, inversion < chord.noteNames.count else {
                throw HarmonyEngineError.invalidInversion(inversion)
            }
            chord.inversion = inversion
        case .scaleDegree(let degree):
            chord.bass = try noteName(for: degree, in: context.scale)
        }
        return chord
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

    /// The root of a spec, and the scale and degree to use for diatonic inference and tension.
    /// `sourceScale` is `nil` when the root is chromatic.
    private struct ResolvedRoot {
        let root: NoteName
        let sourceScale: Scale?
        let sourceDegree: Int?
    }

    private func resolveRoot(_ root: ChordRoot, context: HarmonyContext) throws -> ResolvedRoot {
        switch root {
        case .degree(let degree, let alteration):
            let note = try noteName(for: degree, in: context.scale)
            guard alteration != 0 else {
                return ResolvedRoot(root: note, sourceScale: context.scale, sourceDegree: degree)
            }
            let altered = NoteName(letter: note.letter, accidental: note.accidental + alteration)
            return ResolvedRoot(root: altered, sourceScale: nil, sourceDegree: nil)

        case .borrowed(let degree, let scaleType):
            let parallel = Scale(type: scaleType, root: context.tonic)
            let note = try noteName(for: degree, in: parallel)
            return ResolvedRoot(root: note, sourceScale: parallel, sourceDegree: degree)

        case .applied(let function, let target):
            let targetNote = try noteName(for: target, in: context.scale)
            let note: NoteName
            switch function {
            case .dominant:          note = transpose(targetNote, up: .P5)
            case .leadingTone:       note = transpose(targetNote, down: .m2)
            case .tritoneSubstitute: note = transpose(targetNote, up: .m2)
            case .supertonic:        note = transpose(targetNote, up: .M2)
            }
            return ResolvedRoot(root: note, sourceScale: nil, sourceDegree: nil)

        case .neapolitan:
            return ResolvedRoot(root: transpose(context.tonic, up: .m2), sourceScale: nil, sourceDegree: nil)

        case .augmentedSixth:
            return ResolvedRoot(root: transpose(context.tonic, up: .m6), sourceScale: nil, sourceDegree: nil)

        case .commonToneDiminished(let target):
            let targetNote = try noteName(for: target, in: context.scale)
            return ResolvedRoot(root: targetNote, sourceScale: nil, sourceDegree: nil)
        }
    }

    private func transpose(_ note: NoteName, up interval: Interval) -> NoteName {
        (Pitch(noteName: note, octave: 4) + interval).noteName
    }

    private func transpose(_ note: NoteName, down interval: Interval) -> NoteName {
        (Pitch(noteName: note, octave: 4) - interval).noteName
    }

    // MARK: - Chord type resolution

    /// Returns the explicit chord type, or infers the diatonic quality from the scale.
    /// Heptatonic scales stack thirds. Other scales use `inferChordType`.
    private func resolveChordType(recipe: ChordRecipe, context: HarmonyContext) throws -> ChordType {
        if let chordType = recipe.chordType { return chordType }
        guard let scaleDegree = recipe.scaleDegree else {
            throw HarmonyEngineError.missingChordSource
        }
        return try diatonicTriad(scaleDegree: scaleDegree, scale: context.scale)
    }

    private func diatonicTriad(scaleDegree: Int, scale: Scale) throws -> ChordType {
        guard scaleDegree >= 1, scaleDegree <= scale.noteNames.count else {
            throw HarmonyEngineError.invalidScaleDegree(scaleDegree)
        }
        guard scale.noteNames.count == 7 else {
            return try inferChordType(scaleDegree: scaleDegree, scale: scale)
        }
        return try diatonicChordType(scaleDegree: scaleDegree, scale: scale, stackSize: 3)
    }

    private func defaultChordType(for root: ChordRoot, resolved: ResolvedRoot, context: HarmonyContext) throws -> ChordType {
        switch root {
        case .degree(_, let alteration):
            guard alteration == 0, let scale = resolved.sourceScale, let degree = resolved.sourceDegree else {
                throw HarmonyEngineError.missingChordType
            }
            return try diatonicTriad(scaleDegree: degree, scale: scale)
        case .borrowed:
            guard let scale = resolved.sourceScale, let degree = resolved.sourceDegree else {
                throw HarmonyEngineError.missingChordType
            }
            return try diatonicTriad(scaleDegree: degree, scale: scale)
        case .applied(let function, let target):
            switch function {
            case .dominant, .tritoneSubstitute:
                return .dominant7
            case .leadingTone:
                return .diminished7
            case .supertonic:
                // The related ii is half-diminished when the target chord is minor or diminished.
                let targetTriad = try? diatonicTriad(scaleDegree: target, scale: context.scale)
                let targetIsMinor = targetTriad?.components.contains(.minorThird) ?? false
                return targetIsMinor ? .halfDiminished7 : .minor7
            }
        case .neapolitan:
            return .major
        case .augmentedSixth(let kind):
            // Spelled from the ♭6 root: the ♯4 is written as its enharmonic minor 7th.
            let components: Set<ChordComponent>
            switch kind {
            case .italian: components = [.majorThird, .minorSeventh]
            case .french:  components = [.majorThird, .diminishedFifth, .minorSeventh]
            case .german:  components = [.majorThird, .perfectFifth, .minorSeventh]
            }
            guard let type = ChordType(components: components) else {
                throw HarmonyEngineError.unableToResolveChord
            }
            return type
        case .commonToneDiminished:
            return .diminished7
        }
    }

    /// Infers a triad for non-heptatonic scales from the scale notes above the root.
    /// A third and a fifth must both be in the scale. There is no fallback.
    private func inferChordType(scaleDegree: Int, scale: Scale) throws -> ChordType {
        let root = scale.noteNames[scaleDegree - 1]
        let pcs = Set(scale.noteNames.map(\.pitchClass))
        let r = root.pitchClass
        let hasMin3 = pcs.contains((r + 3) % 12)
        let hasMaj3 = pcs.contains((r + 4) % 12)
        let hasDim5 = pcs.contains((r + 6) % 12)
        let hasP5   = pcs.contains((r + 7) % 12)
        let hasAug5 = pcs.contains((r + 8) % 12)

        var components = Set<ChordComponent>()
        if hasMin3      { components.insert(.minorThird) }
        else if hasMaj3 { components.insert(.majorThird) }
        else { throw HarmonyEngineError.unableToResolveChord }

        if hasP5 { components.insert(.perfectFifth) }
        else if hasMin3, hasDim5 { components.insert(.diminishedFifth) }
        else if hasMaj3, hasAug5 { components.insert(.augmentedFifth) }
        else { throw HarmonyEngineError.unableToResolveChord }

        guard let type = ChordType(components: components) else {
            throw HarmonyEngineError.unableToResolveChord
        }
        return type
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

    /// Adds the tension to the base type.
    ///
    /// Diatonic policies need a heptatonic `scale` and a `scaleDegree`. When they are missing,
    /// the policy throws `unableToResolveChord` if `failsWithoutScaleDegree` is `true`.
    /// Otherwise it keeps the base type (the `ChordRecipe` behavior).
    private func applyTensionPolicy(
        _ policy: TensionPolicy,
        to baseChordType: ChordType,
        scaleDegree: Int?,
        scale: Scale?,
        failsWithoutScaleDegree: Bool
    ) throws -> ChordType {
        let stackSize: Int
        switch policy {
        case .none:
            return baseChordType
        case .custom(let intervals):
            return try rebuildChordType(baseIntervals: baseChordType.intervals, extraIntervals: intervals)
        case .diatonicSeventh:
            stackSize = 4
        case .diatonicExtensions(let maxDegree):
            switch maxDegree {
            case ..<7:    return baseChordType
            case 7..<9:   stackSize = 4
            case 9..<11:  stackSize = 5
            case 11..<13: stackSize = 6
            default:      stackSize = 7
            }
        }

        guard let scaleDegree, let scale, scale.noteNames.count == 7 else {
            if failsWithoutScaleDegree { throw HarmonyEngineError.unableToResolveChord }
            return baseChordType
        }
        let extra = try diatonicIntervals(scaleDegree: scaleDegree, scale: scale, stackSize: stackSize)
        let merged = try rebuildChordType(baseIntervals: baseChordType.intervals, extraIntervals: extra)
        return stackSize > 4 ? removingAvoidNotes(from: merged) : merged
    }

    private func removingAvoidNotes(from chordType: ChordType) -> ChordType {
        guard avoidNotes == .omit else { return chordType }
        let components = chordType.components
        let isDominant = components.contains(.majorThird) && components.contains(.minorSeventh)
        var kept = components
        if components.contains(.majorThird) { kept.remove(.eleventh) }
        if !isDominant { kept.remove(.flatNinth) }
        if !isDominant, components.contains(.perfectFifth) { kept.remove(.flatThirteenth) }
        return ChordType(components: kept) ?? chordType
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

    /// Stacks scale thirds on the degree. Each note goes to the nearest octave above the previous note.
    private func diatonicIntervals(scaleDegree: Int, scale: Scale, stackSize: Int) throws -> [Interval] {
        let noteNames = scale.noteNames
        guard scaleDegree >= 1, scaleDegree <= noteNames.count else {
            throw HarmonyEngineError.invalidScaleDegree(scaleDegree)
        }

        let rootIndex = scaleDegree - 1
        let rootPitch = Pitch(noteName: noteNames[rootIndex], octave: 4)
        var intervals = [Interval.P1]
        var previous = rootPitch

        for stackIndex in 1..<stackSize {
            let target = noteNames[(rootIndex + stackIndex * 2) % noteNames.count]
            // Octaves change at C, not at the scale root. So start at the octave of the previous
            // note and move up until the note is above it.
            var candidate = Pitch(noteName: target, octave: previous.octave)
            while candidate.midiNoteNumber <= previous.midiNoteNumber {
                candidate = Pitch(noteName: target, octave: candidate.octave + 1)
            }
            previous = candidate
            intervals.append(rootPitch.interval(to: candidate))
        }

        return intervals
    }
}
