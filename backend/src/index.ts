import { handleRequest } from "./app.ts";
import type { Env } from "./env.ts";

export default {
  fetch: (req: Request, env: Env, ctx: ExecutionContext) => handleRequest(req, env, undefined, ctx),
} satisfies ExportedHandler<Env>;
