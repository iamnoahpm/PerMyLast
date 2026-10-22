-- NFR-9 style report from real usage. Run: npx wrangler d1 execute permylast --remote --file scripts/cost-report.sql
-- Multiply the token sums by your model's per-million-token prices to get dollars.

-- Average tokens per successful run, by template and model.
SELECT template_id, model, COUNT(*) AS runs,
       ROUND(AVG(COALESCE(input_tokens, 0) + COALESCE(cache_read_tokens, 0) + COALESCE(cache_write_tokens, 0))) AS avg_input_tokens,
       ROUND(AVG(output_tokens)) AS avg_output_tokens, ROUND(AVG(latency_ms)) AS avg_latency_ms
FROM usage_events WHERE status = 'ok' GROUP BY template_id, model;

-- Top 20 users by tokens, last 30 days.
SELECT user_id, COUNT(*) AS runs, SUM(COALESCE(input_tokens, 0)) AS input_tokens, SUM(COALESCE(output_tokens, 0)) AS output_tokens
FROM usage_events WHERE created_at > (strftime('%s', 'now') - 30 * 86400) * 1000
GROUP BY user_id ORDER BY input_tokens + output_tokens DESC LIMIT 20;

-- Failures by status (refunded runs cost nothing to the user but may cost you).
SELECT status, COUNT(*) AS n FROM usage_events GROUP BY status;

-- Trial usage: how many trials ended, and how many credits were used on average.
SELECT COUNT(*) AS trials, ROUND(AVG(used), 1) AS avg_credits_used, SUM(used = allowance) AS fully_used
FROM usage_periods WHERE kind = 'trial';
