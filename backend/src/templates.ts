export interface TemplateRow {
  id: string;
  version: number;
  json: string;
}

/** Body of GET /v1/templates. `templates` is empty when the caller already has the newest version. */
export async function getTemplates(db: D1Database, sinceVersion: number): Promise<{ version: number; templates: unknown[] }> {
  const { results } = await db.prepare("SELECT id, version, json FROM templates WHERE active = 1 ORDER BY id").all<TemplateRow>();
  const version = results.reduce((max, r) => Math.max(max, r.version), 0);
  const templates = sinceVersion >= version && version > 0 ? [] : results.map((r) => JSON.parse(r.json));
  return { version, templates };
}
