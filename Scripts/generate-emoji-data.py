#!/usr/bin/env python3
"""Builds Resources/emoji.json from Unicode data files.

Usage: generate-emoji-data.py <data-dir> <output.json>

<data-dir> must contain, from
https://github.com/unicode-org/cldr-json (cldr-annotations-full and
cldr-annotations-derived-full) and https://unicode.org/Public/emoji/latest/:

    ann-en.json  ann-ru.json  der-en.json  der-ru.json  emoji-test.txt
"""
import json
import re
import sys
from pathlib import Path

# Newest Emoji version that macOS 14 can draw. Raise it when the minimum OS rises.
MAX_EMOJI_VERSION = 15.1
SKIN_TONES = {chr(c) for c in range(0x1F3FB, 0x1F400)}
LINE = re.compile(r"^[0-9A-F ]+;\s*([a-z-]+)\s*#\s*(\S+)\s+E(\d+\.\d+)\s")


def strip_vs(text):
    return text.replace("️", "")


def read_annotations(data_dir, language):
    merged = {}
    for name, root in ((f"ann-{language}.json", "annotations"), (f"der-{language}.json", "annotationsDerived")):
        document = json.loads((data_dir / name).read_text(encoding="utf-8"))
        for key, value in document[root]["annotations"].items():
            merged[strip_vs(key)] = value
    return merged


def read_emoji(data_dir):
    """Returns (displayable emoji in keyboard order, every key emoji-test mentions)."""
    ordered, known = [], set()
    for line in (data_dir / "emoji-test.txt").read_text(encoding="utf-8").splitlines():
        match = LINE.match(line)
        if not match:
            continue
        status, character, version = match.groups()
        known.add(strip_vs(character))
        if status != "fully-qualified" or float(version) > MAX_EMOJI_VERSION:
            continue
        if SKIN_TONES & set(character):
            continue
        ordered.append(character)
    return ordered, known


def record(character, english, russian):
    key = strip_vs(character)
    en, ru = english.get(key), russian.get(key, {})
    if not en or not en.get("tts"):
        return None
    keywords = sorted({*en.get("default", []), *ru.get("default", [])})
    return {"c": character, "n": en["tts"][0], "r": ru.get("tts", [""])[0], "k": keywords}


def main():
    data_dir, output = Path(sys.argv[1]), Path(sys.argv[2])
    english, russian = read_annotations(data_dir, "en"), read_annotations(data_dir, "ru")
    emoji, known_emoji = read_emoji(data_dir)
    symbols = sorted(key for key in english if key not in known_emoji and not SKIN_TONES & set(key))
    records = [r for r in (record(c, english, russian) for c in [*emoji, *symbols]) if r]
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(records, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"{len(records)} entries, {len(emoji)} emoji, {len(symbols)} symbols, {output.stat().st_size} bytes")


if __name__ == "__main__":
    main()
