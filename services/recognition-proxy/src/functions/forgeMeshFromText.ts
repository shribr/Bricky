import {
  app,
  type HttpRequest,
  type HttpResponseInit,
  type InvocationContext,
} from '@azure/functions';
import { verifyDevBypassToken, verifyEntitlement } from '../entitlement.js';
import { createMeshProvider } from '../meshProvider.js';
import { TableQuotaStore, type QuotaStore } from '../quota.js';
import {
  FORGE_SIZES,
  ProxyError,
  type ErrorBody,
  type ForgeMeshRequest,
  type ForgeMeshResult,
  type ForgeSize,
} from '../types.js';

/**
 * POST /api/forgeMeshFromText
 *
 * Premium Set Forge tier: entitlement → per-user quota → **global spend guard**
 * → hosted Tripo text→3D. Returns a `ForgeMeshResult` (a model URL the iOS
 * client downloads + voxelizes). Developer-only, exactly like the other cloud
 * features, so per-generation cost stays controlled.
 *
 * The **global spend guard** is a second quota row (`__global_tripo__`) with a
 * hard monthly cap (`TRIPO_MONTHLY_CAP`), so total vendor spend can never run
 * away regardless of how many users/tokens exist.
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
      Number(env('MONTHLY_QUOTA') ?? '100'),
    );
  }
  return cachedUserQuota;
}

let cachedGlobalGuard: QuotaStore | undefined;
/** Global monthly hard cap across ALL users — the runaway-spend guard. */
function globalGuard(): QuotaStore {
  if (!cachedGlobalGuard) {
    cachedGlobalGuard = new TableQuotaStore(
      requireEnv('QUOTA_TABLE_CONNECTION'),
      Number(env('TRIPO_MONTHLY_CAP') ?? '500'),
    );
  }
  return cachedGlobalGuard;
}

const GLOBAL_KEY = '__global_tripo__';

export async function forgeMeshFromText(
  request: HttpRequest,
  context: InvocationContext,
): Promise<HttpResponseInit> {
  try {
    let body: ForgeMeshRequest;
    try {
      body = (await request.json()) as ForgeMeshRequest;
    } catch {
      throw new ProxyError(400, 'bad_request', 'Invalid JSON body.');
    }
    const prompt = typeof body?.prompt === 'string' ? body.prompt.trim() : '';
    if (prompt.length < 2) {
      throw new ProxyError(400, 'bad_request', 'Missing or too-short prompt.');
    }
    if (prompt.length > 300) {
      throw new ProxyError(400, 'bad_request', 'Prompt is too long.');
    }
    const size: ForgeSize = FORGE_SIZES.includes(body?.size as ForgeSize)
      ? (body.size as ForgeSize)
      : 'medium';

    // Entitlement: real Bricky Pro (StoreKit JWS) or developer bypass.
    const entitlement =
      verifyDevBypassToken(body.entitlementToken, env('DEV_BYPASS_TOKEN')) ??
      verifyEntitlement(body.entitlementToken, {
        bundleId: env('APPSTORE_BUNDLE_ID') ?? 'com.bricky.app',
        environment: env('APPSTORE_ENVIRONMENT') ?? 'Production',
        verifyChain: env('APPSTORE_VERIFY_CHAIN') === 'true',
      });

    // Global spend guard FIRST (cheap fail-fast before per-user).
    try {
      await globalGuard().consume(GLOBAL_KEY);
    } catch (err) {
      if (err instanceof ProxyError && err.status === 429) {
        throw new ProxyError(429, 'quota_exceeded', 'The HD model service is at capacity this month.');
      }
      throw err;
    }

    // Per-user monthly quota.
    const { remaining } = await userQuota().consume(entitlement.userKey);

    // Hosted mesh generation via the configured provider (Tripo by default).
    const provider = createMeshProvider(process.env);
    const result = await provider.forgeFromText(prompt, size);

    const out: ForgeMeshResult = {
      modelUrl: result.modelUrl,
      format: result.format,
      remainingQuota: remaining,
    };
    return { status: 200, jsonBody: out };
  } catch (err) {
    if (err instanceof ProxyError) {
      context.warn(`forgeMeshFromText ${err.code}: ${err.message}`);
      return errorResponse(err);
    }
    context.error('forgeMeshFromText unexpected error', err);
    return errorResponse(new ProxyError(502, 'upstream_error', 'Model generation failed.'));
  }
}

app.http('forgeMeshFromText', {
  methods: ['POST'],
  authLevel: 'anonymous',
  route: 'forgeMeshFromText',
  handler: forgeMeshFromText,
});
