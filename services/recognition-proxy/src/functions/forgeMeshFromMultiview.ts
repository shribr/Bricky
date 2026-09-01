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
  type ForgeMeshMultiviewRequest,
  type ForgeMeshResult,
  type ForgeSize,
} from '../types.js';

/**
 * POST /api/forgeMeshFromMultiview
 *
 * Multiple angles → a genuinely 3D model via the configured provider (Tripo
 * `multiview_to_model`). Same gating as the other mesh paths. Returns a
 * `ForgeMeshResult` (model URL the iOS client downloads + voxelizes).
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

export async function forgeMeshFromMultiview(
  request: HttpRequest,
  context: InvocationContext,
): Promise<HttpResponseInit> {
  try {
    let body: ForgeMeshMultiviewRequest;
    try {
      body = (await request.json()) as ForgeMeshMultiviewRequest;
    } catch {
      throw new ProxyError(400, 'bad_request', 'Invalid JSON body.');
    }
    const images = Array.isArray(body?.imagesBase64)
      ? body.imagesBase64.filter((s) => typeof s === 'string' && s.length >= 32)
      : [];
    if (images.length === 0) {
      throw new ProxyError(400, 'bad_request', 'At least one valid image is required.');
    }
    const mime = typeof body?.mime === 'string' && body.mime.length > 0 ? body.mime : 'image/jpeg';
    const size: ForgeSize = FORGE_SIZES.includes(body?.size as ForgeSize)
      ? (body.size as ForgeSize)
      : 'medium';

    const entitlement =
      verifyDevBypassToken(body.entitlementToken, env('DEV_BYPASS_TOKEN')) ??
      verifyEntitlement(body.entitlementToken, {
        bundleId: env('APPSTORE_BUNDLE_ID') ?? 'com.bricky.app',
        environment: env('APPSTORE_ENVIRONMENT') ?? 'Production',
        verifyChain: env('APPSTORE_VERIFY_CHAIN') === 'true',
      });

    try {
      await globalGuard().consume(GLOBAL_KEY);
    } catch (err) {
      if (err instanceof ProxyError && err.status === 429) {
        throw new ProxyError(429, 'quota_exceeded', 'The HD model service is at capacity this month.');
      }
      throw err;
    }

    const { remaining } = await userQuota().consume(entitlement.userKey);

    const provider = createMeshProvider(process.env);
    const result = await provider.forgeFromMultiview(images.slice(0, 4), mime, size);

    const out: ForgeMeshResult = {
      modelUrl: result.modelUrl,
      format: result.format,
      remainingQuota: remaining,
    };
    return { status: 200, jsonBody: out };
  } catch (err) {
    if (err instanceof ProxyError) {
      context.warn(`forgeMeshFromMultiview ${err.code}: ${err.message}`);
      return errorResponse(err);
    }
    context.error('forgeMeshFromMultiview unexpected error', err);
    return errorResponse(new ProxyError(502, 'upstream_error', 'Model generation failed.'));
  }
}

app.http('forgeMeshFromMultiview', {
  methods: ['POST'],
  authLevel: 'anonymous',
  route: 'forgeMeshFromMultiview',
  handler: forgeMeshFromMultiview,
});
