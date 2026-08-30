# 3D VIEWER — FUTURE ROADMAP

Future enhancements for the 3D build viewer and the completed-set preview.
Captured from product discussion; not yet implemented. Newest ideas first.

## Completed-set preview (NOT the step-by-step instructions)

These belong on the **fully built LEGO set preview screen**, where the model is
complete and the user is exploring it — not in the step-by-step flow.

- **Per-piece / group transparency.** Tap a specific piece (or select a group of
  pieces) and control the transparency for *just those pieces*. Lets the user
  see the other side of a complex model, or peek at internal structure, without
  mentally "taking the model apart".
- **See inside enclosing pieces.** Reduce the transparency of an enclosing piece
  (e.g. a treasure-chest element) to reveal its contents (e.g. the gold coins
  inside). A natural consequence of per-piece transparency applied to a piece
  that visually contains others.
- **Detach / explode selected pieces.** Pull selected pieces away from the model
  (an "exploded view") to inspect how they connect — mirroring how, in the real
  world, you connect and disconnect a piece to see what's around it. Reattach to
  restore. This is the digital version of physically dry-fitting.

Why the preview screen and not the instructions: during step-by-step building
the reveal/highlight logic owns visibility. On the completed model the user is
free-exploring, so per-piece selection, transparency, and explode are additive
and don't fight the step machinery.

## Step-by-step viewer

- **Global see-through slider** — *shipped* (opaque by default; drag to x-ray the
  already-built pieces of the current entity).
- **Entity focus** — *shipped* (camera recenters on the entity being built; other
  entities recede into the background). Currently entities are auto-detected as
  connected components (Option A). Future: derive entities from explicit LDraw
  sub-models (`0 FILE`) for imported OMR sets (Option B) for exact grouping.

## Sub-assemblies & connecting entities (design)

The problem: some sets build two parts independently (e.g. a chair and a desk)
and **connect them at a later step**. Because our current entity detection is
connected components of the *final* model, a pair that eventually joins is a
single component from the start — so it never gets separate focus. The correct
concept is a **temporal sub-assembly**, not a spatial blob. This is exactly what
LDraw / LPub3D / BrickLink Studio encode as **sub-models** (`0 FILE`), each built
on its own page/callout then placed into the parent.

Recommended model:
- **Imports:** derive sub-assemblies from LDraw `0 FILE` sub-models (Option B) —
  authoritative "these steps build a separate thing that later attaches".
- **Authored/procedural:** a `subassemblyID` per placement, or a temporal
  inference (a run of steps disconnected from everything built so far starts a
  new sub-assembly; the step that first bridges two of them is a **merge step**).

POV at a **merge step** (both entities relevant): frame the **union** of the two
sub-assemblies so everything fits (zoom out), with neither backgrounded —
mirroring LPub3D's "final assembly" step after callouts.

Showing *how* two entities connect (the digital alternative to paper arrows):
- **Animated fly-in** — the joining sub-assembly slides/drops into its seat along
  the connection axis. Motion conveys direction better than a static arrow
  (as in LEGO's *Instructions PLUS* and Stud.io animation). Include a **replay**.
- **Exploded offset + 3D pointer line** — park the part offset with a dashed
  pointer to its socket (LPub3D "pointers" / LDraw `BUFEXCHG` separation arrows).
- **Glowing mating studs** — pulse the specific studs + anti-studs that clip.
- **Auto-orbit** to the clearest angle of the join.
- **Scrub control** — manually slide the sub-assembly exploded → seated.

Recommended combo: exploded offset → auto fly-in → glowing connection studs, with
replay/scrub, camera framed to the union at the merge step.

## Content pipeline

- **Scan a real object → 3D model → step-by-step instructions.** Capture a
  physical object (Object Capture / multi-view) and generate both a buildable 3D
  model and generated step instructions. (Tracked as §10 in
  `3D-BUILD-FEATURE-FIX-PLAN.md`; device-only capture.)
- **Printable / paper instructions export.** Export the generated step sequence
  as a printable booklet (per-step renders + piece call-outs), like a classic
  LEGO instruction manual.
- **Import real OMR `.mpd` sets.** Bundle/import official LDraw models so sample
  builds are sophisticated real sets, rendered with authored type-2 edge lines.
  (Ingestion path shipped; needs curated sets whose parts are in the bundled
  library — verify with `SetModelLibrary.missingParts`.)
