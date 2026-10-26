-- The person's name, from Sign in with Apple, which shares it only on the very first authorization. Used to greet
-- them in the app and to personalise email. Cleared with the user row.
ALTER TABLE users ADD COLUMN name TEXT;
