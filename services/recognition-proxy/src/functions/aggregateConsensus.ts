import { app, type InvocationContext, type Timer } from '@azure/functions';
import { TableContributionStore, type ContributionStore } from '../contributionStore.js';
import {
  TableCorrectionIndexStore,
  aggregate,
  type CorrectionIndexStore,
} from '../correctionIndex.js';
import { TableReputationStore, type ReputationStore } from '../reputationStore.js';
import { REPUTATION_PRIOR, reputationWeight, type BetaReputation } from '../reputation.js';
import {
  TableHoneypotStore,
  TableHoneypotResultStore,
  type HoneypotStore,
  type HoneypotResultStore,
} from '../honeypotStore.js';
import { honeypotReputationDeltas, mergeDeltas, type Honeypot } from '../honeypot.js';
import { ProxyError } from '../types.js';

/**
 * Timer: aggregateConsensus (daily 03:00 UTC)
 *
 * Batch job that turns stored contributions into a promoted correction index
 * AND closes the trust loop by earning per-user reputation against settled
 * consensus. Loads prior reputation to trust-weight votes, clusters + resolves
 * crowd consensus, bumps the index version, persists the new index, and writes
 * back freshly-recomputed reputations. Thin wrapper — the real work lives in the
 * pure `aggregate`.
 */

function env(name: string): string | undefined {
  const v = process.env[name];
  return v && v.length > 0 ? v : undefined;
}

function requireEnv(name: string): string {
  const v = env(name);
  if (!v) throw new ProxyError(503, 'not_configured', `Missing configuration: ${name}.`);
  return v;
}

let cachedContribStore: ContributionStore | undefined;
function contributionStore(): ContributionStore {
  if (!cachedContribStore) {
    cachedContribStore = new TableContributionStore(
      env('CONTRIB_TABLE_CONNECTION') ?? requireEnv('QUOTA_TABLE_CONNECTION'),
    );
  }
  return cachedContribStore;
}

let cachedIndexStore: CorrectionIndexStore | undefined;
function correctionIndexStore(): CorrectionIndexStore {
  if (!cachedIndexStore) {
    cachedIndexStore = new TableCorrectionIndexStore(
      env('CORRECTION_INDEX_TABLE_CONNECTION') ??
        env('CONTRIB_TABLE_CONNECTION') ??
        requireEnv('QUOTA_TABLE_CONNECTION'),
    );
  }
  return cachedIndexStore;
}

let cachedReputationStore: ReputationStore | undefined;
function reputationStore(): ReputationStore {
  if (!cachedReputationStore) {
    cachedReputationStore = new TableReputationStore(
      env('REPUTATION_TABLE_CONNECTION') ??
        env('CONTRIB_TABLE_CONNECTION') ??
        requireEnv('QUOTA_TABLE_CONNECTION'),
    );
  }
  return cachedReputationStore;
}

let cachedHoneypotStore: HoneypotStore | undefined;
function honeypotStore(): HoneypotStore {
  if (!cachedHoneypotStore) {
    cachedHoneypotStore = new TableHoneypotStore(
      env('HONEYPOT_TABLE_CONNECTION') ??
        env('CONTRIB_TABLE_CONNECTION') ??
        requireEnv('QUOTA_TABLE_CONNECTION'),
    );
  }
  return cachedHoneypotStore;
}

let cachedHoneypotResultStore: HoneypotResultStore | undefined;
function honeypotResultStore(): HoneypotResultStore {
  if (!cachedHoneypotResultStore) {
    cachedHoneypotResultStore = new TableHoneypotResultStore(
      env('HONEYPOT_TABLE_CONNECTION') ??
        env('CONTRIB_TABLE_CONNECTION') ??
        requireEnv('QUOTA_TABLE_CONNECTION'),
    );
  }
  return cachedHoneypotResultStore;
}

export async function aggregateConsensus(_timer: Timer, context: InvocationContext): Promise<void> {
  try {
    const contribStore = contributionStore();
    const indexStore = correctionIndexStore();
    const repStore = reputationStore();

    const contribs = await contribStore.listRecent();
    const priorReps = await repStore.load();
    const weightOf = (uk: string): number => reputationWeight(priorReps.get(uk) ?? REPUTATION_PRIOR);

    const next = String(Number(await indexStore.currentVersion()) + 1);
    const { index, reputationDeltas } = aggregate(contribs, { version: next, weightOf });
    await indexStore.save(index);

    // Honeypots are the collusion-proof anchor: graded against SECRET known
    // truth, so a colluding group cannot fake them. Combine them additively
    // with consensus-agreement deltas (relative weighting is a tuning knob for
    // later) before the reputation recompute.
    const honeypotList = await honeypotStore().list();
    const honeypotMap = new Map<string, Honeypot>(honeypotList.map((h) => [h.id, h]));
    const hpResults = await honeypotResultStore().listRecent();
    const hpDeltas = honeypotReputationDeltas(honeypotMap, hpResults);
    const mergedDeltas = mergeDeltas(reputationDeltas, hpDeltas);

    // Reputation is recomputed FRESH from the current contribution window (not
    // lifetime-accumulated) so repeated daily runs over the same window are
    // idempotent; a watermark-based lifetime accumulation is a later refinement.
    const newReps = new Map<string, BetaReputation>();
    for (const [userKey, delta] of mergedDeltas) {
      newReps.set(userKey, { a: 1 + delta.agreed, b: 1 + delta.disagreed });
    }
    await repStore.saveAll(newReps);

    context.log(
      `aggregateConsensus: ${contribs.length} contributions → index v${index.version} with ` +
        `${index.entries.length} promoted entries; ${newReps.size} reputations updated.`,
    );
  } catch (err) {
    context.error('aggregateConsensus failed', err);
  }
}

app.timer('aggregateConsensus', {
  schedule: '0 0 3 * * *',
  handler: aggregateConsensus,
});
