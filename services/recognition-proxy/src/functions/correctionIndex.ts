import {
  app,
  type HttpRequest,
  type HttpResponseInit,
  type InvocationContext,
} from '@azure/functions';
import {
  TableCorrectionIndexStore,
  type CorrectionIndexStore,
} from '../correctionIndex.js';
import { ProxyError, type ErrorBody } from '../types.js';

/**
 * GET /api/correctionIndex[?since=<version>]
 *
 * Public download of the promoted correction index. ANONYMOUS on purpose:
 * reading crowd-verified improvements benefits ALL users — only CONTRIBUTING is
 * entitlement-gated. Supports a cheap freshness check via `?since=`: if the
 * caller already has the current version, we answer `{ upToDate: true }` instead
 * of re-sending the payload.
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

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

let cachedStore: CorrectionIndexStore | undefined;
function correctionIndexStore(): CorrectionIndexStore {
  if (!cachedStore) {
    cachedStore = new TableCorrectionIndexStore(
      env('CORRECTION_INDEX_TABLE_CONNECTION') ??
        env('CONTRIB_TABLE_CONNECTION') ??
        requireEnv('QUOTA_TABLE_CONNECTION'),
    );
  }
  return cachedStore;
}

export async function correctionIndex(
  request: HttpRequest,
  context: InvocationContext,
): Promise<HttpResponseInit> {
  if (request.method === 'OPTIONS') {
    return { status: 204, headers: CORS };
  }
  try {
    const since = request.query.get('since') ?? undefined;
    const index = await correctionIndexStore().load();

    if (!index) {
      return { status: 200, headers: CORS, jsonBody: { version: '0', entries: [] } };
    }
    if (since !== undefined && since === index.version) {
      return { status: 200, headers: CORS, jsonBody: { version: index.version, upToDate: true } };
    }
    return { status: 200, headers: CORS, jsonBody: index };
  } catch (err) {
    if (err instanceof ProxyError) {
      context.warn(`correctionIndex ${err.code}: ${err.message}`);
      const errorBody: ErrorBody = { error: err.message, code: err.code };
      return { status: err.status, headers: CORS, jsonBody: errorBody };
    }
    context.error('correctionIndex unexpected error', err);
    return {
      status: 502,
      headers: CORS,
      jsonBody: { error: 'Could not load the correction index.', code: 'upstream_error' },
    };
  }
}

app.http('correctionIndex', {
  methods: ['GET', 'OPTIONS'],
  authLevel: 'anonymous',
  route: 'correctionIndex',
  handler: correctionIndex,
});
