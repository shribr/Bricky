import { test } from 'node:test';
import assert from 'node:assert/strict';
import { SelfHostedMeshProvider, TripoProvider, createMeshProvider } from '../src/meshProvider.js';
import { ProxyError } from '../src/types.js';

function sequenceFetch(payloads: Array<{ json: unknown }>): typeof fetch {
  let i = 0;
  return (async () => {
    const p = payloads[Math.min(i, payloads.length - 1)];
    i++;
    return { ok: true, status: 200, json: async () => p.json } as unknown as Response;
  }) as typeof fetch;
}

test('createMeshProvider defaults to Tripo when key is set', () => {
  const provider = createMeshProvider({ TRIPO_API_KEY: 'tsk_x' });
  assert.equal(provider.name, 'tripo');
});

test('createMeshProvider honors MESH_PROVIDER=tripo', () => {
  const provider = createMeshProvider({ MESH_PROVIDER: 'Tripo', TRIPO_API_KEY: 'tsk_x' });
  assert.equal(provider.name, 'tripo');
});

test('createMeshProvider throws not_configured when the key is missing', () => {
  assert.throws(() => createMeshProvider({}), (e) => e instanceof ProxyError && e.status === 503);
});

test('createMeshProvider throws for an unknown provider', () => {
  assert.throws(
    () => createMeshProvider({ MESH_PROVIDER: 'acme' }),
    (e) => e instanceof ProxyError && e.status === 503,
  );
});

test('createMeshProvider returns a SelfHostedMeshProvider when MESH_PROVIDER=selfhosted', () => {
  const provider = createMeshProvider({
    MESH_PROVIDER: 'SelfHosted',
    SELFHOSTED_MESH_URL: 'https://mesh.example/forge',
  });
  assert.equal(provider.name, 'selfhosted');
  assert.ok(provider instanceof SelfHostedMeshProvider);
});

test('createMeshProvider throws not_configured when SELFHOSTED_MESH_URL is missing', () => {
  assert.throws(
    () => createMeshProvider({ MESH_PROVIDER: 'selfhosted' }),
    (e) => e instanceof ProxyError && e.status === 503 && e.code === 'not_configured',
  );
});

test('SelfHostedMeshProvider.forgeFromImage posts and parses {modelUrl,format}', async () => {
  const calls: Array<{ url: string; init: RequestInit }> = [];
  const fetchImpl = (async (url: string, init: RequestInit) => {
    calls.push({ url, init });
    return {
      ok: true,
      status: 200,
      json: async () => ({ modelUrl: 'https://mesh.example/out.glb', format: 'glb' }),
    } as unknown as Response;
  }) as unknown as typeof fetch;

  const provider = new SelfHostedMeshProvider({
    url: 'https://mesh.example/forge',
    key: 'secret123',
  });
  const result = await provider.forgeFromImage('aGVsbG8=', 'image/jpeg', 'small', { fetchImpl });

  assert.equal(result.modelUrl, 'https://mesh.example/out.glb');
  assert.equal(result.format, 'glb');
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, 'https://mesh.example/forge');
  assert.equal(calls[0].init.method, 'POST');
  const headers = calls[0].init.headers as Record<string, string>;
  assert.equal(headers.authorization, 'Bearer secret123');
  const sent = JSON.parse(calls[0].init.body as string);
  assert.deepEqual(sent, { mode: 'image', imageBase64: 'aGVsbG8=', mime: 'image/jpeg', size: 'small' });
});

test('SelfHostedMeshProvider defaults format to usdz when omitted', async () => {
  const fetchImpl = (async () =>
    ({
      ok: true,
      status: 200,
      json: async () => ({ modelUrl: 'https://mesh.example/out.usdz' }),
    }) as unknown as Response) as unknown as typeof fetch;
  const provider = new SelfHostedMeshProvider({ url: 'https://mesh.example/forge' });
  const result = await provider.forgeFromText('a red brick', 'medium', { fetchImpl });
  assert.equal(result.format, 'usdz');
});

test('SelfHostedMeshProvider throws upstream_error on non-2xx', async () => {
  const fetchImpl = (async () =>
    ({ ok: false, status: 500, json: async () => ({}) }) as unknown as Response) as unknown as typeof fetch;
  const provider = new SelfHostedMeshProvider({ url: 'https://mesh.example/forge' });
  await assert.rejects(
    () => provider.forgeFromMultiview(['aGVsbG8='], 'image/jpeg', 'small', { fetchImpl }),
    (e) => e instanceof ProxyError && e.status === 502 && e.code === 'upstream_error',
  );
});

test('SelfHostedMeshProvider throws upstream_error on malformed response', async () => {
  const fetchImpl = (async () =>
    ({ ok: true, status: 200, json: async () => ({ notAUrl: true }) }) as unknown as Response) as unknown as typeof fetch;
  const provider = new SelfHostedMeshProvider({ url: 'https://mesh.example/forge' });
  await assert.rejects(
    () => provider.forgeFromImage('aGVsbG8=', 'image/jpeg', 'small', { fetchImpl }),
    (e) => e instanceof ProxyError && e.status === 502 && e.code === 'upstream_error',
  );
});

test('TripoProvider.forgeFromText delegates and returns a model', async () => {
  const provider = new TripoProvider({ apiKey: 'tsk_x' });
  const fetchImpl = sequenceFetch([
    { json: { code: 0, data: { task_id: 'draft1' } } },
    { json: { code: 0, data: { status: 'success', output: {} } } },
    { json: { code: 0, data: { task_id: 'conv1' } } },
    { json: { code: 0, data: { status: 'success', output: { model: 'https://x/m.usdz' } } } },
  ]);
  const result = await provider.forgeFromText('a cat', 'small', {
    fetchImpl,
    sleep: async () => {},
    pollIntervalMs: 0,
  });
  assert.equal(result.modelUrl, 'https://x/m.usdz');
  assert.equal(result.format, 'usdz');
});

test('TripoProvider.forgeFromImage delegates and returns a model', async () => {
  const provider = new TripoProvider({ apiKey: 'tsk_x' });
  const fetchImpl = sequenceFetch([
    { json: { code: 0, data: { image_token: 'img1' } } },
    { json: { code: 0, data: { task_id: 'draftImg' } } },
    { json: { code: 0, data: { status: 'success', output: {} } } },
    { json: { code: 0, data: { task_id: 'conv1' } } },
    { json: { code: 0, data: { status: 'success', output: { model: 'https://x/m.usdz' } } } },
  ]);
  const result = await provider.forgeFromImage('aGVsbG8=', 'image/jpeg', 'small', {
    fetchImpl,
    sleep: async () => {},
    pollIntervalMs: 0,
  });
  assert.equal(result.format, 'usdz');
});

test('TripoProvider.forgeFromMultiview delegates and returns a model', async () => {
  const provider = new TripoProvider({ apiKey: 'tsk_x' });
  const fetchImpl = sequenceFetch([
    { json: { code: 0, data: { image_token: 'front' } } },
    { json: { code: 0, data: { task_id: 'draftMV' } } },
    { json: { code: 0, data: { status: 'success', output: {} } } },
    { json: { code: 0, data: { task_id: 'conv1' } } },
    { json: { code: 0, data: { status: 'success', output: { model: 'https://x/m.usdz' } } } },
  ]);
  const result = await provider.forgeFromMultiview(['aGVsbG8='], 'image/jpeg', 'small', {
    fetchImpl,
    sleep: async () => {},
    pollIntervalMs: 0,
  });
  assert.equal(result.format, 'usdz');
});
