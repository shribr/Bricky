import { TableClient, type TableEntity } from '@azure/data-tables';
import { ProxyError } from './types.js';
import type { Honeypot, HoneypotResult } from './honeypot.js';

/**
 * Table-Storage-backed stores for honeypots and their answers — mirroring the
 * `contributionStore` pattern (cheap, minimal "database"; injectable structural
 * table-client seam for tests).
 *
 * IMPORTANT: no fake honeypots are ever seeded here. The honeypot table ships
 * EMPTY; real known-answer items are inserted operationally from authoritative
 * data (catalog/expert) via `saveAll`.
 */

const HONEYPOT_TABLE = 'brickHoneypots';
const HONEYPOT_PARTITION = 'hp';
const RESULT_TABLE = 'brickHoneypotResults';

const MAX_LABEL_CHARS = 64;
const MAX_ID_CHARS = 64;

interface HoneypotEntity extends TableEntity {
  PartNumber: string;
  Color: string;
  ImageRef: string;
  Source: string;
}

interface HoneypotResultEntity extends TableEntity {
  HoneypotId: string;
  UserKey: string;
  UserPartNumber: string;
  UserColor: string;
}

export interface HoneypotStore {
  list(): Promise<Honeypot[]>;
  saveAll(items: Honeypot[]): Promise<void>;
}

export interface HoneypotResultStore {
  save(result: HoneypotResult): Promise<void>;
  /** Read back recent answers for batch aggregation. */
  listRecent(limit?: number): Promise<HoneypotResult[]>;
}

/**
 * The narrow slice of `TableClient` these stores depend on. Declaring it
 * structurally lets tests inject an in-memory fake without any real Azure
 * connectivity. The production `TableClient` satisfies it directly.
 */
export interface HoneypotTableClient {
  createTable(): Promise<unknown>;
  createEntity(entity: TableEntity): Promise<unknown>;
  upsertEntity(entity: TableEntity, mode?: 'Merge' | 'Replace'): Promise<unknown>;
  listEntities?<T extends TableEntity>(options?: unknown): AsyncIterable<T>;
}

function dayMarker(now = new Date()): string {
  return now.toISOString().slice(0, 10);
}

/** Table-Storage-backed honeypot store for production. */
export class TableHoneypotStore implements HoneypotStore {
  private readonly client: HoneypotTableClient;
  private ensured = false;

  /**
   * @param connectionString Azure Storage connection string.
   * @param client Optional injected client (test seam). When omitted a real
   *   `TableClient` is built from `connectionString`.
   */
  constructor(connectionString: string, client?: HoneypotTableClient) {
    this.client =
      client ?? TableClient.fromConnectionString(connectionString, HONEYPOT_TABLE);
  }

  private async ensureTable(): Promise<void> {
    if (this.ensured) return;
    await this.client.createTable();
    this.ensured = true;
  }

  async list(): Promise<Honeypot[]> {
    await this.ensureTable();
    const out: Honeypot[] = [];
    if (!this.client.listEntities) return out;
    const options = { queryOptions: { filter: `PartitionKey eq '${HONEYPOT_PARTITION}'` } };
    for await (const e of this.client.listEntities<HoneypotEntity>(options)) {
      if (String(e.partitionKey) !== HONEYPOT_PARTITION) continue;
      out.push({
        id: String(e.rowKey),
        partNumber: String(e.PartNumber),
        color: String(e.Color),
        imageRef: String(e.ImageRef),
        source: String(e.Source),
      });
    }
    return out;
  }

  async saveAll(items: Honeypot[]): Promise<void> {
    await this.ensureTable();
    for (const h of items) {
      const entity: HoneypotEntity = {
        partitionKey: HONEYPOT_PARTITION,
        rowKey: h.id,
        PartNumber: h.partNumber,
        Color: h.color,
        ImageRef: h.imageRef,
        Source: h.source,
      };
      await this.client.upsertEntity(entity, 'Replace');
    }
  }
}

/** Table-Storage-backed honeypot-result store for production. */
export class TableHoneypotResultStore implements HoneypotResultStore {
  private readonly client: HoneypotTableClient;
  private ensured = false;

  constructor(connectionString: string, client?: HoneypotTableClient) {
    this.client =
      client ?? TableClient.fromConnectionString(connectionString, RESULT_TABLE);
  }

  private async ensureTable(): Promise<void> {
    if (this.ensured) return;
    await this.client.createTable();
    this.ensured = true;
  }

  async save(result: HoneypotResult): Promise<void> {
    await this.ensureTable();
    const now = new Date();
    const rowKey = `${now.getTime()}-${Math.random().toString(36).slice(2, 8)}`;
    const entity: HoneypotResultEntity = {
      partitionKey: dayMarker(now),
      rowKey,
      HoneypotId: result.honeypotId,
      UserKey: result.userKey,
      UserPartNumber: result.userPartNumber,
      UserColor: result.userColor,
    };
    await this.client.createEntity(entity);
  }

  async listRecent(limit = 5000): Promise<HoneypotResult[]> {
    await this.ensureTable();
    const out: HoneypotResult[] = [];
    if (!this.client.listEntities) return out;
    for await (const e of this.client.listEntities<HoneypotResultEntity>()) {
      out.push({
        honeypotId: String(e.HoneypotId),
        userKey: String(e.UserKey),
        userPartNumber: String(e.UserPartNumber),
        userColor: String(e.UserColor),
      });
      if (out.length >= limit) break;
    }
    return out;
  }
}

function requireString(value: unknown, field: string, maxLen: number): string {
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

/**
 * Validate + normalize an incoming answer into a `HoneypotResult` (minus
 * `userKey`, which the handler sets from the verified entitlement). Throws
 * `ProxyError(400)` on invalid input.
 */
export function validateHoneypotResult(body: unknown): Omit<HoneypotResult, 'userKey'> {
  if (!body || typeof body !== 'object') {
    throw new ProxyError(400, 'bad_request', 'Missing answer.');
  }
  const raw = body as Record<string, unknown>;
  const honeypotId = requireString(raw.honeypotId, 'honeypotId', MAX_ID_CHARS);
  const userPartNumber = requireString(raw.userPartNumber, 'userPartNumber', MAX_LABEL_CHARS);
  const userColor = requireString(raw.userColor, 'userColor', MAX_LABEL_CHARS);
  return { honeypotId, userPartNumber, userColor };
}
