import { TableClient, type TableEntity } from '@azure/data-tables';
import type { StoredContribution } from './contributionStore.js';
import {
  clusterVotes,
  computeConsensus,
  decodeEmbedding,
  type ConsensusOptions,
  type Vote,
} from './consensus.js';

/**
 * Turns stored crowdsourced contributions into a promoted "correction index":
 * the small, downloadable artifact that lets the app nudge its own scanner
 * toward crowd-verified answers. Each entry is one visual cluster whose shape
 * and/or color cleared consensus promotion, keyed by a representative
 * (centroid) embedding. Pure builder below; Table-backed persistence at bottom.
 *
 * See docs/CROWDSOURCED-SCANNER-ACCURACY-PLAN.md (the "serve it back" slice).
 */

export interface CorrectionIndexEntry {
  clusterId: string; // deterministic (e.g. `${version}-${i}`)
  embeddingBase64: string; // representative = centroid of member embeddings, re-encoded LE Float32 base64
  shapeLabel: string | null; // promoted part number, or null if shape not promoted
  colorLabel: string | null; // promoted color, or null if color not promoted
  members: number;
  shapeConfidence: number;
  colorConfidence: number;
}

export interface CorrectionIndex {
  version: string;
  generatedAt: string;
  entries: CorrectionIndexEntry[];
}

/** Per-user tally of agreements/disagreements earned in one aggregate run. */
export interface ReputationDelta {
  agreed: number;
  disagreed: number;
}

/** Result of a trust-aware aggregate: the index plus per-user reputation deltas. */
export interface AggregateResult {
  index: CorrectionIndex;
  reputationDeltas: Map<string, ReputationDelta>; // per userKey, summed over promoted channels
}

/** Encode number[] as base64 of little-endian Float32 — inverse of `decodeEmbedding`. */
function encodeEmbedding(values: number[]): string {
  const buf = Buffer.alloc(values.length * 4);
  for (let i = 0; i < values.length; i++) buf.writeFloatLE(values[i], i * 4);
  return buf.toString('base64');
}

/** Element-wise mean of a cluster's member embeddings (the representative). */
function centroid(embeddings: number[][]): number[] {
  const dim = embeddings.reduce((m, e) => Math.max(m, e.length), 0);
  const sum = new Array<number>(dim).fill(0);
  for (const e of embeddings) {
    for (let i = 0; i < dim; i++) sum[i] += i < e.length ? e[i] : 0;
  }
  const n = Math.max(1, embeddings.length);
  return sum.map((s) => s / n);
}

/**
 * Cluster + resolve consensus, keeping only clusters where `shape.promoted ||
 * color.promoted`, AND compute per-user reputation deltas earned this run.
 *
 * Entry↔cluster alignment: `computeConsensus` re-clusters internally via
 * `clusterVotes` in input order. We therefore cluster ONCE here with the SAME
 * threshold and SAME vote order, so `clusters[i]` (member votes for the centroid
 * + reputation scoring) lines up exactly with `consensus[i]` (the resolved
 * shape/color). Both are deterministic single-pass, so index `i` refers to the
 * same cluster.
 *
 * Reputation deltas: for each cluster, for each channel that PROMOTED (shape and
 * color independently), the promoted `label` is the settled ground truth. Every
 * member vote's channel label is compared to it — matching → `agreed++`, else
 * `disagreed++`, accumulated per `userKey`. Channels/clusters that did NOT
 * promote have no settled ground truth and contribute nothing. A user may agree
 * on shape yet disagree on color in the same cluster.
 */
export function aggregate(
  contributions: StoredContribution[],
  opts: {
    consensus?: ConsensusOptions;
    version?: string;
    now?: Date;
    weightOf?: (userKey: string) => number;
  } = {},
): AggregateResult {
  const version = opts.version ?? '1';
  const generatedAt = (opts.now ?? new Date()).toISOString();

  const votes: Vote[] = contributions.map((c) => ({
    userKey: c.userKey,
    embedding: decodeEmbedding(c.embeddingBase64),
    shapeLabel: c.userPartNumber,
    colorLabel: c.userColor,
    predictedShape: c.predictedPartNumber,
    predictedColor: c.predictedColor,
  }));

  // Trust weighting is supplied by the caller (persisted reputation). Defaults
  // to uniform weight so pure/self-contained callers behave as before.
  const weightOf = opts.weightOf ?? (() => 1);

  // Pin the same threshold used by both passes so cluster i ↔ consensus i.
  const cosineThreshold = opts.consensus?.cosineThreshold;
  const clusters = clusterVotes(votes, cosineThreshold);
  const consensus = computeConsensus(votes, {
    ...opts.consensus,
    cosineThreshold,
    weightOf,
  });

  const entries: CorrectionIndexEntry[] = [];
  const reputationDeltas = new Map<string, ReputationDelta>();

  const bump = (userKey: string, agreed: boolean): void => {
    let d = reputationDeltas.get(userKey);
    if (!d) {
      d = { agreed: 0, disagreed: 0 };
      reputationDeltas.set(userKey, d);
    }
    if (agreed) d.agreed++;
    else d.disagreed++;
  };

  for (let i = 0; i < consensus.length; i++) {
    const c = consensus[i];
    const members = clusters[i];

    // Earn reputation on each promoted channel against its settled label.
    if (c.shape.promoted && c.shape.label !== null) {
      for (const v of members) bump(v.userKey, v.shapeLabel === c.shape.label);
    }
    if (c.color.promoted && c.color.label !== null) {
      for (const v of members) bump(v.userKey, v.colorLabel === c.color.label);
    }

    if (!c.shape.promoted && !c.color.promoted) continue;
    const rep = centroid(members.map((v) => v.embedding));
    entries.push({
      clusterId: `${version}-${i}`,
      embeddingBase64: encodeEmbedding(rep),
      shapeLabel: c.shape.promoted ? c.shape.label : null,
      colorLabel: c.color.promoted ? c.color.label : null,
      members: c.members,
      shapeConfidence: c.shape.confidence,
      colorConfidence: c.color.confidence,
    });
  }

  return { index: { version, generatedAt, entries }, reputationDeltas };
}

/**
 * Build only the promoted correction index (no reputation deltas). Thin wrapper
 * over `aggregate` so there is a single clustering/consensus path.
 */
export function buildCorrectionIndex(
  contributions: StoredContribution[],
  opts: { consensus?: ConsensusOptions; version?: string; now?: Date } = {},
): CorrectionIndex {
  return aggregate(contributions, opts).index;
}

// --- Persistence ---------------------------------------------------------

const META_TABLE_NAME = 'brickCorrectionIndexMeta';
const ENTRIES_TABLE_NAME = 'brickCorrectionIndex';
const META_PARTITION = 'meta';
const META_ROW = 'current';

interface MetaEntity extends TableEntity {
  Version: string;
  GeneratedAt: string;
  EntryCount: number;
}

interface EntryEntity extends TableEntity {
  EmbeddingBase64: string;
  ShapeLabel: string; // '' encodes null (labels are never empty)
  ColorLabel: string; // '' encodes null
  Members: number;
  ShapeConfidence: number;
  ColorConfidence: number;
}

export interface CorrectionIndexStore {
  currentVersion(): Promise<string>; // "0" when none saved
  save(index: CorrectionIndex): Promise<void>;
  load(): Promise<CorrectionIndex | null>;
}

/**
 * The narrow slice of `TableClient` this store depends on. Declaring it
 * structurally lets tests inject an in-memory fake; the production
 * `TableClient` satisfies it directly.
 */
export interface CorrectionIndexTableClient {
  createTable(): Promise<unknown>;
  upsertEntity(entity: TableEntity, mode?: 'Merge' | 'Replace'): Promise<unknown>;
  getEntity<T extends TableEntity>(partitionKey: string, rowKey: string): Promise<T>;
  listEntities<T extends TableEntity>(options?: unknown): AsyncIterable<T>;
}

function isNotFound(err: unknown): boolean {
  const status = (err as { statusCode?: number; status?: number } | undefined)?.statusCode ??
    (err as { status?: number } | undefined)?.status;
  return status === 404;
}

/** Table-Storage-backed correction-index store for production. */
export class TableCorrectionIndexStore implements CorrectionIndexStore {
  private readonly meta: CorrectionIndexTableClient;
  private readonly entries: CorrectionIndexTableClient;
  private ensured = false;

  /**
   * @param connectionString Azure Storage connection string.
   * @param clients Optional injected clients (test seam). When omitted, real
   *   `TableClient`s are built from `connectionString`.
   */
  constructor(
    connectionString: string,
    clients?: { meta: CorrectionIndexTableClient; entries: CorrectionIndexTableClient },
  ) {
    this.meta =
      clients?.meta ?? TableClient.fromConnectionString(connectionString, META_TABLE_NAME);
    this.entries =
      clients?.entries ?? TableClient.fromConnectionString(connectionString, ENTRIES_TABLE_NAME);
  }

  private async ensureTables(): Promise<void> {
    if (this.ensured) return;
    await this.meta.createTable();
    await this.entries.createTable();
    this.ensured = true;
  }

  async currentVersion(): Promise<string> {
    await this.ensureTables();
    try {
      const meta = await this.meta.getEntity<MetaEntity>(META_PARTITION, META_ROW);
      return String(meta.Version);
    } catch (err) {
      if (isNotFound(err)) return '0';
      throw err;
    }
  }

  async save(index: CorrectionIndex): Promise<void> {
    await this.ensureTables();
    // Write exactly the version passed in — the caller decides the next version.
    for (const entry of index.entries) {
      const entity: EntryEntity = {
        partitionKey: index.version,
        rowKey: entry.clusterId,
        EmbeddingBase64: entry.embeddingBase64,
        ShapeLabel: entry.shapeLabel ?? '',
        ColorLabel: entry.colorLabel ?? '',
        Members: entry.members,
        ShapeConfidence: entry.shapeConfidence,
        ColorConfidence: entry.colorConfidence,
      };
      await this.entries.upsertEntity(entity, 'Replace');
    }
    const meta: MetaEntity = {
      partitionKey: META_PARTITION,
      rowKey: META_ROW,
      Version: index.version,
      GeneratedAt: index.generatedAt,
      EntryCount: index.entries.length,
    };
    await this.meta.upsertEntity(meta, 'Replace');
  }

  async load(): Promise<CorrectionIndex | null> {
    await this.ensureTables();
    let meta: MetaEntity;
    try {
      meta = await this.meta.getEntity<MetaEntity>(META_PARTITION, META_ROW);
    } catch (err) {
      if (isNotFound(err)) return null;
      throw err;
    }
    const version = String(meta.Version);
    const entries: CorrectionIndexEntry[] = [];
    const options = { queryOptions: { filter: `PartitionKey eq '${version}'` } };
    for await (const e of this.entries.listEntities<EntryEntity>(options)) {
      if (String(e.partitionKey) !== version) continue;
      entries.push({
        clusterId: String(e.rowKey),
        embeddingBase64: String(e.EmbeddingBase64),
        shapeLabel: e.ShapeLabel ? String(e.ShapeLabel) : null,
        colorLabel: e.ColorLabel ? String(e.ColorLabel) : null,
        members: Number(e.Members),
        shapeConfidence: Number(e.ShapeConfidence),
        colorConfidence: Number(e.ColorConfidence),
      });
    }
    return { version, generatedAt: String(meta.GeneratedAt), entries };
  }
}
