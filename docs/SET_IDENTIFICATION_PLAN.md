# Set Identification — "Scan a Built Model, Get the Set"

**Status:** Proposal / planning
**Author:** Bricky lead dev
**Last updated:** 2026-06-28

---

## 1. Goal

Extend the **Scanner** (formerly "Scan Bricks") so it can identify not just
loose bricks and minifigures in a pile, but **complete, already-built LEGO
sets**. A user points the camera at an assembled model — a Millennium Falcon, a
modular building, a Technic car — and Bricky answers **"This is set #75192,
Millennium Falcon (UCS, 2017)"** with confidence, year, theme, piece count, and
a link to the set's inventory.

This is gated as a **premium (monthly subscription) capability** that today is
only reachable through the existing in-app developer override (the "dev pro
hack"). See §7.

---

## 2. Why this is fundamentally different from the current scanners

| Current capability | How it works today |
|---|---|
| Brick pile scan | On-device Vision (rectangle/contour/stud detection) → color → local `LegoPartsCatalog` match. Fully offline. |
| Minifigure ID | On-device cascade: color filter → `TorsoEmbeddingIndex` / `FaceEmbeddingIndex` (DINOv2 embeddings pre-computed offline). Fully offline. |
| Famous-subject recognition | Cloud: `AzureOpenAIRecognitionClient` → `recognition-proxy` (Azure Functions) → **GPT-4o vision**. Developer-only, server-side monthly quota. |

A **built set** is a single 3D object with enormous appearance variance:
viewing angle, lighting, partial occlusion, missing/substituted parts, MOC
look-alikes, and sets that share 90% of their silhouette (e.g. the many
near-identical Creator 3-in-1 houses). There is **no stud grid or torso** to key
off. This is an open-world fine-grained recognition problem across ~23,000
retired + current sets.

---

## 3. The core question: do we need GPT vision?

**Short answer: yes — for the general "any of 23k sets from any angle" case,
a vision-language model (GPT-4o vision, via the existing proxy) is the only
realistic path.** Here's the reasoning, and the one viable offline alternative.

### Option A — Pre-embed reference images of every set (offline, like minifigs)

This mirrors the minifigure pipeline: download the official box/set image for
every set from Rebrickable/BrickLink, compute a DINOv2 embedding per set, ship a
`SetEmbeddingIndex` in the bundle, and do nearest-neighbor at scan time.

- **It works for**: matching a photo that looks like the **catalog image**
  (similar angle, the "hero" render).
- **It fails for**: a model the user built and photographed from their own
  angle, on their carpet, half in shadow. A single reference embedding per set
  does not generalize across viewpoints. You'd need many rendered views per set
  (multi-view synthesis from LDraw geometry) to get robust coverage — that's a
  large offline render + embed pipeline and a multi-hundred-MB index.
- **Storage reality:** the user's instinct is correct — *"unless I scanned a pic
  of all 23k sets and saved it to the app, this needs GPT vision."* Even if we
  bundle reference embeddings (not raw images), single-view embeddings are not
  enough for real-world built models. Multi-view coverage that *would* be enough
  is heavy.

**Verdict:** viable only as a **confidence booster / offline fallback for the
top-N most popular sets**, not as the primary identifier.

### Option B — GPT-4o vision via the existing proxy (recommended primary)

Reuse the exact pattern already shipping for famous-subject recognition:

```
ScannerView → SetIdentificationService → recognition-proxy (Azure Functions)
            → Azure OpenAI GPT-4o vision → { setNumber, name, theme, year, confidence }
```

GPT-4o vision can reason about a built model from an arbitrary angle and name
the set, especially well-known ones. We constrain hallucination by:

1. Prompting it to return **strict JSON** and an **empty result when unsure**
   (the proxy already does exactly this for subjects — reuse the discipline).
2. **Grounding the answer against a real set catalog.** GPT names a candidate;
   we resolve it against a bundled Rebrickable/BrickLink set index
   (`set number ↔ name ↔ year ↔ theme ↔ part count`). If GPT's guess doesn't
   resolve to a real set, we down-rank or reject it. This is the anti-fabrication
   guard required by our "no fake data" rule.

**Verdict:** primary identifier. Open-world, robust to angle, no giant on-device
index. Cost and privacy are managed by the proxy (key never on device,
server-side monthly quota, image sent only on explicit user action).

### Recommended architecture: **B primary, A as an optional offline booster**

```
                 ┌─────────────────────────────────────────────┐
  Captured frame │ 1. On-device gate: is this a *built model*    │
  ──────────────▶│    (not a pile / not a minifig)? Reuse        │
                 │    PhotoSubjectClassifier to route.           │
                 └───────────────┬─────────────────────────────┘
                                 │ built-model
                 ┌───────────────▼─────────────────────────────┐
                 │ 2. (Optional, offline) SetEmbeddingIndex     │
                 │    nearest-neighbor on top-N popular sets.   │
                 │    If high confidence → return, skip cloud.  │
                 └───────────────┬─────────────────────────────┘
                                 │ low confidence / not in index
                 ┌───────────────▼─────────────────────────────┐
                 │ 3. Cloud: SetIdentificationService → proxy   │
                 │    → GPT-4o vision → candidate set number(s) │
                 └───────────────┬─────────────────────────────┘
                                 │
                 ┌───────────────▼─────────────────────────────┐
                 │ 4. Ground candidate vs. bundled set catalog. │
                 │    Reject unresolved guesses. Return result. │
                 └─────────────────────────────────────────────┘
```

Step 2 is optional and can ship in a later phase; it reduces cloud cost for the
most-scanned sets and gives an offline answer for them.

---

## 4. Data we need

- **Set catalog** (read-only bundled JSON, like the existing catalogs):
  set number, name, theme, subtheme, year, part count, minifig count, image URL.
  Source: Rebrickable CSV exports (free, license-permitting) or BrickLink. This
  is a few MB gzipped for ~23k sets — comparable to the existing 16k-minifig
  gzipped catalog. **Never modified at runtime** (catalog rule).
- **(Phase 2, optional) Reference embeddings** for top-N sets: produced offline
  in `Tools/` (new `Tools/set-embeddings/` pipeline mirroring
  `Tools/torso-embeddings/`), bundled as a binary index loaded at runtime.

No new always-on cloud compute → stays under the **$200 cloud cost cap**
(GPT-4o vision calls are pay-per-use and quota-capped server-side).

---

## 5. Implementation plan (model → service → proxy → view model → view → tests)

Following the app's MVVM + service-singleton conventions.

### Phase 0 — Naming & gating groundwork (small)
- [x] Rename "Scan Bricks" → **Scanner** (button, screen, nav title, UI tests).
- [ ] Introduce a `PremiumFeature` concept in `SubscriptionManager` so set
      identification can be gated by the **paid monthly tier** rather than the
      developer override alone (see §7).

### Phase 1 — Set catalog (offline grounding)
- [ ] `Models/LegoSet.swift` — `LegoSet` struct (`Codable`, `Identifiable`).
- [ ] `Services/LegoSetCatalog.swift` — `static let shared`, loads the gzipped
      bundled set catalog, exposes `set(byNumber:)`, fuzzy `resolve(name:year:)`.
- [ ] `Tools/extract_set_catalog.py` — offline script to build the bundled JSON
      from Rebrickable exports (documented, re-runnable).
- [ ] Tests: `BrickyTests/LegoSetCatalogTests.swift` (load, lookup, fuzzy
      resolve, missing-set behavior).

### Phase 2 — Cloud set identification (GPT-4o vision)
- [ ] **Proxy:** new `services/recognition-proxy/src/functions/identifySet.ts`
      + `identifySet` system prompt (strict JSON: `setNumber`, `name`, `theme`,
      `year`, `confidence`, `reasoning`). Reuse `entitlement.ts`, `quota.ts`,
      and the `OpenAIConfig` plumbing from `openai.ts`. Add proxy unit tests in
      `services/recognition-proxy/test/`.
- [ ] **App service:** `Services/SetIdentificationService.swift` — protocol +
      `AzureOpenAISetClient` mirroring `AzureOpenAIRecognitionClient`. New
      `AppConfig.setIdentificationEndpoint` (`/api/identifySet`).
- [ ] **Grounding:** resolve GPT's candidate against `LegoSetCatalog`; drop
      anything that doesn't map to a real set number (anti-fabrication guard).
- [ ] **View model:** `ViewModels/SetIdentificationViewModel.swift`
      (`idle / classifying / uploading / results([LegoSet]) / error / notEntitled`),
      mirroring `ImageRecognitionViewModel`.
- [ ] **View:** add a "Identify a Set" entry point on the Scanner landing
      (`PreScanAnalysisView`) and a results screen. Gate visibility on the
      premium entitlement; show paywall/upsell otherwise.
- [ ] Tests: service (mocked client, grounding, reject-unresolved), view model
      (state transitions, entitlement gating), with `@MainActor` test classes.

### Phase 3 — Optional offline booster (top-N sets)
- [ ] `Tools/set-embeddings/` pipeline: render multi-view images from LDraw/box
      art → DINOv2 embeddings → `SetEmbeddingIndex` binary.
- [ ] `Services/SetEmbeddingIndex.swift` loader + nearest-neighbor; short-circuit
      the cloud call when on-device confidence is high.
- [ ] Tests + golden fixtures for the index.

### Phase 4 — Polish & docs
- [ ] Save identified sets into inventory / a "My Sets" collection.
- [ ] Update `CHANGELOG.md`, `docs/FEATURES.md`, `VERSION`.

---

## 6. Level of effort

| Phase | Scope | Rough LOE |
|---|---|---|
| 0 — Naming + gating groundwork | Rename (done) + `PremiumFeature` gate | ~0.5 day |
| 1 — Set catalog | Model, catalog service, extract script, tests | ~2–3 days |
| 2 — Cloud set ID (GPT-4o) | Proxy function, app service, grounding, VM, view, tests | ~4–6 days |
| 3 — Offline booster (optional) | Render+embed pipeline, index, integration | ~5–8 days |
| 4 — Polish + docs | Inventory save, docs | ~1–2 days |

**MVP (Phases 0–2)** delivers real set identification: **~1–1.5 weeks** of
focused work. Phase 3 is a meaningful add-on and can follow later. The single
biggest external dependency is the **set catalog data** (Rebrickable/BrickLink
licensing + extraction); everything else reuses patterns already in the app.

### Key risks
- **Fine-grained accuracy:** near-identical sets (Creator variants, City police
  stations across years) will confuse even GPT-4o. Mitigate with catalog
  grounding, returning **top-3 candidates** with confidence, and letting the
  user confirm — never assert a single wrong answer (no-fake-data rule).
- **Cost:** every cloud ID is a GPT-4o vision call. The existing proxy's
  server-side monthly quota already caps this; keep it conservative.
- **Data licensing:** confirm Rebrickable/BrickLink terms before bundling the
  catalog and any reference imagery.

---

## 7. Subscription gating

Today, cloud AI (`canUseAIRecognition`) is unlocked **only** by
`developerProOverride` (the 7-tap "dev pro hack"), and the proxy honors **only**
the dev-bypass token. There is intentionally **no purchasable subscription path**
wired up yet — `SubscriptionManager` even notes `verifyEntitlement` is "retained
for a future paid tier."

**Set identification is that future paid tier's flagship feature.** Plan:

1. **Introduce a real monthly subscription product** (`Bricky Pro Monthly`)
   alongside the existing one-time `proProductID`. Add it to `productIDs`,
   `Bricky.storekit`, and App Store Connect.
2. **Gate set ID on `isPro` *and* a feature flag** (`PremiumFeature.setIdentification`),
   so it lights up for **both** real monthly subscribers **and** the developer
   override. Until the monthly product ships/approves, it remains reachable only
   through the dev override — exactly the current state for cloud AI — so we can
   build and test end-to-end now without a live IAP.
3. **Proxy entitlement:** extend the proxy to accept **either** the dev-bypass
   token (dev-only) **or** a verified StoreKit JWS for the monthly product
   (`verifyEntitlement`, already stubbed). Server-side monthly quota applies to
   paying users; the dev path keeps its own safety cap.
4. **Paywall:** when a free user taps "Identify a Set", show the existing
   paywall upselling the monthly subscription. Graceful free-tier experience
   per the subscription rule.

Net: ships **dev-only first** (no IAP dependency, identical to today's cloud-AI
posture), then flips to **paid monthly** by enabling the product and the
StoreKit verification branch in the proxy — no rework of the feature itself.

---

## 8. Open questions
- Rebrickable vs. BrickLink as the catalog/image source (licensing + coverage)?
- Top-3 candidate UX with user confirmation, or single best guess above a
  confidence threshold?
- Should an identified set auto-populate the part inventory from the catalog's
  part list (powerful, but a larger data import)?
