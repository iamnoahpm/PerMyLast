// The "Help me" picker groups actions under tabs (see
// design_handoff_help_me_tabs/README.md and design_handoff_per_my_last/).
// Tabs — "modes" — are fully user-owned: renamable, addable, deletable, and
// reorderable via the Tone Presets editor in Settings. DEFAULT_MODES is only
// the seed for a fresh install; a preset's `category` field always names
// whichever mode it currently lives under.
const DEFAULT_MODES = ['Reply', 'Write', 'Understand'];

const DEFAULT_PRESETS = [
  { label: 'Email', category: 'Reply', icon: '📧', blurb: 'Workplace email reply in your tone', tone: 'Direct', prompt: 'You are an expert email writer who drafts clear, professional email replies for workplace contexts. Write the reply in a Direct tone.', isEmail: true, isDefault: true },
  { label: 'Message', category: 'Reply', icon: '💬', blurb: 'Short chat / DM reply', tone: 'Warm', prompt: 'Write a short, natural reply to this message. Keep it conversational and to the point.', isEmail: false, isDefault: false },
  { label: 'Rewrite like Native', category: 'Write', icon: '✍️', blurb: 'Clear, native English level', tone: 'Neutral', prompt: 'Rewrite this text like a native English.', isEmail: false, isDefault: true },
  { label: 'Rewrite Like Me', category: 'Write', icon: '🙋‍♂', blurb: 'Match my style, my English level', tone: 'Personal', prompt: 'Rewrite this text like me.', isEmail: false, isDefault: false },
  { label: 'Fix Grammar', category: 'Write', icon: '🔤', blurb: 'Spelling and grammar only', tone: 'Neutral', prompt: 'Fix grammar and spelling.', isEmail: false, isDefault: false },
  { label: 'Professional', category: 'Write', icon: '👔', blurb: 'Raise the register', tone: 'Formal', prompt: 'Make this more professional.', isEmail: false, isDefault: false },
  { label: 'Explain', category: 'Understand', icon: '💡', blurb: 'Plain-language summary', tone: 'Plain', prompt: 'Explain this in simple terms.', isEmail: false, isDefault: true },
  // {{motherLanguage}} is resolved client-side from the Settings "mother
  // language" field before sending — see resolvedPromptText/resolvedBlurbText
  // in index.html. The blurb carries the same token so the chip hint on the
  // main page shows the actual configured language, not a generic label.
  { label: 'Translate', category: 'Understand', icon: '🌐', blurb: 'Into {{motherLanguage}}', tone: 'Neutral', prompt: 'Translate this into {{motherLanguage}}', isEmail: false, isDefault: false, requiresMotherLanguage: true }
].map((p) => ({ ...p, originalPrompt: p.prompt, uses: 0 }));

function validateLabel(label) {
  return typeof label === 'string' && label.trim().length > 0;
}

function trimmed(s) {
  return typeof s === 'string' ? s.trim() : '';
}

// A category is valid as long as it names one of the caller's current modes.
// Falls back case-insensitively first (so presets saved under an older,
// differently-cased mode name — e.g. this app's own pre-user-owned-tabs
// 'reply'/'write'/'understand' — keep working without an explicit migration
// step), then to the first known mode if there's no match at all.
function normalizeCategory(category, modes) {
  const validModes = Array.isArray(modes) && modes.length ? modes : DEFAULT_MODES;
  if (validModes.includes(category)) return category;
  const ci = typeof category === 'string' ? validModes.find((m) => m.toLowerCase() === category.toLowerCase()) : null;
  return ci || validModes[0];
}

// The single place that enforces "every field has a valid shape" and "each
// category has exactly one isDefault:true (the first one found, in array
// order, if the incoming data has zero or more than one)". Every mutation
// below funnels its result through this before returning, so the invariant
// always holds regardless of what a caller passed in — including presets
// saved by an older version of the app that never had category/blurb/
// isDefault/tone/uses/originalPrompt at all.
function normalizePresets(list, modes) {
  const withFields = list.map((p) => ({
    label: p.label,
    category: normalizeCategory(p.category, modes),
    icon: typeof p.icon === 'string' ? p.icon : '',
    blurb: typeof p.blurb === 'string' ? p.blurb : '',
    tone: typeof p.tone === 'string' ? p.tone : '',
    prompt: p.prompt,
    // Set once, at creation, and preserved through every later edit — the
    // baseline the "Edited" pill and "Reset to original" compare against.
    // Falls back to the current prompt for records saved before this field
    // existed, so old data reads as "not edited" rather than crashing.
    originalPrompt: typeof p.originalPrompt === 'string' ? p.originalPrompt : p.prompt,
    uses: Number.isFinite(p.uses) ? p.uses : 0,
    isEmail: !!p.isEmail,
    isDefault: !!p.isDefault,
    requiresMotherLanguage: !!p.requiresMotherLanguage
  }));

  const defaultSeen = new Set();
  const result = withFields.map((p) => {
    if (p.isDefault && !defaultSeen.has(p.category)) {
      defaultSeen.add(p.category);
      return p;
    }
    return { ...p, isDefault: false };
  });
  result.forEach((p, i) => {
    if (defaultSeen.has(p.category)) return;
    if (result.findIndex((x) => x.category === p.category) === i) {
      result[i] = { ...p, isDefault: true };
      defaultSeen.add(p.category);
    }
  });
  return result;
}

// Creates a brand-new preset, or overwrites an existing one in place when
// `preset.label` already matches (last write wins) — the same path Settings'
// "+ Add" button and the main popup's inline "Save & overwrite" both use.
// On a genuine overwrite, `originalPrompt`/`uses` carry over from the stored
// record rather than resetting, since only a fresh insert should establish a
// new baseline / start the usage count at zero.
function upsertPreset(list, preset, modes) {
  const idx = list.findIndex((p) => p.label === preset.label.trim());
  const stored = idx === -1 ? null : list[idx];
  const entry = {
    label: preset.label.trim(),
    category: normalizeCategory(preset.category, modes),
    icon: typeof preset.icon === 'string' ? preset.icon.trim() : '',
    blurb: typeof preset.blurb === 'string' ? preset.blurb.trim() : '',
    tone: typeof preset.tone === 'string' ? preset.tone.trim() : (stored ? stored.tone : ''),
    prompt: preset.prompt,
    originalPrompt: stored ? stored.originalPrompt : preset.prompt,
    uses: stored ? stored.uses : 0,
    isEmail: !!preset.isEmail,
    isDefault: !!preset.isDefault,
    requiresMotherLanguage: !!preset.requiresMotherLanguage
  };
  let next;
  if (idx === -1) {
    next = [...list, entry];
  } else {
    next = list.slice();
    next[idx] = entry;
  }
  return normalizePresets(next, modes);
}

// A preset can't be deleted if it's the current default for its category, or
// if it's the only preset left in that category — every category must always
// have at least one selectable action so the picker is never empty. (A
// freshly created, not-yet-populated tab starting at zero presets is a
// different, valid state reached via addMode, not through this path.)
function deletePreset(list, label, modes) {
  const target = list.find((p) => p.label === label);
  if (!target) return list;
  if (target.isDefault) return list;
  const category = normalizeCategory(target.category, modes);
  const siblingCount = list.filter((p) => normalizeCategory(p.category, modes) === category).length;
  if (siblingCount <= 1) return list;
  return normalizePresets(list.filter((p) => p.label !== label), modes);
}

// Bumps a preset's usage counter after a successful send — best-effort only;
// an unknown label (e.g. the preset was deleted mid-flight) is a silent no-op
// rather than an error, since this is telemetry, not a correctness path.
function incrementUses(list, label) {
  return list.map((p) => (p.label === label ? { ...p, uses: (p.uses || 0) + 1 } : p));
}

// Applies a reorder and/or edits (prompt text, blurb, tone, label rename,
// default flag) from the Settings preset editor. `incoming` entries are
// matched against `stored` by `originalLabel` — the label as last persisted —
// so a pending rename can't break identity mid-edit; `label` carries the
// (possibly new) name to save. `category` and `isEmail` always come from
// `stored`: category isn't reassignable from this editor (a row lives in
// whichever tab's list it's dragged within, not moved between tabs — moving a
// preset to a different tab isn't supported), and isEmail isn't user-editable
// at all. `originalPrompt` and `uses` likewise always carry over from
// `stored` — editing a preset's live prompt must never touch its baseline or
// reset its usage count. Unknown `originalLabel`s in `incoming` are dropped;
// any stored label missing from `incoming` is appended at the end so an edit
// pass can never silently lose a preset.
function applyPresetEdits(stored, incoming, modes) {
  const storedByLabel = new Map(stored.map((p) => [p.label, p]));
  const seen = new Set();
  const result = [];
  incoming.forEach((entry) => {
    const base = storedByLabel.get(entry.originalLabel);
    if (!base) return;
    seen.add(entry.originalLabel);
    const promptValid = typeof entry.prompt === 'string' && entry.prompt.trim().length > 0;
    const labelValid = typeof entry.label === 'string' && entry.label.trim().length > 0;
    result.push({
      label: labelValid ? entry.label.trim() : base.label,
      category: normalizeCategory(base.category, modes),
      icon: typeof entry.icon === 'string' ? entry.icon.trim() : base.icon,
      blurb: typeof entry.blurb === 'string' ? entry.blurb.trim() : base.blurb,
      tone: typeof entry.tone === 'string' ? entry.tone.trim() : base.tone,
      prompt: promptValid ? entry.prompt : base.prompt,
      originalPrompt: base.originalPrompt,
      uses: base.uses,
      isEmail: base.isEmail,
      isDefault: !!entry.isDefault,
      requiresMotherLanguage: base.requiresMotherLanguage
    });
  });
  stored.forEach((p) => { if (!seen.has(p.label)) result.push(p); });
  return normalizePresets(result, modes);
}

// Appends a new, uniquely-named tab ("New tab", "New tab 2", ...) — the tab
// starts with zero presets until the user adds one via "+ Add to {name}".
function addMode(modes) {
  const base = 'New tab';
  if (!modes.includes(base)) return [...modes, base];
  let n = 2;
  while (modes.includes(`${base} ${n}`)) n++;
  return [...modes, `${base} ${n}`];
}

// Renames a tab, cascading the change onto every preset filed under it.
// Returns null (a no-op for the caller) if `to` is blank, unknown `from`, or
// collides with a different existing tab name — callers should leave state
// untouched when this returns null rather than assume success.
function renameMode(modes, presets, from, to) {
  const next = trimmed(to);
  if (!next || !modes.includes(from)) return null;
  if (next !== from && modes.includes(next)) return null;
  const nextModes = modes.map((m) => (m === from ? next : m));
  const nextPresets = presets.map((p) => (p.category === from ? { ...p, category: next } : p));
  return { modes: nextModes, presets: normalizePresets(nextPresets, nextModes) };
}

// Deletes a tab and every preset filed under it. Refuses to delete the last
// remaining tab (returns null) so there's always at least one place for
// presets to live, and refuses an unknown name.
function deleteMode(modes, presets, name) {
  if (modes.length <= 1 || !modes.includes(name)) return null;
  const nextModes = modes.filter((m) => m !== name);
  const nextPresets = presets.filter((p) => p.category !== name);
  return { modes: nextModes, presets: normalizePresets(nextPresets, nextModes) };
}

// Reorders tabs to match `orderedNames`. Any name from `modes` missing in
// `orderedNames` is appended at the end, and names in `orderedNames` that
// aren't in `modes` are ignored — a partial or stale list can never drop a
// tab or invent one.
function reorderModes(modes, orderedNames) {
  const known = new Set(modes);
  const next = orderedNames.filter((m) => known.has(m));
  modes.forEach((m) => { if (!next.includes(m)) next.push(m); });
  return next;
}

function buildClaudeRequest(text, prompt, isEmail) {
  if (isEmail) {
    return {
      system: 'You are an email writing assistant. Write ONLY the reply email content, no preamble. Start with the greeting and end with a sign-off. Professional yet friendly unless told otherwise.',
      content: 'Email to reply to:\n' + text + '\n\nInstructions: ' + prompt.trim()
    };
  }
  return {
    system: 'You are a text processing assistant. Respond ONLY with the processed result, no preamble, explanation, or surrounding quotation marks.',
    content: prompt + '\n\nText: ' + text
  };
}

module.exports = {
  DEFAULT_MODES, DEFAULT_PRESETS,
  validateLabel, normalizeCategory, normalizePresets, upsertPreset, deletePreset, incrementUses, applyPresetEdits,
  addMode, renameMode, deleteMode, reorderModes,
  buildClaudeRequest
};
