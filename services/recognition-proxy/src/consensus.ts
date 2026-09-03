/**
 * Trust-weighted Bayesian consensus for crowdsourced brick corrections.
 *
 * Raw user labels never change the model directly. Votes are clustered by visual
 * similarity (cosine on embeddings), then shape and color are resolved as two
 * INDEPENDENT channels via a shrinkage prior anchored to the model's own guess:
 *
 *     tally[ℓ] = Σ_{u votes ℓ} weightOf(u)  +  (ℓ === priorLabel ? priorStrength : 0)
 *
 * A label is only promoted once it clears a quorum of summed USER weight (the
 * prior does not count toward quorum) AND a confidence bar on the top1/top2
 * margin. This keeps a lone early vote pinned to the prior (cold-start safety)
 * and makes zero-weight (untrusted/adversarial) voters inert.
 *
 * See docs/CROWDSOURCED-SCANNER-ACCURACY-PLAN.md §3, §4, §6. Pure functions, no I/O.
 */

export interface Vote {
  userKey: string;
  embedding: number[];
  shapeLabel: string; // e.g. partNumber
  colorLabel: string;
  predictedShape: string; // model's guess (prior)
  predictedColor: string;
}

export interface ChannelConsensus {
  label: string | null; // winning label, or null if no votes
  confidence: number; // 0..1 normalized top1/top2 margin (1 = unanimous)
  promoted: boolean; // cleared quorum + confidence gates
  tally: Record<string, number>; // total weighted score incl. prior, per label
  userWeight: Record<string, number>; // summed user weight (NO prior), per label
}

export interface ClusterConsensus {
  members: number;
  shape: ChannelConsensus;
  color: ChannelConsensus;
}

export interface ConsensusOptions {
  cosineThreshold?: number; // default 0.9 — cluster join threshold
  priorStrength?: number; // α pseudo-count, default 3 (cold-start knob)
  quorum?: number; // min summed USER weight on the winner, default 2
  promoteConfidence?: number; // τ, default 0.6
  weightOf?: (userKey: string) => number; // default () => 1
}

const DEFAULT_COSINE_THRESHOLD = 0.9;
const DEFAULT_PRIOR_STRENGTH = 3;
const DEFAULT_QUORUM = 2;
const DEFAULT_PROMOTE_CONFIDENCE = 0.6;
const DEFAULT_WEIGHT_OF: (userKey: string) => number = () => 1;

/** Cosine similarity of two equal-length vectors. Returns 0 if either is zero. */
export function cosineSimilarity(a: number[], b: number[]): number {
  const n = Math.min(a.length, b.length);
  let dot = 0;
  let na = 0;
  let nb = 0;
  for (let i = 0; i < n; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  if (na <= 0 || nb <= 0) return 0;
  return dot / (Math.sqrt(na) * Math.sqrt(nb));
}

/** Decode a base64 string of little-endian Float32 into number[]. */
export function decodeEmbedding(base64: string): number[] {
  const buf = Buffer.from(base64, 'base64');
  const count = Math.floor(buf.byteLength / 4);
  const out = new Array<number>(count);
  for (let i = 0; i < count; i++) {
    out[i] = buf.readFloatLE(i * 4);
  }
  return out;
}

/**
 * Greedy single-pass clustering: assign each vote to the first existing cluster
 * whose CENTROID cosine >= threshold (centroid recomputed as a running mean),
 * else start a new cluster.
 */
export function clusterVotes(votes: Vote[], cosineThreshold: number = DEFAULT_COSINE_THRESHOLD): Vote[][] {
  const clusters: Vote[][] = [];
  const centroids: number[][] = [];

  for (const vote of votes) {
    let joined = false;
    for (let c = 0; c < clusters.length; c++) {
      if (cosineSimilarity(vote.embedding, centroids[c]) >= cosineThreshold) {
        clusters[c].push(vote);
        centroids[c] = runningMean(centroids[c], clusters[c].length - 1, vote.embedding);
        joined = true;
        break;
      }
    }
    if (!joined) {
      clusters.push([vote]);
      centroids.push([...vote.embedding]);
    }
  }

  return clusters;
}

/** Incorporate `next` into a centroid that was the mean of `count` vectors. */
function runningMean(centroid: number[], count: number, next: number[]): number[] {
  const n = Math.max(centroid.length, next.length);
  const out = new Array<number>(n);
  for (let i = 0; i < n; i++) {
    const c = i < centroid.length ? centroid[i] : 0;
    const x = i < next.length ? next[i] : 0;
    out[i] = (c * count + x) / (count + 1);
  }
  return out;
}

/** Most frequent value in a list (deterministic tiebreak by label string). */
function mode(values: string[]): string | null {
  if (values.length === 0) return null;
  const counts = new Map<string, number>();
  for (const v of values) counts.set(v, (counts.get(v) ?? 0) + 1);
  let best: string | null = null;
  let bestCount = -1;
  for (const [label, count] of counts) {
    if (count > bestCount || (count === bestCount && (best === null || label < best))) {
      best = label;
      bestCount = count;
    }
  }
  return best;
}

/** Resolve a single channel (shape or color) for one cluster's votes. */
function resolveChannel(
  labels: string[],
  priors: string[],
  userKeys: string[],
  weightOf: (userKey: string) => number,
  priorStrength: number,
  quorum: number,
  promoteConfidence: number,
): ChannelConsensus {
  const userWeight: Record<string, number> = {};
  const tally: Record<string, number> = {};

  if (labels.length === 0) {
    return { label: null, confidence: 0, promoted: false, tally, userWeight };
  }

  const priorLabel = mode(priors);

  for (let i = 0; i < labels.length; i++) {
    const label = labels[i];
    const w = weightOf(userKeys[i]);
    userWeight[label] = (userWeight[label] ?? 0) + w;
  }

  // Ensure the prior label is representable even if no user voted for it.
  const candidateLabels = new Set<string>(Object.keys(userWeight));
  if (priorLabel !== null) candidateLabels.add(priorLabel);

  for (const label of candidateLabels) {
    const uw = userWeight[label] ?? 0;
    tally[label] = uw + (label === priorLabel ? priorStrength : 0);
    if (!(label in userWeight)) userWeight[label] = 0;
  }

  // argmax by tally, deterministic tiebreak by label string.
  let winner: string | null = null;
  let winnerScore = -Infinity;
  for (const [label, score] of Object.entries(tally)) {
    if (score > winnerScore || (score === winnerScore && (winner === null || label < winner))) {
      winner = label;
      winnerScore = score;
    }
  }

  // second best tally (for the top1/top2 margin).
  let secondScore = 0;
  const distinctLabels = Object.keys(tally);
  if (distinctLabels.length > 1) {
    secondScore = -Infinity;
    for (const [label, score] of Object.entries(tally)) {
      if (label === winner) continue;
      if (score > secondScore) secondScore = score;
    }
  }

  let confidence: number;
  if (winner === null || winnerScore <= 0) {
    confidence = 0;
  } else if (distinctLabels.length <= 1) {
    confidence = 1;
  } else {
    confidence = (winnerScore - secondScore) / winnerScore;
  }
  confidence = Math.min(1, Math.max(0, confidence));

  const winnerUserWeight = winner === null ? 0 : userWeight[winner] ?? 0;
  const promoted = confidence >= promoteConfidence && winnerUserWeight >= quorum;

  return { label: winner, confidence, promoted, tally, userWeight };
}

/** Cluster the votes, then resolve shape + color consensus per cluster. */
export function computeConsensus(votes: Vote[], options: ConsensusOptions = {}): ClusterConsensus[] {
  const cosineThreshold = options.cosineThreshold ?? DEFAULT_COSINE_THRESHOLD;
  const priorStrength = options.priorStrength ?? DEFAULT_PRIOR_STRENGTH;
  const quorum = options.quorum ?? DEFAULT_QUORUM;
  const promoteConfidence = options.promoteConfidence ?? DEFAULT_PROMOTE_CONFIDENCE;
  const weightOf = options.weightOf ?? DEFAULT_WEIGHT_OF;

  const clusters = clusterVotes(votes, cosineThreshold);

  return clusters.map((members) => {
    const userKeys = members.map((v) => v.userKey);
    const shape = resolveChannel(
      members.map((v) => v.shapeLabel),
      members.map((v) => v.predictedShape),
      userKeys,
      weightOf,
      priorStrength,
      quorum,
      promoteConfidence,
    );
    const color = resolveChannel(
      members.map((v) => v.colorLabel),
      members.map((v) => v.predictedColor),
      userKeys,
      weightOf,
      priorStrength,
      quorum,
      promoteConfidence,
    );
    return { members: members.length, shape, color };
  });
}
