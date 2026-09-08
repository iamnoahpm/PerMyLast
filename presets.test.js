import { describe, it, expect } from 'vitest';
import {
  DEFAULT_MODES, DEFAULT_PRESETS, validateLabel, normalizeCategory, normalizePresets,
  upsertPreset, deletePreset, incrementUses, applyPresetEdits,
  addMode, renameMode, deleteMode, reorderModes, buildClaudeRequest
} from './presets.js';

describe('validateLabel', () => {
  it('rejects blank/whitespace-only labels', () => {
    expect(validateLabel('')).toBe(false);
    expect(validateLabel('   ')).toBe(false);
  });

  it('accepts non-blank labels', () => {
    expect(validateLabel('My Tone')).toBe(true);
  });
});

describe('normalizeCategory', () => {
  it('passes through a valid category', () => {
    expect(normalizeCategory('Reply', DEFAULT_MODES)).toBe('Reply');
  });

  it('falls back case-insensitively to a differently-cased known mode', () => {
    expect(normalizeCategory('reply', DEFAULT_MODES)).toBe('Reply');
  });

  it('falls back to the first mode for anything unknown', () => {
    expect(normalizeCategory('urgent', DEFAULT_MODES)).toBe('Reply');
    expect(normalizeCategory(undefined, DEFAULT_MODES)).toBe('Reply');
  });

  it('defaults to DEFAULT_MODES when no modes list is given', () => {
    expect(normalizeCategory('Write')).toBe('Write');
    expect(normalizeCategory('nope')).toBe('Reply');
  });

  it('respects a custom, user-renamed modes list', () => {
    const modes = ['Work', 'Personal'];
    expect(normalizeCategory('Personal', modes)).toBe('Personal');
    expect(normalizeCategory('Write', modes)).toBe('Work');
  });
});

describe('DEFAULT_PRESETS', () => {
  it('covers all default modes', () => {
    const categories = new Set(DEFAULT_PRESETS.map((p) => p.category));
    expect(categories).toEqual(new Set(DEFAULT_MODES));
  });

  it('has exactly one default per mode', () => {
    DEFAULT_MODES.forEach((mode) => {
      const defaults = DEFAULT_PRESETS.filter((p) => p.category === mode && p.isDefault);
      expect(defaults).toHaveLength(1);
    });
  });
});

describe('normalizePresets', () => {
  it('fills in category/blurb/isDefault/tone/originalPrompt/uses for legacy presets missing those fields', () => {
    const legacy = [{ label: 'Old Tone', prompt: 'Be old:', isEmail: false }];
    const result = normalizePresets(legacy, DEFAULT_MODES);
    expect(result[0]).toEqual({ label: 'Old Tone', category: 'Reply', icon: '', blurb: '', tone: '', prompt: 'Be old:', originalPrompt: 'Be old:', uses: 0, isEmail: false, isDefault: true, requiresMotherLanguage: false });
  });

  it('demotes all but the first isDefault:true within a category', () => {
    const list = [
      { label: 'A', category: 'Write', prompt: 'a', isDefault: true },
      { label: 'B', category: 'Write', prompt: 'b', isDefault: true }
    ];
    const result = normalizePresets(list, DEFAULT_MODES);
    expect(result.filter((p) => p.isDefault)).toHaveLength(1);
    expect(result.find((p) => p.isDefault).label).toBe('A');
  });

  it('promotes the first preset of a category to default when none is marked', () => {
    const list = [
      { label: 'A', category: 'Write', prompt: 'a' },
      { label: 'B', category: 'Write', prompt: 'b' }
    ];
    const result = normalizePresets(list, DEFAULT_MODES);
    expect(result.find((p) => p.isDefault).label).toBe('A');
  });

  it('supports a tab with zero presets (a freshly created, not-yet-populated tab)', () => {
    const result = normalizePresets(DEFAULT_PRESETS, [...DEFAULT_MODES, 'New tab']);
    expect(result.some((p) => p.category === 'New tab')).toBe(false);
    expect(result).toHaveLength(DEFAULT_PRESETS.length);
  });
});

describe('upsertPreset', () => {
  it('appends a new label under its category', () => {
    const next = upsertPreset(DEFAULT_PRESETS, { label: 'Blunt', category: 'Write', blurb: 'No sugarcoating', prompt: 'Be blunt:', isEmail: false }, DEFAULT_MODES);
    const added = next.find((p) => p.label === 'Blunt');
    expect(added).toMatchObject({ label: 'Blunt', category: 'Write', blurb: 'No sugarcoating', prompt: 'Be blunt:', isEmail: false });
  });

  it('overwrites an existing preset in place (last write wins)', () => {
    const overwritten = upsertPreset(DEFAULT_PRESETS, { label: 'Email', category: 'Reply', prompt: 'New email tone:', isEmail: true }, DEFAULT_MODES);
    const found = overwritten.find((p) => p.label === 'Email');
    expect(found.prompt).toBe('New email tone:');
    expect(overwritten).toHaveLength(DEFAULT_PRESETS.length);
  });

  it('still guarantees exactly one default per category after inserting', () => {
    const next = upsertPreset(DEFAULT_PRESETS, { label: 'Blunt', category: 'Write', prompt: 'Be blunt:' }, DEFAULT_MODES);
    expect(next.filter((p) => p.category === 'Write' && p.isDefault)).toHaveLength(1);
  });
});

describe('icon (user-editable, unlike isEmail/requiresMotherLanguage)', () => {
  it('ships a default icon on every built-in preset', () => {
    expect(DEFAULT_PRESETS.every((p) => typeof p.icon === 'string' && p.icon.length > 0)).toBe(true);
  });

  it('can be customized via applyPresetEdits', () => {
    const incoming = DEFAULT_PRESETS.map((p) => p.label === 'Rewrite like Native'
      ? { originalLabel: p.label, label: p.label, prompt: p.prompt, blurb: p.blurb, isDefault: p.isDefault, icon: '🪄' }
      : { originalLabel: p.label, label: p.label, prompt: p.prompt, blurb: p.blurb, isDefault: p.isDefault, icon: p.icon });
    const result = applyPresetEdits(DEFAULT_PRESETS, incoming, DEFAULT_MODES);
    expect(result.find((p) => p.label === 'Rewrite like Native').icon).toBe('🪄');
  });

  it('can be removed entirely (empty string is a valid, intentional value)', () => {
    const incoming = DEFAULT_PRESETS.map((p) => p.label === 'Rewrite like Native'
      ? { originalLabel: p.label, label: p.label, prompt: p.prompt, blurb: p.blurb, isDefault: p.isDefault, icon: '' }
      : { originalLabel: p.label, label: p.label, prompt: p.prompt, blurb: p.blurb, isDefault: p.isDefault, icon: p.icon });
    const result = applyPresetEdits(DEFAULT_PRESETS, incoming, DEFAULT_MODES);
    expect(result.find((p) => p.label === 'Rewrite like Native').icon).toBe('');
  });

  it('falls back to the stored icon when incoming omits it', () => {
    const incoming = DEFAULT_PRESETS.map((p) => ({ originalLabel: p.label, label: p.label, prompt: p.prompt, blurb: p.blurb, isDefault: p.isDefault }));
    const result = applyPresetEdits(DEFAULT_PRESETS, incoming, DEFAULT_MODES);
    expect(result.find((p) => p.label === 'Rewrite like Native').icon).toBe(DEFAULT_PRESETS.find((p) => p.label === 'Rewrite like Native').icon);
  });
});

describe('deletePreset', () => {
  it('removes a non-default preset', () => {
    const after = deletePreset(DEFAULT_PRESETS, 'Fix Grammar', DEFAULT_MODES);
    expect(after.find((p) => p.label === 'Fix Grammar')).toBeUndefined();
    expect(after).toHaveLength(DEFAULT_PRESETS.length - 1);
  });

  it('is a no-op for the current default of a category', () => {
    const after = deletePreset(DEFAULT_PRESETS, 'Rewrite like Native', DEFAULT_MODES);
    expect(after).toEqual(DEFAULT_PRESETS);
  });

  it('is a no-op if it is the last preset in its category, even if not marked default', () => {
    const onlyOneUnderstand = DEFAULT_PRESETS.filter((p) => p.category !== 'Understand' || p.label === 'Translate');
    const after = deletePreset(onlyOneUnderstand, 'Translate', DEFAULT_MODES);
    expect(after).toEqual(onlyOneUnderstand);
  });

  it('is a no-op for an unknown label', () => {
    const after = deletePreset(DEFAULT_PRESETS, 'Does Not Exist', DEFAULT_MODES);
    expect(after).toEqual(DEFAULT_PRESETS);
  });
});

describe('applyPresetEdits', () => {
  it('reorders presets to match the incoming order', () => {
    const incoming = [...DEFAULT_PRESETS].reverse().map((p) => ({ originalLabel: p.label, label: p.label, prompt: p.prompt, blurb: p.blurb, isDefault: p.isDefault }));
    const result = applyPresetEdits(DEFAULT_PRESETS, incoming, DEFAULT_MODES);
    expect(result.map((p) => p.label)).toEqual([...DEFAULT_PRESETS].reverse().map((p) => p.label));
  });

  it('applies an edited prompt and blurb while keeping category/isEmail from stored', () => {
    const incoming = DEFAULT_PRESETS.map((p) => p.label === 'Rewrite like Native'
      ? { originalLabel: p.label, label: p.label, prompt: 'New rewrite prompt:', blurb: 'New blurb', isDefault: p.isDefault }
      : { originalLabel: p.label, label: p.label, prompt: p.prompt, blurb: p.blurb, isDefault: p.isDefault });
    const result = applyPresetEdits(DEFAULT_PRESETS, incoming, DEFAULT_MODES);
    const rewrite = result.find((p) => p.label === 'Rewrite like Native');
    expect(rewrite).toMatchObject({ label: 'Rewrite like Native', category: 'Write', blurb: 'New blurb', prompt: 'New rewrite prompt:', isEmail: false });
  });

  it('renames a preset, matched by originalLabel, without touching its category', () => {
    const incoming = DEFAULT_PRESETS.map((p) => p.label === 'Rewrite like Native'
      ? { originalLabel: p.label, label: 'Reword', prompt: p.prompt, blurb: p.blurb, isDefault: p.isDefault }
      : { originalLabel: p.label, label: p.label, prompt: p.prompt, blurb: p.blurb, isDefault: p.isDefault });
    const result = applyPresetEdits(DEFAULT_PRESETS, incoming, DEFAULT_MODES);
    expect(result.find((p) => p.label === 'Rewrite like Native')).toBeUndefined();
    expect(result.find((p) => p.label === 'Reword')).toMatchObject({ category: 'Write', isDefault: true });
  });

  it('moves the default flag when the incoming data marks a different preset as default', () => {
    const incoming = DEFAULT_PRESETS.map((p) => ({
      originalLabel: p.label, label: p.label, prompt: p.prompt, blurb: p.blurb,
      isDefault: p.label === 'Fix Grammar' ? true : (p.category === 'Write' ? false : p.isDefault)
    }));
    const result = applyPresetEdits(DEFAULT_PRESETS, incoming, DEFAULT_MODES);
    expect(result.find((p) => p.label === 'Fix Grammar').isDefault).toBe(true);
    expect(result.find((p) => p.label === 'Rewrite like Native').isDefault).toBe(false);
    expect(result.filter((p) => p.category === 'Write' && p.isDefault)).toHaveLength(1);
  });

  it('ignores unknown originalLabels', () => {
    const incoming = [
      { originalLabel: 'Rewrite like Native', label: 'Rewrite like Native', prompt: 'x', blurb: '', isDefault: true },
      { originalLabel: 'Ghost Preset', label: 'Ghost Preset', prompt: 'should be dropped' }
    ];
    const result = applyPresetEdits(DEFAULT_PRESETS, incoming, DEFAULT_MODES);
    expect(result.find((p) => p.label === 'Ghost Preset')).toBeUndefined();
  });

  it('appends any stored label missing from incoming, so an edit pass never loses a preset', () => {
    const incoming = DEFAULT_PRESETS.filter((p) => p.label !== 'Explain').map((p) => ({ originalLabel: p.label, label: p.label, prompt: p.prompt, blurb: p.blurb, isDefault: p.isDefault }));
    const result = applyPresetEdits(DEFAULT_PRESETS, incoming, DEFAULT_MODES);
    expect(result.find((p) => p.label === 'Explain')).toMatchObject(DEFAULT_PRESETS.find((p) => p.label === 'Explain'));
    expect(result).toHaveLength(DEFAULT_PRESETS.length);
  });
});

describe('originalPrompt (baseline for the "Edited" pill / Reset to original)', () => {
  it('is set to the prompt itself on every built-in preset', () => {
    DEFAULT_PRESETS.forEach((p) => expect(p.originalPrompt).toBe(p.prompt));
  });

  it('is preserved through upsertPreset when overwriting an existing preset', () => {
    const overwritten = upsertPreset(DEFAULT_PRESETS, { label: 'Email', category: 'Reply', prompt: 'New email tone:', isEmail: true }, DEFAULT_MODES);
    const found = overwritten.find((p) => p.label === 'Email');
    expect(found.prompt).toBe('New email tone:');
    expect(found.originalPrompt).toBe(DEFAULT_PRESETS.find((p) => p.label === 'Email').originalPrompt);
  });

  it('is set once, at creation, for a brand-new preset', () => {
    const next = upsertPreset(DEFAULT_PRESETS, { label: 'Blunt', category: 'Write', prompt: 'Be blunt:' }, DEFAULT_MODES);
    expect(next.find((p) => p.label === 'Blunt').originalPrompt).toBe('Be blunt:');
  });

  it('is preserved through applyPresetEdits when the live prompt changes', () => {
    const incoming = DEFAULT_PRESETS.map((p) => p.label === 'Rewrite like Native'
      ? { originalLabel: p.label, label: p.label, prompt: 'Edited prompt', blurb: p.blurb, isDefault: p.isDefault }
      : { originalLabel: p.label, label: p.label, prompt: p.prompt, blurb: p.blurb, isDefault: p.isDefault });
    const result = applyPresetEdits(DEFAULT_PRESETS, incoming, DEFAULT_MODES);
    const edited = result.find((p) => p.label === 'Rewrite like Native');
    expect(edited.prompt).toBe('Edited prompt');
    expect(edited.originalPrompt).toBe(DEFAULT_PRESETS.find((p) => p.label === 'Rewrite like Native').originalPrompt);
  });
});

describe('incrementUses', () => {
  it('bumps the matching preset\'s usage count by one', () => {
    const result = incrementUses(DEFAULT_PRESETS, 'Email');
    expect(result.find((p) => p.label === 'Email').uses).toBe(1);
  });

  it('does not affect other presets', () => {
    const result = incrementUses(DEFAULT_PRESETS, 'Email');
    expect(result.find((p) => p.label === 'Message').uses).toBe(0);
  });

  it('is a no-op for an unknown label', () => {
    const result = incrementUses(DEFAULT_PRESETS, 'Does Not Exist');
    expect(result).toEqual(DEFAULT_PRESETS);
  });
});

describe('addMode', () => {
  it('appends "New tab" when that name is free', () => {
    expect(addMode(DEFAULT_MODES)).toEqual([...DEFAULT_MODES, 'New tab']);
  });

  it('appends "New tab 2", "New tab 3", ... when earlier names are taken', () => {
    const once = addMode(DEFAULT_MODES);
    const twice = addMode(once);
    expect(twice).toEqual([...DEFAULT_MODES, 'New tab', 'New tab 2']);
  });
});

describe('renameMode', () => {
  it('renames the tab and cascades onto every preset filed under it', () => {
    const result = renameMode(DEFAULT_MODES, DEFAULT_PRESETS, 'Write', 'Compose');
    expect(result.modes).toEqual(['Reply', 'Compose', 'Understand']);
    expect(result.presets.filter((p) => p.category === 'Compose')).toHaveLength(
      DEFAULT_PRESETS.filter((p) => p.category === 'Write').length
    );
    expect(result.presets.some((p) => p.category === 'Write')).toBe(false);
  });

  it('is a no-op (returns null) for a blank name', () => {
    expect(renameMode(DEFAULT_MODES, DEFAULT_PRESETS, 'Write', '   ')).toBeNull();
  });

  it('is a no-op (returns null) when the new name collides with a different existing tab', () => {
    expect(renameMode(DEFAULT_MODES, DEFAULT_PRESETS, 'Write', 'Reply')).toBeNull();
  });

  it('allows renaming to its own current name (no-op collision check should not fire)', () => {
    const result = renameMode(DEFAULT_MODES, DEFAULT_PRESETS, 'Write', 'Write');
    expect(result.modes).toEqual(DEFAULT_MODES);
  });

  it('is a no-op (returns null) for an unknown source tab', () => {
    expect(renameMode(DEFAULT_MODES, DEFAULT_PRESETS, 'Ghost', 'Whatever')).toBeNull();
  });
});

describe('deleteMode', () => {
  it('deletes the tab and every preset filed under it', () => {
    const result = deleteMode(DEFAULT_MODES, DEFAULT_PRESETS, 'Understand');
    expect(result.modes).toEqual(['Reply', 'Write']);
    expect(result.presets.some((p) => p.category === 'Understand')).toBe(false);
  });

  it('refuses (returns null) to delete the last remaining tab', () => {
    expect(deleteMode(['Solo'], [], 'Solo')).toBeNull();
  });

  it('is a no-op (returns null) for an unknown tab', () => {
    expect(deleteMode(DEFAULT_MODES, DEFAULT_PRESETS, 'Ghost')).toBeNull();
  });
});

describe('reorderModes', () => {
  it('reorders to match the given order', () => {
    expect(reorderModes(DEFAULT_MODES, ['Understand', 'Reply', 'Write'])).toEqual(['Understand', 'Reply', 'Write']);
  });

  it('appends any mode missing from the incoming order, so a reorder can never drop a tab', () => {
    expect(reorderModes(DEFAULT_MODES, ['Understand'])).toEqual(['Understand', 'Reply', 'Write']);
  });

  it('ignores unknown names in the incoming order', () => {
    expect(reorderModes(DEFAULT_MODES, ['Ghost', 'Understand', 'Reply', 'Write'])).toEqual(['Understand', 'Reply', 'Write']);
  });
});

describe('buildClaudeRequest', () => {
  it('selects the email system prompt when isEmail is true', () => {
    const { system, content } = buildClaudeRequest('Hi there', 'Reply to this email. Additional context: be firm', true);
    expect(system).toContain('email writing assistant');
    expect(content).toContain('Email to reply to:\nHi there');
    expect(content).toContain('Instructions: Reply to this email. Additional context: be firm');
  });

  it('selects the text-processing system prompt when isEmail is false', () => {
    const { system, content } = buildClaudeRequest('Hi there', 'Make this more professional:', false);
    expect(system).toContain('text processing assistant');
    expect(content).toBe('Make this more professional:\n\nText: Hi there');
  });
});
