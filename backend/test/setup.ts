import { applyD1Migrations } from "cloudflare:test";
import { testEnv } from "./helpers.ts";

await applyD1Migrations(testEnv.DB, (testEnv as unknown as { TEST_MIGRATIONS: Parameters<typeof applyD1Migrations>[1] }).TEST_MIGRATIONS);
