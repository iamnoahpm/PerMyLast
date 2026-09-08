import { describe, it, expect } from 'vitest';
import { STRINGS, t } from './renderer/i18n.js';

describe('i18n STRINGS', () => {
  it('defines the same set of keys for every language', () => {
    const enKeys = Object.keys(STRINGS.en).sort();
    Object.keys(STRINGS).forEach((lang) => {
      expect(Object.keys(STRINGS[lang]).sort()).toEqual(enKeys);
    });
  });
});

describe('t', () => {
  it('returns the requested language string', () => {
    expect(t('vi', 'promptCaption')).toBe('Câu lệnh');
    expect(t('en', 'promptCaption')).toBe('Prompt');
  });

  it('falls back to English for an unknown language', () => {
    expect(t('fr', 'promptCaption')).toBe('Prompt');
  });

  it('substitutes {vars} into the template', () => {
    const result = t('en', 'sourcePlaceholder', { shortcut: '⌃⌘⇧S' });
    expect(result).toContain('⌃⌘⇧S');
    expect(result).not.toContain('{shortcut}');
  });
});
