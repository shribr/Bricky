import {
  app,
  type HttpRequest,
  type HttpResponseInit,
  type InvocationContext,
} from '@azure/functions';
import { TableHoneypotStore, type HoneypotStore } from '../honeypotStore.js';
import { toPublic } from '../honeypot.js';
import { ProxyError, type ErrorBody } from '../types.js';

/**
 * GET /api/honeypots
 *
 * Serves the client-safe honeypot items so the app can run the known-answer
 * quiz. Serving is OPEN (anonymous) because the client needs the images to
 * render the quiz — but the response NEVER includes the secret ground-truth
 * `partNumber`/`color`; only `{ id, imageRef }` via `toPublic`. Returns 200
 * `{ honeypots: PublicHoneypot[] }` or `{ error, code }`.
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

let cachedStore: HoneypotStore | undefined;
function honeypotStore(): HoneypotStore {
  if (!cachedStore) {
    cachedStore = new TableHoneypotStore(
      env('HONEYPOT_TABLE_CONNECTION') ??
        env('CONTRIB_TABLE_CONNECTION') ??
        requireEnv('QUOTA_TABLE_CONNECTION'),
    );
  }
  return cachedStore;
}

export async function honeypots(
  request: HttpRequest,
  context: InvocationContext,
): Promise<HttpResponseInit> {
  if (request.method === 'OPTIONS') {
    return { status: 204, headers: CORS };
  }
  try {
    const items = await honeypotStore().list();
    // Strip ground truth — clients only ever see { id, imageRef }.
    return { status: 200, headers: CORS, jsonBody: { honeypots: items.map(toPublic) } };
  } catch (err) {
    if (err instanceof ProxyError) {
      context.warn(`honeypots ${err.code}: ${err.message}`);
      const errorBody: ErrorBody = { error: err.message, code: err.code };
      return { status: err.status, headers: CORS, jsonBody: errorBody };
    }
    context.error('honeypots unexpected error', err);
    return {
      status: 502,
      headers: CORS,
      jsonBody: { error: 'Could not load honeypots.', code: 'upstream_error' },
    };
  }
}

app.http('honeypots', {
  methods: ['GET', 'OPTIONS'],
  authLevel: 'anonymous',
  route: 'honeypots',
  handler: honeypots,
});
