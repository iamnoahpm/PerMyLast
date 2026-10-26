// Sign in with Apple token revocation. Apple requires an app that offers Sign in with Apple to revoke the user's token
// when they delete their account. At sign-in the app sends the one-time authorization code; we trade it for a refresh
// token and keep it, and on deletion we hand it back to Apple's /auth/revoke. Needs a Sign in with Apple key from the
// developer portal: APPLE_TEAM_ID, APPLE_KEY_ID (vars) and APPLE_PRIVATE_KEY (secret, the .p8 contents). Without them
// nothing here runs and sign-in and deletion work as before.
import type { Deps, Env } from "./env.ts";
import { b64urlEncode } from "./jwt.ts";

const APPLE = "https://appleid.apple.com";
const enc = new TextEncoder();

export const revocationConfigured = (env: Env) => Boolean(env.APPLE_TEAM_ID && env.APPLE_KEY_ID && env.APPLE_PRIVATE_KEY);

function pemToDer(pem: string): Uint8Array {
  const body = pem.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(/\s+/g, "");
  return Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
}

/** The ES256 JWT Apple wants as `client_secret`. Valid for 5 minutes. */
export async function appleClientSecret(env: Env, now: number): Promise<string> {
  const iat = Math.floor(now / 1000);
  const head = b64urlEncode(enc.encode(JSON.stringify({ alg: "ES256", kid: env.APPLE_KEY_ID })));
  const claims = b64urlEncode(enc.encode(JSON.stringify({ iss: env.APPLE_TEAM_ID, iat, exp: iat + 300, aud: APPLE, sub: env.APPLE_CLIENT_ID.split(",")[0].trim() })));
  const key = await crypto.subtle.importKey("pkcs8", pemToDer(env.APPLE_PRIVATE_KEY!), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, enc.encode(`${head}.${claims}`));
  return `${head}.${claims}.${b64urlEncode(sig)}`;
}

async function post(env: Env, deps: Deps, path: string, params: Record<string, string>): Promise<Response> {
  const body = new URLSearchParams({ client_id: env.APPLE_CLIENT_ID.split(",")[0].trim(), client_secret: await appleClientSecret(env, deps.now()), ...params });
  return deps.fetch(`${APPLE}${path}`, { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body, signal: AbortSignal.timeout(5000) });
}

/** Trades the authorization code from sign-in for a refresh token, or null if Apple refuses (never throws). */
export async function exchangeAuthorizationCode(env: Env, deps: Deps, code: string): Promise<string | null> {
  try {
    const res = await post(env, deps, "/auth/token", { code, grant_type: "authorization_code" });
    if (!res.ok) return null;
    const token = ((await res.json()) as { refresh_token?: unknown }).refresh_token;
    return typeof token === "string" && token ? token : null;
  } catch {
    return null;
  }
}

/** Tells Apple this app no longer has access to the user's Apple ID. True when Apple accepted it. Never throws. */
export async function revokeAppleToken(env: Env, deps: Deps, refreshToken: string): Promise<boolean> {
  try {
    return (await post(env, deps, "/auth/revoke", { token: refreshToken, token_type_hint: "refresh_token" })).ok;
  } catch {
    return false;
  }
}
