// Client for the shared-key credits backend (Supabase). Pure logic with an
// injectable fetch so it can be unit-tested; main.js owns token storage.
//
// SUPABASE_URL and the anon key are public by design (they ship in every
// Supabase client app) — row-level security and the service-role-only RPCs
// are what protect the data. Leave them empty to disable the credits mode.
const SUPABASE_URL = process.env.PML_SUPABASE_URL || '';
const SUPABASE_ANON_KEY = process.env.PML_SUPABASE_ANON_KEY || '';

function isConfigured(cfg = { url: SUPABASE_URL, anonKey: SUPABASE_ANON_KEY }) {
  return !!(cfg.url && cfg.anonKey);
}

class CreditsError extends Error {
  constructor(code, message, extra) {
    super(message);
    this.code = code;
    Object.assign(this, extra);
  }
}

const REWRITE_ERRORS = {
  unauthorized: 'Your session expired. Sign in again in Settings.',
  no_credits: "You're out of credits. Subscribe or renew in Settings, or switch to your own API key.",
  too_long: 'That text is too long for credits mode. Shorten it or use your own API key.',
  upstream_error: 'Claude is unavailable right now. Your credit was not used — try again.',
  server_error: 'Something went wrong on our side. Your credit was not used — try again.'
};

function messageForError(code) {
  return REWRITE_ERRORS[code] || REWRITE_ERRORS.server_error;
}

function createClient(cfg, fetchImpl) {
  const base = String(cfg.url || '').replace(/\/+$/, '');
  const common = { 'Content-Type': 'application/json', apikey: cfg.anonKey };

  async function call(path, { method = 'POST', body, token } = {}) {
    const headers = { ...common };
    if (token) headers.Authorization = 'Bearer ' + token;
    const res = await fetchImpl(base + path, { method, headers, body: body ? JSON.stringify(body) : undefined });
    let data = null;
    try { data = await res.json(); } catch (e) { /* empty body */ }
    return { res, data };
  }

  return {
    // Emails a 6-digit code (no deep link needed, which suits a menu-bar app).
    async sendCode(email) {
      const { res, data } = await call('/auth/v1/otp', { body: { email, create_user: true } });
      if (!res.ok) throw new CreditsError('send_failed', (data && (data.msg || data.error_description)) || 'Could not send the code.');
    },

    async verifyCode(email, code) {
      const { res, data } = await call('/auth/v1/verify', { body: { type: 'email', email, token: code } });
      if (!res.ok || !data || !data.access_token) {
        throw new CreditsError('verify_failed', (data && (data.msg || data.error_description)) || 'That code is not valid or has expired.');
      }
      return toSession(data);
    },

    async refresh(refreshToken) {
      const { res, data } = await call('/auth/v1/token?grant_type=refresh_token', { body: { refresh_token: refreshToken } });
      if (!res.ok || !data || !data.access_token) throw new CreditsError('unauthorized', REWRITE_ERRORS.unauthorized);
      return toSession(data);
    },

    async getProfile(token) {
      const { res, data } = await call(
        '/rest/v1/profiles?select=credits,credits_limit,subscription_status,current_period_end&limit=1',
        { method: 'GET', token }
      );
      if (res.status === 401) throw new CreditsError('unauthorized', REWRITE_ERRORS.unauthorized);
      if (!res.ok || !Array.isArray(data) || !data[0]) throw new CreditsError('server_error', REWRITE_ERRORS.server_error);
      return normalizeProfile(data[0]);
    },

    async rewrite(token, { system, content }) {
      const { res, data } = await call('/functions/v1/rewrite', { body: { system, content }, token });
      if (res.ok && data && typeof data.text === 'string') {
        return { text: data.text, creditsRemaining: data.creditsRemaining };
      }
      const code = (data && data.error) || (res.status === 401 ? 'unauthorized' : res.status === 402 ? 'no_credits' : 'server_error');
      throw new CreditsError(code, messageForError(code), {
        creditsRemaining: data && typeof data.creditsRemaining === 'number' ? data.creditsRemaining : undefined
      });
    },

    async billingUrl(token, action) {
      const { res, data } = await call('/functions/v1/billing', { body: { action }, token });
      if (res.ok && data && data.url) return data.url;
      throw new CreditsError((data && data.error) || 'server_error',
        data && data.error === 'already_subscribed' ? 'You already have an active subscription.' : 'Could not open billing. Try again.');
    }
  };
}

function toSession(d) {
  return {
    accessToken: d.access_token,
    refreshToken: d.refresh_token,
    // Refresh a minute early so a request never races the expiry.
    expiresAt: Date.now() + Math.max(0, (d.expires_in || 3600) - 60) * 1000,
    email: (d.user && d.user.email) || ''
  };
}

function normalizeProfile(p) {
  const active = ['active', 'trialing'].includes(p.subscription_status);
  return {
    credits: Math.max(0, Number(p.credits) || 0),
    limit: Number(p.credits_limit) || 1000,
    subscribed: active,
    status: p.subscription_status || 'none',
    renewsAt: p.current_period_end || null
  };
}

module.exports = { isConfigured, createClient, CreditsError, messageForError, normalizeProfile, toSession, SUPABASE_URL, SUPABASE_ANON_KEY };
