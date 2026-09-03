import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  cosineSimilarity,
  decodeEmbedding,
  clusterVotes,
  computeConsensus,
  type Vote,
} from '../src/consensus.js';

function encodeEmbedding(values: number[]): string {
  const buf = Buffer.alloc(values.length * 4);
  for (let i = 0; i < values.length; i++) buf.writeFloatLE(values[i], i * 4);
  return buf.toString('base64');
}

function vote(partial: Partial<Vote> & Pick<Vote, 'userKey'>): Vote {
  return {
    embedding: [1, 0, 0],
    shapeLabel: '3001',
    colorLabel: 'Red',
    predictedShape: '3001',
    predictedColor: 'Red',
    ...partial,
  };
}

test('cosineSimilarity: orthogonal vectors → 0, identical → 1', () => {
  assert.equal(cosineSimilarity([1, 0], [0, 1]), 0);
  assert.ok(Math.abs(cosineSimilarity([1, 2, 3], [1, 2, 3]) - 1) < 1e-9);
  assert.equal(cosineSimilarity([0, 0], [1, 1]), 0); // zero vector guard
});

test('decodeEmbedding round-trips a known base64 of Float32s', () => {
  const values = [1, 2, -0.5, 0.25];
  const decoded = decodeEmbedding(encodeEmbedding(values));
  assert.deepEqual(decoded, values); // all exact in Float32
});

test('clusterVotes: near-identical embeddings share a cluster, a far one splits', () => {
  const votes = [
    vote({ userKey: 'u1', embedding: [1, 0, 0] }),
    vote({ userKey: 'u2', embedding: [0.99, 0.01, 0] }),
    vote({ userKey: 'u3', embedding: [0, 1, 0] }),
  ];
  const clusters = clusterVotes(votes, 0.9);
  assert.equal(clusters.length, 2);
  const sizes = clusters.map((c) => c.length).sort();
  assert.deepEqual(sizes, [1, 2]);
});

test('weighted voting: trusted majority label wins even against a cheaper label and the prior', () => {
  // prior is "B" for all; 3 trusted votes for "A" (weight 5) beat 2 cheap votes for "B" (weight 0.1).
  const votes: Vote[] = [
    vote({ userKey: 'a1', shapeLabel: 'A', predictedShape: 'B' }),
    vote({ userKey: 'a2', shapeLabel: 'A', predictedShape: 'B' }),
    vote({ userKey: 'a3', shapeLabel: 'A', predictedShape: 'B' }),
    vote({ userKey: 'b1', shapeLabel: 'B', predictedShape: 'B' }),
    vote({ userKey: 'b2', shapeLabel: 'B', predictedShape: 'B' }),
  ];
  const weightOf = (u: string) => (u.startsWith('a') ? 5 : 0.1);
  const [c] = computeConsensus(votes, { weightOf });
  assert.equal(c.shape.label, 'A');
  assert.equal(c.shape.promoted, true);
});

test('cold start: a single low-weight vote disagreeing with the prior is NOT promoted', () => {
  const votes: Vote[] = [
    vote({ userKey: 'newbie', shapeLabel: 'B', predictedShape: 'A' }), // prior A, user says B
  ];
  const [c] = computeConsensus(votes, { weightOf: () => 0.3 });
  assert.equal(c.shape.label, 'A'); // prior still wins
  assert.equal(c.shape.promoted, false);
  assert.equal(c.shape.userWeight['A'] ?? 0, 0); // prior contributes no user weight
});

test('quorum gate: high confidence but userWeight(winner) < quorum → not promoted; add a trusted vote → promoted', () => {
  const base: Vote[] = [
    vote({ userKey: 'u1', shapeLabel: 'A', predictedShape: 'A' }),
  ];
  const [c1] = computeConsensus(base, { weightOf: () => 1, quorum: 2 });
  assert.equal(c1.shape.label, 'A');
  assert.equal(c1.shape.confidence, 1); // only one label
  assert.equal(c1.shape.promoted, false); // userWeight 1 < quorum 2

  const more: Vote[] = [...base, vote({ userKey: 'u2', shapeLabel: 'A', predictedShape: 'A' })];
  const [c2] = computeConsensus(more, { weightOf: () => 1, quorum: 2 });
  assert.equal(c2.shape.userWeight['A'], 2);
  assert.equal(c2.shape.promoted, true);
});

test('separate channels: agree on shape but split on color → shape promoted, color not', () => {
  const votes: Vote[] = [
    vote({ userKey: 'u1', shapeLabel: '3001', colorLabel: 'Red', predictedShape: '3001', predictedColor: 'Red' }),
    vote({ userKey: 'u2', shapeLabel: '3001', colorLabel: 'Blue', predictedShape: '3001', predictedColor: 'Red' }),
  ];
  const [c] = computeConsensus(votes, { weightOf: () => 1, quorum: 2 });
  assert.equal(c.shape.label, '3001');
  assert.equal(c.shape.promoted, true);
  assert.equal(c.color.label, 'Red'); // prior + one vote
  assert.equal(c.color.promoted, false); // winner userWeight 1 < quorum 2
});

test('adversary: a heavily-voted label from zero-weight users never wins or promotes', () => {
  const votes: Vote[] = [];
  for (let i = 0; i < 10; i++) {
    votes.push(vote({ userKey: `spam${i}`, shapeLabel: 'SPAM', predictedShape: '3001' }));
  }
  const [c] = computeConsensus(votes, { weightOf: () => 0 });
  assert.notEqual(c.shape.label, 'SPAM'); // prior "3001" wins
  assert.equal(c.shape.label, '3001');
  assert.equal(c.shape.promoted, false);
  assert.equal(c.shape.userWeight['SPAM'], 0);
});
