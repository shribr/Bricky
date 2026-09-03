import {
  app,
  type HttpRequest,
  type HttpResponseInit,
  type InvocationContext,
} from '@azure/functions';
import { verifyDevBypassToken, verifyEntitlement } from '../entitlement.js';
import {
  TableHoneypotResultStore,
  validateHoneypotResult,
  type HoneypotResultStore,
} from '../honeypotStore.js';
import { TableQuotaStore, type QuotaStore } from '../quota.js';
import { ProxyError, type ErrorBody } from '../types.js';
import type { HoneypotResult } from '../honeypot.js';

/**
 * POST /api/submitHoneypot
 *
 * Records a user's answer to a known-answer honeypot item. Gated by the SAME
 * dev-bypass-OR-StoreKit entitlement as `contributeFlag`, then a generous
 * per-user monthly spam cap. The answer is graded LATER (in the consensus batch)
 * against the secret truth, so no truth is exchanged here. Returns 200
 * `{ ok: true }` or `{ error, code }`.
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

function errorResponse(err: ProxyError): HttpResponseInit {
  const body: ErrorBody = { error: err.message, code: err.code };
  return { status: err.status, jsonBody: body };
}

let cachedUserQuota: QuotaStore | undefined;
function userQuota(): QuotaStore {
  if (!cachedUserQuota) {
    cachedUserQuota = new TableQuotaStore(
      requireEnv('QUOTA_TABLE_CONNECTION'),
      Number(env('HONEYPOT_MONTHLY_QUOTA') ?? '2000'),
    );
  }
  return cachedUserQuota;
}

let cachedStore: HoneypotResultStore | undefined;
function honeypotResultStore(): HoneypotResultStore {
  if (!cachedStore) {
    cachedStore = new TableHoneypotResultStore(
      env('HONEYPOT_TABLE_CONNECTION') ??
        env('CONTRIB_TABLE_CONNECTION') ??
        requireEnv('QUOTA_TABLE_CONNECTION'),
    );
  }
  return cachedStore;
}

export async function submitHoneypot(
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

    const partial = validateHoneypotResult(body);
    const result: HoneypotResult = { ...partial, userKey: entitlement.userKey };

    // Per-user spam cap — generous, just prevents runaway abuse.
    try {
      await userQuota().consume(entitlement.userKey);
    } catch (err) {
      if (err instanceof ProxyError && err.status === 429) {
        throw new ProxyError(429, 'quota_exceeded', 'Monthly honeypot allowance used up.');
      }
      throw err;
    }

    await honeypotResultStore().save(result);

    return { status: 200, jsonBody: { ok: true } };
  } catch (err) {
    if (err instanceof ProxyError) {
      context.warn(`submitHoneypot ${err.code}: ${err.message}`);
      return errorResponse(err);
    }
    context.error('submitHoneypot unexpected error', err);
    return errorResponse(
      new ProxyError(502, 'upstream_error', 'Could not record your answer.'),
    );
  }
}

app.http('submitHoneypot', {
  methods: ['POST'],
  authLevel: 'anonymous',
  route: 'submitHoneypot',
  handler: submitHoneypot,
});
