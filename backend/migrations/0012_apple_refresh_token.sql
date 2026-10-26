-- Sign in with Apple: the refresh token from the sign-in authorization code, kept only so it can be revoked when the
-- account is deleted (App Store requirement). Cleared with the user row.
ALTER TABLE users ADD COLUMN apple_refresh_token TEXT;
