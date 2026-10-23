-- Why a run failed: HTTP status and Anthropic error type, or the exception text. Null for successful runs.
ALTER TABLE usage_events ADD COLUMN error_detail TEXT;
