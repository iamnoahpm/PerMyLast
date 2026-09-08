import { describe, it, expect } from 'vitest';
import { LANGUAGES, findLanguages } from './renderer/languages.js';

describe('LANGUAGES', () => {
  it('is sorted A-Z by name', () => {
    const names = LANGUAGES.map((l) => l.name);
    const sorted = [...names].sort((a, b) => a.localeCompare(b));
    expect(names).toEqual(sorted);
  });

  it('gives every language a flag', () => {
    expect(LANGUAGES.every((l) => typeof l.flag === 'string' && l.flag.length > 0)).toBe(true);
  });
});

describe('findLanguages', () => {
  it('matches by substring, case-insensitively', () => {
    const results = findLanguages('viet');
    expect(results.map((l) => l.name)).toContain('Vietnamese');
  });

  it('matches a substring anywhere in the name, not just the start', () => {
    const results = findLanguages('ese');
    const names = results.map((l) => l.name);
    expect(names).toContain('Japanese');
    expect(names).toContain('Vietnamese');
    expect(names).toContain('Chinese (Simplified)');
  });

  it('returns results already sorted A-Z', () => {
    const results = findLanguages('an');
    const names = results.map((l) => l.name);
    expect(names).toEqual([...names].sort((a, b) => a.localeCompare(b)));
  });

  it('returns an empty array for a blank query', () => {
    expect(findLanguages('')).toEqual([]);
    expect(findLanguages('   ')).toEqual([]);
  });

  it('respects an optional limit', () => {
    expect(findLanguages('a', 3)).toHaveLength(3);
  });
});
