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
  type ForgeMeshImageRequest,
  type ForgeMeshResult,
  type ForgeSize,
} from '../types.js';

/**
 * POST /api/forgeMeshFromImage
 *
 * Image → high-fidelity 3D via the configured mesh provider (Tripo by default).
 * Same gating as the text path: entitlement → per-user quota → global spend
 * guard → provider. Returns a `ForgeMeshResult` (a model URL the iOS client
 * downloads + voxelizes). Provider-agnostic via `MESH_PROVIDER`.
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

export async function forgeMeshFromImage(
  request: HttpRequest,
  context: InvocationContext,
): Promise<HttpResponseInit> {
  try {
    let body: ForgeMeshImageRequest;
    try {
      body = (await request.json()) as ForgeMeshImageRequest;
    } catch {
      throw new ProxyError(400, 'bad_request', 'Invalid JSON body.');
    }
    const imageBase64 = typeof body?.imageBase64 === 'string' ? body.imageBase64 : '';
    if (imageBase64.length < 32) {
      throw new ProxyError(400, 'bad_request', 'Missing or invalid image.');
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

    // Global spend guard first.
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
    const result = await provider.forgeFromImage(imageBase64, mime, size);

    const out: ForgeMeshResult = {
      modelUrl: result.modelUrl,
      format: result.format,
      remainingQuota: remaining,
    };
    return { status: 200, jsonBody: out };
  } catch (err) {
    if (err instanceof ProxyError) {
      context.warn(`forgeMeshFromImage ${err.code}: ${err.message}`);
      return errorResponse(err);
    }
    context.error('forgeMeshFromImage unexpected error', err);
    return errorResponse(new ProxyError(502, 'upstream_error', 'Model generation failed.'));
  }
}

app.http('forgeMeshFromImage', {
  methods: ['POST'],
  authLevel: 'anonymous',
  route: 'forgeMeshFromImage',
  handler: forgeMeshFromImage,
});
