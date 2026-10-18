// Generated from the Electron app's renderer/wartimePeacetime.js.
// Paraphrased from Gergely Orosz, "Wartime" vs "Peacetime" at Tech Companies
// (The Pragmatic Engineer, 28 Mar 2023).
import Foundation

public enum OperatingMode: String, CaseIterable, Sendable {
    case wartime, peacetime
}

public struct OperatingModeRow: Equatable, Sendable {
    public let label: String
    public let value: String
}

public struct OperatingModeGroup: Equatable, Sendable {
    public let title: String
    public let rows: [OperatingModeRow]
}

public struct OperatingModeProfile: Equatable, Sendable {
    public let groups: [OperatingModeGroup]
    public let why: String
}

public enum WartimePeacetime {
    public static func profile(for mode: OperatingMode) -> OperatingModeProfile {
        switch mode {
        case .wartime: return wartime
        case .peacetime: return peacetime
        }
    }

    public static let wartime = OperatingModeProfile(
        groups: [
            OperatingModeGroup(title: "Business environment", rows: [
                OperatingModeRow(label: "Business pressure", value: "Existential. The company is fending off a real threat to its survival or position."),
                OperatingModeRow(label: "Focus on competition", value: "Preoccupied with rivals; every move is read against what competitors are doing."),
                OperatingModeRow(label: "Top priority for dev teams", value: "Ship quickly. Speed beats polish."),
                OperatingModeRow(label: "Deadlines", value: "Non-negotiable. Missing one is treated as a real problem.")
            ]),
            OperatingModeGroup(title: "How work gets done", rows: [
                OperatingModeRow(label: "Meetings", value: "Kept to a minimum in favour of doing the work. \"Done is better than perfect.\""),
                OperatingModeRow(label: "Conflict", value: "Acceptable, even encouraged, when it helps things move faster."),
                OperatingModeRow(label: "Process", value: "Broken or skipped whenever it's slowing the outcome down."),
                OperatingModeRow(label: "Scope", value: "No room for \"nice to have\" work; only what the business needs right now.")
            ]),
            OperatingModeGroup(title: "Culture and tone", rows: [
                OperatingModeRow(label: "Workplace frustration", value: "Stress and overwhelm are treated as normal, with little repercussion for showing it."),
                OperatingModeRow(label: "Work-life balance", value: "Not a priority. Long hours are expected during pushes."),
                OperatingModeRow(label: "Decision-making", value: "Fast and decisive."),
                OperatingModeRow(label: "Leadership visibility", value: "Highly visible, involved down to fine detail."),
                OperatingModeRow(label: "Leadership style", value: "Raw and direct, sometimes at the edge of professional norms."),
                OperatingModeRow(label: "Unpopular decisions", value: "Made frequently when leadership sees them as necessary.")
            ]),
            OperatingModeGroup(title: "How to operate well in this mode", rows: [
                OperatingModeRow(label: "Pace", value: "Move fast, but pace yourself. Constant sprinting risks burnout."),
                OperatingModeRow(label: "Conflict", value: "Don't take it personally; it's usually the pressure talking, not the person."),
                OperatingModeRow(label: "Politics", value: "Standing with the CEO or CTO matters more than broad alliance-building."),
                OperatingModeRow(label: "Priorities", value: "Work only on what the business needs right now; long-term bets can wait."),
                OperatingModeRow(label: "Biggest risk", value: "Burnout, both your own and your team's.")
            ])
        ],
        why: "Wartime works when a company faces a genuine existential threat: a competitor overtaking it, collapsing market share, or running out of money. It trades sustainability for speed."
    )

    public static let peacetime = OperatingModeProfile(
        groups: [
            OperatingModeGroup(title: "Business environment", rows: [
                OperatingModeRow(label: "Business pressure", value: "Little to none. The company holds a solid position and isn't fighting to survive."),
                OperatingModeRow(label: "Focus on competition", value: "No need to be obsessed with what rivals are doing."),
                OperatingModeRow(label: "Top priority for dev teams", value: "Ship thoroughly validated features, not just fast ones."),
                OperatingModeRow(label: "Deadlines", value: "A bonus to hit, not a must.")
            ]),
            OperatingModeGroup(title: "How work gets done", rows: [
                OperatingModeRow(label: "Meetings", value: "Common and expected, to keep everyone aligned. \"Alignment matters more than speed.\""),
                OperatingModeRow(label: "Conflict", value: "Discouraged, even where it might help things move faster."),
                OperatingModeRow(label: "Process", value: "Followed; it exists for a reason."),
                OperatingModeRow(label: "Scope", value: "Room for \"nice to have\" work and longer-term investment.")
            ]),
            OperatingModeGroup(title: "Culture and tone", rows: [
                OperatingModeRow(label: "Workplace frustration", value: "Not acceptable if it becomes unprofessional; there can be real repercussions."),
                OperatingModeRow(label: "Work-life balance", value: "A real focus, often backed by explicit WLB-friendly policies."),
                OperatingModeRow(label: "Decision-making", value: "Aims for common ground rather than fast calls."),
                OperatingModeRow(label: "Leadership visibility", value: "Less visible day to day, not involved in most detail."),
                OperatingModeRow(label: "Leadership style", value: "Measured and professional."),
                OperatingModeRow(label: "Unpopular decisions", value: "Avoided; little appetite to make any group unhappy.")
            ]),
            OperatingModeGroup(title: "How to operate well in this mode", rows: [
                OperatingModeRow(label: "Pace", value: "Sustainable by design, but watch for stagnation or boredom."),
                OperatingModeRow(label: "Conflict", value: "Figure out why it's happening; it's not welcomed here the way it is in wartime."),
                OperatingModeRow(label: "Politics", value: "Build alliances across teams; they help you get things done and can help your career."),
                OperatingModeRow(label: "Priorities", value: "Also invest in longer-term initiatives, not just immediate needs."),
                OperatingModeRow(label: "Biggest risk", value: "Stagnation or boredom, the mirror image of wartime burnout.")
            ])
        ],
        why: "Peacetime tends to follow a stabilising event: an IPO, a strong quarter, or a deliberate reset by leadership. It trades some speed for a working environment people can sustain."
    )

    /// Plain-text block appended to prompts so the model reasons in the chosen mode.
    public static func exportText(for mode: OperatingMode) -> String {
        let data = profile(for: mode)
        let label = mode.rawValue.uppercased()
        var lines: [String] = [
            "COMPANY OPERATING MODE: \(label)",
            "",
            "Treat the company as currently operating in \(label) mode. When you give advice, feedback, or suggestions, reason and respond according to the priorities below rather than generic best practice.",
            ""
        ]
        for (i, group) in data.groups.enumerated() {
            lines.append("\(group.title):")
            for row in group.rows { lines.append("- \(row.label): \(row.value)") }
            if i < data.groups.count - 1 { lines.append("") }
        }
        lines.append("")
        lines.append("Context: \(data.why)")
        return lines.joined(separator: "\n")
    }
}
