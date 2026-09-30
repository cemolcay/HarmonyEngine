import Foundation
import MusicTheory

/// The display names of a chord in a key.
public struct ChordName: Hashable, Sendable {
    /// The Roman numeral analysis, for example `"V7/ii"`, `"♭VII"`, `"viiø7"`, `"Ger+6"`.
    public let roman: String
    /// The chord symbol, for example `"A7"`, `"B♭"`, `"Bm7♭5"`.
    public let symbol: String
}

/// Names a `ChordSpec` in a `HarmonyContext`.
///
/// Numerals follow these rules:
/// - The case shows the third: upper case for a major third or no third, lower case for a minor third.
/// - An accidental prefix shows a root that is not the scale note of that degree (♭VII in major).
///   For scales that do not have 7 notes, the reference is the major scale on the scale root.
/// - The suffix shows the quality: `°`, `ø7`, `°7`, `+`, `7`, `maj7`, extensions, and alterations.
/// - Inversions use figured-bass numbers: `6`, `64` for triads, and `65`, `43`, `42` for seventh chords.
public struct ChordNamer {
    private let builder: ChordBuilder
    private static let numerals = ["I", "II", "III", "IV", "V", "VI", "VII"]

    public init(builder: ChordBuilder = ChordBuilder()) {
        self.builder = builder
    }

    /// Names the spec. It throws the same errors as `ChordBuilder.buildChord(spec:context:)`.
    public func name(spec: ChordSpec, context: HarmonyContext) throws -> ChordName {
        let chord = try builder.buildChord(spec: spec, context: context)
        return ChordName(roman: roman(for: spec, chord: chord, context: context), symbol: chord.notation)
    }

    // MARK: - Roman numerals

    private func roman(for spec: ChordSpec, chord: Chord, context: HarmonyContext) -> String {
        switch spec.root {
        case .degree, .borrowed:
            let (prefix, index) = numeral(for: chord.root, in: context.scale)
            return prefix + figured(Self.numerals[index], chord: chord)

        case .applied(let function, let target):
            let base: String
            switch function {
            case .dominant:          base = "V"
            case .leadingTone:       base = "VII"
            case .tritoneSubstitute: base = "subV"
            case .supertonic:        base = "II"
            }
            return figured(base, chord: chord) + "/" + targetNumeral(target, context: context)

        case .neapolitan:
            return "N" + inversionFigure(chord: chord, kind: .triad)

        case .augmentedSixth(let kind):
            switch kind {
            case .italian: return "It+6"
            case .french:  return "Fr+6"
            case .german:  return "Ger+6"
            }

        case .commonToneDiminished(let target):
            return "CT°7/" + targetNumeral(target, context: context)
        }
    }

    /// The accidental prefix and the numeral index (0–6) of a root in a scale.
    private func numeral(for root: NoteName, in scale: Scale) -> (String, Int) {
        let index = scale.root.letter.diatonicDistance(to: root.letter)
        let reference: NoteName
        if scale.noteNames.count == 7 {
            reference = scale.noteNames[index]
        } else {
            reference = Scale(type: .major, root: scale.root).noteNames[index]
        }
        var alteration = (root.pitchClass - reference.pitchClass) % 12
        if alteration > 6 { alteration -= 12 }
        if alteration < -6 { alteration += 12 }
        let prefix = alteration < 0
            ? String(repeating: "♭", count: -alteration)
            : String(repeating: "♯", count: alteration)
        return (prefix, index)
    }

    private func targetNumeral(_ degree: Int, context: HarmonyContext) -> String {
        guard let target = try? builder.buildChord(spec: .degree(degree), context: context) else {
            return degree >= 1 && degree <= 7 ? Self.numerals[degree - 1] : "\(degree)"
        }
        let (prefix, index) = numeral(for: target.root, in: context.scale)
        let isMinor = target.type.components.contains(.minorThird)
        let numeral = Self.numerals[index]
        return prefix + (isMinor ? numeral.lowercased() : numeral)
    }

    /// Applies the case, the quality suffix, and the inversion figure to a numeral.
    private func figured(_ numeral: String, chord: Chord) -> String {
        let components = chord.type.components
        let isMinor = components.contains(.minorThird)
        let cased = isMinor ? lowercasedNumeral(numeral) : numeral
        let (suffix, kind) = qualitySuffix(components)
        let figure = inversionFigure(chord: chord, kind: kind)
        guard !figure.isEmpty else { return cased + suffix }
        // A seventh chord figure replaces the "7" of the suffix.
        if kind == .seventh {
            return cased + suffix.dropLast() + figure
        }
        return cased + suffix + figure
    }

    /// Keeps the "sub" prefix of a tritone substitute in lower case, and lower-cases the numeral.
    private func lowercasedNumeral(_ numeral: String) -> String {
        if numeral.hasPrefix("sub") { return "sub" + numeral.dropFirst(3).lowercased() }
        return numeral.lowercased()
    }

    /// Tells which inversion figures a chord can use.
    private enum FigureKind {
        /// Triad figures: 6, 64.
        case triad
        /// Seventh chord figures: 65, 43, 42. The suffix ends with "7".
        case seventh
        /// No figure (extended or altered chords).
        case none
    }

    private func qualitySuffix(_ components: Set<ChordComponent>) -> (String, FigureKind) {
        let hasMinor3 = components.contains(.minorThird)
        let hasMajor3 = components.contains(.majorThird)
        let hasDim5 = components.contains(.diminishedFifth)
        let hasAug5 = components.contains(.augmentedFifth)
        let hasDim7 = components.contains(.diminishedSeventh)
        let hasMin7 = components.contains(.minorSeventh)
        let hasMaj7 = components.contains(.majorSeventh)
        let hasSeventh = hasDim7 || hasMin7 || hasMaj7

        var suffix = ""
        if hasMinor3, hasDim5, hasDim7 {
            suffix = "°7"
        } else if hasMinor3, hasDim5, hasMin7 {
            suffix = "ø7"
        } else if hasMinor3, hasDim5 {
            suffix = "°"
        } else if hasMajor3, hasAug5 {
            suffix = hasMaj7 ? "+maj7" : (hasMin7 ? "+7" : "+")
        } else if hasMaj7 {
            suffix = "maj7"
        } else if hasMin7 {
            suffix = "7"
        } else if components.contains(.majorSixth) {
            suffix = "6"
        }

        // The highest natural extension replaces the 7 (for example 9, 11, 13).
        let naturalExtensions: [(ChordComponent, String)] = [(.thirteenth, "13"), (.eleventh, "11"), (.ninth, "9")]
        if let highest = naturalExtensions.first(where: { components.contains($0.0) }) {
            if hasSeventh, suffix.hasSuffix("7") {
                suffix = String(suffix.dropLast()) + highest.1
            } else {
                suffix += "add" + highest.1
            }
        }

        // Suspensions: only when there is no third.
        if !hasMinor3, !hasMajor3 {
            if components.contains(.perfectFourth) { suffix += "sus4" }
            if components.contains(.majorSecond) { suffix += "sus2" }
        }

        // Alterations that are not part of the quality.
        let alterations: [(ChordComponent, String)] = [
            (.flatNinth, "♭9"), (.sharpNinth, "♯9"), (.sharpEleventh, "♯11"), (.flatThirteenth, "♭13"),
        ]
        let altered = alterations.filter { components.contains($0.0) }.map(\.1)
        var finalSuffix = suffix
        if hasMajor3, hasDim5 { finalSuffix += "(♭5)" }
        if !altered.isEmpty { finalSuffix += "(" + altered.joined(separator: ",") + ")" }
        let kind: FigureKind
        if finalSuffix != suffix || suffix.contains("add") || suffix.contains("sus") {
            kind = .none
        } else if !hasSeventh {
            kind = .triad
        } else {
            kind = suffix.hasSuffix("7") ? .seventh : .none
        }
        return (finalSuffix, kind)
    }

    private func inversionFigure(chord: Chord, kind: FigureKind) -> String {
        guard chord.bass == nil, chord.inversion > 0 else { return "" }
        let figures: [String]
        switch kind {
        case .triad:   figures = ["", "6", "64"]
        case .seventh: figures = ["", "65", "43", "42"]
        case .none:    return ""
        }
        return chord.inversion < figures.count ? figures[chord.inversion] : ""
    }
}
