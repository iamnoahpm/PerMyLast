#!/usr/bin/env node
// NFR-10: how much latency the proxy adds before the first streamed token (target: under 150 ms at p50).
// Compares time-to-first-token calling Anthropic's API directly with calling it through /v1/run.
//
//   Against a deployed Worker (uses your keys; costs a few cents):
//     PROXY_URL=https://<worker> TOKEN=<access token> ANTHROPIC_API_KEY=... node scripts/measure-latency.mjs [runs]
//   Against a local Worker and fake upstream (no cost): see backend/README, "Latency".
//     PROXY_URL=http://127.0.0.1:8787 TOKEN=... DIRECT_URL=http://127.0.0.1:9999 ANTHROPIC_API_KEY=local node scripts/measure-latency.mjs 40
const runs = Number(process.argv[2] ?? 20);
const proxy = process.env.PROXY_URL, token = process.env.TOKEN, key = process.env.ANTHROPIC_API_KEY;
const direct = process.env.DIRECT_URL ?? "https://api.anthropic.com";
if (!proxy || !token || !key) { console.error("Set PROXY_URL, TOKEN and ANTHROPIC_API_KEY."); process.exit(2); }

async function firstToken(url, init, marker) {
  const t0 = performance.now();
  const res = await fetch(url, init);
  if (!res.ok) throw new Error(`${url} -> ${res.status}`);
  const reader = res.body.getReader();
  const dec = new TextDecoder();
  let buf = "";
  for (;;) {
    const { value, done } = await reader.read();
    if (done) throw new Error("stream ended before a token");
    buf += dec.decode(value, { stream: true });
    if (buf.includes(marker)) { const ms = performance.now() - t0; reader.cancel().catch(() => {}); return ms; }
  }
}
const pct = (a, p) => [...a].sort((x, y) => x - y)[Math.min(a.length - 1, Math.floor((p / 100) * a.length))];

const body = { model: process.env.MODEL ?? "claude-haiku-4-5", max_tokens: 16, stream: true, system: "Reply with one short word.", messages: [{ role: "user", content: "Hi" }] };
const directInit = { method: "POST", headers: { "x-api-key": key, "anthropic-version": "2023-06-01", "content-type": "application/json" }, body: JSON.stringify(body) };
const proxyInit = { method: "POST", headers: { authorization: `Bearer ${token}`, "content-type": "application/json" }, body: JSON.stringify({ template_id: "ask", variables: { content: "Hi" } }) };

const d = [], p = [];
await firstToken(`${direct}/v1/messages`, directInit, "text_delta").catch(() => {}); // warm up
for (let i = 0; i < runs; i++) {
  d.push(await firstToken(`${direct}/v1/messages`, directInit, "text_delta"));
  p.push(await firstToken(`${proxy}/v1/run`, proxyInit, "event: delta"));
  await new Promise((r) => setTimeout(r, 3200)); // stay under the per-minute rate limit
}
const row = (n, a) => `${n.padEnd(8)} p50 ${pct(a, 50).toFixed(0).padStart(5)} ms   p95 ${pct(a, 95).toFixed(0).padStart(5)} ms`;
console.log(row("direct", d)); console.log(row("proxy", p));
const added = pct(p, 50) - pct(d, 50);
console.log(`\nproxy adds ${added.toFixed(0)} ms at p50 -> ${added < 150 ? "PASS" : "FAIL"} (target < 150 ms)`);
