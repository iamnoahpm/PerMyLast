export interface Env {
  DB: D1Database;
  /** Secret: signs session tokens. `wrangler secret put JWT_SECRET`. */
  JWT_SECRET: string;
  /** Sign in with Apple audience: the app's bundle id (comma-separated for more than one). */
  APPLE_CLIENT_ID: string;
  /** Google OAuth client id(s), comma-separated. */
  GOOGLE_CLIENT_ID: string;
  /** Secret: the shared Anthropic key. Only ever read here, never sent to the app (NFR-1). */
  ANTHROPIC_API_KEY?: string;
  /** Override for tests and local runs; defaults to https://api.anthropic.com. */
  ANTHROPIC_BASE_URL?: string;
  /** Secret: Resend API key for sign-in emails. */
  RESEND_API_KEY?: string;
  /** From address for sign-in emails, e.g. "Per My Last <login@yourdomain.com>". */
  MAIL_FROM?: string;
  /** App Store environments to accept, comma-separated. Default "Production"; add "Sandbox" while testing. */
  APPSTORE_ENVIRONMENTS?: string;
  /** "log" prints codes to the Worker log instead of emailing. Local development only. */
  MAIL_MODE?: string;
}

/** Things the tests replace. */
export interface Deps {
  fetch: typeof fetch;
  now: () => number;
  /** Sends a sign-in email. Throws if email is not configured. */
  sendEmail: (env: Env, to: string, subject: string, text: string) => Promise<void>;
  /** Tests pin their own root certificate here; production uses Apple's (config.APPLE_ROOT_SHA256). */
  appleRootSha256?: string[];
}
