#!/usr/bin/env python3
"""Parse all LegoPartsCatalog*.swift files and emit a single JSON resource.

Output schema (array of objects):
  {
    "partNumber": "3001",
    "name": "Brick 2x4",
    "category": "Brick",
    "dimensions": {"studsWide": 2, "studsLong": 4, "heightUnits": 3},
    "commonColors": ["Red","Blue",...] | "_all" | "_basic" | "_structural" | "_bright" | "_trans",
    "weight": 2.32,
    "keywords": ["basic"]
  }

The color-set sentinels ("_all" etc.) preserve the existing aliasing —
the Swift loader expands them at decode time so we don't bloat the JSON
with the full 22-element color array repeated 1,600 times.
"""
import re
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SERVICES = ROOT / "Bricky" / "Services"
OUT_PATH = ROOT / "Bricky" / "Resources" / "LegoPartsCatalog.json"

CATALOG_FILES = [
    "LegoPartsCatalog.swift",
    "LegoPartsCatalogExtended.swift",
    "LegoPartsCatalogExtended2.swift",
    "LegoPartsCatalogExtended3.swift",
    "LegoPartsCatalogExtended4.swift",
    "LegoPartsCatalogExtended5.swift",
    "LegoPartsCatalogExtended6.swift",
]

# Color-list aliases recognized in the Swift sources. Any literal color
# array matching one of these gets emitted as the sentinel string instead.
COLOR_ALIASES = {
    "allColors": "_all",
    "basicColors": "_basic",
    "structuralColors": "_structural",
    "brightColors": "_bright",
    "transColors": "_trans",
}

# Map raw enum names to LegoColor rawValues. Built from LegoColor enum.
COLOR_ENUM_TO_RAW = {
    "red": "Red", "blue": "Blue", "yellow": "Yellow", "green": "Green",
    "black": "Black", "white": "White", "gray": "Gray", "darkGray": "Dark Gray",
    "orange": "Orange", "brown": "Brown", "tan": "Tan", "darkBlue": "Dark Blue",
    "darkGreen": "Dark Green", "darkRed": "Dark Red", "lime": "Lime",
    "purple": "Purple", "pink": "Pink", "lightBlue": "Light Blue",
    "transparent": "Transparent", "transparentBlue": "Trans Blue",
    "transparentRed": "Trans Red",
}

# Match the entire CatalogPiece(...) call. Multiline. We use a balanced
# parens approach since regex can't fully handle nested parens, but the
# arguments here only nest one level (PieceDimensions(...) and arrays).
PIECE_START_RE = re.compile(r"CatalogPiece\(\s*partNumber:\s*\"([^\"]+)\"")


def find_piece_blocks(text: str):
    """Yield (start, end) char offsets for each CatalogPiece(...) call."""
    for match in PIECE_START_RE.finditer(text):
        start = match.start()
        # Walk forward counting parens until we close the outer ()
        depth = 0
        i = start
        n = len(text)
        # advance past the constructor name to the first '('
        while i < n and text[i] != "(":
            i += 1
        # i is at first '('
        while i < n:
            c = text[i]
            if c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
                if depth == 0:
                    yield start, i + 1
                    break
            elif c == "\"":
                # skip string literals so internal parens don't confuse us
                i += 1
                while i < n and text[i] != "\"":
                    if text[i] == "\\":
                        i += 1
                    i += 1
            i += 1


KEYWORDS_RE = re.compile(r"keywords:\s*\[([^\]]*)\]")
NAME_RE = re.compile(r'name:\s*"([^"]*)"')
CATEGORY_RE = re.compile(r"category:\s*\.([a-zA-Z]+)")
DIMS_RE = re.compile(
    r"PieceDimensions\(\s*studsWide:\s*(\d+)\s*,\s*studsLong:\s*(\d+)\s*,\s*heightUnits:\s*(\d+)"
)
WEIGHT_RE = re.compile(r"weight:\s*([0-9.]+)")
COMMON_COLORS_RE = re.compile(r"commonColors:\s*([^,\n][^\n]*)")


def parse_color_argument(raw: str):
    """Return either a sentinel string or a list of LegoColor raw values."""
    raw = raw.strip()
    # Strip trailing comma if present (we matched up to next field)
    if raw.endswith(","):
        raw = raw[:-1].strip()
    # Trim trailing close-paren if we accidentally captured it (final field)
    # We only want the value expression itself.
    # Aliased identifier case: bare identifier (no brackets, no '.')
    if raw in COLOR_ALIASES:
        return COLOR_ALIASES[raw]
    # Array literal case: starts with [ ... ]
    if raw.startswith("["):
        # find matching close bracket
        depth = 0
        end = -1
        for i, c in enumerate(raw):
            if c == "[":
                depth += 1
            elif c == "]":
                depth -= 1
                if depth == 0:
                    end = i
                    break
        if end < 0:
            return []
        body = raw[1:end]
        items = [x.strip() for x in body.split(",") if x.strip()]
        result = []
        for item in items:
            # item like ".red"
            if item.startswith("."):
                key = item[1:]
                if key in COLOR_ENUM_TO_RAW:
                    result.append(COLOR_ENUM_TO_RAW[key])
        return result
    # Unknown form — return empty
    return []


def parse_block(block: str):
    """Parse a single CatalogPiece(...) call into a dict."""
    part_no_match = re.search(r'partNumber:\s*"([^"]*)"', block)
    name_match = NAME_RE.search(block)
    cat_match = CATEGORY_RE.search(block)
    dims_match = DIMS_RE.search(block)
    weight_match = WEIGHT_RE.search(block)
    colors_match = COMMON_COLORS_RE.search(block)
    keywords_match = KEYWORDS_RE.search(block)

    if not (part_no_match and name_match and cat_match and dims_match and colors_match):
        return None

    # commonColors: capture everything from "commonColors:" up to the next
    # field-or-end. Since args are usually on one line, we capture to the
    # next ", weight:" or ", keywords:" or ")".
    colors_segment = colors_match.group(1)
    # cut at ", weight:" or ", keywords:" or final ')'
    cut_indices = []
    for marker in [", weight:", ", keywords:"]:
        idx = colors_segment.find(marker)
        if idx >= 0:
            cut_indices.append(idx)
    # Also cut at the closing paren of the CatalogPiece call (last ')')
    if cut_indices:
        colors_segment = colors_segment[:min(cut_indices)]
    else:
        # Trim trailing ) if any
        colors_segment = colors_segment.rstrip(") ")

    common_colors = parse_color_argument(colors_segment)

    # Keywords list
    keywords = []
    if keywords_match:
        body = keywords_match.group(1)
        for item in re.findall(r'"([^"]*)"', body):
            keywords.append(item)

    return {
        "partNumber": part_no_match.group(1),
        "name": name_match.group(1),
        "category": pretty_category(cat_match.group(1)),
        "dimensions": {
            "studsWide": int(dims_match.group(1)),
            "studsLong": int(dims_match.group(2)),
            "heightUnits": int(dims_match.group(3)),
        },
        "commonColors": common_colors,
        "weight": float(weight_match.group(1)) if weight_match else 0.0,
        "keywords": keywords,
    }


def pretty_category(name: str) -> str:
    """Map enum case (e.g. 'darkGray', 'minifigure') to PieceCategory rawValue."""
    # Read once; PieceCategory rawValues come from LegoPiece.swift.
    mapping = {
        "brick": "Brick", "plate": "Plate", "tile": "Tile", "slope": "Slope",
        "arch": "Arch", "round": "Round", "technic": "Technic",
        "specialty": "Specialty", "minifigure": "Minifigure",
        "window": "Window/Door", "wheel": "Wheel", "connector": "Connector",
        "hinge": "Hinge", "bracket": "Bracket", "wedge": "Wedge", "other": "Other",
    }
    return mapping.get(name, name)


def main():
    all_pieces = []
    seen = set()
    for fname in CATALOG_FILES:
        path = SERVICES / fname
        if not path.exists():
            print(f"  skip (not found): {fname}", file=sys.stderr)
            continue
        text = path.read_text()
        count = 0
        for start, end in find_piece_blocks(text):
            block = text[start:end]
            piece = parse_block(block)
            if piece is None:
                continue
            if piece["partNumber"] in seen:
                continue
            seen.add(piece["partNumber"])
            all_pieces.append(piece)
            count += 1
        print(f"  {fname}: {count} pieces", file=sys.stderr)

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text(json.dumps(all_pieces, indent=2))
    size_kb = OUT_PATH.stat().st_size / 1024
    print(f"\nWrote {len(all_pieces)} pieces to {OUT_PATH} ({size_kb:.1f} KB)", file=sys.stderr)


if __name__ == "__main__":
    main()
