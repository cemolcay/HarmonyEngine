# HarmonyEngine

## Purpose

`HarmonyEngine` is the reusable layer that sits above the `MusicTheory` core library and below any app- or genre-specific logic.

It does not change the core `MusicTheory` package. It consumes:

- `NoteName`
- `Pitch`
- `Interval`
- `Scale`
- `ScaleType`
- `Chord`
- `ChordType` / `ChordComponent`

It provides:

- harmonic context
- chord generation from scale degrees, recipes, and chord specs (including chromatic chords)
- chord names (Roman numeral and symbol)
- scale fit and transition measures
- voice-leading and voicing selection
- MIDI-ready note output (`VoicedChord.midiNotes`)

It does not provide:

- UI code
- DAW/plugin integration
- persistence
- app-specific presets
- genre-specific taste rules
- timing, sequencing, or MIDI event scheduling (the app and BUDKit own these)

## Design Goals

- Keep the module reusable across multiple music apps.
- Favor deterministic output for the same input and config.
- Make harmonic decisions explicit through config and strategy types.
- Separate harmonic intent (`ChordRecipe`, `ChordSpec`) from note rendering (`VoicedChord`).
- Keep style-agnostic defaults.
- No silent fallbacks: when the intent cannot be resolved, throw a `HarmonyEngineError`.

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

Owns decision-making without taste:

- which root and chord type a spec resolves to
- which inversion to use
- which octave/register and voicing shape to use
- how tensions are added, and which avoid notes are removed
- how the bass is placed
- how a chord is named in a key
- how two chords compare (common tones, root motion, voice movement, tension)

### `HarmonySuggest` (separate target in this package)

Owns taste:

- style profiles (Codable data, generated from the Harmonicc style tables by `Scripts/convert_harmonicc_styles.py`)
- candidate generation: diatonic chord flavors on every degree (checked with `ScaleFit`), alterations, and chromatic devices
- ranking of the next chord (`SuggestionEngine`), with reasons and categories
- progression generation (`ProgressionGenerator`, seeded beam search)

It uses the `HarmonyEngine` types and measures. The core target stays free of style rules.
See the README for the score terms.

### App layer

Owns:

- user controls
- preset browsing
- sequencing timeline and MIDI scheduling
- export
- plugin state

## Core Types

### `HarmonyContext`

The harmonic environment: `tonic`, `scale`, optional `tempo`, `preferredRegister` (upper voices), and `bassRegister`.

- `scale` is the active pitch collection. Degrees are 1-based indices into `scale.noteNames`.
- `tonic` is the tonal centre. Borrowed chords use a parallel scale on the tonic.
- Register ranges are constraints for candidate placement.

### `PitchRange`

Inclusive MIDI range. The initializer throws `invalidPitchRange` when `minMidi > maxMidi`.

### `HarmonyRole`

Broad function signal: `tonic`, `predominant`, `dominant`, `color`, `passing`. It sets tension defaults in `ChordRecipe` and biases the voicing score.

### `ChordRecipe`

Harmonic intent with an absolute `root` or a diatonic `scaleDegree`, an optional `chordType`, `role`, `inversionPolicy`, and `tensionPolicy`. `root` wins when both are set.

### `ChordSpec`

Harmonic intent relative to the context. It can express chromatic chords:

| `ChordRoot` | Meaning |
|---|---|
| `.degree(n, alteration:)` | Scale degree, optionally altered (♭VII) |
| `.borrowed(degree:from:)` | Degree of a parallel scale on the tonic |
| `.applied(function, of:)` | V/x, vii°/x, subV/x, ii/x |
| `.neapolitan` | Major triad on ♭2 |
| `.augmentedSixth(kind)` | It+6, Fr+6, Ger+6 on ♭6 |
| `.commonToneDiminished(of:)` | °7 on the target root |

`ChordBass` sets the bass: `.root`, `.inversion(k)`, or `.scaleDegree(n)` (slash chord or pedal).

Rules:

- A `nil` type uses the default of the root kind. An altered degree has no default and throws `missingChordType`.
- Diatonic tension policies need a diatonic source scale (`.degree` without alteration, or `.borrowed`). Other roots throw `unableToResolveChord`.
- `ChordRoot.resolutionTarget` gives the expected resolution degree of chromatic devices.

### `InversionPolicy`

- `rootPosition`: inversion `0`, the best-scored octave
- `keepClose`: lowest inversion, then lowest placement (no scoring)
- `nearest`: best score from all inversions
- `fixed(Int)`: that inversion, the best-scored octave

### `TensionPolicy`

`none`, `diatonicSeventh`, `diatonicExtensions(maxDegree:)`, `custom([Interval])`. Diatonic policies stack scale thirds from the degree. Each stacked note goes to the nearest octave above the previous note (octaves change at C, not at the scale root).

### `AvoidNotePolicy`

`.omit` (default) removes the natural 11 over a major 3rd, and ♭9 / ♭13 over chords that are not dominant 7ths. `.keep` keeps all stacked notes.

### `VoicedChord`

Final output: `chord`, sorted `upperVoices`, and a separate `bassVoice`. `midiNotes` gives all notes, sorted.

## Engine Services

### `ChordBuilder`

- `buildChord(recipe:context:)` and `buildChord(spec:context:)`
- Derives roots from degrees, parallel scales, and applied targets.
- Infers diatonic types by stacking scale thirds (heptatonic scales). For other scales, a triad needs a third and a fifth in the scale.
- Applies the tension and avoid-note policies.

### `ChordNamer`

`name(spec:context:)` returns `ChordName(roman:symbol:)`. Numerals use case for the third, accidentals for roots that are not the scale note of that degree, quality suffixes (`°`, `ø7`, `°7`, `+`, `7`, `maj7`, extensions), and figured-bass inversions (`6`, `64`, `65`, `43`, `42`).

### `ScaleFit`, `VoiceLeadingDistance`, `TransitionMetrics`

- `ScaleFit`: chord pitch classes, outside notes, `isDiatonic`.
- `VoiceLeadingDistance`: voice movement between two voicings (sorted pairing for equal counts, split/merge dynamic programming for different counts), and a pitch-class distance between chords.
- `TransitionMetrics`: root motion, common tones, voice-leading distance, tension, tension change, outside notes.

### `VoiceLeadingEngine`

Configured with `VoicingOptions` (style, max voices, bass mode, bass doubling, top-voice target, register-centre weight).

Algorithm:

1. For each allowed inversion, take the chord tones from the inversion tone, and remove the tones that the style, `maxVoices`, and bass doubling ask to remove.
2. Stack the tones in chord-tone order, then apply the style (drop 2, drop 3, drop 2 & 4, spread).
3. Place the shape in every octave that keeps all upper voices in `preferredRegister`.
4. Place the bass near the previous bass (or the register middle).
5. Filter by `VoicingConstraints` (best effort: fall back to all candidates).
6. Score: voice movement + voice-count change + top-voice leap ×1.5 + bass outside register ×4 + role bias + top-voice target + register centre. Pick by policy. Ties: inversion, bass, top.

## Error Model

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

## Tests

The tests cover:

- degree-to-root resolution in major, minor, and custom scales
- diatonic triads and sevenths in every heptatonic scale type and every key (all notes in the scale)
- avoid-note removal
- borrowed, altered, applied, Neapolitan, augmented sixth, and common-tone diminished chords
- Roman numerals, figures, and symbols
- golden progressions (Creedence, Andalusian cadence, Coltrane changes)
- voicing styles, omissions, bass modes, targets, and invariants over all styles and inversions
- register constraints and deterministic output

## Defaults

- inversion policy: `.nearest`
- tension policy: `.none`
- avoid notes: `.omit`
- voicing: `.close`, bass follows the inversion, bass doubled in the upper voices
- preferred register: MIDI `60...84`
- bass register: MIDI `36...55`

## Non-Goals

- genre presets and taste rules in the core target (see `HarmonySuggest`)
- chord recognition from arbitrary note lists
- DAW transport sync
- MIDI event timing
- random generation without seeded control
