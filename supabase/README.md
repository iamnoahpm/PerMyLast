# Per My Last — credits backend

Shared-key credits: users sign in by email code, subscribe through Stripe, and get
1,000 rewrites per billing period. The app only displays the balance; this
backend owns it. Your Anthropic key never ships in the app.

## One-time setup

1. **Supabase project** — create one, then `supabase link --project-ref <ref>`.
2. **Auth** — Authentication → Email: enable email OTP. In the *Magic Link*
   email template, include `{{ .Token }}` (the 6-digit code) instead of only the link.
3. **Schema** — `supabase db push` (applies `migrations/0001_credits.sql`).
4. **Stripe** — create a recurring Product/Price (monthly). Add a webhook endpoint
   `https://<ref>.supabase.co/functions/v1/stripe-webhook` for events:
   `checkout.session.completed`, `invoice.paid`,
   `customer.subscription.updated`, `customer.subscription.deleted`.
   Enable the Customer Portal in Stripe settings.
5. **Secrets**
   ```bash
   supabase secrets set ANTHROPIC_API_KEY=sk-ant-... \
     STRIPE_SECRET_KEY=sk_live_... STRIPE_WEBHOOK_SECRET=whsec_... \
     STRIPE_PRICE_ID=price_... SITE_URL=https://permylast.app \
     CREDITS_MODEL=claude-sonnet-5 PLAN_CREDITS=1000
   ```
6. **Deploy**
   ```bash
   supabase functions deploy rewrite
   supabase functions deploy billing
   supabase functions deploy stripe-webhook --no-verify-jwt
   ```
7. **App config** — set `SUPABASE_URL` and `SUPABASE_ANON_KEY` at the top of
   `credits.js` (both are public by design), or export `PML_SUPABASE_URL` /
   `PML_SUPABASE_ANON_KEY` for dev. While empty, the app hides credits mode.

## Notes

- **Cost**: 1,000 rewrites at your `CREDITS_MODEL` price must stay under the
  monthly fee. A cheaper model (e.g. `claude-haiku-4-5`) widens the margin.
- **Abuse**: the server pins model/max_tokens and caps input length, but accepts the
  client's system prompt. Add per-user rate limiting before a public launch.
- **Privacy**: request text is never logged or stored; only error codes are logged.
  Update the website privacy copy to say text passes through the server in credits mode.
- **Rollover**: `invoice.paid` resets the balance to `PLAN_CREDITS` (no rollover).
