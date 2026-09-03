/**
 * Per-user Beta reputation used to trust-weight crowdsourced brick votes.
 *
 * A user's reliability is modeled as a Beta(a, b) posterior: `a` counts times
 * their vote agreed with settled consensus / a honeypot, `b` counts times it
 * disagreed. New users start at Beta(1, 1) (mean 0.5 → ~zero weight) so a Sybil
 * flood or an accidental mis-labeler cannot move a label until they've earned
 * trust against known answers. See docs/CROWDSOURCED-SCANNER-ACCURACY-PLAN.md §4.
 *
 * Pure functions, no side effects, no I/O.
 */

export interface BetaReputation {
  a: number;
  b: number;
}

/** Fresh user: Beta(1, 1) → mean 0.5 → weight 0 (probation). */
export const REPUTATION_PRIOR: BetaReputation = { a: 1, b: 1 };

/**
 * Return a new reputation with `a` bumped when the vote agreed with ground
 * truth / settled consensus, or `b` bumped when it disagreed. Does not mutate
 * the input.
 */
export function updateReputation(rep: BetaReputation, agreed: boolean): BetaReputation {
  return agreed ? { a: rep.a + 1, b: rep.b } : { a: rep.a, b: rep.b + 1 };
}

/** Posterior mean a/(a+b). Guards divide-by-zero by returning 0.5. */
export function reputationMean(rep: BetaReputation): number {
  const total = rep.a + rep.b;
  if (total <= 0) return 0.5;
  return rep.a / total;
}

/**
 * Vote weight in [0, 1] derived conservatively from the mean:
 * `max(0, 2·mean − 1)`. Sub-50% agreement contributes nothing, a fresh user
 * (~0.5) contributes ~0, and weight rises toward 1 as agreements accumulate.
 */
export function reputationWeight(rep: BetaReputation): number {
  const w = 2 * reputationMean(rep) - 1;
  return w > 0 ? w : 0;
}
