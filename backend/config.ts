// Config for the backend (PRD section 11): one place, no hard-coded values elsewhere.
// Values marked "placeholder" are the PRD's suggestions; set them from measured cost in Phase 3.
export const config = {
  /** Credits (one credit = one prompt run) the Free plan renews with every month. */
  FREE_MONTHLY_CREDITS: 21,
  /** Runs per month for Pro (monthly and yearly). */
  PRO_MONTHLY_RUNS: 1000,

  /** Input cap per run. Placeholder. Used by /v1/run (Phase 3). */
  MAX_INPUT_CHARS: 12_000,
  /** Output cap per run. Placeholder. Used by /v1/run (Phase 3). */
  MAX_OUTPUT_TOKENS: 1_024,
  /** Model for templates without one. Placeholder: a Haiku-class model; confirm the id in Anthropic's docs. */
  DEFAULT_MODEL: "claude-haiku-4-5",
  /** Runs charged for a larger model (NFR-6). Placeholder: set it from the measured cost ratio. */
  EXPENSIVE_MODEL_WEIGHT: 4,
  /** A model counts as larger when its id starts with one of these. The default model (Haiku class) is not listed. */
  EXPENSIVE_MODEL_PREFIXES: ["claude-opus", "claude-sonnet", "claude-fable"],
  RATE_LIMIT_PER_MIN: 20,
  MAX_CONCURRENT_STREAMS: 2,
  UPSTREAM_TIMEOUT_S: 60,

  /** Onboarding funnel events (anonymous): events per request, and the most one install may ever log. */
  EVENTS_PER_REQUEST: 20,
  EVENTS_PER_INSTALL: 500,

  /** Email sign-in codes. */
  EMAIL_CODE_TTL_S: 600,
  EMAIL_CODE_MAX_ATTEMPTS: 5,
  /** Codes sent to one address per 15 minutes. */
  EMAIL_CODES_PER_WINDOW: 3,

  /** Bundle id the App Store transactions must belong to. */
  BUNDLE_ID: "app.permylast",
  /** Months of updates a Power user (lifetime) purchase or upgrade buys. */
  UPDATE_WINDOW_MONTHS: 12,
  /**
   * Each upgrade costs half the previous purchase: base price, then 50%, 25%, ... Stores sell fixed prices, so every
   * step is its own product (`lifetime_upgrade_1` ... `_N`). Past step N the last product is offered again.
   */
  UPGRADE_TIERS: 3,
  /** Days of access kept while a subscription payment is being retried (FR-P5). */
  GRACE_DAYS: 7,
  /** SHA-256 of Apple Root CA - G3 (DER). App Store signatures must chain to it. Source: apple.com/certificateauthority. */
  APPLE_ROOT_SHA256: "63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179",

  /** Session lifetimes. */
  ACCESS_TOKEN_TTL_S: 3600,
  REFRESH_TOKEN_TTL_S: 60 * 60 * 24 * 90,
} as const;
