/**
 * Honeypots: known-answer brick items whose grading is a collusion-proof trust
 * signal. Unlike consensus (which a coordinated Sybil group can move), a
 * honeypot's ground-truth label is SECRET and seeded from authoritative data
 * (catalog/expert), so grading a user's answer against it is manipulation-proof.
 * The resulting agree/disagree deltas anchor per-user Beta reputation.
 *
 * Pure functions, no side effects, no I/O. See
 * docs/CROWDSOURCED-SCANNER-ACCURACY-PLAN.md §4.
 */

/** A known-answer item. `partNumber`/`color` are the SECRET ground truth. */
export interface Honeypot {
  id: string;
  partNumber: string; // true shape (secret; never served to clients)
  color: string; // true color (secret)
  imageRef: string; // what the client shows the user (e.g. a catalog image key); public
  source: string; // provenance, e.g. 'catalog'
}

/** The client-safe view — NO ground-truth labels. */
export interface PublicHoneypot {
  id: string;
  imageRef: string;
}

export interface HoneypotResult {
  honeypotId: string;
  userKey: string;
  userPartNumber: string;
  userColor: string;
}

/** Strip the secret ground-truth labels, leaving only what a client may see. */
export function toPublic(h: Honeypot): PublicHoneypot {
  return { id: h.id, imageRef: h.imageRef };
}

/**
 * Grade one answer against the honeypot's secret truth. A channel is left
 * `undefined` when the user gave no answer for it (empty string), so a partial
 * answer is neither rewarded nor penalized on the missing channel.
 */
export function gradeHoneypot(
  h: Honeypot,
  r: HoneypotResult,
): { shapeAgreed?: boolean; colorAgreed?: boolean } {
  const out: { shapeAgreed?: boolean; colorAgreed?: boolean } = {};
  if (r.userPartNumber.length > 0) {
    out.shapeAgreed = r.userPartNumber === h.partNumber;
  }
  if (r.userColor.length > 0) {
    out.colorAgreed = r.userColor === h.color;
  }
  return out;
}

/**
 * Reputation deltas from honeypot answers — collusion-proof because each answer
 * is graded against known truth, not against other (potentially colluding)
 * users. For each result whose `honeypotId` is a known honeypot, a matched
 * channel bumps `agreed` and a mismatched channel bumps `disagreed`; channels
 * the user left blank are skipped. Results for unknown honeypots are ignored.
 */
export function honeypotReputationDeltas(
  honeypots: Map<string, Honeypot>,
  results: HoneypotResult[],
): Map<string, { agreed: number; disagreed: number }> {
  const deltas = new Map<string, { agreed: number; disagreed: number }>();
  const bump = (userKey: string, agreed: boolean): void => {
    const cur = deltas.get(userKey) ?? { agreed: 0, disagreed: 0 };
    if (agreed) cur.agreed += 1;
    else cur.disagreed += 1;
    deltas.set(userKey, cur);
  };

  for (const r of results) {
    const h = honeypots.get(r.honeypotId);
    if (!h) continue; // unknown honeypot — ignore
    const { shapeAgreed, colorAgreed } = gradeHoneypot(h, r);
    if (shapeAgreed !== undefined) bump(r.userKey, shapeAgreed);
    if (colorAgreed !== undefined) bump(r.userKey, colorAgreed);
  }
  return deltas;
}

/**
 * Additively merge two per-user delta maps, summing `agreed`/`disagreed` for
 * each userKey. Used to combine consensus-earned deltas with honeypot-earned
 * deltas before recomputing reputation. Neither input is mutated.
 */
export function mergeDeltas(
  ...maps: Array<Map<string, { agreed: number; disagreed: number }>>
): Map<string, { agreed: number; disagreed: number }> {
  const out = new Map<string, { agreed: number; disagreed: number }>();
  for (const m of maps) {
    for (const [userKey, d] of m) {
      const cur = out.get(userKey) ?? { agreed: 0, disagreed: 0 };
      cur.agreed += d.agreed;
      cur.disagreed += d.disagreed;
      out.set(userKey, cur);
    }
  }
  return out;
}
