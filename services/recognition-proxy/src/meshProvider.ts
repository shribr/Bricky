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
    // case 'meshy': return new MeshyProvider({ apiKey: requireEnv(env, 'MESHY_API_KEY') });
    // case 'csm':   return new CSMProvider({ apiKey: requireEnv(env, 'CSM_API_KEY') });
    // case 'rodin': return new RodinProvider({ apiKey: requireEnv(env, 'RODIN_API_KEY') });
    default:
      throw new ProxyError(503, 'not_configured', `Unknown MESH_PROVIDER '${name}'.`);
  }
}
