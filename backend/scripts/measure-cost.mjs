#!/usr/bin/env node
// Measures what a run costs, using the same request the proxy sends (system prompt, model, token cap).
// Costs real money on YOUR Anthropic key (a few cents). Usage:
//   ANTHROPIC_API_KEY=... INPUT_USD_PER_MTOK=... OUTPUT_USD_PER_MTOK=... node scripts/measure-cost.mjs [model]
// Take the per-million-token prices for your model from Anthropic's pricing page; they are not hard-coded here.
import { readFileSync } from "node:fs";

const key = process.env.ANTHROPIC_API_KEY;
if (!key) { console.error("Set ANTHROPIC_API_KEY (your own key, only used locally)."); process.exit(2); }
const model = process.argv[2] ?? "claude-haiku-4-5";
const inPrice = Number(process.env.INPUT_USD_PER_MTOK), outPrice = Number(process.env.OUTPUT_USD_PER_MTOK);
const maxTokens = Number(process.env.MAX_OUTPUT_TOKENS ?? 1024);

const bundled = JSON.parse(readFileSync(new URL("../../Packages/PerMyLastCore/Sources/PerMyLastCore/Resources/Templates.json", import.meta.url), "utf8"));
const system = Object.fromEntries(bundled.templates.map((t) => [t.id, t.system]));

// Typical inputs: a short message, a medium email, a long email.
const samples = [
  ["text.process", "Rewrite this as a casual Teams message. Fix grammar and flow only.\n\nText: hey can u join the call at 3 tmrw, its about the budget thing we talked abt"],
  ["text.process", "Translate this into Vietnamese.\n\nText: Thanks for the update. I reviewed the document and have a few questions about the timeline for the second phase, mainly whether the vendor can deliver before the end of the quarter."],
  ["email.reply", "Email to reply to:\n" + "Hi Noah, following up on the proposal we sent last week. ".repeat(12) + "\n\nInstructions: Confirm I can make it, but ask to push 30 minutes."],
  ["ask", "What is the difference between a mutex and a semaphore? Keep it short."],
];

let totalIn = 0, totalOut = 0;
for (const [id, content] of samples) {
  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "x-api-key": key, "anthropic-version": "2023-06-01", "content-type": "application/json" },
    body: JSON.stringify({ model, max_tokens: maxTokens, system: [{ type: "text", text: system[id], cache_control: { type: "ephemeral" } }], messages: [{ role: "user", content }] }),
  });
  const body = await res.json();
  if (!res.ok) { console.error(id, res.status, body.error?.message); process.exit(1); }
  const u = body.usage;
  const input = u.input_tokens + (u.cache_creation_input_tokens ?? 0) + (u.cache_read_input_tokens ?? 0);
  totalIn += input; totalOut += u.output_tokens;
  console.log(`${id.padEnd(13)} in ${String(input).padStart(5)}  out ${String(u.output_tokens).padStart(5)}`);
}
const avgIn = totalIn / samples.length, avgOut = totalOut / samples.length;
console.log(`\naverage per run: ${avgIn.toFixed(0)} input tokens, ${avgOut.toFixed(0)} output tokens (model ${model})`);
if (inPrice > 0 && outPrice > 0) {
  const perRun = (avgIn * inPrice + avgOut * outPrice) / 1e6;
  console.log(`average cost per run: $${perRun.toFixed(5)}`);
  console.log(`trial worst case (50 runs): $${(perRun * 50).toFixed(2)}   Pro at 1000 runs/month: $${(perRun * 1000).toFixed(2)} (before store fees)`);
} else {
  console.log("Set INPUT_USD_PER_MTOK and OUTPUT_USD_PER_MTOK to see dollars.");
}
