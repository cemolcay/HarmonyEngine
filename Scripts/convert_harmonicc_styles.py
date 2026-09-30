#!/usr/bin/env python3
"""Converts the Harmonicc style tables into HarmonySuggest style profiles.

Usage:
    python3 Scripts/convert_harmonicc_styles.py <Harmonicc/Harmonics folder> > Sources/HarmonySuggest/StyleProfiles.swift

Input files:
    HarmonicStyle.swift     style characteristics and getNextFunctions tables
    HarmonicFunction.swift  the `next` table used by the `.general` style

Rules:
    - Transitions: the n-th listed next function gets RANK_WEIGHTS[n]. `HarmonicFunction.allCases` gives every
      degree ALL_CASES_WEIGHT. A `default:` case fills the functions that are not listed.
    - Flavors: chord qualities and extensions map to ChordFlavor weights. Triads and sevenths get a baseline.
    - Alterations and special chord types map to AlterationTension and ChromaticDevice values.
    - Borrowed chords that are commented out in Harmonicc are included (the new model can express them).
    - Cadence strength and voicing come from the style family tables below.
"""

import re
import sys
from pathlib import Path

DEGREES = {
    "tonic": 1, "supertonic": 2, "mediant": 3, "subdominant": 4,
    "dominant": 5, "submediant": 6, "leadingTone": 7,
}
RANK_WEIGHTS = [1.0, 0.8, 0.65, 0.5, 0.4, 0.35, 0.3]
ALL_CASES_WEIGHT = 0.6

QUALITY_FLAVORS = {
    # Diminished and augmented triads come from the scale; they do not make triads a main flavor of the style.
    "major": ("triad", 1.0), "minor": ("triad", 1.0), "diminished": ("triad", 0.3), "augmented": ("triad", 0.3),
    "dominantSeventh": ("dominantSeventh", 1.0), "majorSeventh": ("seventh", 1.0), "minorSeventh": ("seventh", 1.0),
    "diminishedSeventh": ("seventh", 1.0), "halfDiminished": ("seventh", 1.0), "minorMajorSeventh": ("seventh", 1.0),
    "suspended2": ("sus2", 0.5), "suspended4": ("sus4", 0.5), "dominantSuspendedFourth": ("sevenSus4", 0.5),
    "addedSixth": ("six", 0.5), "addedNinth": ("add9", 0.5), "sixNine": ("sixNine", 0.5),
}
EXTENSION_FLAVORS = {
    "ninth": [("ninth", 0.4)],
    "eleventh": [("eleventh", 0.3)],
    "thirteenth": [("thirteenth", 0.3)],
    "ninthEleventh": [("ninth", 0.4), ("eleventh", 0.3)],
    "ninthThirteenth": [("ninth", 0.4), ("thirteenth", 0.3)],
    "eleventhThirteenth": [("eleventh", 0.3), ("thirteenth", 0.3)],
    "fullThirteen": [("thirteenth", 0.3)],
}
FLAVOR_BASELINES = {"triad": 0.3, "dominantSeventh": 0.35, "seventh": 0.2}
FLAVOR_ORDER = ["triad", "dominantSeventh", "seventh", "ninth", "eleventh", "thirteenth", "sus2", "sus4", "sevenSus4",
                "six", "add9", "sixNine", "bluesSeventh"]
# Hand-tuned flavor weights that the Harmonicc tables cannot express.
FLAVOR_OVERRIDES = {"blues": {"seventh": 0.2, "ninth": 0, "thirteenth": 0, "bluesSeventh": 1.0}}
# The largest weight of a move to the same degree (the Harmonicc lists are not always in preference order).
SAME_DEGREE_CAP = 0.3

ALTERATIONS = {
    "flatNinth": ["flatNinth"], "sharpNinth": ["sharpNinth"], "bothNinths": ["flatNinth", "sharpNinth"],
    "sharpEleven": ["sharpEleventh"], "flatThirteenth": ["flatThirteenth"],
    "alteredDominant": ["flatNinth", "sharpNinth", "flatThirteenth"],
    "wholeTone": ["sharpEleventh", "flatThirteenth"],
    "flatFifth": ["sharpEleventh"], "sharpFifth": ["flatThirteenth"], "bothFifths": ["sharpEleventh", "flatThirteenth"],
    "alteredFifthNinth": ["flatNinth", "sharpEleventh"], "flatEleventh": [],
}
ALTERATION_ORDER = ["flatNinth", "sharpNinth", "sharpEleventh", "flatThirteenth"]

SPECIAL_DEVICES = {
    "secondaryDominantOfTwo": [(".appliedDominant(target: 2)", 0.6)],
    "secondaryDominantOfThree": [(".appliedDominant(target: 3)", 0.6)],
    "secondaryDominantOfFour": [(".appliedDominant(target: 4)", 0.6)],
    "secondaryDominantOfFive": [(".appliedDominant(target: 5)", 0.6)],
    "secondaryDominantOfSix": [(".appliedDominant(target: 6)", 0.6)],
    "secondaryDominantNinth": [(".appliedDominant(target: 2)", 0.4), (".appliedDominant(target: 5)", 0.4)],
    "secondaryDominantThirteen": [(".appliedDominant(target: 2)", 0.4), (".appliedDominant(target: 5)", 0.4)],
    "secondaryAlteredDominant": [(".appliedDominant(target: 2)", 0.4), (".appliedDominant(target: 5)", 0.4)],
    "tritoneSubstitute": [(".tritoneSubstitute(target: 1)", 0.6)],
    "substituteMinorTwo": [(".tritoneSubstitute(target: 2)", 0.5)],
    "substituteMinorFive": [(".tritoneSubstitute(target: 5)", 0.5)],
    "italianSixth": [(".augmentedSixth(.italian)", 0.5)],
    "frenchSixth": [(".augmentedSixth(.french)", 0.5)],
    "germanSixth": [(".augmentedSixth(.german)", 0.5)],
    "neapolitanSixth": [(".neapolitan", 0.5)],
    "cadentialSixFour": [(".cadentialSixFour", 0.5)],
    "diminishedPassing": [(".appliedLeadingTone(target: 2)", 0.4), (".appliedLeadingTone(target: 5)", 0.4)],
    "commonToneDiminished": [(".commonToneDiminished", 0.4)],
    # Commented out in Harmonicc; the new model can express them.
    "borrowedMinorOne": [(".borrowed(degree: 1, from: .minor)", 0.5)],
    "borrowedMinorFour": [(".borrowed(degree: 4, from: .minor)", 0.5)],
    "borrowedMinorSix": [(".borrowed(degree: 6, from: .minor)", 0.5)],
    "borrowedMinorSeven": [(".borrowed(degree: 7, from: .minor)", 0.5)],
    "borrowedMajorThree": [(".borrowed(degree: 3, from: .minor)", 0.5)],
    "borrowedMajorTwo": [(".borrowed(degree: 2, from: .phrygian)", 0.4)],
    "borrowedHalfDimTwo": [(".borrowed(degree: 2, from: .minor)", 0.4)],
    "borrowedDimSeven": [(".borrowed(degree: 7, from: .harmonicMinor)", 0.4)],
}
SPECIAL_ALTERATIONS = {"secondaryAlteredDominant": ["flatNinth", "sharpNinth"]}

# Styles that use the related ii of each applied dominant (ii–V chains).
RELATED_TWO_STYLES = {"swing", "bebop", "jazz", "fusion", "latinJazz", "bossa", "samba"}

CADENCE_STRENGTH = {
    "rAndB": 0.6, "funk": 0.6, "fusion": 0.6, "electronic": 0.6, "cinematic": 0.6, "contemporary": 0.6,
    "african": 0.6, "indian": 0.6, "middleEastern": 0.6,
    "ambient": 0.3, "modal": 0.3, "minimalist": 0.3, "impressionist": 0.3, "avantGarde": 0.3,
}
DROP2_ROOT_BASS = {"swing", "bebop", "jazz", "fusion", "latinJazz", "bossa", "samba", "rAndB", "funk"}
SPREAD = {"ambient", "cinematic", "impressionist"}


def strip_line_comments(text):
    return re.sub(r"//[^\n]*", "", text)


def names_in(text):
    return re.findall(r"\.(\w+)", strip_line_comments(text))


def parse_descriptions(style_source):
    block = style_source.split("var description: String {", 1)[1].split("var characteristics", 1)[0]
    return re.findall(r"case \.(\w+): return \"([^\"]+)\"", block)


def parse_characteristics(style_source):
    block = style_source.split("var characteristics: StyleCharacteristics {", 1)[1].split("// Style characteristics structure", 1)[0]
    result = {}
    for match in re.finditer(r"case \.(\w+):\s*return StyleCharacteristics\((.*?)\n\s*\)\s*\n", block, re.S):
        body = match.group(2)

        def array(label):
            found = re.search(label + r":\s*\[(.*?)\]", body, re.S)
            return found.group(1) if found else ""

        specials_text = array("preferredSpecialTypes")
        result[match.group(1)] = {
            "qualities": names_in(array("preferredQualities")),
            "extensions": names_in(array("preferredExtensions")),
            "alterations": names_in(array("preferredAlterations")),
            "specials": names_in(specials_text),
            "borrowed": re.findall(r"//\s*\.(borrowed\w+)", specials_text),
        }
    return result


def parse_function_lists(block):
    """Parses `case .fn: return [...]` / `default:` lines of a function switch."""
    lists = {}
    default = None
    for match in re.finditer(r"(case \.(\w+)|default):\s*\n?\s*return (HarmonicFunction\.allCases|\.next|\[(.*?)\])", block, re.S):
        values = "ALL" if match.group(3) == "HarmonicFunction.allCases" else names_in(match.group(4) or "")
        if match.group(1) == "default":
            default = values
        else:
            lists[match.group(2)] = values
    if default is not None:
        for function in DEGREES:
            lists.setdefault(function, default)
    return lists


def parse_transitions(style_source, function_source):
    block = style_source.split("func getNextFunctions", 1)[1]
    result = {}
    for match in re.finditer(r"case \.(\w+):\s*\n\s*switch current \{(.*?)\n\s*\}\s*\n", block, re.S):
        result[match.group(1)] = parse_function_lists(match.group(2))
    next_block = function_source.split("var next: [HarmonicFunction] {", 1)[1]
    result["general"] = parse_function_lists(next_block)
    return result


def transitions_swift(lists):
    lines = []
    for function, degree in DEGREES.items():
        targets = lists.get(function, [])
        if targets == "ALL":
            weighted = [(to, ALL_CASES_WEIGHT) for to in DEGREES.values()]
        else:
            weighted = [(DEGREES[name], RANK_WEIGHTS[min(rank, len(RANK_WEIGHTS) - 1)]) for rank, name in enumerate(targets)]
        for to, weight in weighted:
            if to == degree:
                weight = min(weight, SAME_DEGREE_CAP)
            lines.append(f"            DegreeTransition(from: {degree}, to: {to}, weight: {weight}),")
    return "\n".join(lines)


def profile_swift(style_id, name, characteristics, lists):
    flavors = dict(FLAVOR_BASELINES)
    for quality in characteristics["qualities"]:
        flavor, weight = QUALITY_FLAVORS[quality]
        flavors[flavor] = max(flavors.get(flavor, 0), weight)
    for extension in characteristics["extensions"]:
        for flavor, weight in EXTENSION_FLAVORS[extension]:
            flavors[flavor] = max(flavors.get(flavor, 0), weight)
    flavors.update(FLAVOR_OVERRIDES.get(style_id, {}))

    alterations = set()
    for alteration in characteristics["alterations"]:
        alterations.update(ALTERATIONS[alteration])
    for special in characteristics["specials"]:
        alterations.update(SPECIAL_ALTERATIONS.get(special, []))

    devices = {}
    for special in characteristics["specials"] + characteristics["borrowed"]:
        for device, weight in SPECIAL_DEVICES[special]:
            devices[device] = max(devices.get(device, 0), weight)
    if style_id in RELATED_TWO_STYLES:
        for device in list(devices):
            target = re.match(r"\.appliedDominant\(target: (\d)\)", device)
            if target:
                key = f".relatedSupertonic(target: {target.group(1)})"
                devices[key] = max(devices.get(key, 0), 0.4)

    if style_id in DROP2_ROOT_BASS:
        voicing = "VoicingOptions(style: .drop2, bassMode: .root)"
    elif style_id in SPREAD:
        voicing = "VoicingOptions(style: .spread)"
    else:
        voicing = "VoicingOptions()"

    flavor_lines = ", ".join(f".{f}: {flavors[f]}" for f in FLAVOR_ORDER if flavors.get(f, 0) > 0)
    alteration_lines = ", ".join(f".{a}" for a in ALTERATION_ORDER if a in alterations)
    device_lines = "\n".join(f"            DeviceWeight({d}, weight: {w})," for d, w in devices.items())
    devices_swift = f"[\n{device_lines}\n        ]" if devices else "[]"

    return f"""    /// {name}.
    static let {style_id} = StyleProfile(
        id: "{style_id}",
        name: "{name}",
        transitions: [
{transitions_swift(lists)}
        ],
        flavors: [{flavor_lines}],
        alterations: [{alteration_lines}],
        devices: {devices_swift},
        cadenceStrength: {CADENCE_STRENGTH.get(style_id, 1.0)},
        voicing: {voicing}
    )
"""


def main():
    folder = Path(sys.argv[1])
    style_source = (folder / "HarmonicStyle.swift").read_text()
    function_source = (folder / "HarmonicFunction.swift").read_text()

    descriptions = parse_descriptions(style_source)
    characteristics = parse_characteristics(style_source)
    transitions = parse_transitions(style_source, function_source)

    missing = [s for s, _ in descriptions if s not in characteristics or s not in transitions]
    if missing:
        sys.exit(f"Missing tables for: {missing}")

    print("// Generated by Scripts/convert_harmonicc_styles.py from the Harmonicc style tables.")
    print("// Edit the script and generate the file again. Do not edit this file by hand.")
    print()
    print("import HarmonyEngine")
    print()
    print("public extension StyleProfile {")
    for style_id, name in descriptions:
        print(profile_swift(style_id, name, characteristics[style_id], transitions[style_id]))
    print("    /// All styles, in the Harmonicc order.")
    print("    static let all: [StyleProfile] = [")
    for style_id, _ in descriptions:
        print(f"        {style_id},")
    print("    ]")
    print()
    print("    /// The style with this identifier.")
    print("    static func named(_ id: String) -> StyleProfile? {")
    print("        all.first { $0.id == id }")
    print("    }")
    print("}")


if __name__ == "__main__":
    main()
