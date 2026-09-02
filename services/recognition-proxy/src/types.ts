/**
 * Shared types mirroring the iOS `RecognitionResult` / `RecognizedSubject`
 * Codable contract. The proxy is the source of truth for this shape.
 */

export type SubjectCategory =
  | 'person'
  | 'character'
  | 'landmark'
  | 'place'
  | 'musician'
  | 'artwork'
  | 'animal'
  | 'object'
  | 'unknown';

export const SUBJECT_CATEGORIES: readonly SubjectCategory[] = [
  'person',
  'character',
  'landmark',
  'place',
  'musician',
  'artwork',
  'animal',
  'object',
  'unknown',
];

export interface RecognizedSubject {
  name: string;
  category: SubjectCategory;
  /** Clamped 0...1. */
  confidence: number;
  summary: string;
  location?: string;
}

export interface RecognitionResult {
  subjects: RecognizedSubject[];
  remainingQuota: number;
}

export interface RecognitionRequest {
  imageBase64: string;
  entitlementToken: string;
}

/**
 * One LEGO set proposed by the vision model for a scanned built model. The iOS
 * app grounds each proposal against its bundled set catalog before display.
 */
export interface IdentifiedSet {
  /** Official set number, e.g. "75192". */
  setNumber: string;
  name: string;
  theme?: string;
  year?: number;
  /** Clamped 0...1. */
  confidence: number;
  summary: string;
}

export interface SetIdentificationResult {
  candidates: IdentifiedSet[];
  remainingQuota: number;
}

export interface SetIdentificationRequest {
  imageBase64: string;
  entitlementToken: string;
}

/** A support inquiry submitted from the marketing site contact form. */
export interface SupportInquiry {
  email: string;
  message: string;
  /** Optional subject/topic; defaults handled server-side. */
  topic?: string;
  /** Honeypot field — must be empty; bots tend to fill it. */
  website?: string;
}

export type ErrorCode =
  | 'bad_request'
  | 'not_entitled'
  | 'quota_exceeded'
  | 'upstream_error'
  | 'upstream_timeout'
  | 'not_configured'
  | 'not_found'
  | 'rate_limited';

export interface ErrorBody {
  error: string;
  code: ErrorCode;
}

/** Thrown by handlers to short-circuit with an HTTP status + machine code. */
export class ProxyError extends Error {
  constructor(
    public readonly status: number,
    public readonly code: ErrorCode,
    message: string,
  ) {
    super(message);
    this.name = 'ProxyError';
  }
}

// ---------------------------------------------------------------------------
// Set Forge — text → voxel model (Phase 2)
// ---------------------------------------------------------------------------

export type ForgeSize = 'small' | 'medium' | 'large';

export const FORGE_SIZES: readonly ForgeSize[] = ['small', 'medium', 'large'];

/**
 * The LEGO colour names the model may use. These MUST match the iOS `LegoColor`
 * raw values exactly so the client can decode each voxel colour directly.
 */
export const FORGE_COLORS: readonly string[] = [
  'Red', 'Blue', 'Yellow', 'Green', 'Black', 'White', 'Gray', 'Dark Gray',
  'Orange', 'Brown', 'Tan', 'Dark Blue', 'Dark Green', 'Dark Red', 'Lime',
  'Purple', 'Pink', 'Light Blue',
];

export interface ForgeTextRequest {
  prompt: string;
  size: ForgeSize;
  entitlementToken: string;
}

/** One occupied cell in the generated voxel model. */
export interface ForgeVoxel {
  x: number;
  y: number;
  z: number;
  /** A value from `FORGE_COLORS`. */
  color: string;
}

/** The expanded voxel model returned to the iOS client. */
export interface ForgeModelResult {
  width: number;
  height: number;
  depth: number;
  voxels: ForgeVoxel[];
  subject: string;
  remainingQuota: number;
}

// ---------------------------------------------------------------------------
// Set Forge — text → 3D mesh via hosted vendor (Tripo). Higher fidelity than
// the GPT voxel DSL; returns a downloadable model the iOS client voxelizes.
// ---------------------------------------------------------------------------

export interface ForgeMeshRequest {
  prompt: string;
  size: ForgeSize;
  entitlementToken: string;
}

export interface ForgeMeshResult {
  /** Direct URL to the generated 3D model. */
  modelUrl: string;
  /** Lowercased file extension, e.g. "glb", "usdz", "fbx". */
  format: string;
  remainingQuota: number;
}

export interface ForgeMeshImageRequest {
  imageBase64: string;
  /** MIME type of the image, e.g. "image/jpeg". */
  mime: string;
  size: ForgeSize;
  entitlementToken: string;
}

export interface ForgeMeshMultiviewRequest {
  /** Up to 4 base64 images in [front, left, back, right] order. */
  imagesBase64: string[];
  mime: string;
  size: ForgeSize;
  entitlementToken: string;
}


