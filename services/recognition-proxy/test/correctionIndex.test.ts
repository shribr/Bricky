import { test } from 'node:test';
import assert from 'node:assert/strict';
import { TableEntity } from '@azure/data-tables';
import { decodeEmbedding } from '../src/consensus.js';
import type { StoredContribution } from '../src/contributionStore.js';
import {
  buildCorrectionIndex,
  TableCorrectionIndexStore,
  type CorrectionIndex,
  type CorrectionIndexTableClient,
} from '../src/correctionIndex.js';

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

// 1. A cluster of agreeing weight-1 votes above quorum yields one entry.
test('buildCorrectionIndex: agreeing cluster promotes one entry with expected labels', () => {
  const contribs = [
    contrib({ userKey: 'u1', userPartNumber: 'A', userColor: 'Red', predictedPartNumber: 'A', predictedColor: 'Red' }),
    contrib({ userKey: 'u2', userPartNumber: 'A', userColor: 'Red', predictedPartNumber: 'A', predictedColor: 'Red' }),
    contrib({ userKey: 'u3', userPartNumber: 'A', userColor: 'Red', predictedPartNumber: 'A', predictedColor: 'Red' }),
  ];
  const index = buildCorrectionIndex(contribs, { version: '5' });
  assert.equal(index.version, '5');
  assert.equal(index.entries.length, 1);
  const e = index.entries[0];
  assert.equal(e.shapeLabel, 'A');
  assert.equal(e.colorLabel, 'Red');
  assert.equal(e.members, 3);
  assert.equal(e.clusterId, '5-0');
  assert.ok(e.shapeConfidence >= 0 && e.shapeConfidence <= 1);
  assert.ok(e.colorConfidence >= 0 && e.colorConfidence <= 1);
});

// 2. Unpromoted clusters are excluded (lone vote never clears quorum).
test('buildCorrectionIndex: a lone vote produces no entry', () => {
  const index = buildCorrectionIndex([contrib({ userKey: 'solo' })]);
  assert.equal(index.entries.length, 0);
});

// 3. Separate channels: agree on shape, split on color → colorLabel is null.
test('buildCorrectionIndex: shape promoted, split color stays null', () => {
  const contribs = [
    contrib({ userKey: 'u1', userColor: 'Red', predictedColor: 'Green' }),
    contrib({ userKey: 'u2', userColor: 'Red', predictedColor: 'Green' }),
    contrib({ userKey: 'u3', userColor: 'Blue', predictedColor: 'Green' }),
    contrib({ userKey: 'u4', userColor: 'Blue', predictedColor: 'Green' }),
  ];
  const index = buildCorrectionIndex(contribs);
  assert.equal(index.entries.length, 1);
  const e = index.entries[0];
  assert.equal(e.shapeLabel, 'A');
  assert.equal(e.colorLabel, null);
});

// 4. Centroid: emitted embedding decodes to the element-wise mean of members.
test('buildCorrectionIndex: representative embedding is the member centroid', () => {
  const contribs = [
    contrib({ userKey: 'u1', embedding: [2, 0, 0] }),
    contrib({ userKey: 'u2', embedding: [4, 0, 0] }),
    contrib({ userKey: 'u3', embedding: [6, 0, 0] }),
  ];
  const index = buildCorrectionIndex(contribs);
  assert.equal(index.entries.length, 1);
  const decoded = decodeEmbedding(index.entries[0].embeddingBase64);
  assert.equal(decoded.length, 3);
  assert.ok(Math.abs(decoded[0] - 4) < 1e-4);
  assert.ok(Math.abs(decoded[1] - 0) < 1e-4);
  assert.ok(Math.abs(decoded[2] - 0) < 1e-4);
});

// 5. Entry↔cluster alignment: two far clusters → two entries, correct per-cluster labels.
test('buildCorrectionIndex: two distinct clusters align to two labelled entries', () => {
  const contribs = [
    contrib({ userKey: 'a1', embedding: [1, 0, 0], userPartNumber: 'A', predictedPartNumber: 'A', userColor: 'Red', predictedColor: 'Red' }),
    contrib({ userKey: 'a2', embedding: [1, 0, 0], userPartNumber: 'A', predictedPartNumber: 'A', userColor: 'Red', predictedColor: 'Red' }),
    contrib({ userKey: 'a3', embedding: [1, 0, 0], userPartNumber: 'A', predictedPartNumber: 'A', userColor: 'Red', predictedColor: 'Red' }),
    contrib({ userKey: 'b1', embedding: [0, 1, 0], userPartNumber: 'B', predictedPartNumber: 'B', userColor: 'Blue', predictedColor: 'Blue' }),
    contrib({ userKey: 'b2', embedding: [0, 1, 0], userPartNumber: 'B', predictedPartNumber: 'B', userColor: 'Blue', predictedColor: 'Blue' }),
    contrib({ userKey: 'b3', embedding: [0, 1, 0], userPartNumber: 'B', predictedPartNumber: 'B', userColor: 'Blue', predictedColor: 'Blue' }),
  ];
  const index = buildCorrectionIndex(contribs, { version: '2' });
  assert.equal(index.entries.length, 2);
  const [first, second] = index.entries;
  assert.equal(first.clusterId, '2-0');
  assert.equal(first.shapeLabel, 'A');
  assert.equal(first.colorLabel, 'Red');
  assert.equal(second.clusterId, '2-1');
  assert.equal(second.shapeLabel, 'B');
  assert.equal(second.colorLabel, 'Blue');
});

// 6. TableCorrectionIndexStore save→load round-trips via injected fake clients.
class NotFoundError extends Error {
  statusCode = 404;
}

class FakeIndexTableClient implements CorrectionIndexTableClient {
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
  async getEntity<T extends TableEntity>(partitionKey: string, rowKey: string): Promise<T> {
    const found = this.rows.get(this.key(partitionKey, rowKey));
    if (!found) throw new NotFoundError('entity not found');
    return found as T;
  }
  async *listEntities<T extends TableEntity>(): AsyncIterable<T> {
    for (const e of this.rows.values()) yield e as T;
  }
}

test('TableCorrectionIndexStore: currentVersion is "0" before save, round-trips after', async () => {
  const meta = new FakeIndexTableClient();
  const entries = new FakeIndexTableClient();
  const store = new TableCorrectionIndexStore('', { meta, entries });

  assert.equal(await store.currentVersion(), '0');
  assert.equal(await store.load(), null);

  const index: CorrectionIndex = {
    version: '3',
    generatedAt: '2026-09-03T00:00:00.000Z',
    entries: [
      {
        clusterId: '3-0',
        embeddingBase64: encodeEmbedding([1, 2, 3]),
        shapeLabel: 'A',
        colorLabel: null,
        members: 4,
        shapeConfidence: 0.9,
        colorConfidence: 0.1,
      },
      {
        clusterId: '3-1',
        embeddingBase64: encodeEmbedding([4, 5, 6]),
        shapeLabel: null,
        colorLabel: 'Blue',
        members: 5,
        shapeConfidence: 0.2,
        colorConfidence: 0.8,
      },
    ],
  };
  await store.save(index);

  assert.equal(await store.currentVersion(), '3');
  const loaded = await store.load();
  assert.ok(loaded);
  assert.equal(loaded.version, '3');
  assert.equal(loaded.generatedAt, '2026-09-03T00:00:00.000Z');
  assert.equal(loaded.entries.length, 2);

  const byId = new Map(loaded.entries.map((e) => [e.clusterId, e]));
  const e0 = byId.get('3-0');
  const e1 = byId.get('3-1');
  assert.ok(e0 && e1);
  assert.equal(e0.shapeLabel, 'A');
  assert.equal(e0.colorLabel, null);
  assert.equal(e0.members, 4);
  assert.deepEqual(decodeEmbedding(e0.embeddingBase64), [1, 2, 3]);
  assert.equal(e1.shapeLabel, null);
  assert.equal(e1.colorLabel, 'Blue');
  assert.deepEqual(decodeEmbedding(e1.embeddingBase64), [4, 5, 6]);
});
