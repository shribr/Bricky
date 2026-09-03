import { app, type InvocationContext, type Timer } from '@azure/functions';
import { TableContributionStore, type ContributionStore } from '../contributionStore.js';
import {
  TableCorrectionIndexStore,
  buildCorrectionIndex,
  type CorrectionIndexStore,
} from '../correctionIndex.js';
import { ProxyError } from '../types.js';

/**
 * Timer: aggregateConsensus (daily 03:00 UTC)
 *
 * Batch job that turns stored contributions into a promoted correction index.
 * Reads recent contributions, clusters + resolves crowd consensus, bumps the
 * index version, and persists the new index for the public download endpoint.
 * Thin wrapper — the real work lives in the pure `buildCorrectionIndex`.
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

export async function aggregateConsensus(_timer: Timer, context: InvocationContext): Promise<void> {
  try {
    const contribStore = contributionStore();
    const indexStore = correctionIndexStore();

    const contribs = await contribStore.listRecent();
    const next = String(Number(await indexStore.currentVersion()) + 1);
    const index = buildCorrectionIndex(contribs, { version: next });
    await indexStore.save(index);

    context.log(
      `aggregateConsensus: ${contribs.length} contributions → index v${index.version} with ${index.entries.length} promoted entries.`,
    );
  } catch (err) {
    context.error('aggregateConsensus failed', err);
  }
}

app.timer('aggregateConsensus', {
  schedule: '0 0 3 * * *',
  handler: aggregateConsensus,
});
