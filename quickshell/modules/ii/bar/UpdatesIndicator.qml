import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

// Indicador de actualizaciones pendientes para la familia de paneles `ii`.
// La familia `waffle` ya tiene su UpdatesButton; el servicio Updates es
// compartido, asi que aqui solo hace falta la presentacion.
Item {
    id: root

    property color color: Appearance.colors.colOnLayer1
    // Visible con cualquier actualizacion pendiente. waffle solo lo muestra al
    // pasar adviseUpdateThreshold (75): no te enteras hasta llevar semanas sin
    // actualizar. Los umbrales siguen usandose para el color.
    readonly property bool shouldShow: Updates.available && Updates.count > 0
    readonly property color effectiveColor: Updates.updateStronglyAdvised ? Appearance.colors.colOnSecondaryContainer : root.color

    implicitWidth: rowLayout.implicitWidth
    implicitHeight: rowLayout.implicitHeight

    RowLayout {
        id: rowLayout
        anchors.centerIn: parent
        spacing: 4

        MaterialSymbol {
            text: "sync"
            iconSize: Appearance.font.pixelSize.larger
            color: root.effectiveColor
        }

        StyledText {
            text: Updates.count
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: root.effectiveColor
        }
    }

    // Tras lanzar la actualizacion el contador queda obsoleto hasta el siguiente
    // checkInterval (120 min). Se re-consulta para que el icono desaparezca solo.
    Timer {
        id: recheckTimer
        interval: 30000
        repeat: true
        property int remaining: 0
        onTriggered: {
            Updates.refresh();
            remaining--;
            if (remaining <= 0) stop();
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                Updates.refresh(); // clic derecho: comprobar ahora
                return;
            }
            Quickshell.execDetached(["bash", "-c", Config.options.apps.update]);
            recheckTimer.remaining = 20; // ~10 min de re-comprobaciones
            recheckTimer.restart();
        }
    }
}
