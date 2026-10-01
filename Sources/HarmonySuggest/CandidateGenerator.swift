import Foundation
import MusicTheory
import HarmonyEngine

/// A chord that the engine can suggest, before scoring.
struct Candidate {
    enum Source: Hashable {
        /// A diatonic chord of this flavor.
        case diatonic(ChordFlavor)
        /// A diatonic dominant-quality chord with a chromatic alteration.
        case altered(ChordFlavor)
        /// A chromatic device, with the weight from the profile. Borrowed chords also have a flavor.
        case device(ChromaticDevice, weight: Double, flavor: ChordFlavor?)
    }

    let spec: ChordSpec
    let chord: Chord
    let source: Source
    let category: SuggestionCategory
}

/// Builds the candidate chords for a context and a style profile.
struct CandidateGenerator {
    let builder: ChordBuilder

    /// Returns the candidates, without duplicates. Diatonic chords come first, so a chromatic device that sounds
    /// the same as a diatonic chord is removed.
    func candidates(
        context: HarmonyContext,
        profile: StyleProfile,
        current: ChordSpec?,
        knobs: SuggestionKnobs
    ) -> [Candidate] {
        var result = [Candidate]()
        var seen = Set<SoundKey>()
        let degreeCount = context.scale.noteNames.count
        let allowsChromatic = knobs.chromaticism > 0

        func add(_ spec: ChordSpec, source: Candidate.Source) {
            guard let chord = try? builder.buildChord(spec: spec, context: context) else { return }
            let key = SoundKey(chord)
            guard !seen.contains(key) else { return }
            let isDiatonic = ScaleFit.isDiatonic(chord, in: context.scale)
            let category: SuggestionCategory
            let components = chord.type.components
            let isDominantQuality = components.contains(.majorThird) && components.contains(.minorSeventh)
            switch source {
            case .diatonic(.dominantSeventh) where !isDominantQuality:
                return
            case .diatonic(.bluesSeventh):
                guard isDiatonic || allowsChromatic else { return }
                category = isDiatonic ? .diatonic : .chromatic
            case .diatonic(let flavor) where isDiatonic:
                let plain: Set<ChordFlavor> = [.triad, .dominantSeventh, .seventh]
                category = plain.contains(flavor) ? .diatonic : .color
            case .diatonic:
                return
            case .altered where !isDiatonic && !isDominantQuality:
                // A chromatic ♯11 is used on dominant chords only. On major 7th chords, only the
                // diatonic (Lydian) ♯11 is used.
                return
            case .altered:
                category = isDiatonic ? .color : .chromatic
            case .device:
                category = isDiatonic ? .diatonic : .chromatic
            }
            // Only an accepted chord blocks later chords with the same sound.
            seen.insert(key)
            result.append(Candidate(spec: spec, chord: chord, source: source, category: category))
        }

        // Diatonic flavors on every degree.
        for degree in 1...max(degreeCount, 1) {
            guard let triad = try? builder.buildChord(spec: .degree(degree), context: context) else { continue }
            for flavor in ChordFlavor.allCases where (profile.flavors[flavor] ?? 0) > 0 {
                guard let spec = realize(flavor, degree: degree, triad: triad.type) else { continue }
                add(spec, source: .diatonic(flavor))
            }
        }

        // Alterations on dominant-quality and major 7th chords.
        if allowsChromatic, !profile.alterations.isEmpty {
            for candidate in result {
                guard case .diatonic(let flavor) = candidate.source, flavor != .triad else { continue }
                for spec in alteredSpecs(of: candidate, alterations: profile.alterations) {
                    add(spec, source: .altered(flavor))
                }
            }
        }

        guard allowsChromatic else { return result }

        // The dominant of the harmonic minor in minor keys (common practice in every style).
        var devices = profile.devices
        if degreeCount == 7, let dominant = try? builder.buildChord(spec: .degree(5), context: context),
           dominant.type.components.contains(.minorThird) {
            devices.append(DeviceWeight(.borrowed(degree: 5, from: .harmonicMinor), weight: 0.7))
            devices.append(DeviceWeight(.borrowed(degree: 7, from: .harmonicMinor), weight: 0.4))
        }

        for deviceWeight in devices where deviceWeight.weight > 0 {
            for (spec, flavor) in specs(for: deviceWeight.device, context: context, profile: profile, current: current) {
                add(spec, source: .device(deviceWeight.device, weight: deviceWeight.weight, flavor: flavor))
                // Alterations on applied dominants.
                if case .appliedDominant = deviceWeight.device,
                   let chord = try? builder.buildChord(spec: spec, context: context) {
                    let base = Candidate(spec: spec, chord: chord, source: .device(deviceWeight.device, weight: deviceWeight.weight, flavor: nil), category: .chromatic)
                    for altered in alteredSpecs(of: base, alterations: profile.alterations) {
                        add(altered, source: .device(deviceWeight.device, weight: deviceWeight.weight * 0.5, flavor: nil))
                    }
                }
            }
        }

        return result
    }

    // MARK: - Flavors

    private func realize(_ flavor: ChordFlavor, degree: Int, triad: ChordType) -> ChordSpec? {
        let triadComponents = triad.components
        let hasFifth = triadComponents.contains(.perfectFifth)

        func typed(_ components: Set<ChordComponent>) -> ChordSpec? {
            ChordType(components: components).map { ChordSpec(root: .degree(degree), type: $0) }
        }

        switch flavor {
        case .triad:      return .degree(degree)
        case .dominantSeventh, .seventh:
            return .degree(degree, tension: .diatonicSeventh)
        case .bluesSeventh:
            let isMajor = triadComponents.contains(.majorThird) && hasFifth
            return isMajor ? ChordSpec(root: .degree(degree), type: .dominant7) : nil
        case .ninth:      return .degree(degree, tension: .diatonicExtensions(maxDegree: 9))
        case .eleventh:   return .degree(degree, tension: .diatonicExtensions(maxDegree: 11))
        case .thirteenth: return .degree(degree, tension: .diatonicExtensions(maxDegree: 13))
        case .sus2:       return ChordSpec(root: .degree(degree), type: .sus2)
        case .sus4:       return ChordSpec(root: .degree(degree), type: .sus4)
        case .sevenSus4:  return typed([.perfectFourth, .perfectFifth, .minorSeventh])
        case .six:        return hasFifth ? typed(triadComponents.union([.majorSixth])) : nil
        case .add9:       return hasFifth ? typed(triadComponents.union([.ninth])) : nil
        case .sixNine:    return hasFifth ? typed(triadComponents.union([.majorSixth, .ninth])) : nil
        }
    }

    private func alteredSpecs(of candidate: Candidate, alterations: [AlterationTension]) -> [ChordSpec] {
        let components = candidate.chord.type.components
        let isDominant = components.contains(.majorThird) && components.contains(.minorSeventh)
        let isMajorSeventh = components.contains(.majorThird) && components.contains(.majorSeventh)
        guard isDominant || isMajorSeventh else { return [] }

        return alterations.compactMap { alteration in
            guard isDominant || alteration == .sharpEleventh else { return nil }
            var altered = components
            altered.remove(alteration.replaces)
            altered.insert(alteration.component)
            guard let type = ChordType(components: altered) else { return nil }
            return ChordSpec(root: candidate.spec.root, type: type, bass: candidate.spec.bass)
        }
    }

    // MARK: - Devices

    private func specs(
        for device: ChromaticDevice,
        context: HarmonyContext,
        profile: StyleProfile,
        current: ChordSpec?
    ) -> [(ChordSpec, ChordFlavor?)] {
        let degreeCount = context.scale.noteNames.count

        /// A target must be a scale degree with a major or minor triad.
        func isTonicizable(_ target: Int) -> Bool {
            guard target >= 1, target <= degreeCount,
                  let triad = try? builder.buildChord(spec: .degree(target), context: context) else { return false }
            return triad.type.components.contains(.perfectFifth)
        }

        switch device {
        case .appliedDominant(let target):
            guard target != 1, isTonicizable(target) else { return [] }
            return [(ChordSpec(root: .applied(.dominant, of: target)), nil)]
        case .appliedLeadingTone(let target):
            guard target != 1, isTonicizable(target) else { return [] }
            return [(ChordSpec(root: .applied(.leadingTone, of: target)), nil)]
        case .tritoneSubstitute(let target):
            guard isTonicizable(target) else { return [] }
            return [(ChordSpec(root: .applied(.tritoneSubstitute, of: target)), nil)]
        case .relatedSupertonic(let target):
            guard target != 1, isTonicizable(target) else { return [] }
            return [(ChordSpec(root: .applied(.supertonic, of: target)), nil)]
        case .borrowed(let degree, let scaleType):
            guard scaleType != context.scale.type else { return [] }
            // A borrowed chord uses the flavor weights: the triad, and the seventh chord.
            let root = ChordRoot.borrowed(degree: degree, from: scaleType)
            var specs: [(ChordSpec, ChordFlavor?)] = [(ChordSpec(root: root), .triad)]
            let seventh = ChordSpec(root: root, tension: .diatonicSeventh)
            if let chord = try? builder.buildChord(spec: seventh, context: context) {
                let components = chord.type.components
                let isDominant = components.contains(.majorThird) && components.contains(.minorSeventh)
                let flavor: ChordFlavor = isDominant ? .dominantSeventh : .seventh
                if (profile.flavors[flavor] ?? 0) > 0 { specs.append((seventh, flavor)) }
            }
            return specs
        case .neapolitan:
            return [(ChordSpec(root: .neapolitan, bass: .inversion(1)), nil)]
        case .augmentedSixth(let kind):
            return [(ChordSpec(root: .augmentedSixth(kind)), nil)]
        case .commonToneDiminished:
            guard case .degree(let degree, 0)? = current?.root else { return [] }
            return [(ChordSpec(root: .commonToneDiminished(of: degree)), nil)]
        case .cadentialSixFour:
            return [(ChordSpec(root: .degree(1), bass: .inversion(2)), nil)]
        }
    }
}

/// Identifies chords that sound the same: the same pitch classes and the same bass.
struct SoundKey: Hashable {
    let pitchClasses: Set<Int>
    let bass: Int

    init(_ chord: Chord) {
        pitchClasses = ScaleFit.pitchClasses(of: chord)
        if let bass = chord.bass {
            self.bass = bass.pitchClass
        } else {
            let noteNames = chord.noteNames
            self.bass = noteNames[min(chord.inversion, noteNames.count - 1)].pitchClass
        }
    }
}
