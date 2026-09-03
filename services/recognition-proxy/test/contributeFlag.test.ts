import { test } from 'node:test';
import assert from 'node:assert/strict';
import { TableEntity } from '@azure/data-tables';
import {
  TableContributionStore,
  validateObservation,
  type ContributionObservation,
  type ContributionTableClient,
} from '../src/contributionStore.js';
import { ProxyError } from '../src/types.js';

function wellFormed(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    embeddingBase64: 'aGVsbG8=',
    action: 'correct',
    predictedPartNumber: '3001',
    predictedColor: 'Red',
    predictedConfidence: 0.72,
    userPartNumber: '3002',
    userColor: 'Blue',
    userStudsWide: 2,
    userStudsLong: 4,
    correctedShape: true,
    correctedColor: false,
    appVersion: '1.4.0',
    anonUserId: 'anon-abc',
    entitlementToken: 'dev-override:secret',
    ...overrides,
  };
}

// --- validateObservation: happy path + normalization ---

test('validateObservation accepts a well-formed observation and returns normalized values', () => {
  const obs = validateObservation(wellFormed());
  assert.equal(obs.action, 'correct');
  assert.equal(obs.predictedPartNumber, '3001');
  assert.equal(obs.userPartNumber, '3002');
  assert.equal(obs.userStudsWide, 2);
  assert.equal(obs.userStudsLong, 4);
  assert.equal(obs.predictedConfidence, 0.72);
});

test('validateObservation clamps predictedConfidence into 0..1', () => {
  assert.equal(validateObservation(wellFormed({ predictedConfidence: 1.9 })).predictedConfidence, 1);
  assert.equal(validateObservation(wellFormed({ predictedConfidence: -0.5 })).predictedConfidence, 0);
});

test('validateObservation coerces boolean flags', () => {
  const obs = validateObservation(wellFormed({ correctedShape: 1, correctedColor: 0 }));
  assert.equal(obs.correctedShape, true);
  assert.equal(obs.correctedColor, false);
});

test('validateObservation does not surface the entitlementToken as a required field', () => {
  const obs = validateObservation(wellFormed({ entitlementToken: undefined }));
  assert.equal(obs.entitlementToken, undefined);
});

// --- validateObservation: rejection cases ---

test('validateObservation throws 400 for missing embeddingBase64', () => {
  assert.throws(
    () => validateObservation(wellFormed({ embeddingBase64: undefined })),
    (e) => e instanceof ProxyError && e.status === 400 && e.code === 'bad_request',
  );
});

test('validateObservation throws 400 for an invalid action', () => {
  assert.throws(
    () => validateObservation(wellFormed({ action: 'delete' })),
    (e) => e instanceof ProxyError && e.status === 400,
  );
});

test('validateObservation throws 400 for out-of-range studs', () => {
  assert.throws(
    () => validateObservation(wellFormed({ userStudsWide: 0 })),
    (e) => e instanceof ProxyError && e.status === 400,
  );
  assert.throws(
    () => validateObservation(wellFormed({ userStudsLong: 65 })),
    (e) => e instanceof ProxyError && e.status === 400,
  );
});

test('validateObservation throws 400 for non-integer studs', () => {
  assert.throws(
    () => validateObservation(wellFormed({ userStudsWide: 2.5 })),
    (e) => e instanceof ProxyError && e.status === 400,
  );
});

test('validateObservation throws 400 for over-length fields', () => {
  assert.throws(
    () => validateObservation(wellFormed({ predictedColor: 'x'.repeat(65) })),
    (e) => e instanceof ProxyError && e.status === 400,
  );
  assert.throws(
    () => validateObservation(wellFormed({ embeddingBase64: 'a'.repeat(200_001) })),
    (e) => e instanceof ProxyError && e.status === 400,
  );
});

// --- TableContributionStore.save: persisted entity shape ---

class FakeTableClient implements ContributionTableClient {
  createdTable = false;
  entities: TableEntity[] = [];
  async createTable(): Promise<unknown> {
    this.createdTable = true;
    return undefined;
  }
  async createEntity(entity: TableEntity): Promise<unknown> {
    this.entities.push(entity);
    return undefined;
  }
}

test('TableContributionStore.save writes the expected entity fields', async () => {
  const fake = new FakeTableClient();
  const store = new TableContributionStore('', fake);
  const obs = validateObservation(wellFormed()) as ContributionObservation;

  await store.save('user-key-1', obs);

  assert.equal(fake.createdTable, true);
  assert.equal(fake.entities.length, 1);
  const e = fake.entities[0] as Record<string, unknown>;
  assert.equal(e.UserKey, 'user-key-1');
  assert.equal(e.Action, 'correct');
  assert.equal(e.PredictedPartNumber, '3001');
  assert.equal(e.PredictedColor, 'Red');
  assert.equal(e.UserPartNumber, '3002');
  assert.equal(e.UserColor, 'Blue');
  assert.equal(e.UserStudsWide, 2);
  assert.equal(e.UserStudsLong, 4);
  assert.equal(e.CorrectedShape, true);
  assert.equal(e.CorrectedColor, false);
  assert.equal(e.AppVersion, '1.4.0');
  assert.equal(e.AnonUserId, 'anon-abc');
  assert.equal(e.EmbeddingBase64, 'aGVsbG8=');
  assert.ok(typeof e.partitionKey === 'string' && (e.partitionKey as string).length === 10);
  assert.ok(typeof e.rowKey === 'string' && (e.rowKey as string).length > 0);
});

test('TableContributionStore.save never persists the entitlementToken', async () => {
  const fake = new FakeTableClient();
  const store = new TableContributionStore('', fake);
  const obs: ContributionObservation = {
    ...(validateObservation(wellFormed()) as ContributionObservation),
    entitlementToken: 'dev-override:super-secret',
  };

  await store.save('user-key-2', obs);

  const e = fake.entities[0] as Record<string, unknown>;
  assert.equal(e.entitlementToken, undefined);
  assert.equal(e.EntitlementToken, undefined);
  const serialized = JSON.stringify(e);
  assert.ok(!serialized.includes('super-secret'));
  assert.ok(!serialized.toLowerCase().includes('entitlement'));
});
