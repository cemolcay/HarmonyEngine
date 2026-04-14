import MusicTheory
import HarmonyEngine

// ============================================================
// MARK: 1. HarmonyContext
// ============================================================
// HarmonyContext is the environment every engine call works within.
// It sets the key, scale, and the MIDI register ranges for upper
// voices and bass.

let context = HarmonyContext(
    tonic: .c,
    scale: Scale(type: .major, root: .c)
    // preferredRegister defaults to MIDI 60–84
    // bassRegister defaults to MIDI 36–55
)

let minorContext = HarmonyContext(
    tonic: .a,
    scale: Scale(type: .minor, root: .a)
)

// ============================================================
// MARK: 2. ChordBuilder — explicit recipe
// ============================================================
// ChordRecipe describes what you want. ChordBuilder resolves it
// into a concrete Chord.

let builder = ChordBuilder()

// Absolute root — scale is irrelevant
let fMaj7 = try builder.buildChord(
    recipe: ChordRecipe(root: .f, chordType: .major7),
    context: context
)
print("Absolute root:", fMaj7.root, fMaj7.type.symbol) // F Maj7

// Scale degree with an explicit chord type
let gDom7 = try builder.buildChord(
    recipe: ChordRecipe(scaleDegree: 5, chordType: .dominant7),
    context: context
)
print("Degree 5 explicit:", gDom7.root, gDom7.type.symbol) // G 7

// ============================================================
// MARK: 3. ChordBuilder — inferred diatonic quality
// ============================================================
// When chordType is omitted, ChordBuilder infers the quality from
// the scale. Works for heptatonic (7-note) scales.

let inferredDegrees = try (1...7).map { degree in
    try builder.buildChord(
        recipe: ChordRecipe(scaleDegree: degree),
        context: context
    )
}
print("\nC major diatonic triads:")
inferredDegrees.forEach { print(" ", $0.root, $0.type.symbol) }
// C M  D m  E m  F M  G M  A m  B dim

// ============================================================
// MARK: 4. HarmonyRole — role-driven chord building
// ============================================================
// HarmonyRole provides defaults for tension and voicing bias
// without overriding anything you set explicitly.

// .dominant adds a diatonic seventh automatically
let dominantChord = try builder.buildChord(
    recipe: ChordRecipe(scaleDegree: 5, role: .dominant),
    context: context
)
print("\nDominant role (degree 5):", dominantChord.root, dominantChord.type.symbol) // G 7

// .color adds extensions up to the 9th
let colorChord = try builder.buildChord(
    recipe: ChordRecipe(scaleDegree: 1, role: .color),
    context: context
)
print("Color role (degree 1):", colorChord.root, colorChord.type.symbol)

// Explicit TensionPolicy.none suppresses the role's tension default
let triadOnly = try builder.buildChord(
    recipe: ChordRecipe(scaleDegree: 5, role: .dominant, tensionPolicy: TensionPolicy.none),
    context: context
)
print("Dominant role, explicit .none tension:", triadOnly.root, triadOnly.type.symbol) // G M

// ============================================================
// MARK: 5. HarmonicPalette — chord catalog
// ============================================================
// HarmonicPalette answers "what chords exist in this key?"

let triads = try HarmonicPalette.diatonicTriads(in: context)
print("\nDiatonic triads in C major:")
triads.forEach { print(" ", $0.root, $0.type.symbol) }

let sevenths = try HarmonicPalette.diatonicSevenths(in: context)
print("\nDiatonic seventh chords in C major:")
sevenths.forEach { print(" ", $0.root, $0.type.symbol) }

// Role-filtered subsets
let tonicChords     = try HarmonicPalette.chords(for: .tonic,       in: context)
let predominantChords = try HarmonicPalette.chords(for: .predominant, in: context)
let dominantChords  = try HarmonicPalette.chords(for: .dominant,    in: context)

print("\nTonic chords:      ", tonicChords.map { "\($0.root)\($0.type.symbol)" })
print("Predominant chords:", predominantChords.map { "\($0.root)\($0.type.symbol)" })
print("Dominant chords:   ", dominantChords.map { "\($0.root)\($0.type.symbol)" })

// ============================================================
// MARK: 6. VoiceLeadingEngine — single chord
// ============================================================
// VoiceLeadingEngine places a Chord in the correct register and
// chooses the smoothest inversion.

let voicer = VoiceLeadingEngine()

let cMaj7Voiced = try voicer.voice(
    chord: Chord(type: .major7, root: .c),
    previous: nil,
    context: context,
    policy: .nearest
)

print("\nCmaj7 voiced:")
print("  Upper voices:", cMaj7Voiced.upperVoices.map(\.midiNoteNumber))
print("  Bass voice:  ", cMaj7Voiced.bassVoice.midiNoteNumber)
print("  MIDI notes:  ", cMaj7Voiced.midiNotes)

// ============================================================
// MARK: 7. Voice leading through a progression
// ============================================================
// The engine tracks the previous VoicedChord so each new voicing
// minimises movement from the one before.

let progression: [(degree: Int, role: HarmonyRole)] = [
    (1, .tonic),
    (6, .tonic),
    (4, .predominant),
    (5, .dominant),
]

print("\nVoiced I–VI–IV–V in C major:")
var previous: VoicedChord?

for (degree, role) in progression {
    let recipe = ChordRecipe(scaleDegree: degree, role: role)
    let chord  = try builder.buildChord(recipe: recipe, context: context)
    let voiced = try voicer.voice(
        chord: chord,
        previous: previous,
        context: context,
        policy: .nearest,
        role: role
    )

    print("  Degree \(degree) (\(chord.root)\(chord.type.symbol))")
    print("    upper:", voiced.upperVoices.map(\.midiNoteNumber),
          "  bass:", voiced.bassVoice.midiNoteNumber)

    previous = voiced
}

// ============================================================
// MARK: 8. VoicedChord → MIDI
// ============================================================
// VoicedChord gives you raw MIDI note numbers. Your app decides
// timing, velocity, and channel routing.

let voiced = try voicer.voice(
    chord: dominantChord,
    previous: nil,
    context: context,
    policy: .nearest,
    role: .dominant
)

// All notes together (e.g. one-channel output)
let allNotes = voiced.midiNotes
print("\nAll MIDI notes:", allNotes)

// Split bass and chord for separate channel routing
let bassNote   = voiced.bassVoice.midiNoteNumber
let chordNotes = voiced.upperVoices.map(\.midiNoteNumber)
print("Bass channel:  ", bassNote)
print("Chord channel: ", chordNotes)

// ============================================================
// MARK: 9. Custom scale context
// ============================================================
// HarmonyContext works with any Scale, including custom ones.
// Chord quality inference requires a heptatonic scale; for others,
// provide an explicit chordType.

let dorianContext = HarmonyContext(
    tonic: .d,
    scale: Scale(type: .dorian, root: .d)
)

let dorianTriads = try HarmonicPalette.diatonicTriads(in: dorianContext)
print("\nDiatonic triads in D Dorian:")
dorianTriads.forEach { print(" ", $0.root, $0.type.symbol) }

// Custom 4-note scale — explicit chordType required
let tetrachord = Scale(intervals: [.P1, .m2, .P4, .P5], root: .d, name: "Tetrachord")
let tetContext = HarmonyContext(tonic: .d, scale: tetrachord)

let tetChord = try builder.buildChord(
    recipe: ChordRecipe(scaleDegree: 2, chordType: .minor),
    context: tetContext
)
print("\nTetrachord degree 2:", tetChord.root, tetChord.type.symbol) // Eb m
