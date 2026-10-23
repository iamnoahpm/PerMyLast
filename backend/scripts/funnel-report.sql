-- Onboarding funnel. Run: npx wrangler d1 execute permylast --remote --file scripts/funnel-report.sql
-- One row per install per step (COUNT DISTINCT), so retries and reopened windows do not inflate anything.
-- Change the 30 to look at a different window (days).

-- 1. The funnel: installs that reached each step, and the share of the first step.
WITH reached(step, n, ord) AS (
  SELECT 'started',              COUNT(DISTINCT install_id), 1 FROM onboarding_events WHERE name = 'onboarding_started'           AND at > (strftime('%s','now') - 30*86400) * 1000
  UNION ALL SELECT 'sample run',        COUNT(DISTINCT install_id), 2 FROM onboarding_events WHERE name = 'onboarding_sample_run'        AND at > (strftime('%s','now') - 30*86400) * 1000
  UNION ALL SELECT 'copied result',     COUNT(DISTINCT install_id), 3 FROM onboarding_events WHERE name = 'onboarding_copy_clicked'      AND at > (strftime('%s','now') - 30*86400) * 1000
  UNION ALL SELECT 'shortcut worked',   COUNT(DISTINCT install_id), 4 FROM onboarding_events WHERE name = 'onboarding_shortcut_tested'   AND at > (strftime('%s','now') - 30*86400) * 1000
  UNION ALL SELECT 'got access',        COUNT(DISTINCT install_id), 5 FROM onboarding_events WHERE name IN ('onboarding_access_trial_started','onboarding_access_own_key_saved') AND at > (strftime('%s','now') - 30*86400) * 1000
  UNION ALL SELECT 'finished',          COUNT(DISTINCT install_id), 6 FROM onboarding_events WHERE name = 'onboarding_completed'         AND at > (strftime('%s','now') - 30*86400) * 1000
  UNION ALL SELECT 'first real run',    COUNT(DISTINCT install_id), 7 FROM onboarding_events WHERE name = 'first_real_run'               AND at > (strftime('%s','now') - 30*86400) * 1000
)
SELECT step, n, ROUND(100.0 * n / (SELECT n FROM reached WHERE ord = 1), 1) AS pct_of_started FROM reached ORDER BY ord;

-- 2. Where people leave: the last step screen each unfinished install saw.
SELECT json_extract(e.props, '$.step') AS last_step_seen, COUNT(*) AS installs
FROM onboarding_events e
WHERE e.name = 'onboarding_step_viewed'
  AND e.at = (SELECT MAX(at) FROM onboarding_events x WHERE x.install_id = e.install_id AND x.name = 'onboarding_step_viewed')
  AND NOT EXISTS (SELECT 1 FROM onboarding_events c WHERE c.install_id = e.install_id AND c.name IN ('onboarding_completed','onboarding_skipped'))
GROUP BY last_step_seen ORDER BY installs DESC;

-- 3. Explicit skips, by step.
SELECT json_extract(props, '$.step') AS skipped_at, COUNT(DISTINCT install_id) AS installs
FROM onboarding_events WHERE name = 'onboarding_skipped' GROUP BY skipped_at ORDER BY installs DESC;

-- 4. Access choice: trial or own key.
SELECT name, COUNT(DISTINCT install_id) AS installs FROM onboarding_events
WHERE name IN ('onboarding_access_trial_code_sent','onboarding_access_trial_started','onboarding_access_own_key_saved') GROUP BY name;

-- 5. Time to first real run (minutes, median-ish via average and max) for installs that got there.
SELECT COUNT(*) AS installs,
       ROUND(AVG(f.at - s.at) / 60000.0, 1) AS avg_minutes,
       ROUND(MAX(f.at - s.at) / 60000.0, 1) AS max_minutes
FROM (SELECT install_id, MIN(at) AS at FROM onboarding_events WHERE name = 'onboarding_started' GROUP BY install_id) s
JOIN (SELECT install_id, MIN(at) AS at FROM onboarding_events WHERE name = 'first_real_run' GROUP BY install_id) f USING (install_id);

-- 6. Funnel by app version, to compare releases.
SELECT app_version, COUNT(DISTINCT CASE WHEN name = 'onboarding_started' THEN install_id END) AS started,
       COUNT(DISTINCT CASE WHEN name = 'onboarding_completed' THEN install_id END) AS completed,
       COUNT(DISTINCT CASE WHEN name = 'first_real_run' THEN install_id END) AS first_run
FROM onboarding_events GROUP BY app_version ORDER BY app_version DESC;
