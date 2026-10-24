import { describe, it, expect, vi } from 'vitest';
import { createRequire } from 'module';
const require = createRequire(import.meta.url);
const { createClient, CreditsError, normalizeProfile, isConfigured, messageForError } = require('./credits.js');

const cfg = { url: 'https://x.supabase.co/', anonKey: 'anon' };
const reply = (status, body) => vi.fn().mockResolvedValue({ ok: status < 400, status, json: async () => body });

describe('isConfigured', () => {
  it('needs both url and anon key', () => {
    expect(isConfigured({ url: '', anonKey: 'a' })).toBe(false);
    expect(isConfigured(cfg)).toBe(true);
  });
});

describe('rewrite', () => {
  it('returns text and remaining credits, sending the bearer token', async () => {
    const f = reply(200, { text: 'hi', creditsRemaining: 41 });
    const r = await createClient(cfg, f).rewrite('tok', { system: 's', content: 'c' });
    expect(r).toEqual({ text: 'hi', creditsRemaining: 41 });
    expect(f.mock.calls[0][0]).toBe('https://x.supabase.co/functions/v1/rewrite');
    expect(f.mock.calls[0][1].headers.Authorization).toBe('Bearer tok');
  });

  it('maps 402 to no_credits', async () => {
    await expect(createClient(cfg, reply(402, { error: 'no_credits' })).rewrite('t', { system: '', content: 'c' }))
      .rejects.toMatchObject({ code: 'no_credits', message: messageForError('no_credits') });
  });

  it('keeps the refunded balance on upstream errors', async () => {
    await expect(createClient(cfg, reply(502, { error: 'upstream_error', creditsRemaining: 7 })).rewrite('t', { system: '', content: 'c' }))
      .rejects.toMatchObject({ code: 'upstream_error', creditsRemaining: 7 });
  });

  it('treats a bare 401 as unauthorized', async () => {
    await expect(createClient(cfg, reply(401, null)).rewrite('t', { system: '', content: 'c' }))
      .rejects.toMatchObject({ code: 'unauthorized' });
  });
});

describe('auth', () => {
  it('verifyCode returns a session', async () => {
    const s = await createClient(cfg, reply(200, { access_token: 'a', refresh_token: 'r', expires_in: 3600, user: { email: 'u@x.com' } })).verifyCode('u@x.com', '123456');
    expect(s).toMatchObject({ accessToken: 'a', refreshToken: 'r', email: 'u@x.com' });
    expect(s.expiresAt).toBeGreaterThan(Date.now());
  });

  it('verifyCode rejects a bad code', async () => {
    await expect(createClient(cfg, reply(400, { msg: 'Token has expired' })).verifyCode('u@x.com', '000000'))
      .rejects.toBeInstanceOf(CreditsError);
  });
});

describe('profile', () => {
  it('normalizes and flags active subscriptions', () => {
    expect(normalizeProfile({ credits: 847, credits_limit: 1000, subscription_status: 'active' }))
      .toMatchObject({ credits: 847, limit: 1000, subscribed: true });
    expect(normalizeProfile({ credits: -3, subscription_status: 'none' }))
      .toMatchObject({ credits: 0, limit: 1000, subscribed: false });
  });

  it('getProfile throws unauthorized on 401', async () => {
    await expect(createClient(cfg, reply(401, {})).getProfile('t')).rejects.toMatchObject({ code: 'unauthorized' });
  });
});
