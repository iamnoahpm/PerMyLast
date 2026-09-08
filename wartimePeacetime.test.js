import { describe, it, expect } from 'vitest';
import { WARTIME_PEACETIME_CONFIG, buildWartimePeacetimeExportText } from './renderer/wartimePeacetime.js';

describe('WARTIME_PEACETIME_CONFIG', () => {
  it('defines exactly four groups per mode, matching the spec', () => {
    expect(WARTIME_PEACETIME_CONFIG.wartime.groups).toHaveLength(4);
    expect(WARTIME_PEACETIME_CONFIG.peacetime.groups).toHaveLength(4);
  });

  it('gives both modes a why sentence', () => {
    expect(WARTIME_PEACETIME_CONFIG.wartime.why.length).toBeGreaterThan(0);
    expect(WARTIME_PEACETIME_CONFIG.peacetime.why.length).toBeGreaterThan(0);
  });
});

describe('buildWartimePeacetimeExportText', () => {
  it('starts with the mode header and instruction line', () => {
    const text = buildWartimePeacetimeExportText('wartime');
    expect(text).toMatch(/^COMPANY OPERATING MODE: WARTIME/);
    expect(text).toContain('Treat the company as currently operating in WARTIME mode');
  });

  it('includes every group title and row for the selected mode', () => {
    const text = buildWartimePeacetimeExportText('peacetime');
    WARTIME_PEACETIME_CONFIG.peacetime.groups.forEach((group) => {
      expect(text).toContain(group.title + ':');
      group.rows.forEach(([label, value]) => {
        expect(text).toContain(`- ${label}: ${value}`);
      });
    });
  });

  it('ends with the why sentence prefixed by "Context:"', () => {
    const text = buildWartimePeacetimeExportText('wartime');
    expect(text.trim().endsWith('Context: ' + WARTIME_PEACETIME_CONFIG.wartime.why)).toBe(true);
  });

  it('does not mix content between modes', () => {
    const wartimeText = buildWartimePeacetimeExportText('wartime');
    expect(wartimeText).not.toContain(WARTIME_PEACETIME_CONFIG.peacetime.why);
  });

  it('throws for an unknown mode', () => {
    expect(() => buildWartimePeacetimeExportText('transitioning')).toThrow();
  });
});
