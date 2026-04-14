import Foundation
import MusicTheory

/// A catalog of available chords for a given `HarmonyContext`.
///
/// `HarmonicPalette` answers the question "what chords exist in this key?" — giving the app
/// a menu to display, a pool for suggestion logic, or a validation check.
/// All methods delegate to `ChordBuilder` using the context's scale.
public struct HarmonicPalette {

    /// All diatonic triads for every scale degree in the given context.
    public static func diatonicTriads(in context: HarmonyContext) throws -> [Chord] {
        try build(in: context, tensionPolicy: .none)
    }

    /// All diatonic seventh chords for every scale degree in the given context.
    public static func diatonicSevenths(in context: HarmonyContext) throws -> [Chord] {
        try build(in: context, tensionPolicy: .diatonicSeventh)
    }

    /// Diatonic chords for every scale degree, stacking the given number of thirds.
    ///
    /// `stackSize` maps to tension:
    /// - 3 → triads
    /// - 4 → seventh chords
    /// - 5 → ninth chords
    /// - 6 → eleventh chords
    /// - 7+ → thirteenth chords
    public static func diatonicChords(in context: HarmonyContext, stackSize: Int) throws -> [Chord] {
        let tension: TensionPolicy
        switch stackSize {
        case ...3:   tension = .none
        case 4:      tension = .diatonicSeventh
        case 5:      tension = .diatonicExtensions(maxDegree: 9)
        case 6:      tension = .diatonicExtensions(maxDegree: 11)
        default:     tension = .diatonicExtensions(maxDegree: 13)
        }
        return try build(in: context, tensionPolicy: tension)
    }

    /// Chords conventionally associated with a harmonic role in the given context.
    ///
    /// Degree assignments follow common-practice diatonic function for heptatonic scales:
    /// - `.tonic` → degrees 1, 3, 6
    /// - `.predominant` → degrees 2, 4
    /// - `.dominant` → degrees 5, 7
    /// - `.color`, `.passing` → all degrees
    ///
    /// For non-heptatonic scales all degrees are returned regardless of role.
    public static func chords(for role: HarmonyRole, in context: HarmonyContext) throws -> [Chord] {
        let degrees = diatonicDegrees(for: role, in: context)
        return try degrees.map { degree in
            let recipe = ChordRecipe(scaleDegree: degree, role: role)
            return try ChordBuilder().buildChord(recipe: recipe, context: context)
        }
    }

    // MARK: - Private helpers

    private static func build(in context: HarmonyContext, tensionPolicy: TensionPolicy) throws -> [Chord] {
        let count = context.scale.noteNames.count
        return try (1...count).map { degree in
            let recipe = ChordRecipe(scaleDegree: degree, tensionPolicy: tensionPolicy)
            return try ChordBuilder().buildChord(recipe: recipe, context: context)
        }
    }

    private static func diatonicDegrees(for role: HarmonyRole, in context: HarmonyContext) -> [Int] {
        let count = context.scale.noteNames.count
        guard count == 7 else { return Array(1...count) }
        switch role {
        case .tonic:       return [1, 3, 6]
        case .predominant: return [2, 4]
        case .dominant:    return [5, 7]
        case .color:       return Array(1...7)
        case .passing:     return Array(1...7)
        }
    }
}
