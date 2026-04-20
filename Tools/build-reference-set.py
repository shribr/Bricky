#!/usr/bin/env python3
"""
Build a curated bundled reference image set for offline minifigure ID.

Run once (with internet) to download ~2000 popular minifigure images from
the rebrickable CDN, resize them, and write them into the app bundle so
identification works offline on first launch.

Usage:
    pip install Pillow requests
    python3 Tools/build-reference-set.py

Output:
    Bricky/Resources/MinifigImages/<figure-id>.jpg   (one image per figure)
    Bricky/Resources/MinifigImages/index.json        (figureId -> filename)

Filters:
    - Skip Duplo
    - Skip polybag-only / promotional themes
    - Include all Collectible Minifigures Series

Targets:
    - ~2000 figures
    - ~40 MB total bundle size (max 280 px, JPEG quality 78)
"""

from __future__ import annotations

import gzip
import json
import os
import sys
import re
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from io import BytesIO
from pathlib import Path

try:
    import requests
    from PIL import Image
except ImportError:
    print("Missing dependencies. Install with: pip install Pillow requests")
    sys.exit(1)

# ── Configuration ──────────────────────────────────────────────────────

REPO_ROOT = Path(__file__).resolve().parent.parent
CATALOG_PATH = REPO_ROOT / "Bricky" / "Resources" / "MinifigureCatalog.json.gz"
OUTPUT_DIR = REPO_ROOT / "Bricky" / "Resources" / "MinifigImages"
INDEX_FILE = OUTPUT_DIR / "index.json"

TARGET_FIGURE_COUNT = 4000
MAX_DIMENSION = 280
JPEG_QUALITY = 78

DOWNLOAD_TIMEOUT_SEC = 15
DOWNLOAD_CONCURRENCY = 12
RETRY_COUNT = 2

EXCLUDED_THEME_PATTERNS = [
    r"\bduplo\b",
    r"\bpolybag\b",
    r"\bpromotional?\b",
]

ALWAYS_INCLUDE_THEME_PATTERNS = [
    r"\bcollectible minifigures?\b",
    r"\bminifigures? series\b",
    r"\bcmf\b",
]

# Themes weighted as "popular" — get a scoring boost so we prioritize them
POPULAR_THEMES = [
    "star wars",
    "city",
    "ninjago",
    "marvel",
    "harry potter",
    "friends",
    "minecraft",
    "classic space",
    "castle",
    "indiana jones",
    "pirates",
    "creator",
    "creator expert",
    "ideas",
    "speed champions",
    "jurassic world",
    "lord of the rings",
    "the hobbit",
    "disney",
    "super heroes",
    "dc",
    "batman",
    "ghostbusters",
    "back to the future",
    "spongebob",
    "the simpsons",
    "monkie kid",
]

# Classic / vintage themes — almost exclusively pre-2000, and they'll
# be the majority of what real users scan (their childhood collections).
# These get a flat bonus regardless of year, because recency scoring
# above heavily favors modern sets.
CLASSIC_ERA_THEMES = [
    "castle",
    "classic castle",
    "classic space",
    "classic town",
    "classic",
    "pirates",
    "pirates i",
    "pirates ii",
    "imperial armada",
    "imperial guards",
    "imperial soldiers",
    "islanders",
    "forestmen",
    "black falcon",
    "crusaders",
    "lion knights",
    "dragon knights",
    "wolfpack",
    "black knights",
    "royal knights",
    "knights kingdom",
    "fright knights",
    "dark forest",
    "ninja",
    "western",
    "cowboys",
    "adventurers",
    "aquazone",
    "aquanauts",
    "aquaraiders",
    "aquasharks",
    "hydronauts",
    "stingrays",
    "arctic",
    "divers",
    "extreme team",
    "fire",
    "hospital",
    "paradisa",
    "police",
    "space police",
    "blacktron",
    "blacktron ii",
    "m-tron",
    "ice planet",
    "spyrius",
    "ufo",
    "insectoids",
    "life on mars",
    "roboforce",
    "exploriens",
    "unitron",
    "time cruisers",
    "time twisters",
    "futuron",
    "rock raiders",
    "island xtreme stunts",
    "alpha team",
    "dino attack",
    "dino 2010",
    "dinosaurs",
    "divers",
    "homemaker",
    "fabuland",
    "legoland",
]

CURRENT_YEAR = 2026


# ── High-value pinned figure IDs ───────────────────────────────────────
#
# These figures MUST be included in the bundled set regardless of the
# scoring heuristic, because they have distinctive printed torsos that
# the visual-similarity pipeline can rely on for offline identification
# of common vintage scans (Classic Town Police, Castle factions, Pirates,
# Space subthemes, etc.). Without explicit pins, scoring sometimes
# drops them in favor of higher-recency-but-less-distinctive figures.
#
# Add new IDs here whenever a real-world scan misses a figure that has
# an unmistakable torso print. One scan ≈ one new pin.
PINNED_FIGURE_IDS = {
    # Classic Town Police — black jacket with white zipper + star badge
    "fig-000697",  # cop031 — Policeman, Black Jacket with Zipper and Badge (Town, 2000)
    # Add more high-value distinctive-torso pins below as scans surface them.
}


# ── Catalog loading ────────────────────────────────────────────────────


def load_catalog() -> list[dict]:
    if not CATALOG_PATH.exists():
        print(f"Catalog not found at {CATALOG_PATH}")
        sys.exit(1)
    with gzip.open(CATALOG_PATH, "rb") as f:
        data = json.load(f)
    if isinstance(data, dict) and "figures" in data:
        figures = data["figures"]
    elif isinstance(data, list):
        figures = data
    else:
        print("Unexpected catalog format (expected list or dict with 'figures').")
        sys.exit(1)
    print(f"Loaded {len(figures)} figures from catalog")
    return figures


# ── Filtering & scoring ────────────────────────────────────────────────


def matches_any(text: str, patterns: list[str]) -> bool:
    text_lower = text.lower()
    return any(re.search(p, text_lower) for p in patterns)


def is_excluded(figure: dict) -> bool:
    theme = (figure.get("theme") or "").lower()
    name = (figure.get("name") or "").lower()
    if matches_any(theme, EXCLUDED_THEME_PATTERNS):
        return True
    if matches_any(name, EXCLUDED_THEME_PATTERNS):
        return True
    return False


def is_always_included(figure: dict) -> bool:
    theme = (figure.get("theme") or "").lower()
    return matches_any(theme, ALWAYS_INCLUDE_THEME_PATTERNS)


def score_figure(figure: dict) -> float:
    """Popularity score — higher is better."""
    score = 0.0

    year = figure.get("year") or 2000
    # Recent figures get a modest boost. Cap lower than before so
    # vintage figures aren't crowded out by forgettable modern ones.
    recency = max(0, 10 - (CURRENT_YEAR - year))
    score += recency * 2

    theme = (figure.get("theme") or "").lower()
    name = (figure.get("name") or "").lower()

    if any(p in theme for p in POPULAR_THEMES):
        # Flat popular-theme bonus high enough that a vintage iconic
        # figure (e.g. 1994 Pirates Islanders) still makes the cut
        # against a boring modern figure that has only recency going
        # for it. Without this, classic themes get crowded out.
        score += 30

    # Classic/vintage era bonus — these are the figures users are
    # most likely to have from their childhood collections. Apply a
    # large flat bonus PLUS an extra "true vintage" bonus for anything
    # pre-2000 to guarantee broad coverage of classic lines.
    if any(p in theme for p in CLASSIC_ERA_THEMES):
        score += 35
    if year and year < 2000:
        score += 20
    if year and year < 1990:
        score += 10  # on top of the pre-2000 bonus — extra-early classics

    # Always-included themes (CMF) get a big bonus
    if is_always_included(figure):
        score += 25

    # Iconic name patterns — ensures bellwether figures always make
    # the cut regardless of age. Expanded to cover classic character
    # archetypes (knights, pirates, spacemen, etc.).
    ICONIC_NAME_PATTERNS = [
        r"\bislander\b",
        r"\bking kahuka\b",
        r"\bcaptain redbeard\b",
        r"\bgovernor broadside\b",
        r"\bclassic space\b",
        r"\bblacksmith\b",
        r"\bforestman\b",
        r"\bforestmen\b",
        r"\brobin hood\b",
        r"\bninja\b",
        r"\bspaceman\b",
        r"\bastronaut\b",
        r"\bcosmonaut\b",
        r"\bknight\b",
        r"\bking\b",
        r"\bqueen\b",
        r"\bprince\b",
        r"\bprincess\b",
        r"\bjester\b",
        r"\bwizard\b",
        r"\bsorcerer\b",
        r"\bpirate\b",
        r"\bcaptain\b",
        r"\bbuccaneer\b",
        r"\bskeleton\b",
        r"\bmummy\b",
        r"\bmonster\b",
        r"\bcowboy\b",
        r"\bsheriff\b",
        r"\bbandit\b",
        r"\bindian chief\b",
        r"\bconquistador\b",
        r"\bexplorer\b",
        r"\badventurer\b",
        r"\bdiver\b",
        r"\baquanaut\b",
        r"\bblacktron\b",
        r"\bm-tron\b",
        r"\bice planet\b",
        r"\bspyrius\b",
        r"\bfuturon\b",
        r"\bunitron\b",
        r"\bexploriens\b",
        r"\bfabuland\b",
        r"\blegoland\b",
        r"\bhomemaker\b",
    ]
    if any(re.search(p, name) for p in ICONIC_NAME_PATTERNS):
        score += 40
    # Iconic patterns in the theme name (catches generic "Knight" figures
    # in Castle theme even when the figure name itself is just "Peasant").
    if any(re.search(p, theme) for p in ICONIC_NAME_PATTERNS):
        score += 15

    # Slight boost for figures with more parts (more iconic)
    part_count = figure.get("partCount") or 0
    score += min(part_count * 0.5, 5)

    return score


def select_figures(all_figures: list[dict]) -> list[dict]:
    # Must have an image URL
    candidates = [
        f for f in all_figures
        if (f.get("imgURL") or "").strip() and not is_excluded(f)
    ]
    print(f"After excluding Duplo/polybag/promo: {len(candidates)} figures")

    # Pinned figures always go in first, regardless of scoring or theme.
    # These are figures with distinctive printed torsos that the visual
    # pipeline relies on for offline ID of common vintage scans.
    pinned = [f for f in candidates if f.get("id") in PINNED_FIGURE_IDS]
    pinned_ids = {f["id"] for f in pinned}
    if pinned:
        print(f"Pinned: {len(pinned)} high-value distinctive-torso figures")
    missing_pins = PINNED_FIGURE_IDS - pinned_ids
    if missing_pins:
        print(
            f"WARNING: {len(missing_pins)} pinned figures not found in catalog "
            f"(or have no image URL): {sorted(missing_pins)}"
        )

    remaining = [f for f in candidates if f["id"] not in pinned_ids]

    # Always-include first (CMF), then top by score
    cmf = [f for f in remaining if is_always_included(f)]
    others = [f for f in remaining if not is_always_included(f)]

    others_sorted = sorted(others, key=score_figure, reverse=True)
    remaining_slots = max(0, TARGET_FIGURE_COUNT - len(pinned) - len(cmf))
    selected = pinned + cmf + others_sorted[:remaining_slots]

    # Cap at target (in case pinned + CMF alone exceeds it)
    selected = selected[:TARGET_FIGURE_COUNT]

    print(
        f"Selected {len(selected)} figures "
        f"({len(pinned)} pinned, {len(cmf)} CMF, "
        f"{len(selected) - len(pinned) - len(cmf)} popular)"
    )
    return selected


# ── Download + resize ──────────────────────────────────────────────────


def download_and_save(figure: dict, session: requests.Session) -> tuple[str, bool, str]:
    """Returns (figure_id, success, error_message)."""
    fig_id = figure["id"]
    url = (figure.get("imgURL") or "").strip()
    if not url:
        return fig_id, False, "no url"

    out_path = OUTPUT_DIR / f"{fig_id}.jpg"
    if out_path.exists():
        return fig_id, True, "cached"

    last_err = ""
    for attempt in range(RETRY_COUNT + 1):
        try:
            resp = session.get(url, timeout=DOWNLOAD_TIMEOUT_SEC)
            if resp.status_code != 200:
                last_err = f"http {resp.status_code}"
                continue
            img = Image.open(BytesIO(resp.content)).convert("RGB")
            # Resize maintaining aspect ratio
            img.thumbnail((MAX_DIMENSION, MAX_DIMENSION), Image.LANCZOS)
            img.save(out_path, "JPEG", quality=JPEG_QUALITY, optimize=True)
            return fig_id, True, "downloaded"
        except Exception as e:  # noqa: BLE001
            last_err = str(e)
            if attempt < RETRY_COUNT:
                time.sleep(0.5 * (attempt + 1))

    return fig_id, False, last_err


def download_all(figures: list[dict]) -> dict[str, str]:
    """Download in parallel. Returns figureId -> filename map."""
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    index: dict[str, str] = {}
    failures: list[tuple[str, str]] = []

    session = requests.Session()
    session.headers.update({
        "User-Agent": "BrickyReferenceSetBuilder/1.0",
    })

    total = len(figures)
    completed = 0
    bytes_so_far = 0

    print(f"Downloading {total} images (concurrency={DOWNLOAD_CONCURRENCY})...")

    with ThreadPoolExecutor(max_workers=DOWNLOAD_CONCURRENCY) as pool:
        futures = {pool.submit(download_and_save, f, session): f for f in figures}
        for fut in as_completed(futures):
            fig_id, ok, msg = fut.result()
            completed += 1
            if ok:
                index[fig_id] = f"{fig_id}.jpg"
                if msg == "downloaded":
                    bytes_so_far += (OUTPUT_DIR / f"{fig_id}.jpg").stat().st_size
            else:
                failures.append((fig_id, msg))
            if completed % 50 == 0 or completed == total:
                mb = bytes_so_far / (1024 * 1024)
                print(
                    f"  {completed}/{total} done "
                    f"({len(index)} ok, {len(failures)} failed, {mb:.1f} MB downloaded)"
                )

    if failures:
        print(f"\n{len(failures)} downloads failed (first 10):")
        for fig_id, err in failures[:10]:
            print(f"  {fig_id}: {err}")

    return index


# ── Index file ─────────────────────────────────────────────────────────


def write_index(index: dict[str, str]) -> None:
    payload = {
        "version": 1,
        "figureCount": len(index),
        "files": index,
    }
    INDEX_FILE.write_text(json.dumps(payload, separators=(",", ":")))
    print(f"Wrote index with {len(index)} entries to {INDEX_FILE}")


def cleanup_stale_files(index: dict[str, str]) -> None:
    """Delete any .jpg in OUTPUT_DIR that isn't referenced by the index.

    Stale files accumulate across runs when the selection criteria change
    (e.g. new vintage bonuses drop some modern figures and add classic
    ones). Without cleanup, the bundle grows unbounded.
    """
    kept = set(index.values())
    removed = 0
    freed_bytes = 0
    for p in OUTPUT_DIR.glob("*.jpg"):
        if p.name not in kept:
            freed_bytes += p.stat().st_size
            p.unlink()
            removed += 1
    if removed:
        mb = freed_bytes / (1024 * 1024)
        print(f"Cleaned up {removed} stale images ({mb:.1f} MB freed)")


def report_total_size() -> None:
    total = 0
    file_count = 0
    for p in OUTPUT_DIR.glob("*.jpg"):
        total += p.stat().st_size
        file_count += 1
    mb = total / (1024 * 1024)
    print(f"\n✓ Final: {file_count} images, {mb:.1f} MB on disk")
    if mb > 50:
        print("  Note: bundle is over 50 MB — consider lowering JPEG_QUALITY or MAX_DIMENSION")


# ── Main ───────────────────────────────────────────────────────────────


def main() -> int:
    print("Bricky reference image set builder")
    print("==================================")
    figures = load_catalog()
    selected = select_figures(figures)
    if not selected:
        print("No figures selected — aborting.")
        return 1
    index = download_all(selected)
    write_index(index)
    cleanup_stale_files(index)
    report_total_size()
    print("\nDone. Remember to:")
    print("  1. Verify project.yml includes Bricky/Resources/MinifigImages")
    print("  2. Run `xcodegen generate` if you use XcodeGen")
    print("  3. Build the app and verify the index loads")
    return 0


if __name__ == "__main__":
    sys.exit(main())
