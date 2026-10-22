import { takeRateSlot } from "./limits.ts";
import { authenticate, refreshSession, signInWithProvider, type Provider } from "./auth.ts";
import { normalizeEmail, requestEmailCode, verifyEmailCode } from "./emailAuth.ts";
import { sendEmail } from "./email.ts";
import type { Deps, Env } from "./env.ts";
import { AuthError } from "./jwt.ts";
import { getMe } from "./me.ts";
import { AppStoreError, handleAppStoreNotification, submitTransaction } from "./appstore.ts";
import { handleLemonSqueezy, verifySignature } from "./lemonsqueezy.ts";
import { activateLicense } from "./license.ts";
import { handleRun } from "./run.ts";
import { getTemplates } from "./templates.ts";
import { startTrial } from "./trial.ts";

const defaultDeps: Deps = { fetch: (...args) => fetch(...args), now: () => Date.now(), sendEmail };
const noContext = { waitUntil() {}, passThroughOnException() {}, props: {} } as unknown as ExecutionContext;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });
}

function fail(status: number, code: string, message: string, extra: Record<string, unknown> = {}): Response {
  return json({ error: { code, message, ...extra } }, status);
}

async function readJson(req: Request): Promise<Record<string, unknown> | null> {
  const text = await req.text();
  if (text.length > 16_384) return null;
  try {
    const v = JSON.parse(text);
    return v && typeof v === "object" ? (v as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

function appStoreFailure(error: AppStoreError): Response {
  return error.code === "wrong_account" ? fail(409, error.code, error.message) : fail(400, error.code, error.message);
}

/** Every request the Worker serves. Paths follow the PRD (section 5). */
export async function handleRequest(req: Request, env: Env, deps: Deps = defaultDeps, ctx: ExecutionContext = noContext): Promise<Response> {
  const url = new URL(req.url);
  const route = `${req.method} ${url.pathname}`;
  try {
    if (!env.JWT_SECRET) return fail(500, "internal_error", "The server is not configured.");

    switch (route) {
      case "GET /v1/me": {
        const userId = await authenticate(req, env, deps.now());
        if (!userId) return fail(401, "unauthenticated", "Sign in to continue.");
        return json(await getMe(env.DB, userId, deps.now()));
      }
      case "GET /v1/templates": {
        const userId = await authenticate(req, env, deps.now());
        if (!userId) return fail(401, "unauthenticated", "Sign in to continue.");
        return json(await getTemplates(env.DB, Number(url.searchParams.get("since_version") ?? "0") || 0));
      }
      case "POST /v1/auth/apple":
      case "POST /v1/auth/google": {
        const body = await readJson(req);
        const idToken = body?.id_token;
        if (typeof idToken !== "string" || !idToken) return fail(400, "bad_request", "id_token is required.");
        const provider = url.pathname.endsWith("apple") ? "apple" : "google";
        const nonce = typeof body?.nonce === "string" ? body.nonce : undefined;
        return json(await signInWithProvider(env, deps, provider as Provider, idToken, nonce));
      }
      case "POST /v1/auth/email/request": {
        const body = await readJson(req);
        const email = normalizeEmail(body?.email);
        if (!email) return fail(400, "bad_request", "A valid email address is required.");
        try {
          await requestEmailCode(env, deps, email);
        } catch (error) {
          console.error("email failed", error instanceof Error ? error.message : error);
          return fail(503, "email_unavailable", "We couldn't send the email. Try again later.");
        }
        return json({ ok: true }); // the same answer whether or not the address has an account
      }
      case "POST /v1/auth/email/verify": {
        const body = await readJson(req);
        const email = normalizeEmail(body?.email);
        if (!email || typeof body?.code !== "string" || !/^\d{6}$/.test(body.code.trim())) return fail(400, "bad_request", "email and a 6-digit code are required.");
        try {
          return json(await verifyEmailCode(env, deps, email, body.code));
        } catch (error) {
          if (error instanceof AuthError) return fail(401, "invalid_code", "That code is wrong or has expired.");
          throw error;
        }
      }
      case "POST /v1/trial/start": {
        const userId = await authenticate(req, env, deps.now());
        if (!userId) return fail(401, "unauthenticated", "Sign in to continue.");
        const result = await startTrial(env.DB, userId, (await readJson(req))?.install_id_hash, deps.now());
        if (result.ok) return json({ plan: result.plan, trial_ends_at: result.trial_ends_at, runs_allowance: result.runs_allowance });
        return result.reason === "trial_already_used"
          ? fail(409, "trial_already_used", "A free trial has already been used on this Mac.")
          : fail(400, "bad_request", "install_id_hash must be a SHA-256 hex string.");
      }
      case "POST /v1/run": {
        const userId = await authenticate(req, env, deps.now());
        if (!userId) return fail(401, "unauthenticated", "Sign in to continue.");
        return handleRun(req, env, deps, ctx, userId, fail);
      }
      case "POST /v1/purchases/storekit": {
        const userId = await authenticate(req, env, deps.now());
        if (!userId) return fail(401, "unauthenticated", "Sign in to continue.");
        try {
          await submitTransaction(env, deps, userId, (await readJson(req))?.signed_transaction);
          return json(await getMe(env.DB, userId, deps.now()));
        } catch (error) {
          if (error instanceof AppStoreError) return appStoreFailure(error);
          throw error;
        }
      }
      case "POST /v1/license/activate": {
        const userId = await authenticate(req, env, deps.now());
        if (!userId) return fail(401, "unauthenticated", "Sign in to continue.");
        const limited = await takeRateSlot(env.DB, userId, deps.now());
        if (!limited.ok) return fail(429, "rate_limited", "Too many attempts. Try again shortly.", { retry_after: limited.retryAfter });
        const licenseKey = (await readJson(req))?.license_key;
        if (typeof licenseKey !== "string" || licenseKey.trim().length < 8 || licenseKey.length > 200) return fail(400, "bad_request", "license_key is required.");
        const result = await activateLicense(env, userId, licenseKey, deps.now());
        if (result.ok) return json(await getMe(env.DB, userId, deps.now()));
        return result.reason === "license_already_used"
          ? fail(409, "license_already_used", "That license key is already linked to another account.")
          : fail(404, "unknown_license", "We couldn't find that license key. If you just bought it, try again in a minute.");
      }
      case "POST /webhooks/lemonsqueezy": {
        const raw = await req.text();
        if (!env.LS_WEBHOOK_SECRET) return fail(503, "not_configured", "Webhook is not configured.");
        if (!(await verifySignature(raw, req.headers.get("x-signature"), env.LS_WEBHOOK_SECRET))) return fail(401, "invalid_signature", "Bad signature.");
        return json({ ok: true, outcome: await handleLemonSqueezy(env, deps, raw) });
      }
      case "POST /webhooks/appstore": {
        try {
          return json({ ok: true, outcome: await handleAppStoreNotification(env, deps, await readJson(req)) });
        } catch (error) {
          if (error instanceof AppStoreError) return appStoreFailure(error);
          throw error;
        }
      }
      case "POST /v1/auth/refresh": {
        const body = await readJson(req);
        const token = body?.refresh_token;
        if (typeof token !== "string" || !token) return fail(400, "bad_request", "refresh_token is required.");
        return json(await refreshSession(env, deps, token));
      }
    }

    const known = ["/v1/purchases/storekit", "/v1/license/activate", "/webhooks/lemonsqueezy", "/webhooks/appstore", "/v1/me", "/v1/templates", "/v1/run", "/v1/trial/start", "/v1/auth/apple", "/v1/auth/google", "/v1/auth/refresh",
      "/v1/auth/email/request", "/v1/auth/email/verify"];
    return known.includes(url.pathname) ? fail(405, "method_not_allowed", "Method not allowed.") : fail(404, "not_found", "Not found.");
  } catch (error) {
    if (error instanceof AuthError) return fail(401, "invalid_token", "That sign-in could not be verified.");
    console.error("unhandled", error instanceof Error ? error.message : error);
    return fail(500, "internal_error", "Something went wrong.");
  }
}
