// POST /rewrite  { system, content }  ->  { text, creditsRemaining }
// Spends one credit, calls Anthropic with the shared key, refunds on failure.
// Request/response text is never logged or stored.
import { admin, getUser, json } from '../_shared/auth.ts';

const MODEL = Deno.env.get('CREDITS_MODEL') ?? 'claude-sonnet-5';
const MAX_SYSTEM_CHARS = 8_000;
const MAX_CONTENT_CHARS = 20_000;
const MAX_TOKENS = 1024;

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  const user = await getUser(req);
  if (!user) return json({ error: 'unauthorized' }, 401);

  let body: { system?: unknown; content?: unknown };
  try { body = await req.json(); } catch { return json({ error: 'bad_request' }, 400); }
  const { system, content } = body;
  if (typeof system !== 'string' || typeof content !== 'string' || !content.trim()) {
    return json({ error: 'bad_request' }, 400);
  }
  if (system.length > MAX_SYSTEM_CHARS || content.length > MAX_CONTENT_CHARS) {
    return json({ error: 'too_long' }, 413);
  }

  // Spend first so parallel requests can't overspend; refund if Anthropic fails.
  const { data: remaining, error: spendErr } = await admin.rpc('consume_credit', { p_user: user.id });
  if (spendErr) return json({ error: 'server_error' }, 500);
  if (remaining === null || remaining === undefined) return json({ error: 'no_credits' }, 402);

  try {
    // Model and max_tokens are pinned here; the client cannot choose them.
    const res = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': Deno.env.get('ANTHROPIC_API_KEY')!,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify({
        model: MODEL,
        max_tokens: MAX_TOKENS,
        system,
        messages: [{ role: 'user', content }],
      }),
    });
    const data = await res.json();
    if (!res.ok) throw new Error(`anthropic_${res.status}`);
    const block = Array.isArray(data.content)
      ? data.content.find((b: { type: string; text?: string }) => b.type === 'text' && b.text)
      : null;
    if (!block) throw new Error('empty_response');
    return json({ text: block.text, creditsRemaining: remaining });
  } catch (err) {
    const { data: refunded } = await admin.rpc('refund_credit', { p_user: user.id });
    console.error('rewrite failed:', (err as Error).message); // message only, never request text
    return json({ error: 'upstream_error', creditsRemaining: refunded ?? remaining }, 502);
  }
});
