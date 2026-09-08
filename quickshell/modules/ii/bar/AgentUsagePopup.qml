import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

StyledPopup {
    id: root

    function formatTokens(n) {
        if (n >= 1e9) return (n / 1e9).toFixed(1) + " B";
        if (n >= 1e6) return (n / 1e6).toFixed(1) + " M";
        if (n >= 1e3) return (n / 1e3).toFixed(1) + " k";
        return String(n);
    }

    // "2026-09-08T14:00:00Z" -> "14:00". Anything unparseable is shown as-is.
    function formatReset(iso) {
        if (!iso) return "";
        const d = new Date(iso);
        if (isNaN(d.getTime())) return iso;
        return Qt.formatDateTime(d, "ddd HH:mm");
    }

    Column {
        anchors.centerIn: parent
        spacing: 12

        Repeater {
            model: AgentUsage.agents

            Column {
                required property var modelData
                spacing: 6

                StyledPopupHeaderRow {
                    icon: "smart_toy"
                    label: modelData.name + (modelData.tier ? "  ·  " + modelData.tier : "")
                }

                Column {
                    spacing: 4

                    // Only meaningful while the agent's sign-in is valid.
                    StyledPopupValueRow {
                        visible: modelData.hasLimit
                        icon: "data_usage"
                        label: Translation.tr("Quota used:")
                        value: modelData.percent.toFixed(1) + " %"
                    }
                    StyledPopupValueRow {
                        visible: modelData.hasLimit && modelData.resetsAt !== ""
                        icon: "restart_alt"
                        label: Translation.tr("Resets:")
                        value: root.formatReset(modelData.resetsAt)
                    }
                    // Only when there is no quota figure at all. Upstream says
                    // "Sign-in expired", which misleads -- you are still signed
                    // in, the stored access token simply aged out. It is minted
                    // by the Claude Code CLI and lasts ~12 h, so it lapses on
                    // its own; nothing needs doing and saying otherwise sent us
                    // chasing a non-problem.
                    StyledPopupValueRow {
                        visible: !modelData.hasLimit && modelData.status !== ""
                        icon: "info"
                        label: Translation.tr("Quota:")
                        value: Translation.tr("not available right now")
                    }
                    StyledPopupValueRow {
                        icon: "forum"
                        label: Translation.tr("Prompts today:")
                        value: String(modelData.todayPrompts)
                    }
                    StyledPopupValueRow {
                        visible: modelData.todayTokens > 0
                        icon: "token"
                        label: Translation.tr("Tokens today:")
                        value: root.formatTokens(modelData.todayTokens)
                    }
                }
            }
        }

        StyledText {
            visible: AgentUsage.agents.length === 0
            text: AgentUsage.checking
                ? Translation.tr("Collecting…")
                : Translation.tr("No agent data")
            color: Appearance.colors.colSubtext
        }
    }
}
