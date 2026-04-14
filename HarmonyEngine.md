# HarmonyEngine

## Purpose

`HarmonyEngine` is the reusable layer that sits above the `MusicTheory` core library and below any app- or genre-specific logic.

It should not change the core `MusicTheory` package. It should consume:

- `NoteName`
- `Pitch`
- `Interval`
- `Scale`
- `ScaleType`
- `Chord`
- `ChordType`

Its job is to provide:

- harmonic context
- progression modeling
- chord generation from scale degrees or recipes
- voice-leading and voicing selection
- MIDI-ready note output

It should not provide:

- UI code
- DAW/plugin integration
- persistence
- app-specific presets
- genre-specific taste rules

## Design Goals

- Keep the module reusable across multiple music apps.
- Favor deterministic output for the same input and config.
- Make harmonic decisions explicit through config and strategy types.
- Separate harmonic intent from note rendering.
- Keep style-agnostic defaults.

## Module Boundaries

### `MusicTheory` core

Owns pure music objects:

- notes
- intervals
- scales
- chords
- spelling
- inversion-aware chord pitch generation

### `HarmonyEngine`

Owns decision-making:

- which chord to choose
- which inversion to use
- which octave/register to place voices in
- how tensions are added or removed
- how bass motion is constrained
- how chords are converted into MIDI note lists

### App layer

Owns:

- user controls
- preset browsing
- sequencing timeline
- export
- plugin state

## Core Types

### `HarmonyContext`

Defines the harmonic environment.

Suggested fields:

```swift
struct HarmonyContext {
    let tonic: NoteName
    let scale: Scale
    let tempo: Tempo?
    let preferredRegister: PitchRange
    let bassRegister: PitchRange
}
```

Rules:

- `scale` is the active pitch collection.
- `tonic` is the tonal center and may differ from `scale.root` in modal contexts if needed later.
- register ranges are constraints, not guarantees.

### `PitchRange`

Simple reusable range type.

```swift
struct PitchRange {
    let minMidi: Int
    let maxMidi: Int
}
```

Rules:

- use inclusive bounds
- validate `minMidi <= maxMidi`

### `HarmonyRole`

Functional grouping for chord choices.

```swift
enum HarmonyRole {
    case tonic
    case predominant
    case dominant
    case color
    case passing
}
```

This is intentionally broad. Do not model advanced academic function taxonomies yet.

### `ProgressionStep`

Represents one harmonic slot.

```swift
struct ProgressionStep {
    let bar: Int
    let beat: Double
    let durationBeats: Double
    let role: HarmonyRole?
    let scaleDegree: Int?
    let chordRecipe: ChordRecipe?
}
```

Rules:

- allow either `scaleDegree` or `chordRecipe`
- `chordRecipe` wins if both are present
- keep timing simple: beats within bars

### `Progression`

Collection of ordered progression steps.

```swift
struct Progression {
    let steps: [ProgressionStep]
    let loopLengthBars: Int
}
```

Rules:

- steps sorted by `(bar, beat)`
- no overlapping steps in v1

### `ChordRecipe`

Describes harmonic intent without fixing final voicing.

```swift
struct ChordRecipe {
    let root: NoteName?
    let scaleDegree: Int?
    let chordType: ChordType
    let inversionPolicy: InversionPolicy
    let tensionPolicy: TensionPolicy
}
```

Rules:

- use `root` for absolute chords
- use `scaleDegree` for diatonic/modal chords
- one of `root` or `scaleDegree` must be set

### `InversionPolicy`

```swift
enum InversionPolicy {
    case rootPosition
    case keepClose
    case nearest
    case fixed(Int)
}
```

Semantics:

- `rootPosition`: always use inversion `0`
- `keepClose`: prefer lowest inversion that fits register cleanly
- `nearest`: choose inversion with minimum voice movement from prior chord
- `fixed(Int)`: exact inversion index

### `TensionPolicy`

```swift
enum TensionPolicy {
    case none
    case diatonicSeventh
    case diatonicExtensions(maxDegree: Int)
    case custom([Interval])
}
```

Rules:

- use this to derive richer chord types from simpler harmonic intent
- keep tension selection deterministic

### `VoicedChord`

Final harmony output before MIDI conversion.

```swift
struct VoicedChord {
    let chord: Chord
    let pitches: [Pitch]
    let bassPitch: Pitch
    let topPitch: Pitch
}
```

Rules:

- `pitches` sorted ascending
- `bassPitch == pitches.first`
- `topPitch == pitches.last`

## Engine Services

### `ChordBuilder`

Responsibility:

- resolve a `ProgressionStep` into a `Chord`
- derive roots from scale degrees
- apply tension policy before voicing

Methods:

```swift
protocol ChordBuilding {
    func buildChord(step: ProgressionStep, context: HarmonyContext) throws -> Chord
}
```

Behavior:

- for degree-based chords, use `context.scale.noteNames`
- map degree to root note directly
- do not perform harmonic analysis
- do not choose octave/register here

### `VoiceLeadingEngine`

Responsibility:

- convert a `Chord` into a playable register-specific `VoicedChord`
- choose inversion
- keep movement smooth when configured

Methods:

```swift
protocol VoiceLeading {
    func voice(
        chord: Chord,
        previous: VoicedChord?,
        context: HarmonyContext,
        policy: InversionPolicy
    ) -> VoicedChord
}
```

V1 algorithm:

- generate all chord inversions using `Chord.inversions`
- for each inversion, generate pitches across candidate octaves around preferred register
- reject voicings outside `preferredRegister`
- score each candidate by:
  - total semitone movement from `previous`
  - top-note leap penalty
  - bass-range penalty
- choose lowest score

Do not implement advanced SATB rules in v1.

### `MidiChordRenderer`

Responsibility:

- convert `VoicedChord` to MIDI note numbers and timing events

Methods:

```swift
struct MidiChordEvent {
    let note: Int
    let velocity: Int
    let startBeat: Double
    let durationBeats: Double
    let channel: Int
}
```

```swift
protocol MidiRendering {
    func render(progression: Progression, in context: HarmonyContext) throws -> [MidiChordEvent]
}
```

Rules:

- use voiced pitches as-is
- no humanization in v1
- channel default = 0
- velocity default configurable at renderer init

## Suggested File Layout

If this is built in a separate package/module, use:

```text
HarmonyEngine/
  HarmonyContext.swift
  Progression.swift
  ChordRecipe.swift
  ChordBuilder.swift
  VoiceLeadingEngine.swift
  MidiChordRenderer.swift
  Errors.swift
```

If built in the same repo first, place docs only for now and keep code in a separate target later.

## Error Model

Use explicit typed errors:

```swift
enum HarmonyEngineError: Error {
    case invalidScaleDegree(Int)
    case missingChordSource
    case voicingOutOfRange
    case unableToResolveChord
}
```

Do not use silent fallbacks when the harmonic intent cannot be resolved.

## V1 Acceptance Criteria

- Can generate a chord from a scale degree and `ChordType`
- Can generate a small progression as ordered `VoicedChord` values
- Can choose inversions using a deterministic nearest-voice algorithm
- Can render MIDI note events from the progression
- Produces stable output for the same input

## Tests

Write tests for:

- degree-to-root resolution in major and minor scales
- custom `Scale(intervals:root:name:)` contexts
- inversion selection with and without previous chord
- register constraints
- MIDI event rendering order and note values
- deterministic output for repeated runs

## Defaults

Use these defaults unless an app layer overrides them:

- inversion policy: `.nearest`
- tension policy: `.none`
- preferred register: MIDI `60...84`
- bass register: MIDI `36...55`
- velocity: `100`

## Non-Goals

- genre presets
- chord recognition
- roman numeral analysis
- reharmonization suggestion AI
- DAW transport sync
- random generation without seeded control
