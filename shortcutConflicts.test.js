import { describe, it, expect } from 'vitest';
import { findShortcutConflict } from './renderer/shortcutConflicts.js';

describe('findShortcutConflict', () => {
  it('flags a known macOS system shortcut regardless of modifier order', () => {
    expect(findShortcutConflict('Command+Q')).toMatchObject({ scope: 'system' });
    expect(findShortcutConflict('Q+Command')).toMatchObject({ scope: 'system' });
  });

  it('flags a known common-app shortcut', () => {
    const result = findShortcutConflict('Command+Shift+S');
    expect(result).toMatchObject({ scope: 'app', app: expect.stringContaining('TextEdit') });
  });

  it('returns null for a combo with no known conflict', () => {
    expect(findShortcutConflict('Control+Command+Shift+S')).toBeNull();
  });

  it('respects the scope filter', () => {
    expect(findShortcutConflict('Command+Q', 'app')).toBeNull();
    expect(findShortcutConflict('Command+Shift+S', 'system')).toBeNull();
  });

  it('is case-insensitive', () => {
    expect(findShortcutConflict('command+q')).toMatchObject({ scope: 'system' });
  });
});
