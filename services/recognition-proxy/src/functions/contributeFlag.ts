import {
  app,
  type HttpRequest,
  type HttpResponseInit,
  type InvocationContext,
} from '@azure/functions';
import { verifyDevBypassToken, verifyEntitlement } from '../entitlement.js';
import {
  TableContributionStore,
  validateObservation,
  type ContributionStore,
} from '../contributionStore.js';
import { TableQuotaStore, type QuotaStore } from '../quota.js';
import { ProxyError, type ErrorBody } from '../types.js';

/**
 * POST /api/contributeFlag
 *
 * Ingests a user's brick correction/confirmation ("Observation") and stores it
 * so a later batch job can build crowd consensus. Gated by the same
 * dev-bypass-OR-StoreKit entitlement as the mesh handlers, then a generous
 * per-user monthly spam cap. Returns 200 `{ ok: true }` or `{ error, code }`.
 */

function env(name: string): string | undefined {
  const v = process.env[name];
  return v && v.length > 0 ? v : undefined;
}

function requireEnv(name: string): string {
  const v = env(name);
  if (!v) {
    throw new ProxyError(503, 'not_configured', `Missing configuration: ${name}.`);
  }
  return v;
}

function errorResponse(err: ProxyError): HttpResponseInit {
  const body: ErrorBody = { error: err.message, code: err.code };
  return { status: err.status, jsonBody: body };
}

let cachedUserQuota: QuotaStore | undefined;
function userQuota(): QuotaStore {
  if (!cachedUserQuota) {
    cachedUserQuota = new TableQuotaStore(
      requireEnv('QUOTA_TABLE_CONNECTION'),
      Number(env('CONTRIB_MONTHLY_QUOTA') ?? '2000'),
    );
  }
  return cachedUserQuota;
}

let cachedStore: ContributionStore | undefined;
function contributionStore(): ContributionStore {
  if (!cachedStore) {
    cachedStore = new TableContributionStore(
      env('CONTRIB_TABLE_CONNECTION') ?? requireEnv('QUOTA_TABLE_CONNECTION'),
    );
  }
  return cachedStore;
}

export async function contributeFlag(
  request: HttpRequest,
  context: InvocationContext,
): Promise<HttpResponseInit> {
  try {
    let body: { entitlementToken?: string };
    try {
      body = (await request.json()) as { entitlementToken?: string };
    } catch {
      throw new ProxyError(400, 'bad_request', 'Invalid JSON body.');
    }

    const entitlement =
      verifyDevBypassToken(body.entitlementToken, env('DEV_BYPASS_TOKEN')) ??
      verifyEntitlement(body.entitlementToken, {
        bundleId: env('APPSTORE_BUNDLE_ID') ?? 'com.bricky.app',
        environment: env('APPSTORE_ENVIRONMENT') ?? 'Production',
        verifyChain: env('APPSTORE_VERIFY_CHAIN') === 'true',
      });

    const obs = validateObservation(body);

    // Per-user spam cap — generous, just prevents runaway abuse.
    try {
      await userQuota().consume(entitlement.userKey);
    } catch (err) {
      if (err instanceof ProxyError && err.status === 429) {
        throw new ProxyError(
          429,
          'quota_exceeded',
          'Monthly contribution allowance used up.',
        );
      }
      throw err;
    }

    await contributionStore().save(entitlement.userKey, obs);

    return { status: 200, jsonBody: { ok: true } };
  } catch (err) {
    if (err instanceof ProxyError) {
      context.warn(`contributeFlag ${err.code}: ${err.message}`);
      return errorResponse(err);
    }
    context.error('contributeFlag unexpected error', err);
    return errorResponse(new ProxyError(502, 'upstream_error', 'Could not record your contribution.'));
  }
}

app.http('contributeFlag', {
  methods: ['POST'],
  authLevel: 'anonymous',
  route: 'contributeFlag',
  handler: contributeFlag,
});
