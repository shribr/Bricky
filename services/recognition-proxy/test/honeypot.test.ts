import { test } from 'node:test';
import assert from 'node:assert/strict';
import { TableEntity } from '@azure/data-tables';
import {
  toPublic,
  gradeHoneypot,
  honeypotReputationDeltas,
  mergeDeltas,
  type Honeypot,
  type HoneypotResult,
} from '../src/honeypot.js';
import {
  TableHoneypotStore,
  TableHoneypotResultStore,
  validateHoneypotResult,
  type HoneypotTableClient,
} from '../src/honeypotStore.js';
import { reputationWeight } from '../src/reputation.js';
import { ProxyError } from '../src/types.js';

function hp(overrides: Partial<Honeypot> = {}): Honeypot {
  return {
    id: 'h1',
    partNumber: '3001',
    color: 'Red',
    imageRef: 'catalog/3001-red.jpg',
    source: 'catalog',
    ...overrides,
  };
}

function result(overrides: Partial<HoneypotResult> = {}): HoneypotResult {
  return {
    honeypotId: 'h1',
    userKey: 'u1',
    userPartNumber: '3001',
    userColor: 'Red',
    ...overrides,
  };
}

// --- 1. gradeHoneypot ---

test('gradeHoneypot: exact shape+color match → both agreed', () => {
  const g = gradeHoneypot(hp(), result());
  assert.deepEqual(g, { shapeAgreed: true, colorAgreed: true });
});

test('gradeHoneypot: wrong color → shapeAgreed true, colorAgreed false', () => {
  const g = gradeHoneypot(hp(), result({ userColor: 'Blue' }));
  assert.equal(g.shapeAgreed, true);
  assert.equal(g.colorAgreed, false);
});

test('gradeHoneypot: empty user answer for a channel leaves that channel undefined', () => {
  const g = gradeHoneypot(hp(), result({ userColor: '' }));
  assert.equal(g.shapeAgreed, true);
  assert.equal(g.colorAgreed, undefined);

  const g2 = gradeHoneypot(hp(), result({ userPartNumber: '' }));
  assert.equal(g2.shapeAgreed, undefined);
  assert.equal(g2.colorAgreed, true);
});

// --- 2. honeypotReputationDeltas ---

test('honeypotReputationDeltas: a user who nails N honeypots gets agreed on both channels', () => {
  const map = new Map<string, Honeypot>([
    ['h1', hp({ id: 'h1', partNumber: '3001', color: 'Red' })],
    ['h2', hp({ id: 'h2', partNumber: '3002', color: 'Blue' })],
  ]);
  const results: HoneypotResult[] = [
    result({ honeypotId: 'h1', userKey: 'u1', userPartNumber: '3001', userColor: 'Red' }),
    result({ honeypotId: 'h2', userKey: 'u1', userPartNumber: '3002', userColor: 'Blue' }),
  ];
  const deltas = honeypotReputationDeltas(map, results);
  assert.deepEqual(deltas.get('u1'), { agreed: 4, disagreed: 0 });
});

test('honeypotReputationDeltas: a user who fails gets disagreed', () => {
  const map = new Map<string, Honeypot>([['h1', hp()]]);
  const results: HoneypotResult[] = [
    result({ userKey: 'bad', userPartNumber: '9999', userColor: 'Green' }),
  ];
  const deltas = honeypotReputationDeltas(map, results);
  assert.deepEqual(deltas.get('bad'), { agreed: 0, disagreed: 2 });
});

test('honeypotReputationDeltas: results referencing an unknown honeypotId are ignored', () => {
  const map = new Map<string, Honeypot>([['h1', hp()]]);
  const results: HoneypotResult[] = [
    result({ honeypotId: 'nope', userKey: 'ghost', userPartNumber: '3001', userColor: 'Red' }),
  ];
  const deltas = honeypotReputationDeltas(map, results);
  assert.equal(deltas.get('ghost'), undefined);
  assert.equal(deltas.size, 0);
});

// --- 3. toPublic strips ground truth ---

test('toPublic strips partNumber/color, leaving only id + imageRef', () => {
  const pub = toPublic(hp());
  assert.deepEqual(pub, { id: 'h1', imageRef: 'catalog/3001-red.jpg' });
  assert.equal((pub as Record<string, unknown>).partNumber, undefined);
  assert.equal((pub as Record<string, unknown>).color, undefined);
});

// --- 4. Store round-trips via fake clients ---

class FakeHoneypotTableClient implements HoneypotTableClient {
  createdTable = false;
  rows = new Map<string, TableEntity>();
  private key(pk: string, rk: string): string {
    return `${pk}\u0000${rk}`;
  }
  async createTable(): Promise<unknown> {
    this.createdTable = true;
    return undefined;
  }
  async createEntity(entity: TableEntity): Promise<unknown> {
    this.rows.set(this.key(String(entity.partitionKey), String(entity.rowKey)), entity);
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

test('TableHoneypotStore: saveAll then list round-trips honeypots; ships empty', async () => {
  const client = new FakeHoneypotTableClient();
  const store = new TableHoneypotStore('', client);

  assert.deepEqual(await store.list(), []); // ships EMPTY — no fake seed data

  const items: Honeypot[] = [
    hp({ id: 'h1', partNumber: '3001', color: 'Red', imageRef: 'a.jpg', source: 'catalog' }),
    hp({ id: 'h2', partNumber: '3002', color: 'Blue', imageRef: 'b.jpg', source: 'expert' }),
  ];
  await store.saveAll(items);

  const loaded = await store.list();
  assert.equal(loaded.length, 2);
  const byId = new Map(loaded.map((h) => [h.id, h]));
  assert.deepEqual(byId.get('h1'), items[0]);
  assert.deepEqual(byId.get('h2'), items[1]);
});

test('TableHoneypotResultStore: save then listRecent round-trips results', async () => {
  const client = new FakeHoneypotTableClient();
  const store = new TableHoneypotResultStore('', client);

  await store.save(result({ honeypotId: 'h1', userKey: 'u1', userPartNumber: '3001', userColor: 'Red' }));
  await store.save(result({ honeypotId: 'h2', userKey: 'u2', userPartNumber: '3002', userColor: 'Blue' }));

  const recent = await store.listRecent();
  assert.equal(recent.length, 2);
  const users = new Set(recent.map((r) => r.userKey));
  assert.ok(users.has('u1'));
  assert.ok(users.has('u2'));
  const u1 = recent.find((r) => r.userKey === 'u1');
  assert.equal(u1?.honeypotId, 'h1');
  assert.equal(u1?.userPartNumber, '3001');
  assert.equal(u1?.userColor, 'Red');
});

test('validateHoneypotResult rejects missing/oversized fields', () => {
  assert.throws(() => validateHoneypotResult({ userPartNumber: '3001', userColor: 'Red' }), ProxyError);
  assert.throws(() => validateHoneypotResult({ honeypotId: 'h1', userColor: 'Red' }), ProxyError);
  assert.throws(
    () => validateHoneypotResult({ honeypotId: 'x'.repeat(65), userPartNumber: '3001', userColor: 'Red' }),
    ProxyError,
  );
  const ok = validateHoneypotResult({ honeypotId: 'h1', userPartNumber: ' 3001 ', userColor: ' Red ' });
  assert.deepEqual(ok, { honeypotId: 'h1', userPartNumber: '3001', userColor: 'Red' });
});

// --- 5. Merge semantics: combined agreed/disagreed is the SUM ---

test('mergeDeltas sums agreed/disagreed per userKey across maps', () => {
  const consensus = new Map([
    ['u1', { agreed: 3, disagreed: 1 }],
    ['u2', { agreed: 0, disagreed: 2 }],
  ]);
  const honeypot = new Map([
    ['u1', { agreed: 2, disagreed: 0 }],
    ['u3', { agreed: 1, disagreed: 4 }],
  ]);
  const merged = mergeDeltas(consensus, honeypot);
  assert.deepEqual(merged.get('u1'), { agreed: 5, disagreed: 1 });
  assert.deepEqual(merged.get('u2'), { agreed: 0, disagreed: 2 });
  assert.deepEqual(merged.get('u3'), { agreed: 1, disagreed: 4 });
  // Inputs are not mutated.
  assert.deepEqual(consensus.get('u1'), { agreed: 3, disagreed: 1 });
});

// --- 6. Anchor effect: failing honeypots drags a collusion-agreeing user down ---

test('honeypots anchor: a user who agrees with a colluding consensus but fails honeypots ends with low weight', () => {
  // Consensus rewards the colluder heavily (as if a Sybil ring self-agreed).
  const consensusDeltas = new Map([['colluder', { agreed: 8, disagreed: 0 }]]);

  // But the colluder fails a batch of honeypots (graded vs secret truth).
  const map = new Map<string, Honeypot>([
    ['h1', hp({ id: 'h1', partNumber: '3001', color: 'Red' })],
    ['h2', hp({ id: 'h2', partNumber: '3002', color: 'Blue' })],
    ['h3', hp({ id: 'h3', partNumber: '3003', color: 'Green' })],
    ['h4', hp({ id: 'h4', partNumber: '3004', color: 'Yellow' })],
    ['h5', hp({ id: 'h5', partNumber: '3005', color: 'Black' })],
  ]);
  const hpResults: HoneypotResult[] = [...map.keys()].map((id) =>
    result({ honeypotId: id, userKey: 'colluder', userPartNumber: 'WRONG', userColor: 'WRONG' }),
  );
  const hpDeltas = honeypotReputationDeltas(map, hpResults);

  const merged = mergeDeltas(consensusDeltas, hpDeltas);
  const d = merged.get('colluder');
  assert.ok(d);
  // 8 fake agreements vs 10 honeypot disagreements (2 channels × 5 items).
  const weight = reputationWeight({ a: 1 + d.agreed, b: 1 + d.disagreed });
  assert.ok(weight < 0.5, `expected weight < 0.5, got ${weight}`);
});
