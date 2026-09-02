import { test } from 'node:test';
import assert from 'node:assert/strict';
import { SelfHostedMeshProvider, TripoProvider, ReplicateMeshProvider, createMeshProvider } from '../src/meshProvider.js';
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

test('createMeshProvider returns a ReplicateMeshProvider when MESH_PROVIDER=replicate', () => {
  const provider = createMeshProvider({
    MESH_PROVIDER: 'Replicate',
    REPLICATE_API_TOKEN: 'r8_x',
    REPLICATE_MODEL_VERSION: 'ver123',
  });
  assert.equal(provider.name, 'replicate');
  assert.ok(provider instanceof ReplicateMeshProvider);
});

test('createMeshProvider throws not_configured when REPLICATE_MODEL_VERSION is missing', () => {
  assert.throws(
    () => createMeshProvider({ MESH_PROVIDER: 'replicate', REPLICATE_API_TOKEN: 'r8_x' }),
    (e) => e instanceof ProxyError && e.status === 503 && e.code === 'not_configured',
  );
});

test('ReplicateMeshProvider.forgeFromImage creates a prediction, polls, and returns the mesh URL', async () => {
  const calls: Array<{ url: string; init: RequestInit }> = [];
  const responses = [
    { ok: true, status: 201, json: async () => ({ id: 'p1', status: 'processing', urls: { get: 'https://api.replicate.test/v1/predictions/p1' } }) },
    { ok: true, status: 200, json: async () => ({ id: 'p1', status: 'succeeded', output: 'https://cdn.replicate.test/mesh.obj' }) },
  ];
  let i = 0;
  const fetchImpl = (async (url: string, init: RequestInit) => {
    calls.push({ url, init });
    return responses[Math.min(i++, responses.length - 1)] as unknown as Response;
  }) as unknown as typeof fetch;

  const provider = new ReplicateMeshProvider({
    apiToken: 'r8_secret',
    modelVersion: 'ver123',
    baseUrl: 'https://api.replicate.test/v1',
  });
  const result = await provider.forgeFromImage('aGVsbG8=', 'image/png', 'small', {
    fetchImpl,
    sleep: async () => {},
  });

  assert.equal(result.modelUrl, 'https://cdn.replicate.test/mesh.obj');
  assert.equal(result.format, 'obj');
  assert.equal(calls.length, 2);
  assert.equal(calls[0].url, 'https://api.replicate.test/v1/predictions');
  assert.equal(calls[0].init.method, 'POST');
  const createHeaders = calls[0].init.headers as Record<string, string>;
  assert.equal(createHeaders.authorization, 'Token r8_secret');
  assert.equal(createHeaders.prefer, 'wait');
  const body = JSON.parse(calls[0].init.body as string);
  assert.equal(body.version, 'ver123');
  assert.equal(body.input.image_path, 'data:image/png;base64,aGVsbG8=');
  assert.equal(calls[1].url, 'https://api.replicate.test/v1/predictions/p1');
  assert.equal(calls[1].init.method ?? 'GET', 'GET');
});

test('ReplicateMeshProvider returns immediately on a synchronous succeeded prediction', async () => {
  let count = 0;
  const fetchImpl = (async () => {
    count++;
    return { ok: true, status: 201, json: async () => ({ status: 'succeeded', output: ['https://cdn.replicate.test/a.glb'] }) } as unknown as Response;
  }) as unknown as typeof fetch;
  const provider = new ReplicateMeshProvider({ apiToken: 'r8', modelVersion: 'v', baseUrl: 'https://api.replicate.test/v1' });
  const result = await provider.forgeFromImage('aGk=', 'image/jpeg', 'small', { fetchImpl });
  assert.equal(result.modelUrl, 'https://cdn.replicate.test/a.glb');
  assert.equal(result.format, 'glb');
  assert.equal(count, 1, 'no polling when the create call already succeeded');
});

test('ReplicateMeshProvider throws upstream_error when the prediction fails', async () => {
  const fetchImpl = (async () =>
    ({ ok: true, status: 201, json: async () => ({ status: 'failed' }) }) as unknown as Response) as unknown as typeof fetch;
  const provider = new ReplicateMeshProvider({ apiToken: 'r8', modelVersion: 'v', baseUrl: 'https://api.replicate.test/v1' });
  await assert.rejects(
    () => provider.forgeFromImage('aGk=', 'image/jpeg', 'small', { fetchImpl, sleep: async () => {} }),
    (e) => e instanceof ProxyError && e.status === 502 && e.code === 'upstream_error',
  );
});

test('ReplicateMeshProvider does not support text-to-3D', () => {
  const provider = new ReplicateMeshProvider({ apiToken: 'r8', modelVersion: 'v' });
  assert.throws(
    () => provider.forgeFromText(),
    (e) => e instanceof ProxyError && e.status === 503 && e.code === 'not_configured',
  );
});

test('ReplicateMeshProvider.forgeFromMultiview uses the first view', async () => {
  const calls: Array<{ init: RequestInit }> = [];
  const fetchImpl = (async (_url: string, init: RequestInit) => {
    calls.push({ init });
    return { ok: true, status: 201, json: async () => ({ status: 'succeeded', output: 'https://cdn.replicate.test/m.usdz' }) } as unknown as Response;
  }) as unknown as typeof fetch;
  const provider = new ReplicateMeshProvider({ apiToken: 'r8', modelVersion: 'v', baseUrl: 'https://api.replicate.test/v1' });
  const result = await provider.forgeFromMultiview(['front==', 'left=='], 'image/jpeg', 'medium', { fetchImpl });
  assert.equal(result.format, 'usdz');
  const body = JSON.parse(calls[0].init.body as string);
  assert.equal(body.input.image_path, 'data:image/jpeg;base64,front==');
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
