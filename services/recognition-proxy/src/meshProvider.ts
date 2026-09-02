import { ProxyError, type ForgeSize } from './types.js';
import {
  forgeMeshFromImage as forgeTripoMeshFromImage,
  forgeMeshFromMultiview as forgeTripoMeshFromMultiview,
  forgeMeshFromText as forgeTripoMesh,
  type PollOptions,
  type TripoConfig,
  type TripoResult,
} from './tripo.js';

/**
 * Provider-agnostic mesh generation.
 *
 * Every hosted text→3D vendor (Tripo today; Meshy / CSM / Rodin next) is exposed
 * behind the same `MeshProvider` interface, so the Function handler and the iOS
 * client never depend on a specific vendor. Swap vendors by setting the
 * `MESH_PROVIDER` app setting and that provider's API-key setting — no code
 * change in the handler, no app update.
 */

export interface MeshResult {
  modelUrl: string;
  format: string;
}

export interface MeshProvider {
  readonly name: string;
  /**
   * Forge a 3D model from text and return a downloadable model URL in a
   * Model I/O-readable format (USDZ/OBJ) so the iOS client can voxelize it.
   */
  forgeFromText(prompt: string, size: ForgeSize, options?: PollOptions): Promise<MeshResult>;
  /**
   * Forge a 3D model from a base64 image (same output contract as text).
   */
  forgeFromImage(
    imageBase64: string,
    mime: string,
    size: ForgeSize,
    options?: PollOptions,
  ): Promise<MeshResult>;
  /**
   * Forge a genuinely 3D model from up to 4 base64 views (front/left/back/right).
   */
  forgeFromMultiview(
    imagesBase64: string[],
    mime: string,
    size: ForgeSize,
    options?: PollOptions,
  ): Promise<MeshResult>;
}

/** Tripo implementation (thin wrapper over the Tripo client). */
export class TripoProvider implements MeshProvider {
  readonly name = 'tripo';
  constructor(private readonly config: TripoConfig) {}

  forgeFromText(prompt: string, size: ForgeSize, options?: PollOptions): Promise<TripoResult> {
    return forgeTripoMesh(prompt, size, this.config, options ?? {});
  }

  forgeFromImage(
    imageBase64: string,
    mime: string,
    size: ForgeSize,
    options?: PollOptions,
  ): Promise<TripoResult> {
    return forgeTripoMeshFromImage(imageBase64, mime, size, this.config, options ?? {});
  }

  forgeFromMultiview(
    imagesBase64: string[],
    mime: string,
    size: ForgeSize,
    options?: PollOptions,
  ): Promise<TripoResult> {
    return forgeTripoMeshFromMultiview(imagesBase64, mime, size, this.config, options ?? {});
  }
}

/** Config for a self-hosted / open-source mesh endpoint. */
export interface SelfHostedMeshConfig {
  /** Base URL of the deployed inference endpoint (POST target). */
  url: string;
  /** Optional bearer key sent as `Authorization: Bearer <key>`. */
  key?: string;
}

/**
 * Self-hosted / open-source mesh provider.
 *
 * Lets "Cloud AI" run at $0 per-scan by delegating to a model you host yourself
 * (e.g. TripoSR or InstantMesh behind a small HTTP wrapper). Deploy any endpoint
 * that accepts the JSON contract below and returns `{ modelUrl, format? }`, then
 * set `MESH_PROVIDER=selfhosted` and `SELFHOSTED_MESH_URL` (plus optional
 * `SELFHOSTED_MESH_KEY`). Request body by mode:
 *   text:      { mode: 'text', prompt, size }
 *   image:     { mode: 'image', imageBase64, mime, size }
 *   multiview: { mode: 'multiview', imagesBase64, mime, size }
 */
export class SelfHostedMeshProvider implements MeshProvider {
  readonly name = 'selfhosted';
  constructor(private readonly config: SelfHostedMeshConfig) {}

  forgeFromText(prompt: string, size: ForgeSize, options?: PollOptions): Promise<MeshResult> {
    return this.post({ mode: 'text', prompt, size }, options);
  }

  forgeFromImage(
    imageBase64: string,
    mime: string,
    size: ForgeSize,
    options?: PollOptions,
  ): Promise<MeshResult> {
    return this.post({ mode: 'image', imageBase64, mime, size }, options);
  }

  forgeFromMultiview(
    imagesBase64: string[],
    mime: string,
    size: ForgeSize,
    options?: PollOptions,
  ): Promise<MeshResult> {
    return this.post({ mode: 'multiview', imagesBase64, mime, size }, options);
  }

  private async post(payload: Record<string, unknown>, options?: PollOptions): Promise<MeshResult> {
    const fetchImpl = options?.fetchImpl ?? fetch;
    const headers: Record<string, string> = { 'content-type': 'application/json' };
    if (this.config.key) {
      headers.authorization = `Bearer ${this.config.key}`;
    }
    let response: Response;
    try {
      response = await fetchImpl(this.config.url, {
        method: 'POST',
        headers,
        body: JSON.stringify(payload),
      });
    } catch {
      throw new ProxyError(502, 'upstream_error', 'Self-hosted mesh generation failed.');
    }
    if (!response.ok) {
      throw new ProxyError(502, 'upstream_error', 'Self-hosted mesh generation failed.');
    }
    let data: { modelUrl?: unknown; format?: unknown };
    try {
      data = (await response.json()) as { modelUrl?: unknown; format?: unknown };
    } catch {
      throw new ProxyError(502, 'upstream_error', 'Self-hosted mesh generation failed.');
    }
    const modelUrl = typeof data?.modelUrl === 'string' ? data.modelUrl : '';
    if (modelUrl.length === 0) {
      throw new ProxyError(502, 'upstream_error', 'Self-hosted mesh generation failed.');
    }
    const format = typeof data?.format === 'string' && data.format.length > 0 ? data.format : 'usdz';
    return { modelUrl, format };
  }
}

/** Config for the Replicate-hosted open-source mesh models. */
export interface ReplicateMeshConfig {
  /** Replicate API token (sent as `Authorization: Token <token>`). */
  apiToken: string;
  /** Model version hash to run, e.g. a TripoSR/InstantMesh version. */
  modelVersion: string;
  /** Input field the model expects the image under (default `image_path`). */
  imageField?: string;
  /** API base (override for testing; default `https://api.replicate.com/v1`). */
  baseUrl?: string;
}

interface ReplicatePrediction {
  id?: string;
  status?: string;
  output?: unknown;
  urls?: { get?: string };
}

/** First downloadable URL in a Replicate `output` (string | array | object). */
function extractOutputUrl(output: unknown): string {
  if (typeof output === 'string') return output;
  if (Array.isArray(output)) {
    const first = output.find((o) => typeof o === 'string');
    return typeof first === 'string' ? first : '';
  }
  if (output && typeof output === 'object') {
    const url = (output as { url?: unknown }).url;
    return typeof url === 'string' ? url : '';
  }
  return '';
}

/** Model I/O-readable format from the URL extension (default `glb`). */
function formatFromUrl(url: string): string {
  const m = url.match(/\.(usdz|usdc|obj|glb|gltf|ply)(?:\?|#|$)/i);
  return m ? m[1].toLowerCase() : 'glb';
}

/**
 * Replicate provider — runs an open-source image→3D model (TripoSR/InstantMesh)
 * on Replicate's pay-per-use GPUs, so "Cloud AI" works with no always-on GPU and
 * only an API token. Set `MESH_PROVIDER=replicate`, `REPLICATE_API_TOKEN`, and
 * `REPLICATE_MODEL_VERSION` (the version hash of an image→3D model that outputs a
 * Model I/O-readable mesh — prefer OBJ/USDZ). These models are image-based, so
 * text→3D is unsupported; multi-view uses the first (front) view.
 */
export class ReplicateMeshProvider implements MeshProvider {
  readonly name = 'replicate';
  constructor(private readonly config: ReplicateMeshConfig) {}

  forgeFromText(): Promise<MeshResult> {
    throw new ProxyError(
      503,
      'not_configured',
      'Text-to-3D is not supported by the Replicate provider; scan a photo or multiple views.',
    );
  }

  forgeFromImage(
    imageBase64: string,
    mime: string,
    _size: ForgeSize,
    options?: PollOptions,
  ): Promise<MeshResult> {
    return this.run(imageBase64, mime, options);
  }

  forgeFromMultiview(
    imagesBase64: string[],
    mime: string,
    _size: ForgeSize,
    options?: PollOptions,
  ): Promise<MeshResult> {
    const first = imagesBase64[0];
    if (!first) {
      throw new ProxyError(400, 'bad_request', 'No views provided.');
    }
    return this.run(first, mime, options);
  }

  private async run(imageBase64: string, mime: string, options?: PollOptions): Promise<MeshResult> {
    const fetchImpl = options?.fetchImpl ?? fetch;
    const sleep = options?.sleep ?? ((ms: number) => new Promise<void>((r) => setTimeout(r, ms)));
    const maxAttempts = options?.maxAttempts ?? 90;
    const intervalMs = options?.pollIntervalMs ?? 2000;
    const base = this.config.baseUrl ?? 'https://api.replicate.com/v1';
    const imageField = this.config.imageField ?? 'image_path';
    const dataUri = `data:${mime};base64,${imageBase64}`;

    let prediction = await this.request(
      `${base}/predictions`,
      {
        method: 'POST',
        headers: {
          authorization: `Token ${this.config.apiToken}`,
          'content-type': 'application/json',
          // Resolve synchronously when the run is fast enough to skip polling.
          prefer: 'wait',
        },
        body: JSON.stringify({
          version: this.config.modelVersion,
          input: { [imageField]: dataUri },
        }),
      },
      fetchImpl,
    );

    let attempt = 0;
    while (prediction.status !== 'succeeded') {
      if (prediction.status === 'failed' || prediction.status === 'canceled') {
        throw new ProxyError(502, 'upstream_error', 'Replicate mesh generation failed.');
      }
      if (attempt >= maxAttempts) {
        throw new ProxyError(504, 'upstream_timeout', 'Replicate mesh generation timed out.');
      }
      await sleep(intervalMs);
      const pollUrl = prediction.urls?.get ?? `${base}/predictions/${prediction.id ?? ''}`;
      prediction = await this.request(
        pollUrl,
        { method: 'GET', headers: { authorization: `Token ${this.config.apiToken}` } },
        fetchImpl,
      );
      attempt++;
    }

    const modelUrl = extractOutputUrl(prediction.output);
    if (modelUrl.length === 0) {
      throw new ProxyError(502, 'upstream_error', 'Replicate returned no model URL.');
    }
    return { modelUrl, format: formatFromUrl(modelUrl) };
  }

  private async request(
    url: string,
    init: RequestInit,
    fetchImpl: typeof fetch,
  ): Promise<ReplicatePrediction> {
    let response: Response;
    try {
      response = await fetchImpl(url, init);
    } catch {
      throw new ProxyError(502, 'upstream_error', 'Replicate mesh generation failed.');
    }
    if (!response.ok) {
      throw new ProxyError(502, 'upstream_error', 'Replicate mesh generation failed.');
    }
    try {
      return (await response.json()) as ReplicatePrediction;
    } catch {
      throw new ProxyError(502, 'upstream_error', 'Replicate mesh generation failed.');
    }
  }
}

type Env = Record<string, string | undefined>;

function requireEnv(env: Env, name: string): string {
  const v = env[name];
  if (!v || v.length === 0) {
    throw new ProxyError(503, 'not_configured', `Missing configuration: ${name}.`);
  }
  return v;
}

/**
 * Build the configured mesh provider from environment. Defaults to Tripo.
 *
 * To add a vendor: implement a `MeshProvider` and add a `case` here that reads
 * its API key. Nothing else in the pipeline changes.
 */
export function createMeshProvider(env: Env = process.env): MeshProvider {
  const name = (env.MESH_PROVIDER ?? 'tripo').trim().toLowerCase();
  switch (name) {
    case 'tripo':
      return new TripoProvider({ apiKey: requireEnv(env, 'TRIPO_API_KEY') });
    case 'selfhosted':
      // Deploy a TripoSR/InstantMesh-compatible endpoint and set
      // MESH_PROVIDER=selfhosted + SELFHOSTED_MESH_URL (+ optional SELFHOSTED_MESH_KEY).
      return new SelfHostedMeshProvider({
        url: requireEnv(env, 'SELFHOSTED_MESH_URL'),
        key: env.SELFHOSTED_MESH_KEY,
      });
    case 'replicate':
      // Pay-per-use open-source image→3D (TripoSR/InstantMesh) with only a token
      // and a model version — no GPU to host. Prefer a version that outputs OBJ/USDZ.
      return new ReplicateMeshProvider({
        apiToken: requireEnv(env, 'REPLICATE_API_TOKEN'),
        modelVersion: requireEnv(env, 'REPLICATE_MODEL_VERSION'),
        imageField: env.REPLICATE_IMAGE_FIELD,
        baseUrl: env.REPLICATE_API_BASE,
      });
    // case 'meshy': return new MeshyProvider({ apiKey: requireEnv(env, 'MESHY_API_KEY') });
    // case 'csm':   return new CSMProvider({ apiKey: requireEnv(env, 'CSM_API_KEY') });
    // case 'rodin': return new RodinProvider({ apiKey: requireEnv(env, 'RODIN_API_KEY') });
    default:
      throw new ProxyError(503, 'not_configured', `Unknown MESH_PROVIDER '${name}'.`);
  }
}
