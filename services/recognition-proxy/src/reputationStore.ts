import { TableClient, type TableEntity } from '@azure/data-tables';
import { type BetaReputation } from './reputation.js';

/**
 * Persists per-user Beta reputation (`{a, b}`) in Azure Table Storage — the same
 * cheap, minimal "database" the other stores use. The consensus batch job loads
 * these to trust-weight votes and writes them back after each run so reputation
 * is EARNED against settled consensus. All users share a single partition
 * (`rep`); RowKey is the opaque `userKey`. Missing users are simply absent from
 * the returned map (callers fall back to `REPUTATION_PRIOR`).
 *
 * See docs/CROWDSOURCED-SCANNER-ACCURACY-PLAN.md §4.
 */

const TABLE_NAME = 'brickReputation';
const PARTITION = 'rep';

interface ReputationEntity extends TableEntity {
  A: number;
  B: number;
}

export interface ReputationStore {
  /** userKey -> {a,b}; missing users simply absent. */
  load(): Promise<Map<string, BetaReputation>>;
  /** Upsert each entry. */
  saveAll(reps: Map<string, BetaReputation>): Promise<void>;
}

/**
 * The narrow slice of `TableClient` this store depends on. Declaring it
 * structurally lets tests inject an in-memory fake; the production
 * `TableClient` satisfies it directly.
 */
export interface ReputationTableClient {
  createTable(): Promise<unknown>;
  upsertEntity(entity: TableEntity, mode?: 'Merge' | 'Replace'): Promise<unknown>;
  listEntities<T extends TableEntity>(options?: unknown): AsyncIterable<T>;
}

/** Table-Storage-backed reputation store for production. */
export class TableReputationStore implements ReputationStore {
  private readonly client: ReputationTableClient;
  private ensured = false;

  /**
   * @param connectionString Azure Storage connection string.
   * @param client Optional injected client (test seam). When omitted a real
   *   `TableClient` is built from `connectionString`.
   */
  constructor(connectionString: string, client?: ReputationTableClient) {
    this.client =
      client ?? TableClient.fromConnectionString(connectionString, TABLE_NAME);
  }

  private async ensureTable(): Promise<void> {
    if (this.ensured) return;
    await this.client.createTable();
    this.ensured = true;
  }

  async load(): Promise<Map<string, BetaReputation>> {
    await this.ensureTable();
    const out = new Map<string, BetaReputation>();
    const options = { queryOptions: { filter: `PartitionKey eq '${PARTITION}'` } };
    for await (const e of this.client.listEntities<ReputationEntity>(options)) {
      if (String(e.partitionKey) !== PARTITION) continue;
      out.set(String(e.rowKey), { a: Number(e.A), b: Number(e.B) });
    }
    return out;
  }

  async saveAll(reps: Map<string, BetaReputation>): Promise<void> {
    await this.ensureTable();
    for (const [userKey, rep] of reps) {
      const entity: ReputationEntity = {
        partitionKey: PARTITION,
        rowKey: userKey,
        A: rep.a,
        B: rep.b,
      };
      await this.client.upsertEntity(entity, 'Replace');
    }
  }
}
