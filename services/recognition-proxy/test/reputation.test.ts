import { test } from 'node:test';
import assert from 'node:assert/strict';
import { REPUTATION_PRIOR, updateReputation, reputationMean, reputationWeight } from '../src/reputation.js';

test('updateReputation increments a on agree, b on disagree, without mutating input', () => {
  const rep = { a: 1, b: 1 };
  const agreed = updateReputation(rep, true);
  const disagreed = updateReputation(rep, false);
  assert.deepEqual(agreed, { a: 2, b: 1 });
  assert.deepEqual(disagreed, { a: 1, b: 2 });
  assert.deepEqual(rep, { a: 1, b: 1 }); // unchanged
});

test('reputationMean is 0.5 for the fresh prior and guards divide-by-zero', () => {
  assert.equal(reputationMean(REPUTATION_PRIOR), 0.5);
  assert.equal(reputationMean({ a: 0, b: 0 }), 0.5);
});

test('reputationWeight is ~0 for a fresh {1,1} user', () => {
  assert.equal(reputationWeight(REPUTATION_PRIOR), 0);
});

test('reputationWeight rises toward 1 as agreements accumulate', () => {
  let rep = REPUTATION_PRIOR;
  const w0 = reputationWeight(rep);
  for (let i = 0; i < 20; i++) rep = updateReputation(rep, true);
  const w1 = reputationWeight(rep);
  assert.equal(w0, 0);
  assert.ok(w1 > 0.8, `expected high weight, got ${w1}`);
  assert.ok(w1 < 1);
});

test('reputationWeight is 0 for a mostly-disagreeing user', () => {
  let rep = REPUTATION_PRIOR;
  for (let i = 0; i < 10; i++) rep = updateReputation(rep, false);
  rep = updateReputation(rep, true); // one lucky agree, still sub-50%
  assert.equal(reputationWeight(rep), 0);
});
