import { TableClient, type TableEntity } from '@azure/data-tables';
import { ProxyError } from './types.js';

/**
 * Persists crowdsourced brick corrections/confirmations ("Observations") into
 * Azure Table Storage — the same cheap, minimal "database" the support store
 * uses. A later batch job reads these to build crowd consensus that improves
 * scanner accuracy. PartitionKey is the UTC day (`YYYY-MM-DD`) so observations
 * are naturally bucketed by date; RowKey is a timestamp-sortable unique id.
 *
 * The `entitlementToken` on an incoming payload is used ONLY for auth in the
 * handler — it is never persisted here.
 */

const TABLE_NAME = 'brickContributions';

export interface ContributionObservation {
  embeddingBase64: string;      // Vision feature-print bytes, base64
  action: 'confirm' | 'correct';
  predictedPartNumber: string;
  predictedColor: string;
  predictedConfidence: number;  // 0..1
  userPartNumber: string;
  userColor: string;
  userStudsWide: number;
  userStudsLong: number;
  correctedShape: boolean;
  correctedColor: boolean;
  appVersion: string;
  anonUserId: string;
  entitlementToken?: string;    // used for auth, NOT stored
}

interface ContributionEntity extends TableEntity {
  UserKey: string;
  Action: string;
  PredictedPartNumber: string;
  PredictedColor: string;
  PredictedConfidence: number;
  UserPartNumber: string;
  UserColor: string;
  UserStudsWide: number;
  UserStudsLong: number;
  CorrectedShape: boolean;
  CorrectedColor: boolean;
  AppVersion: string;
  AnonUserId: string;
  EmbeddingBase64: string;
}

/** A persisted contribution, carrying the `userKey` recorded at save time. */
export interface StoredContribution extends ContributionObservation {
  userKey: string;
}

export interface ContributionStore {
  save(userKey: string, obs: ContributionObservation): Promise<void>;
  /** Read back recent contributions for batch aggregation (newest-ish first). */
  listRecent(limit?: number): Promise<StoredContribution[]>;
}

/**
 * The narrow slice of `TableClient` this store depends on. Declaring it as a
 * structural interface lets tests inject an in-memory fake without any real
 * Azure connectivity. The production `TableClient` satisfies it directly.
 * `listEntities` is optional so the save-only fakes in existing tests keep
 * type-checking; the production `TableClient` provides it.
 */
export interface ContributionTableClient {
  createTable(): Promise<unknown>;
  createEntity(entity: TableEntity): Promise<unknown>;
  listEntities?<T extends TableEntity>(): AsyncIterable<T>;
}

function dayMarker(now = new Date()): string {
  return now.toISOString().slice(0, 10);
}

/** Table-Storage-backed contribution store for production. */
export class TableContributionStore implements ContributionStore {
  private readonly client: ContributionTableClient;
  private ensured = false;

  /**
   * @param connectionString Azure Storage connection string.
   * @param client Optional injected client (test seam). When omitted a real
   *   `TableClient` is built from `connectionString`.
   */
  constructor(connectionString: string, client?: ContributionTableClient) {
    this.client =
      client ?? TableClient.fromConnectionString(connectionString, TABLE_NAME);
  }

  private async ensureTable(): Promise<void> {
    if (this.ensured) return;
    await this.client.createTable();
    this.ensured = true;
  }

  async save(userKey: string, obs: ContributionObservation): Promise<void> {
    await this.ensureTable();
    const now = new Date();
    const rowKey = `${now.getTime()}-${Math.random().toString(36).slice(2, 8)}`;
    // Note: entitlementToken is intentionally NOT written — it is auth-only.
    const entity: ContributionEntity = {
      partitionKey: dayMarker(now),
      rowKey,
      UserKey: userKey,
      Action: obs.action,
      PredictedPartNumber: obs.predictedPartNumber,
      PredictedColor: obs.predictedColor,
      PredictedConfidence: obs.predictedConfidence,
      UserPartNumber: obs.userPartNumber,
      UserColor: obs.userColor,
      UserStudsWide: obs.userStudsWide,
      UserStudsLong: obs.userStudsLong,
      CorrectedShape: obs.correctedShape,
      CorrectedColor: obs.correctedColor,
      AppVersion: obs.appVersion,
      AnonUserId: obs.anonUserId,
      EmbeddingBase64: obs.embeddingBase64,
    };
    await this.client.createEntity(entity);
  }

  async listRecent(limit = 5000): Promise<StoredContribution[]> {
    await this.ensureTable();
    const out: StoredContribution[] = [];
    if (!this.client.listEntities) return out;
    for await (const e of this.client.listEntities<ContributionEntity>()) {
      out.push({
        userKey: String(e.UserKey),
        action: e.Action === 'confirm' ? 'confirm' : 'correct',
        predictedPartNumber: String(e.PredictedPartNumber),
        predictedColor: String(e.PredictedColor),
        predictedConfidence: Number(e.PredictedConfidence),
        userPartNumber: String(e.UserPartNumber),
        userColor: String(e.UserColor),
        userStudsWide: Number(e.UserStudsWide),
        userStudsLong: Number(e.UserStudsLong),
        correctedShape: Boolean(e.CorrectedShape),
        correctedColor: Boolean(e.CorrectedColor),
        appVersion: String(e.AppVersion),
        anonUserId: String(e.AnonUserId),
        embeddingBase64: String(e.EmbeddingBase64),
      });
      if (out.length >= limit) break;
    }
    return out;
  }
}

const MAX_EMBEDDING_CHARS = 200_000;
const MAX_LABEL_CHARS = 64;
const MAX_APP_VERSION_CHARS = 32;
const MAX_ANON_USER_ID_CHARS = 64;

function requireString(
  value: unknown,
  field: string,
  maxLen: number,
): string {
  if (typeof value !== 'string') {
    throw new ProxyError(400, 'bad_request', `Missing or invalid ${field}.`);
  }
  const trimmed = value.trim();
  if (trimmed.length === 0) {
    throw new ProxyError(400, 'bad_request', `Missing or invalid ${field}.`);
  }
  if (trimmed.length > maxLen) {
    throw new ProxyError(400, 'bad_request', `${field} is too long.`);
  }
  return trimmed;
}

function requireIntInRange(
  value: unknown,
  field: string,
  min: number,
  max: number,
): number {
  const n = typeof value === 'number' ? value : Number(value);
  if (!Number.isFinite(n) || !Number.isInteger(n) || n < min || n > max) {
    throw new ProxyError(
      400,
      'bad_request',
      `${field} must be an integer in ${min}..${max}.`,
    );
  }
  return n;
}

/** Validate + normalize an incoming payload; throws ProxyError(400) on invalid. */
export function validateObservation(body: unknown): ContributionObservation {
  if (!body || typeof body !== 'object') {
    throw new ProxyError(400, 'bad_request', 'Missing observation.');
  }
  const raw = body as Record<string, unknown>;

  const embeddingBase64 = requireString(
    raw.embeddingBase64,
    'embeddingBase64',
    MAX_EMBEDDING_CHARS,
  );

  if (raw.action !== 'confirm' && raw.action !== 'correct') {
    throw new ProxyError(400, 'bad_request', "action must be 'confirm' or 'correct'.");
  }
  const action = raw.action;

  const predictedPartNumber = requireString(
    raw.predictedPartNumber,
    'predictedPartNumber',
    MAX_LABEL_CHARS,
  );
  const predictedColor = requireString(raw.predictedColor, 'predictedColor', MAX_LABEL_CHARS);
  const userPartNumber = requireString(raw.userPartNumber, 'userPartNumber', MAX_LABEL_CHARS);
  const userColor = requireString(raw.userColor, 'userColor', MAX_LABEL_CHARS);
  const appVersion = requireString(raw.appVersion, 'appVersion', MAX_APP_VERSION_CHARS);
  const anonUserId = requireString(raw.anonUserId, 'anonUserId', MAX_ANON_USER_ID_CHARS);

  const rawConfidence =
    typeof raw.predictedConfidence === 'number'
      ? raw.predictedConfidence
      : Number(raw.predictedConfidence);
  if (!Number.isFinite(rawConfidence)) {
    throw new ProxyError(400, 'bad_request', 'predictedConfidence must be a finite number.');
  }
  const predictedConfidence = Math.min(1, Math.max(0, rawConfidence));

  const userStudsWide = requireIntInRange(raw.userStudsWide, 'userStudsWide', 1, 64);
  const userStudsLong = requireIntInRange(raw.userStudsLong, 'userStudsLong', 1, 64);

  return {
    embeddingBase64,
    action,
    predictedPartNumber,
    predictedColor,
    predictedConfidence,
    userPartNumber,
    userColor,
    userStudsWide,
    userStudsLong,
    correctedShape: Boolean(raw.correctedShape),
    correctedColor: Boolean(raw.correctedColor),
    appVersion,
    anonUserId,
  };
}
