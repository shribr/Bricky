import { test } from 'node:test';
import assert from 'node:assert/strict';
import jwt from 'jsonwebtoken';
import { verifyEntitlement, verifyDevBypassToken, DEV_BYPASS_PREFIX } from '../src/entitlement.js';
import { ProxyError } from '../src/types.js';

const opts = { bundleId: 'com.bricky.app', environment: 'Production' };

function token(payload: Record<string, unknown>): string {
  // Unsigned (alg none) JWS — verifyEntitlement decodes, it does not verify
  // signature locally. (Chain verification is a cloud-only concern.)
  return jwt.sign(payload, '', { algorithm: 'none' });
}

const validPayload = {
  originalTransactionId: 'orig-123',
  bundleId: 'com.bricky.app',
  environment: 'Production',
  productId: 'com.bricky.app.pro.monthly',
  expiresDate: Date.now() + 86_400_000,
};

test('accepts an active Pro entitlement and returns userKey', () => {
  const result = verifyEntitlement(token(validPayload), opts);
  assert.equal(result.userKey, 'orig-123');
  assert.equal(result.productId, 'com.bricky.app.pro.monthly');
});

test('accepts the shipping non-consumable Pro product', () => {
  const result = verifyEntitlement(
    token({ ...validPayload, productId: 'com.bricky.app.pro' }),
    opts,
  );
  assert.equal(result.productId, 'com.bricky.app.pro');
});

test('rejects a missing token', () => {
  assert.throws(() => verifyEntitlement(undefined, opts), (e: unknown) => {
    return e instanceof ProxyError && e.status === 401 && e.code === 'not_entitled';
  });
});

test('rejects a non-Pro product', () => {
  assert.throws(
    () => verifyEntitlement(token({ ...validPayload, productId: 'com.bricky.app.tip' }), opts),
    (e: unknown) => e instanceof ProxyError && e.status === 403,
  );
});

test('rejects an expired subscription', () => {
  assert.throws(
    () => verifyEntitlement(token({ ...validPayload, expiresDate: Date.now() - 1000 }), opts),
    (e: unknown) => e instanceof ProxyError && e.code === 'not_entitled',
  );
});

test('rejects a revoked subscription', () => {
  assert.throws(
    () => verifyEntitlement(token({ ...validPayload, revocationDate: Date.now() }), opts),
    (e: unknown) => e instanceof ProxyError && e.status === 403,
  );
});

test('rejects a bundle mismatch', () => {
  assert.throws(
    () => verifyEntitlement(token({ ...validPayload, bundleId: 'com.evil.app' }), opts),
    (e: unknown) => e instanceof ProxyError && e.status === 403,
  );
});

test('rejects an environment mismatch', () => {
  assert.throws(
    () => verifyEntitlement(token({ ...validPayload, environment: 'Sandbox' }), opts),
    (e: unknown) => e instanceof ProxyError && e.status === 403,
  );
});

// --- Apple JWS signature-chain verification (verifyChain: true) ---

const chainOpts = { ...opts, verifyChain: true };

// A throwaway self-signed EC P-256 cert + key (NOT chained to Apple Root CA).
// Used to forge a structurally-valid, validly-signed token that must still be
// rejected because it is not anchored to Apple's pinned root.
const FAKE_CERT_DER_B64 =
  'MIIBVTCB/AIJAIwYmT5pAd2bMAoGCCqGSM49BAMCMDMxEjAQBgNVBAMMCU5vdCBBcHBsZTEQMA4GA1UE' +
  'CgwHRm9yZ2VyeTELMAkGA1UEBhMCVVMwHhcNMjYwNjAyMDQ0ODMwWhcNMzYwNTMwMDQ0ODMwWjAzMRIw' +
  'EAYDVQQDDAlOb3QgQXBwbGUxEDAOBgNVBAoMB0ZvcmdlcnkxCzAJBgNVBAYTAlVTMFkwEwYHKoZIzj0C' +
  'AQYIKoZIzj0DAQcDQgAEO5vWrPwLjXwZKDTXPFbIpbx0Nqq7V34E1pojgcW8i02F05hm+VKIVLIs+Kic' +
  '1G1kKXL4NeIdSV4j8GuEVOiHMDAKBggqhkjOPQQDAgNIADBFAiBXa64vmedBbtfRzFAw2JZh9OOrxw42' +
  'nXYRHI0YIPpCfwIhALiK0ZNkgqCnPWvAPjBxevwHxoqvsou+FnEVfXH4rUN+';

const FAKE_KEY_PEM = [
  '-----BEGIN EC PRIVATE KEY-----',
  'MHcCAQEEIEpWiPoNT1ANeGicI6gMOkVZigLLVCEis1LAcXSYbOeaoAoGCCqGSM49',
  'AwEHoUQDQgAEO5vWrPwLjXwZKDTXPFbIpbx0Nqq7V34E1pojgcW8i02F05hm+VKI',
  'VLIs+Kic1G1kKXL4NeIdSV4j8GuEVOiHMA==',
  '-----END EC PRIVATE KEY-----',
].join('\n');

test('verifyChain rejects an unsigned token (no x5c header)', () => {
  assert.throws(
    () => verifyEntitlement(token(validPayload), chainOpts),
    (e: unknown) =>
      e instanceof ProxyError && e.status === 403 && e.code === 'not_entitled',
  );
});

test('verifyChain rejects a token whose x5c is not a real certificate', () => {
  const forged = jwt.sign(validPayload, FAKE_KEY_PEM, {
    algorithm: 'ES256',
    header: { alg: 'ES256', x5c: ['not-a-cert', 'also-not-a-cert'] },
  });
  assert.throws(
    () => verifyEntitlement(forged, chainOpts),
    (e: unknown) => e instanceof ProxyError && e.status === 403,
  );
});

test('verifyChain rejects a validly-signed token not anchored to Apple root', () => {
  // Signature is valid for the leaf, but the chain is a single self-signed
  // cert that does not chain to Apple Root CA - G3 -> must be rejected.
  const forged = jwt.sign(validPayload, FAKE_KEY_PEM, {
    algorithm: 'ES256',
    header: { alg: 'ES256', x5c: [FAKE_CERT_DER_B64, FAKE_CERT_DER_B64] },
  });
  assert.throws(
    () => verifyEntitlement(forged, chainOpts),
    (e: unknown) =>
      e instanceof ProxyError && e.status === 403 && e.code === 'not_entitled',
  );
});

test('verifyChain disabled (dev) still accepts an unsigned fixture', () => {
  // Regression guard: local/dev path must remain decode-only.
  const result = verifyEntitlement(token(validPayload), opts);
  assert.equal(result.userKey, 'orig-123');
});

// --- Developer bypass token (DEV_BYPASS_TOKEN configured) ---

const DEV_SECRET = 'test-dev-secret-123';
const DEV_TOKEN = `${DEV_BYPASS_PREFIX}${DEV_SECRET}`;

test('verifyDevBypassToken returns null when no secret is configured', () => {
  assert.equal(verifyDevBypassToken(DEV_TOKEN, undefined), null);
});

test('verifyDevBypassToken returns null for a non-bypass token', () => {
  assert.equal(verifyDevBypassToken(token(validPayload), DEV_SECRET), null);
});

test('verifyDevBypassToken accepts a matching secret and returns a stable userKey', () => {
  const result = verifyDevBypassToken(DEV_TOKEN, DEV_SECRET);
  assert.ok(result);
  assert.equal(result?.userKey, 'dev-override');
});

test('verifyDevBypassToken rejects a bypass token with the wrong secret', () => {
  assert.throws(
    () => verifyDevBypassToken(`${DEV_BYPASS_PREFIX}wrong`, DEV_SECRET),
    (e: unknown) => e instanceof ProxyError && e.status === 401 && e.code === 'not_entitled',
  );
});

test('verifyDevBypassToken returns null for an undefined token', () => {
  assert.equal(verifyDevBypassToken(undefined, DEV_SECRET), null);
});
