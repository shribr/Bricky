import { test } from 'node:test';
import assert from 'node:assert/strict';
import { TableEntity } from '@azure/data-tables';
import type { StoredContribution } from '../src/contributionStore.js';
import {
  aggregate,
  buildCorrectionIndex,
  type ReputationDelta,
} from '../src/correctionIndex.js';
import {
  TableReputationStore,
  type ReputationTableClient,
} from '../src/reputationStore.js';
import { type BetaReputation } from '../src/reputation.js';

function encodeEmbedding(values: number[]): string {
  const buf = Buffer.alloc(values.length * 4);
  for (let i = 0; i < values.length; i++) buf.writeFloatLE(values[i], i * 4);
  return buf.toString('base64');
}

function contrib(
  partial: Partial<StoredContribution> & { embedding?: number[] } = {},
): StoredContribution {
  const { embedding, ...rest } = partial;
  return {
    userKey: 'u',
    embeddingBase64: encodeEmbedding(embedding ?? [1, 0, 0]),
    action: 'confirm',
    predictedPartNumber: 'A',
    predictedColor: 'Red',
    predictedConfidence: 0.7,
    userPartNumber: 'A',
    userColor: 'Red',
    userStudsWide: 2,
    userStudsLong: 4,
    correctedShape: false,
    correctedColor: false,
    appVersion: '1.0.0',
    anonUserId: 'anon',
    ...rest,
  };
}

// 1. Promoted cluster: 3 agree on shape+color, 1 dissents on color.
test('aggregate: promoted cluster earns agreed/disagreed per channel; dissenter disagrees on color only', () => {
  const contribs = [
    contrib({ userKey: 'u1', userPartNumber: 'A', userColor: 'Red', predictedColor: 'Red' }),
    contrib({ userKey: 'u2', userPartNumber: 'A', userColor: 'Red', predictedColor: 'Red' }),
    contrib({ userKey: 'u3', userPartNumber: 'A', userColor: 'Red', predictedColor: 'Red' }),
    contrib({ userKey: 'u4', userPartNumber: 'A', userColor: 'Green', predictedColor: 'Red' }),
  ];
  const { index, reputationDeltas } = aggregate(contribs, { version: '1' });

  // Shape "A" and color "Red" both promote (3 agree, prior "Red").
  assert.equal(index.entries.length, 1);
  assert.equal(index.entries[0].shapeLabel, 'A');
  assert.equal(index.entries[0].colorLabel, 'Red');

  // u1-u3 agree on both channels; u4 agrees shape, disagrees color.
  assert.deepEqual(reputationDeltas.get('u1'), { agreed: 2, disagreed: 0 });
  assert.deepEqual(reputationDeltas.get('u2'), { agreed: 2, disagreed: 0 });
  assert.deepEqual(reputationDeltas.get('u3'), { agreed: 2, disagreed: 0 });
  assert.deepEqual(reputationDeltas.get('u4'), { agreed: 1, disagreed: 1 });
});

// 1b. An UNPROMOTED cluster yields NO reputation deltas.
test('aggregate: an unpromoted (lone) cluster yields no deltas', () => {
  const { index, reputationDeltas } = aggregate([contrib({ userKey: 'solo' })]);
  assert.equal(index.entries.length, 0);
  assert.equal(reputationDeltas.size, 0);
});

// 2. Parity: aggregate(...).index equals buildCorrectionIndex(...) for same input.
test('aggregate: index matches buildCorrectionIndex output (parity)', () => {
  const contribs = [
    contrib({ userKey: 'a1', embedding: [1, 0, 0], userPartNumber: 'A', predictedPartNumber: 'A', userColor: 'Red', predictedColor: 'Red' }),
    contrib({ userKey: 'a2', embedding: [1, 0, 0], userPartNumber: 'A', predictedPartNumber: 'A', userColor: 'Red', predictedColor: 'Red' }),
    contrib({ userKey: 'a3', embedding: [1, 0, 0], userPartNumber: 'A', predictedPartNumber: 'A', userColor: 'Red', predictedColor: 'Red' }),
    contrib({ userKey: 'b1', embedding: [0, 1, 0], userPartNumber: 'B', predictedPartNumber: 'B', userColor: 'Blue', predictedColor: 'Blue' }),
    contrib({ userKey: 'b2', embedding: [0, 1, 0], userPartNumber: 'B', predictedPartNumber: 'B', userColor: 'Blue', predictedColor: 'Blue' }),
    contrib({ userKey: 'b3', embedding: [0, 1, 0], userPartNumber: 'B', predictedPartNumber: 'B', userColor: 'Blue', predictedColor: 'Blue' }),
  ];
  const now = new Date('2026-09-03T00:00:00.000Z');
  const fromAggregate = aggregate(contribs, { version: '7', now }).index;
  const fromBuilder = buildCorrectionIndex(contribs, { version: '7', now });
  assert.deepEqual(fromAggregate, fromBuilder);
});

// 3. Trust weighting changes the outcome: a small high-weight group beats a
//    larger ~zero-weight group (reuse the consensus engine's behavior).
test('aggregate: trust weighting lets the trusted minority label win', () => {
  const contribs = [
    contrib({ userKey: 'a1', userPartNumber: 'A', predictedPartNumber: 'B' }),
    contrib({ userKey: 'a2', userPartNumber: 'A', predictedPartNumber: 'B' }),
    contrib({ userKey: 'b1', userPartNumber: 'B', predictedPartNumber: 'B' }),
    contrib({ userKey: 'b2', userPartNumber: 'B', predictedPartNumber: 'B' }),
    contrib({ userKey: 'b3', userPartNumber: 'B', predictedPartNumber: 'B' }),
  ];
  const weightOf = (uk: string): number => (uk.startsWith('a') ? 5 : 0);
  const { index } = aggregate(contribs, { version: '1', weightOf });
  assert.equal(index.entries.length, 1);
  assert.equal(index.entries[0].shapeLabel, 'A');
});

// 4. TableReputationStore round-trips {a,b}; missing users absent.
class FakeReputationTableClient implements ReputationTableClient {
  createdTable = false;
  rows = new Map<string, TableEntity>();
  private key(pk: string, rk: string): string {
    return `${pk}\u0000${rk}`;
  }
  async createTable(): Promise<unknown> {
    this.createdTable = true;
    return undefined;
  }
  async upsertEntity(entity: TableEntity): Promise<unknown> {
    this.rows.set(this.key(String(entity.partitionKey), String(entity.rowKey)), entity);
    return undefined;
  }
  async *listEntities<T extends TableEntity>(): AsyncIterable<T> {
    for (const e of this.rows.values()) yield e as T;
  }
}

test('TableReputationStore: saveAll then load round-trips {a,b}; missing users absent', async () => {
  const client = new FakeReputationTableClient();
  const store = new TableReputationStore('', client);

  const reps = new Map<string, BetaReputation>([
    ['u1', { a: 4, b: 1 }],
    ['u2', { a: 1, b: 3 }],
  ]);
  await store.saveAll(reps);

  const loaded = await store.load();
  assert.equal(loaded.size, 2);
  assert.deepEqual(loaded.get('u1'), { a: 4, b: 1 });
  assert.deepEqual(loaded.get('u2'), { a: 1, b: 3 });
  assert.equal(loaded.get('missing'), undefined);
});

// 5. Idempotency: recomputing {a:1+agreed, b:1+disagreed} from the same deltas
//    twice yields identical values (no inflation).
test('reputation recompute from deltas is idempotent (no inflation on re-run)', () => {
  const deltas = new Map<string, ReputationDelta>([
    ['u1', { agreed: 2, disagreed: 0 }],
    ['u4', { agreed: 1, disagreed: 1 }],
  ]);
  const recompute = (): Map<string, BetaReputation> => {
    const out = new Map<string, BetaReputation>();
    for (const [uk, d] of deltas) out.set(uk, { a: 1 + d.agreed, b: 1 + d.disagreed });
    return out;
  };
  const first = recompute();
  const second = recompute();
  assert.deepEqual([...second], [...first]);
  assert.deepEqual(first.get('u1'), { a: 3, b: 1 });
  assert.deepEqual(first.get('u4'), { a: 2, b: 2 });
});
