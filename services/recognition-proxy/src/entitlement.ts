import { X509Certificate, timingSafeEqual } from 'node:crypto';
import jwt, { type JwtPayload } from 'jsonwebtoken';
import { ProxyError } from './types.js';

/**
 * NOTE: Cloud AI recognition is currently a developer-only feature unlocked
 * solely via the developer-bypass token (see `verifyDevBypassToken`). The live
 * `recognizeImage` handler does NOT call `verifyEntitlement` — it is retained
 * here, fully tested, as reserved infrastructure for a future paid tier.
 *
 * Verifies a StoreKit 2 JWS (`Transaction.jwsRepresentation`) passed by the
 * iOS app and returns a stable per-user identifier (the original transaction
 * id) when the entitlement represents an **active Bricky Pro** subscription.
 *
 * Apple signs JWS with an x5c certificate chain rooted in the Apple Root CA.
 * When `verifyChain` is set (production / `APPSTORE_VERIFY_CHAIN=true`) we
 * cryptographically validate that chain against the pinned Apple Root CA - G3
 * and verify the ES256 JWS signature with the leaf certificate before trusting
 * any payload field. For local/dev (`verifyChain` false) we decode and
 * structurally validate the payload only.
 *
 * Developer-override users have no real receipt. They are only honored via a
 * separate, server-gated developer bypass token (see `verifyDevBypassToken`)
 * which is OFF unless `DEV_BYPASS_TOKEN` is configured on the proxy.
 */

const PRO_PRODUCT_IDS = new Set([
  // Shipping iOS product: a single non-consumable "Bricky Pro" unlock.
  'com.bricky.app.pro',
  // Reserved for a future subscription model (accepted for forward-compat).
  'com.bricky.app.pro.monthly',
  'com.bricky.app.pro.annual',
]);

/**
 * Prefix the iOS app prepends to the shared developer-bypass secret when Pro is
 * granted via the in-app developer override (which produces no StoreKit JWS).
 */
export const DEV_BYPASS_PREFIX = 'dev-override:';

/** Stable quota key used for all developer-bypass traffic. */
const DEV_BYPASS_USER_KEY = 'dev-override';

/** Constant-time string comparison that never short-circuits on length. */
function constantTimeEquals(a: string, b: string): boolean {
  const aBuf = Buffer.from(a, 'utf8');
  const bBuf = Buffer.from(b, 'utf8');
  if (aBuf.length !== bBuf.length) {
    // Compare against self to keep the timing profile uniform, then fail.
    timingSafeEqual(aBuf, aBuf);
    return false;
  }
  return timingSafeEqual(aBuf, bBuf);
}

/**
 * Resolves a developer-bypass entitlement when (and only when) the proxy has a
 * `DEV_BYPASS_TOKEN` secret configured AND the supplied token is the matching
 * `dev-override:<secret>` value. This lets the developer test the Pro AI
 * recognition feature using the in-app developer override (which has no real
 * Apple receipt) without exposing the path on any proxy where the secret is
 * unset (e.g. production).
 *
 * Returns `null` when the token is not a developer-bypass token, or when no
 * secret is configured — callers then fall through to real StoreKit
 * verification, which rejects the token. Throws `not_entitled` when the token
 * IS a bypass token but the secret does not match.
 */
export function verifyDevBypassToken(
  token: string | undefined,
  secret: string | undefined,
): VerifiedEntitlement | null {
  if (!secret || !token || !token.startsWith(DEV_BYPASS_PREFIX)) {
    return null;
  }
  const provided = token.slice(DEV_BYPASS_PREFIX.length);
  if (!constantTimeEquals(provided, secret)) {
    throw new ProxyError(401, 'not_entitled', 'Invalid developer bypass token.');
  }
  return { userKey: DEV_BYPASS_USER_KEY, productId: 'dev-override' };
}

interface StoreKitTransactionPayload extends JwtPayload {
  transactionId?: string;
  originalTransactionId?: string;
  bundleId?: string;
  productId?: string;
  type?: string;
  environment?: string;
  /** Subscription expiry, ms since epoch. */
  expiresDate?: number;
  revocationDate?: number;
}

export interface VerifiedEntitlement {
  /** Stable per-user key used for quota accounting. */
  userKey: string;
  productId: string;
  expiresDate?: number;
}

function decodeJWS(token: string): StoreKitTransactionPayload {
  const decoded = jwt.decode(token, { complete: true });
  if (!decoded || typeof decoded === 'string') {
    throw new ProxyError(401, 'not_entitled', 'Malformed entitlement token.');
  }
  return decoded.payload as StoreKitTransactionPayload;
}

/**
 * Apple Root CA - G3 (DER, base64), pinned as the trust anchor for StoreKit
 * JWS. Self-issued; SHA-256 fingerprint
 * 63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79
 * (https://www.apple.com/certificateauthority/AppleRootCA-G3.cer).
 */
const APPLE_ROOT_CA_G3_DER_B64 =
  'MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBD' +
  'QSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBw' +
  'bGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYD' +
  'VQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9y' +
  'aXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49AgEGBSuBBAAiA2IA' +
  'BJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtfTjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA' +
  '/VhYDKX1DyxNB0cTddqXl5dvMVztK517IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4ia' +
  'pIqZ3r6966/ayySrMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gA' +
  'MGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4at+qIxUCMG1mihDK' +
  '1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM6BgD56KyKA==';

let cachedAppleRoot: X509Certificate | undefined;
function appleRoot(): X509Certificate {
  if (!cachedAppleRoot) {
    cachedAppleRoot = new X509Certificate(
      Buffer.from(APPLE_ROOT_CA_G3_DER_B64, 'base64'),
    );
  }
  return cachedAppleRoot;
}

/**
 * Cryptographically verifies that `token` is a genuine StoreKit JWS signed by
 * Apple: walks the x5c certificate chain, requires each link to be issued and
 * signed by the next, anchors the top of the chain to the pinned Apple Root
 * CA - G3, and finally verifies the ES256 JWS signature with the leaf
 * certificate's public key. Throws `not_entitled` on any failure. This is the
 * control that stops a forged-payload token from passing entitlement and
 * burning OpenAI budget.
 */
function verifyAppleSignature(token: string): void {
  const decoded = jwt.decode(token, { complete: true });
  if (!decoded || typeof decoded === 'string') {
    throw new ProxyError(401, 'not_entitled', 'Malformed entitlement token.');
  }
  const x5c = decoded.header?.x5c;
  if (!Array.isArray(x5c) || x5c.length < 2) {
    throw new ProxyError(403, 'not_entitled', 'Entitlement token is not Apple-signed.');
  }

  let certs: X509Certificate[];
  try {
    certs = x5c.map((b64) => new X509Certificate(Buffer.from(b64, 'base64')));
  } catch {
    throw new ProxyError(403, 'not_entitled', 'Malformed certificate chain.');
  }

  const now = Date.now();
  for (const cert of certs) {
    if (Date.parse(cert.validFrom) > now || Date.parse(cert.validTo) < now) {
      throw new ProxyError(
        403,
        'not_entitled',
        'Certificate in chain is expired or not yet valid.',
      );
    }
  }

  // Each cert must be issued and signed by the next one up the chain.
  for (let i = 0; i < certs.length - 1; i++) {
    if (!certs[i].checkIssued(certs[i + 1]) || !certs[i].verify(certs[i + 1].publicKey)) {
      throw new ProxyError(403, 'not_entitled', 'Broken certificate chain.');
    }
  }

  // Anchor: the top supplied cert must be — or be issued and signed by — the
  // pinned Apple root. We never trust a root supplied inside the token itself.
  const top = certs[certs.length - 1];
  const root = appleRoot();
  const topIsRoot = Buffer.compare(top.raw, root.raw) === 0;
  if (!topIsRoot && !(top.checkIssued(root) && top.verify(root.publicKey))) {
    throw new ProxyError(
      403,
      'not_entitled',
      'Certificate chain is not anchored to Apple Root CA.',
    );
  }

  // Verify the JWS signature itself with the leaf certificate's public key.
  const leafPem = certs[0].publicKey.export({ type: 'spki', format: 'pem' }) as string;
  try {
    jwt.verify(token, leafPem, { algorithms: ['ES256'] });
  } catch {
    throw new ProxyError(403, 'not_entitled', 'Entitlement token signature is invalid.');
  }
}

export function verifyEntitlement(
  token: string | undefined,
  opts: { bundleId: string; environment: string; verifyChain?: boolean },
): VerifiedEntitlement {
  if (!token || token.trim().length === 0) {
    throw new ProxyError(401, 'not_entitled', 'Missing entitlement token.');
  }

  // Production: prove the token is genuinely Apple-signed before trusting any
  // payload claim. Dev/local skips this so unsigned fixtures can be used.
  if (opts.verifyChain) {
    verifyAppleSignature(token);
  }

  const payload = decodeJWS(token);

  if (payload.bundleId && payload.bundleId !== opts.bundleId) {
    throw new ProxyError(403, 'not_entitled', 'Token bundle mismatch.');
  }
  if (payload.environment && payload.environment !== opts.environment) {
    throw new ProxyError(403, 'not_entitled', 'Token environment mismatch.');
  }
  if (!payload.productId || !PRO_PRODUCT_IDS.has(payload.productId)) {
    throw new ProxyError(403, 'not_entitled', 'Not a Bricky Pro entitlement.');
  }
  if (payload.revocationDate) {
    throw new ProxyError(403, 'not_entitled', 'Subscription was revoked.');
  }
  if (payload.expiresDate && payload.expiresDate <= Date.now()) {
    throw new ProxyError(403, 'not_entitled', 'Subscription expired.');
  }

  const userKey = payload.originalTransactionId ?? payload.transactionId;
  if (!userKey) {
    throw new ProxyError(401, 'not_entitled', 'Token missing transaction id.');
  }

  return { userKey, productId: payload.productId, expiresDate: payload.expiresDate };
}
