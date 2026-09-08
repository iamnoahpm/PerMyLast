// Single source of truth for the Wartime/Peacetime configurator (Advanced
// tab). Content lives here, not in settings.html, so editing a row/why
// sentence never requires touching rendering logic. Paraphrased from Gergely
// Orosz, "Wartime" vs "Peacetime" at Tech Companies (The Pragmatic Engineer,
// 28 Mar 2023).
const WARTIME_PEACETIME_CONFIG = {
  wartime: {
    groups: [
      {
        title: 'Business environment',
        rows: [
          ['Business pressure', 'Existential. The company is fending off a real threat to its survival or position.'],
          ['Focus on competition', 'Preoccupied with rivals; every move is read against what competitors are doing.'],
          ['Top priority for dev teams', 'Ship quickly. Speed beats polish.'],
          ['Deadlines', 'Non-negotiable. Missing one is treated as a real problem.']
        ]
      },
      {
        title: 'How work gets done',
        rows: [
          ['Meetings', 'Kept to a minimum in favour of doing the work. "Done is better than perfect."'],
          ['Conflict', 'Acceptable, even encouraged, when it helps things move faster.'],
          ['Process', "Broken or skipped whenever it's slowing the outcome down."],
          ['Scope', 'No room for "nice to have" work; only what the business needs right now.']
        ]
      },
      {
        title: 'Culture and tone',
        rows: [
          ['Workplace frustration', 'Stress and overwhelm are treated as normal, with little repercussion for showing it.'],
          ['Work-life balance', 'Not a priority. Long hours are expected during pushes.'],
          ['Decision-making', 'Fast and decisive.'],
          ['Leadership visibility', 'Highly visible, involved down to fine detail.'],
          ['Leadership style', 'Raw and direct, sometimes at the edge of professional norms.'],
          ['Unpopular decisions', 'Made frequently when leadership sees them as necessary.']
        ]
      },
      {
        title: 'How to operate well in this mode',
        rows: [
          ['Pace', 'Move fast, but pace yourself. Constant sprinting risks burnout.'],
          ['Conflict', "Don't take it personally; it's usually the pressure talking, not the person."],
          ['Politics', 'Standing with the CEO or CTO matters more than broad alliance-building.'],
          ['Priorities', 'Work only on what the business needs right now; long-term bets can wait.'],
          ['Biggest risk', "Burnout, both your own and your team's."]
        ]
      }
    ],
    why: 'Wartime works when a company faces a genuine existential threat: a competitor overtaking it, collapsing market share, or running out of money. It trades sustainability for speed.'
  },
  peacetime: {
    groups: [
      {
        title: 'Business environment',
        rows: [
          ['Business pressure', "Little to none. The company holds a solid position and isn't fighting to survive."],
          ['Focus on competition', "No need to be obsessed with what rivals are doing."],
          ['Top priority for dev teams', 'Ship thoroughly validated features, not just fast ones.'],
          ['Deadlines', 'A bonus to hit, not a must.']
        ]
      },
      {
        title: 'How work gets done',
        rows: [
          ['Meetings', 'Common and expected, to keep everyone aligned. "Alignment matters more than speed."'],
          ['Conflict', 'Discouraged, even where it might help things move faster.'],
          ['Process', 'Followed; it exists for a reason.'],
          ['Scope', 'Room for "nice to have" work and longer-term investment.']
        ]
      },
      {
        title: 'Culture and tone',
        rows: [
          ['Workplace frustration', 'Not acceptable if it becomes unprofessional; there can be real repercussions.'],
          ['Work-life balance', 'A real focus, often backed by explicit WLB-friendly policies.'],
          ['Decision-making', 'Aims for common ground rather than fast calls.'],
          ['Leadership visibility', 'Less visible day to day, not involved in most detail.'],
          ['Leadership style', 'Measured and professional.'],
          ['Unpopular decisions', 'Avoided; little appetite to make any group unhappy.']
        ]
      },
      {
        title: 'How to operate well in this mode',
        rows: [
          ['Pace', 'Sustainable by design, but watch for stagnation or boredom.'],
          ['Conflict', "Figure out why it's happening; it's not welcomed here the way it is in wartime."],
          ['Politics', 'Build alliances across teams; they help you get things done and can help your career.'],
          ['Priorities', 'Also invest in longer-term initiatives, not just immediate needs.'],
          ['Biggest risk', 'Stagnation or boredom, the mirror image of wartime burnout.']
        ]
      }
    ],
    why: 'Peacetime tends to follow a stabilising event: an IPO, a strong quarter, or a deliberate reset by leadership. It trades some speed for a working environment people can sustain.'
  }
};

function buildWartimePeacetimeExportText(mode) {
  const data = WARTIME_PEACETIME_CONFIG[mode];
  if (!data) throw new Error('Unknown mode: ' + mode);
  const modeLabel = mode.toUpperCase();
  const lines = [
    `COMPANY OPERATING MODE: ${modeLabel}`,
    '',
    `Treat the company as currently operating in ${modeLabel} mode. When you give advice, feedback, or suggestions, reason and respond according to the priorities below rather than generic best practice.`,
    ''
  ];
  data.groups.forEach((group, i) => {
    lines.push(`${group.title}:`);
    group.rows.forEach(([label, value]) => lines.push(`- ${label}: ${value}`));
    if (i < data.groups.length - 1) lines.push('');
  });
  lines.push('', `Context: ${data.why}`);
  return lines.join('\n');
}

// Plain <script src> in the renderer (no bundler, no Node require there) —
// expose as a global — while staying importable from vitest/Node for tests.
if (typeof window !== 'undefined') {
  window.WARTIME_PEACETIME_CONFIG = WARTIME_PEACETIME_CONFIG;
  window.buildWartimePeacetimeExportText = buildWartimePeacetimeExportText;
}
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { WARTIME_PEACETIME_CONFIG, buildWartimePeacetimeExportText };
}
