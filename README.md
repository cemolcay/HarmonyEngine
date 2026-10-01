# HarmonyEngine

A reusable Swift library for harmonic decision-making that sits above the [`MusicTheory`](https://github.com/cemolcay/MusicTheory) core library.

`HarmonyEngine` handles chord generation, voice leading, and MIDI note output. Sequencing, timing, and DAW integration belong to the app layer.

The package has two libraries:

- `HarmonyEngine` — style-free chord building, naming, measures, and voicing.
- `HarmonySuggest` — style profiles, next-chord ranking, and progression generation, built on `HarmonyEngine`.

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
    ChordSpec.swift           — ChordSpec, ChordRoot, ChordBass (chromatic chords)
    ChordBuilder.swift        — ChordBuilding protocol + ChordBuilder, AvoidNotePolicy
    ChordNamer.swift          — Roman numeral and chord symbol names
    VoiceLeadingEngine.swift  — VoiceLeading protocol + VoiceLeadingEngine, VoicedChord, VoicingOptions
    ScaleFit.swift            — ScaleFit, VoiceLeadingDistance
    TransitionMetrics.swift   — measures of the move between two chords
    HarmonicPalette.swift     — diatonic chord catalog and role-based queries
    Errors.swift              — HarmonyEngineError
  Sources/HarmonySuggest/
    StyleProfile.swift        — StyleProfile, ChordFlavor, ChromaticDevice, AlterationTension
    StyleProfiles.swift       — the 32 generated style profiles (do not edit by hand)
    Suggestion.swift          — SuggestionRequest, SuggestionKnobs, PhrasePosition, Suggestion, SuggestionWeights
    CandidateGenerator.swift  — candidate chords for a context and profile
    SuggestionEngine.swift    — scoring and ranking
    ProgressionGenerator.swift — seeded beam search, SplitMix64
  Scripts/
    convert_harmonicc_styles.py — generates StyleProfiles.swift from the Harmonicc style tables
  Tests/HarmonyEngineTests/
    HarmonyEngineTests.swift
    ChordSpecTests.swift
    VoicingTests.swift
  Tests/HarmonySuggestTests/
    HarmonySuggestTests.swift
    SuggestionDumpTests.swift — prints rankings when HARMONY_SUGGEST_DUMP=1
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
| `.keepClose` | Lowest inversion, then the lowest placement in the register (no scoring) |
| `.nearest` | Lowest score from all inversions (minimum voice movement from the previous chord) |
| `.fixed(Int)` | Exact inversion index; the octave with the lowest score |

`.rootPosition` and `.fixed` also score their candidates, so they follow the previous chord.

### `TensionPolicy`

| Case | Behavior |
|---|---|
| `nil` | Defer to role default |
| `.none` | No tension — use chord type as-is |
| `.diatonicSeventh` | Add the diatonic 7th from the scale |
| `.diatonicExtensions(maxDegree:)` | Stack diatonic extensions up to the given degree (7, 9, 11, 13). Avoid notes are removed (see `AvoidNotePolicy`) |
| `.custom([Interval])` | Merge arbitrary intervals into the chord |

### `ChordSpec`

Describes a chord relative to the context, including chromatic chords. It transposes with the key and scale.

```swift
ChordSpec.degree(2, tension: .diatonicSeventh)              // ii7
ChordSpec(root: .degree(7, alteration: -1), type: .major)    // ♭VII (explicit type)
ChordSpec(root: .borrowed(degree: 6, from: .minor))          // ♭VI from the parallel minor
ChordSpec(root: .applied(.dominant, of: 2))                  // V7/ii
ChordSpec(root: .applied(.leadingTone, of: 5))               // vii°7/V
ChordSpec(root: .applied(.tritoneSubstitute, of: 1))         // subV7/I
ChordSpec(root: .applied(.supertonic, of: 5))                // ii7/V
ChordSpec(root: .neapolitan, bass: .inversion(1))            // N6
ChordSpec(root: .augmentedSixth(.german))                    // Ger+6
ChordSpec(root: .commonToneDiminished(of: 1))                // CT°7/I
ChordSpec(root: .degree(1), bass: .scaleDegree(3))           // I/3 (slash bass)
```

| Root | Default type when `type` is `nil` |
|---|---|
| `.degree(n)`, `.borrowed` | Diatonic triad of the source scale |
| `.degree(n, alteration:)` with an alteration | None: throws `missingChordType` |
| `.applied(.dominant / .tritoneSubstitute, of:)` | Dominant 7th |
| `.applied(.leadingTone, of:)` | Diminished 7th |
| `.applied(.supertonic, of:)` | Minor 7th, or half-diminished 7th when the target is minor |
| `.neapolitan` | Major triad |
| `.augmentedSixth` | It: ♭6–1–♯4, Fr: ♭6–1–2–♯4, Ger: ♭6–1–♭3–♯4 (the ♯4 is spelled as a ♭7) |
| `.commonToneDiminished` | Diminished 7th on the target root |

`ChordRoot.resolutionTarget` gives the degree that the chord normally resolves to (for example 2 for V/ii, 5 for N6).

```swift
let chord = try ChordBuilder().buildChord(spec: spec, context: context)
let name  = try ChordNamer().name(spec: spec, context: context)   // name.roman == "V7/ii", name.symbol == "A7"
```

### `AvoidNotePolicy`

`ChordBuilder(avoidNotes:)` controls diatonic extension stacking. The default `.omit` removes the natural 11th over a major 3rd, and the ♭9th and ♭13th over chords that are not dominant 7ths. `.keep` keeps all stacked notes.

### `VoicingOptions`

`VoiceLeadingEngine(options:)` sets the voicing shape. The defaults give the close voicing of the first version.

| Option | Behavior |
|---|---|
| `style` | `.close`, `.drop2`, `.drop3`, `.drop2and4`, `.spread`, `.shell` (3rd and 7th), `.rootless` |
| `maxVoices` | Removes the 5th, then the root, the 11th, the 9th, until the count fits (at least 2 voices) |
| `bassMode` | `.chordBass` (slash bass or inversion tone) or `.root` |
| `doublesBassInUpperVoices` | `false` removes the bass pitch class from the upper voices |
| `topVoiceTarget` | A MIDI note that the top voice moves toward |
| `registerCenterWeight` | Moves the voicing toward the middle of the preferred register |

The bass goes to the pitch nearest to the previous bass. Voice movement uses `VoiceLeadingDistance`: sorted voices for the same voice count, or the smallest split/merge movement for different voice counts.

### `ScaleFit` and `TransitionMetrics`

```swift
ScaleFit.isDiatonic(chord, in: context.scale)
ScaleFit.outsidePitchClasses(of: chord, in: context.scale)

let metrics = TransitionMetrics(from: previousChord, to: chord, scale: context.scale)
metrics.rootMotion            // 0–11 semitones up
metrics.commonTones
metrics.voiceLeadingDistance
metrics.tension               // semitone, major 7th, and tritone pairs in the target chord
metrics.outsideNotes
```

A suggestion layer can combine these values into a score. They contain no style rules.

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

## HarmonySuggest

### Style profiles

A `StyleProfile` is Codable data. It contains:

| Field | Meaning |
|---|---|
| `transitions` | Weights of moves between Roman numeral degrees (1–7) |
| `openingWeights` | Weights of degrees as the first chord |
| `flavors` | Weights of chord flavors: triad, dominant 7th, 7th, 9th, 11th, 13th, sus2, sus4, 7sus4, 6, add9, 6/9, blues 7th |
| `alterations` | ♭9, ♯9, ♯11, ♭13 on dominant chords (♯11 on major 7ths only when it is in the scale) |
| `devices` | Chromatic devices and weights: V/x, vii°7/x, subV/x, ii/x, borrowed chords, N6, augmented sixths, CT°7, I64 |
| `rootMotionWeights` | Weights of root motion by interval class |
| `cadenceStrength` | How strongly phrases end on a cadence |
| `voicing` | The default `VoicingOptions` of the style |

`StyleProfile.all` has the 32 Harmonicc styles (`StyleProfile.jazz`, `StyleProfile.named("rAndB")`, …).
They are generated from the Harmonicc tables:

```sh
python3 Scripts/convert_harmonicc_styles.py ../Harmonicc/Harmonicc/Harmonics > Sources/HarmonySuggest/StyleProfiles.swift
```

To tune a style, change the tables or the mappings in the script, and generate the file again.

### Ranking the next chord

```swift
import HarmonySuggest

let request = SuggestionRequest(
    context: context,
    profile: .jazz,
    history: [.degree(2, tension: .diatonicSeventh)],        // the chords so far
    position: PhrasePosition(step: 3, length: 4),            // optional: the phrase position
    knobs: SuggestionKnobs(complexity: 0.5, chromaticism: 0.5, brightness: 0.5)
)
for suggestion in SuggestionEngine().suggestions(for: request) {
    print(suggestion.name.roman, suggestion.name.symbol, suggestion.category, suggestion.reasons)
    // V7 G7 diatonic [...]
}
```

The score adds these terms (see `SuggestionEngine` and `SuggestionWeights`):

- style transition and flavor weights (chromatic devices use their weight scaled by the chromaticism knob),
- voice leading and common tones of the triad cores,
- root motion,
- resolution of the current chord (V/x → x, ii/x → V/x, N6 and augmented sixths → V, CT°7 → its chord, I64 → V),
- cadence at the end of a phrase,
- the complexity and brightness knobs (no effect at 0.5),
- repetition and back-and-forth loops.

Each `Suggestion` has a `category` (`.diatonic`, `.color`, `.chromatic`) and up to 3 `reasons`.
The ranking is deterministic. At most `maxPerRoot` suggestions share a root.

### Generating a progression

```swift
let specs = ProgressionGenerator().generate(length: 8, context: context, profile: .pop, seed: 42)
```

The generator does a beam search over the rankings, with a seeded random value for variety (`temperature`).
The same seed gives the same progression. When `cadenceStrength` ≥ 0.5, the last chord is the tonic.

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
    case missingChordType
    case invalidInversion(Int)
}
```

No silent fallbacks — errors are thrown when harmonic intent cannot be resolved.
For scales that do not have 7 notes, a chord with no explicit type needs a third and a fifth in the scale.

`ChordSpec` adds two errors: `missingChordType` (an altered degree without a type) and `invalidInversion(Int)`.

## Non-Goals

- Progression sequencing or beat/bar timing
- MIDI event scheduling (start time, duration, velocity, channel)
- Genre presets or taste rules
- Chord recognition from notes (`ChordNamer` names a known `ChordSpec`; it does not analyse note lists)
- Reharmonization or AI suggestions
- DAW transport sync or plugin state
- UI or persistence
