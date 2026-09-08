import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

// AI coding-agent usage for the `ii` bar. Shows the worst rate-limit window
// across agents, or today's prompt count when no agent reports a limit (which
// is what happens when a sign-in has expired).
//
// The root has to be a MouseArea, not an Item: StyledPopup activates on
// `hoverTarget.containsMouse`, and a plain Item has no such property -- the
// popup silently never opens. Same shape as Resources.qml.
MouseArea {
    id: root

    property color color: Appearance.colors.colOnLayer1
    readonly property bool shouldShow: AgentUsage.available
    readonly property bool warn: AgentUsage.hasAnyLimit && AgentUsage.maxPercent >= 80
    readonly property color effectiveColor: warn ? Appearance.colors.colOnSecondaryContainer : root.color

    implicitWidth: rowLayout.implicitWidth
    implicitHeight: rowLayout.implicitHeight

    hoverEnabled: !Config.options.bar.tooltips.clickToShow
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: AgentUsage.refresh()

    RowLayout {
        id: rowLayout
        anchors.centerIn: parent
        spacing: 4

        MaterialSymbol {
            text: "smart_toy"
            iconSize: Appearance.font.pixelSize.larger
            color: root.effectiveColor
        }
    }

    AgentUsagePopup {
        hoverTarget: root
    }
}
