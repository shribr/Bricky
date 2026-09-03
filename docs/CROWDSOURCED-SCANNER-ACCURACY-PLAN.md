# Crowdsourced Scanner Accuracy — Design Plan

Goal: turn per-user manual brick corrections/confirmations into a **trust-weighted
global feedback loop** that makes the scanner more accurate for everyone as the
user base grows — while resisting rogue actors, accidental mis-labelers, and
cold-start skew. Improvements are delivered to users **bundled in app releases**
(a signed correction index and/or a retrained model), surfaced in release notes.

This builds directly on what already exists on-device:
- `Bricky/Services/BrickCorrectionStore.swift` — persists a correction (crop + confirmed answer + `correctedShape`/`correctedColor`).
- `Bricky/Services/BrickCorrectionReranker.swift` — local nearest-neighbor reranker (Vision feature prints) that applies corrections to future scans.
- `Bricky/Services/VerificationReliabilityStore.swift` — client-side **measured** accuracy from user verifications.
- `Bricky/Services/*EmbeddingService.swift` — on-device embeddings (DINOv2/CLIP/feature prints).
- `services/recognition-proxy` — Azure Functions backend (pay-per-use) with entitlement + provider patterns to extend.

## 1. Core idea (one sentence)
Raw user labels never change the model directly. Corrections are **clustered by
visual similarity**, resolved by **trust-weighted Bayesian consensus anchored to a
strong authoritative prior**, and only **promoted** to the shared model when they
clear a **quorum + confidence** bar — with per-user reputation earned against
**known-answer honeypots**.

Three consequences, mapped to the known risks:
- **Bad/rogue labelers** → votes are weighted by reputation; reputation is earned by agreeing with ground truth, not with the crowd.
- **Cold start / early skew** → shrink every cluster toward a trusted prior so a lone early vote barely moves the posterior (the opposite of over-weighting early edits).
- **"X, Y, Z said A but W said B"** → that is exactly the per-cluster weighted vote tally, retained and surfaced.

## 2. The contribution record (a "flag")
On confirm (✓) or correct (✗ → edit), upload a compact **Observation**:

| Field | Purpose |
|---|---|
| `embedding` (vector) | visual clustering key, computed on-device (upload embedding-only by default; no raw photo required) |
| `cropThumbnail` (optional, downscaled) | human review queue + retraining set (second, explicit consent) |
| `predictedLabel`, `predictedConfidence` | the model's guess → becomes the prior |
| `userLabel` (part + color + dims), `action` | the vote |
| `shapeChanged` / `colorChanged` | vote on **shape and color independently** (reuse the shape%/color% split) |
| `anonUserId`, `deviceAttestation`, `appVersion`, `modelVersion` | trust, Sybil resistance, reproducibility |

Shape and color are **separate label channels** — a user can be reliable on shape
but poor on color under bad lighting.

## 3. Aggregation: cluster → weighted Bayesian consensus
Cluster incoming embeddings (approximate NN by cosine threshold, or HDBSCAN in a
batch job). Each cluster ≈ "one physical part-in-a-pose." For cluster `c` and
candidate label `ℓ`, score with a shrinkage prior:

```
s_c(ℓ) = α · p_prior(ℓ)  +  Σ_{u ∈ voters(c,ℓ)} w_u
```

- `p_prior` — the model's own prediction and/or a seed label (catalog / Brickognize).
- `α` — pseudo-count strength = the **cold-start knob**. Large early (many trusted votes needed to override the prior); decays as trusted volume grows.
- `w_u` — the voter's trust weight (§4).

Consensus = `argmax_ℓ s_c(ℓ)`; **confidence** = normalized top-1/top-2 margin.
**Promote** only when `confidence > τ` AND `Σ trusted weight ≥ quorum`; else the
cluster stays "pending." Keep the full tally so the app can show *"3 builders
confirmed 3001 Red Brick; 1 said 3002."*

**Upgrade path:** start with the weighted-vote-with-prior (simple, debuggable),
then graduate to **Dawid–Skene** (EM jointly estimating each user's confusion
matrix + the true labels) — the principled version of "learn who's reliable and
down-weight the rest," which naturally neutralizes adversaries.

## 4. Trust / reputation (the anti-abuse core)
Per-user, per-channel **Beta reputation**:

```
r_u = a_u / (a_u + b_u)        w_u = g(r_u)
```

- New users start weak (`a_u = b_u = 1` → `r_u = 0.5`, ~zero weight) → **probation**. This alone defuses Sybil floods and early skew.
- Update `a_u`/`b_u` when a vote agrees/disagrees with (a) **honeypots** and (b) the **eventually-settled** cluster consensus (back-propagated once stable).
- Conservative weighting, e.g. `w_u = max(0, 2·r_u − 1)` so sub-50% agreement contributes nothing; consider log-odds for the trusted tail.

**Honeypots are the key trick.** Seed the verify flow with items whose answer is
already known (catalog renders, expert-labeled crops, Brickognize-high-confidence),
indistinguishable to the user. Honeypot accuracy is a **collusion-proof** trust
signal: a coordinated group can't fake it, and an accidental mis-identifier is
caught early and quietly down-weighted (no punitive UX).

## 5. Anti-abuse specifics
- **Sybil resistance:** Sign in with Apple + **App Attest / DeviceCheck** so each identity has real cost; cap contributions/account/day; new-account probation.
- **Quarantine (shadow) pipeline:** flags never edit the shipped model directly — they feed a *staging* consensus; promotion needs quorum + confidence + (high-impact) human review.
- **Per-user anomaly detection:** monitor disagreement-with-consensus rate, honeypot accuracy, velocity, label entropy; auto-flag accounts that flip many high-confidence bricks or vote in lockstep with new-account clusters.
- **Impact-gated review queue:** a flag that would overturn a well-established high-confidence label → manual review before it lands; low-impact confirmations flow automatically.
- **Immutable audit log + rollback:** every promotion is versioned; a poisoned label can be reverted and contributors re-scored.

## 6. Cold start ("few users → skew")
Make early crowd input **less** influential, not more:
1. **Seed priors** from authoritative sources already integrated (parts catalog, Brickognize, Rebrickable/BrickLink renders) so the system is useful on day one.
2. **High `α` + quorum early, decayed later** (e.g. ≥3 independent trusted confirmations to move a label at launch).
3. **Bootstrap trust from honeypots**, not from each other — identify good early contributors without a crowd to agree with.
4. **Bayesian shrinkage everywhere** — a 2-vote cluster stays pinned to the prior; the posterior only detaches with evidence.

## 7. Closing the loop back to the scanner
- **Short term:** ship promoted consensus as a **server-backed correction index** (the global version of `BrickCorrectionReranker`). Clients periodically download a **signed, versioned** index (embeddings → confirmed labels) and rerank locally. No retraining; works offline after sync.
- **Medium term:** use consensus-labeled crops as a real training set to fine-tune a LEGO-specific classifier/embedding (the CLIP/Brickognize direction), then OTA the model.
- **Always:** canary new indexes/models to a small % of users; watch the aggregate of the client-side **measured** accuracy (`VerificationReliabilityStore`) before global rollout; auto-rollback on regression.

## 8. Delivery via the app release train (bundled accuracy updates)
This is the primary way improvements reach users, and it complements the live
index download:
- Each app release **bundles the current signed correction index** (and/or an updated model) as a resource, versioned by a manifest (§10).
- When a release includes materially improved accuracy data, add a user-facing
  release note, e.g. **"Enhanced brick scanner accuracy from community
  corrections."**
- The live `GET /correctionIndex` download (§7) fills the gap between releases;
  the bundle guarantees a good baseline offline and for fresh installs.
- Benefits: reviewable/QA-able snapshot per release, deterministic rollback (ship
  the prior bundle), and honest changelog history of accuracy gains.

## 9. Infra & cost (respects the $200 cap)
- Extend `services/recognition-proxy`: `POST /contributeFlag`, `GET /correctionIndex?since=<version>`, `GET /correctionIndex/status`.
- Observations in Table/Cosmos (serverless); crops in Blob (cool tier).
- Clustering + consensus in a **scheduled batch job** (timer-triggered Function), never always-on — the biggest cost lever.
- Gate uploads behind existing entitlement/attestation so spam isn't ingested at cost.

## 10. Release-time accuracy check (agent-assisted)
So an accuracy update is never silently missed when shipping a release, define a
deterministic signal the agent checks at version-bump / "ready to push to
production" time:

- **Bundle manifest (in-repo):** `Bricky/Resources/CorrectionIndex/manifest.json`
  ```json
  { "indexVersion": "0", "generatedAt": null, "promotedLabelCount": 0, "sourceThroughDate": null }
  ```
  Bumped whenever a new consensus index is bundled into the app.
- **Server status:** `GET /correctionIndex/status` →
  `{ latestIndexVersion, promotedLabelsSinceVersion, newContributions, updatedAt }`.
- **"Material new data" gate:** server `latestIndexVersion` > bundled `indexVersion`
  **and** `promotedLabelsSinceVersion ≥ N` (start N≈25, tune).

**Agent behavior at release time** (see repo memory `bricky-release-accuracy-check.md`):
when the user signals they are wrapping up and ready to push a production release,
the agent checks the manifest vs. server status. If — and only if — a **real**
signal shows material new crowdsourced accuracy data since the last release, it
proactively says something like:

> "It looks like we've just wrapped up a batch of significant updates. I also
> noticed a significant amount of new user-generated scanner-accuracy data since
> the last release (`promotedLabelsSinceVersion` = N). Want to review and
> incorporate it into this release and add an 'Enhanced brick scanner accuracy'
> release note?"

If the crowdsourcing pipeline isn't built yet (no server status endpoint / empty
manifest), the agent says so plainly — it must **never fabricate** "new accuracy
data" that doesn't exist.

## 11. Phased roadmap
- **P0 (client, mostly done):** local corrections + measured accuracy already exist. Add an upload queue + opt-in consent + App Attest.
- **P1 (ingest + honeypots):** `contributeFlag`, observation store, honeypot seeding, per-user Beta reputation.
- **P2 (consensus + index):** batch clustering + weighted-prior consensus + signed correction index (download + release bundle + manifest).
- **P3 (hardening + learning):** Dawid–Skene, anomaly/Sybil detection, review queue, canary + rollback; then fine-tune the model on consensus data.

## 12. Key risks / open questions
- **Embedding quality gates everything** — clustering is only as good as the vector; general-purpose feature prints cluster loosely, so a LEGO-specific embedding matters most here.
- **Honeypot supply** — need a steady stream of known-answer items (catalog + Brickognize can generate them).
- **Global override policy** — decide whether crowd consensus can ever auto-overturn a high-confidence catalog label, or only via review.
- **Privacy/consent** — uploading crops needs explicit opt-in; prefer embedding-only by default; strip EXIF/location; provide delete-my-contributions.

## Changelog
- 2026-09-02 · Initial design plan: trust-weighted Bayesian consensus with honeypot reputation, shadow/quarantine promotion, cold-start shrinkage; delivery via signed correction index + app-release bundle (§8); agent release-time accuracy check (§10) with in-repo manifest + server status gate.
