# HarmonyEngine

A reusable Swift library for harmonic decision-making that sits above the [`MusicTheory`](https://github.com/cemolcay/MusicTheory) core library.

`HarmonyEngine` handles chord generation, voice leading, and MIDI rendering. It does not contain UI, DAW integration, persistence, or genre-specific logic.

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
    Progression.swift         — Progression, ProgressionStep
    ChordRecipe.swift         — ChordRecipe, InversionPolicy, TensionPolicy
    ChordBuilder.swift        — ChordBuilding protocol + ChordBuilder
    VoiceLeadingEngine.swift  — VoiceLeading protocol + VoiceLeadingEngine, VoicedChord
    MidiChordRenderer.swift   — MidiRendering protocol + MidiChordRenderer, MidiChordEvent
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

### `Progression` / `ProgressionStep`

An ordered, validated collection of harmonic slots. Steps are sorted by `(bar, beat)` and may not overlap.

```swift
let progression = try Progression(
    steps: [
        ProgressionStep(bar: 1, beat: 0, durationBeats: 4, scaleDegree: 1),
        ProgressionStep(bar: 2, beat: 0, durationBeats: 4, scaleDegree: 5),
    ],
    loopLengthBars: 2
)
```

### `ChordRecipe`

Describes harmonic intent without fixing the final voicing. Use `root` for absolute chords or `scaleDegree` for diatonic ones.

```swift
let recipe = ChordRecipe(
    scaleDegree: 5,
    chordType: .dominant7,
    inversionPolicy: .nearest,
    tensionPolicy: .diatonicSeventh
)
```

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
| `.none` | Use the chord type as-is |
| `.diatonicSeventh` | Add the diatonic 7th from the scale |
| `.diatonicExtensions(maxDegree:)` | Stack diatonic extensions up to the given degree (7, 9, 11, 13) |
| `.custom([Interval])` | Merge arbitrary intervals into the chord |

## Services

### `ChordBuilder`

Resolves a `ProgressionStep` into a `Chord`. Derives roots from scale degrees, applies the tension policy.

```swift
let chord = try ChordBuilder().buildChord(step: step, context: context)
```

`chordRecipe` wins over `scaleDegree` when both are present on a step.

### `VoiceLeadingEngine`

Converts a `Chord` into a register-specific `VoicedChord`. Generates all inversions across candidate octaves, rejects voicings outside `preferredRegister`, and scores candidates by voice movement, top-note leap, and bass-range penalty.

```swift
let voiced = try VoiceLeadingEngine().voice(
    chord: chord,
    previous: previousVoicedChord,
    context: context,
    policy: .nearest
)
```

### `MidiChordRenderer`

Combines `ChordBuilder` and `VoiceLeadingEngine` to produce sorted `MidiChordEvent` values from a full progression. Also exposes a `voice(progression:in:)` method to get the intermediate `[VoicedChord]` output.

```swift
let events = try MidiChordRenderer().render(progression: progression, in: context)
// events are sorted by (startBeat, note, channel)
```

Configurable at init: `velocity` (default `100`), `channel` (default `0`), and injectable `ChordBuilding` / `VoiceLeading` implementations.

## Quick Example

```swift
import MusicTheory
import HarmonyEngine

let context = HarmonyContext(tonic: .c, scale: Scale(type: .major, root: .c))

let progression = try Progression(
    steps: [
        ProgressionStep(bar: 1, beat: 0, durationBeats: 4, scaleDegree: 1),
        ProgressionStep(bar: 2, beat: 0, durationBeats: 4, scaleDegree: 4),
        ProgressionStep(bar: 3, beat: 0, durationBeats: 4, scaleDegree: 5),
        ProgressionStep(bar: 4, beat: 0, durationBeats: 4, scaleDegree: 1),
    ],
    loopLengthBars: 4
)

let events = try MidiChordRenderer().render(progression: progression, in: context)
```

## Error Handling

```swift
enum HarmonyEngineError: Error {
    case invalidScaleDegree(Int)
    case missingChordSource
    case invalidPitchRange(minMidi: Int, maxMidi: Int)
    case invalidProgressionStep(bar: Int, beat: Double, durationBeats: Double)
    case overlappingProgressionSteps
    case voicingOutOfRange
    case unableToResolveChord
}
```

No silent fallbacks — errors are thrown when harmonic intent cannot be resolved.

## Non-Goals

- Genre presets or taste rules
- Chord recognition or roman numeral analysis
- Reharmonization or AI suggestions
- DAW transport sync or plugin state
- UI or persistence
