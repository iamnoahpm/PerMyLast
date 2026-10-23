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

-- Cost by plan: tokens used by users on each plan right now (multiply by your model prices).
SELECT COALESCE(e.plan, 'none') AS plan, COUNT(DISTINCT u.user_id) AS users, COUNT(*) AS runs,
       SUM(COALESCE(u.input_tokens, 0)) AS input_tokens, SUM(COALESCE(u.output_tokens, 0)) AS output_tokens
FROM usage_events u
LEFT JOIN entitlements e ON e.user_id = u.user_id AND e.status = 'active' AND e.plan <> 'trial'
WHERE u.status = 'ok'
GROUP BY COALESCE(e.plan, 'none');

-- Trial-to-paid conversion: of everyone who started a trial, how many now hold a paid entitlement.
SELECT COUNT(*) AS trials_started,
       SUM(EXISTS (SELECT 1 FROM entitlements p WHERE p.user_id = t.user_id AND p.plan <> 'trial' AND p.status <> 'refunded')) AS converted,
       ROUND(100.0 * SUM(EXISTS (SELECT 1 FROM entitlements p WHERE p.user_id = t.user_id AND p.plan <> 'trial' AND p.status <> 'refunded')) / COUNT(*), 1) AS conversion_percent
FROM entitlements t WHERE t.plan = 'trial';

-- Why runs failed, newest first.
SELECT datetime(created_at / 1000, 'unixepoch') AS at, status, model, error_detail
FROM usage_events WHERE status != 'ok' ORDER BY created_at DESC LIMIT 20;
