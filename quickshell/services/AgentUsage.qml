pragma Singleton

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/*
 * AI coding-agent usage. Runs the collectors in ~/.local/bin/agent-usage-*
 * and exposes what they print.
 *
 * Each collector prints one JSON object and knows nothing about this service;
 * adding an agent means dropping in another collector. The collectors are
 * vendored from Omarchy (MIT) -- see the header of each script.
 *
 * `percent` is the share of the rate-limit window already used, and only exists
 * while the agent's sign-in is valid. When it is missing the service still has
 * the local transcript stats, which is why `todayPrompts` is exposed separately.
 */
Singleton {
    id: root

    // One entry per agent: { id, name, tier, percent, resetsAt, todayPrompts,
    //                        todayTokens, status, hasLimit }
    property var agents: []
    property bool checking: false

    // Highest limit percentage across agents that actually reported one.
    readonly property real maxPercent: {
        let m = -1;
        for (const a of agents)
            if (a.hasLimit && a.percent > m) m = a.percent;
        return m;
    }
    readonly property bool hasAnyLimit: maxPercent >= 0
    readonly property int todayPrompts: {
        let n = 0;
        for (const a of agents) n += a.todayPrompts;
        return n;
    }
    // Something worth showing at all.
    readonly property bool available: agents.length > 0 && (hasAnyLimit || todayPrompts > 0)

    function load() {}
    function refresh() {
        if (collectProc.running) return;
        collectProc.running = true;
    }

    // Both collectors in one shot; each prints one JSON object on its own line.
    // `|| true` keeps a failing collector from killing the whole pipeline: a
    // missing agent should just be absent, not break the widget.
    Process {
        id: collectProc
        command: ["bash", "-c",
            "for c in ~/.local/bin/agent-usage-*; do " +
            "  [ -x \"$c\" ] || continue; " +
            "  timeout 30 \"$c\" 2>/dev/null || true; " +
            "done"]
        onRunningChanged: root.checking = running
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of text.trim().split("\n")) {
                    if (!line.trim().startsWith("{")) continue;
                    try {
                        const d = JSON.parse(line);
                        // Pick the worst window: that is the one about to bite.
                        // The collector normalises to a 0..1 fraction (its
                        // normalize_utilization divides by 100), and the key is
                        // resetsAt, not resets_at. Getting either wrong is
                        // silent: 70% renders as 0.7% and the reset time simply
                        // never appears.
                        let pct = -1, resets = "";
                        for (const l of (d.limits ?? [])) {
                            const p = Number(l.percent) * 100;
                            if (!isNaN(p) && p > pct) { pct = p; resets = l.resetsAt ?? ""; }
                        }
                        out.push({
                            id: d.id ?? "?",
                            name: d.name ?? d.id ?? "?",
                            tier: d.tierLabel ?? "",
                            percent: pct,
                            hasLimit: pct >= 0,
                            resetsAt: resets,
                            todayPrompts: Number(d.todayPrompts ?? 0),
                            todayTokens: Number(d.todayTotalTokens ?? 0),
                            status: d.usageStatusText ?? ""
                        });
                    } catch (e) {
                        console.warn("[AgentUsage] bad record:", e);
                    }
                }
                root.agents = out;
            }
        }
    }

    Timer {
        interval: 5 * 60 * 1000
        repeat: true
        running: Config.ready
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
