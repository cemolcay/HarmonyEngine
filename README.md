# HarmonyEngine

A reusable Swift library for harmonic decision-making that sits above the [`MusicTheory`](https://github.com/cemolcay/MusicTheory) core library.

`HarmonyEngine` handles chord generation, voice leading, and MIDI note output. Sequencing, timing, and DAW integration belong to the app layer.

## Requirements

- Swift 6.3+
- [`MusicTheory`](https://github.com/cemolcay/MusicTheory) 2.0.0+

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/cemolcay/HarmonyEngine.git", from: "1.0.0")
]
```

## Package Layout

```text
HarmonyEngine/
  Sources/HarmonyEngine/
    HarmonyContext.swift      — HarmonyContext, HarmonyRole, PitchRange
    ChordRecipe.swift         — ChordRecipe, InversionPolicy, TensionPolicy
    ChordBuilder.swift        — ChordBuilding protocol + ChordBuilder
    VoiceLeadingEngine.swift  — VoiceLeading protocol + VoiceLeadingEngine, VoicedChord
    HarmonicPalette.swift     — diatonic chord catalog and role-based queries
    Errors.swift              — HarmonyEngineError
  Tests/HarmonyEngineTests/
    HarmonyEngineTests.swift
```

## Core Types

### `HarmonyContext`

Defines the harmonic environment — tonic, scale, optional tempo, and register ranges.

```swift
let context = HarmonyContext(
    tonic: .c,
    scale: Scale(type: .major, root: .c),
    tempo: Tempo(timeSignature: TimeSignature(beats: 4, beatUnit: 4), bpm: 120)
)
```

Defaults: preferred register MIDI 60–84, bass register MIDI 36–55.

### `HarmonyRole`

Functional grouping that biases chord building and voicing when not overridden explicitly.

| Case | ChordBuilder effect | VoiceLeading effect |
|---|---|---|
| `.tonic` | none | slight preference for root position |
| `.predominant` | none | none |
| `.dominant` | adds diatonic seventh by default | prefers brighter register |
| `.color` | adds diatonic ninth by default | none |
| `.passing` | none | minimises bass movement |

### `ChordRecipe`

Describes harmonic intent without fixing the final voicing.

```swift
// Diatonic chord — quality inferred from scale (heptatonic scales only)
let recipe = ChordRecipe(scaleDegree: 5, role: .dominant)

// Explicit chord type
let recipe = ChordRecipe(scaleDegree: 2, chordType: .minor, inversionPolicy: .nearest)

// Absolute root, ignoring scale
let recipe = ChordRecipe(root: .f, chordType: .major7)
```

- `chordType: ChordType?` — when `nil`, diatonic quality is inferred from the scale degree. Requires a heptatonic scale.
- `role: HarmonyRole?` — provides tension and voicing defaults when not set explicitly.
- `tensionPolicy: TensionPolicy?` — `nil` defers to the role default; `TensionPolicy.none` suppresses tension even when a role is set.

### `InversionPolicy`

| Case | Behavior |
|---|---|
| `.rootPosition` | Always inversion 0 |
| `.keepClose` | Lowest inversion that fits the register cleanly |
| `.nearest` | Minimum voice movement from the previous chord |
| `.fixed(Int)` | Exact inversion index |

### `TensionPolicy`

| Case | Behavior |
|---|---|
| `nil` | Defer to role default |
| `.none` | No tension — use chord type as-is |
| `.diatonicSeventh` | Add the diatonic 7th from the scale |
| `.diatonicExtensions(maxDegree:)` | Stack diatonic extensions up to the given degree (7, 9, 11, 13) |
| `.custom([Interval])` | Merge arbitrary intervals into the chord |

### `VoicedChord`

The output of `VoiceLeadingEngine`. Bass and upper voices are separate so the app can route them independently (e.g., different MIDI channels).

```swift
voiced.upperVoices   // [Pitch] — sorted ascending, within preferredRegister
voiced.bassVoice     // Pitch   — within bassRegister
voiced.allPitches    // [Pitch] — bass + upper voices, sorted ascending
voiced.topPitch      // Pitch   — highest upper voice
voiced.midiNotes     // [Int]   — MIDI note numbers for all pitches, sorted ascending
```

## Services

### `ChordBuilder`

Resolves a `ChordRecipe` into a `Chord`. Derives roots from scale degrees, infers diatonic chord quality, and applies the effective tension policy (explicit setting wins; role provides the default).

```swift
let chord = try ChordBuilder().buildChord(recipe: recipe, context: context)
```

### `VoiceLeadingEngine`

Converts a `Chord` into a register-specific `VoicedChord`. Generates all inversions across candidate octaves, rejects voicings outside `preferredRegister`, and scores candidates by voice movement, top-note leap, bass-range penalty, and optional role bias.

```swift
// Without role
let voiced = try VoiceLeadingEngine().voice(
    chord: chord,
    previous: previousVoicedChord,
    context: context,
    policy: .nearest
)

// With role
let voiced = try VoiceLeadingEngine().voice(
    chord: chord,
    previous: previousVoicedChord,
    context: context,
    policy: .nearest,
    role: .dominant
)
```

### `HarmonicPalette`

Answers "what chords are available in this key?" — useful for building suggestion UIs, validating choices, or exploring a key.

```swift
// All diatonic triads (I through VII)
let triads = try HarmonicPalette.diatonicTriads(in: context)

// All diatonic seventh chords
let sevenths = try HarmonicPalette.diatonicSevenths(in: context)

// Chords stacked to a given depth (3 = triads, 4 = sevenths, 5 = ninths, …)
let ninths = try HarmonicPalette.diatonicChords(in: context, stackSize: 5)

// Chords conventionally associated with a harmonic role
let dominantChords = try HarmonicPalette.chords(for: .dominant, in: context)
// → [G, B] in C major (degrees 5 and 7)
```

Role-to-degree mapping for heptatonic scales: tonic = 1, 3, 6 · predominant = 2, 4 · dominant = 5, 7 · color/passing = all degrees.

## Quick Example

```swift
import MusicTheory
import HarmonyEngine

let context = HarmonyContext(tonic: .c, scale: Scale(type: .major, root: .c))
let engine  = VoiceLeadingEngine()
var previous: VoicedChord?

let degrees = [1, 4, 5, 1]
for degree in degrees {
    let recipe  = ChordRecipe(scaleDegree: degree)
    let chord   = try ChordBuilder().buildChord(recipe: recipe, context: context)
    let voiced  = try engine.voice(chord: chord, previous: previous, context: context, policy: .nearest)

    // Hand MIDI note numbers to your sequencer — timing, velocity, and channel are yours to decide
    mySequencer.schedule(notes: voiced.upperVoices.map(\.midiNoteNumber), channel: 0)
    mySequencer.schedule(notes: [voiced.bassVoice.midiNoteNumber], channel: 1)

    previous = voiced
}
```

## Error Handling

```swift
enum HarmonyEngineError: Error {
    case invalidScaleDegree(Int)
    case missingChordSource
    case invalidPitchRange(minMidi: Int, maxMidi: Int)
    case voicingOutOfRange
    case unableToResolveChord
}
```

No silent fallbacks — errors are thrown when harmonic intent cannot be resolved.

## Non-Goals

- Progression sequencing or beat/bar timing
- MIDI event scheduling (start time, duration, velocity, channel)
- Genre presets or taste rules
- Chord recognition or roman numeral analysis
- Reharmonization or AI suggestions
- DAW transport sync or plugin state
- UI or persistence
