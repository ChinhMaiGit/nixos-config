// Workspace pill with hover previews (top left of every monitor), written 2026-10-05. It took the
// workspace buttons over from Waybar, which has no hover hook and can't show images. Same look
// as the bar's pills; hovering a workspace shows a miniature of it with live images of its
// windows (Hyprland's toplevel export, which also captures windows on hidden workspaces); for
// scrolling-layout workspaces it shows the whole strip with the on-screen part outlined.
// Run with `qs -p workspaces.qml` by the workspace-pill user service; it passes:
//   WS_ACCENT, WS_BACKGROUND, WS_FOREGROUND, WS_DARK_FOREGROUND, WS_SELECTION, WS_FONT
// Left click: go to the workspace. Mouse wheel: next / previous workspace.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

ShellRoot {
  id: root

  readonly property color accent: Quickshell.env("WS_ACCENT") || "#54c8cf"
  readonly property color background: Quickshell.env("WS_BACKGROUND") || "#0b1219"
  readonly property color foreground: Quickshell.env("WS_FOREGROUND") || "#e0f4f5"
  readonly property color darkForeground: Quickshell.env("WS_DARK_FOREGROUND") || "#6598a3"
  readonly property color selection: Quickshell.env("WS_SELECTION") || "#1f334e"
  readonly property string fontFamily: Quickshell.env("WS_FONT") || "JetBrainsMono Nerd Font"

  // Waybar's geometry, so the pill sits where its workspace module was (hyprland.nix)
  readonly property int barTop: 6
  readonly property int barLeft: 10
  readonly property int barHeight: 34

  readonly property int previewWidth: 360

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData
      screen: modelData
      readonly property var monitor: Hyprland.monitorFor(modelData)

      // Workspaces 1-5 always (as Waybar's persistent ones), plus any other one on this monitor
      readonly property var ids: {
        const list = [1, 2, 3, 4, 5]
        for (const ws of Hyprland.workspaces.values) {
          if (ws.id > 5 && ws.monitor === panel.monitor && list.indexOf(ws.id) < 0)
            list.push(ws.id)
        }
        return list.sort((a, b) => a - b)
      }
      property int hoveredId: -1
      property real hoveredX: 0

      function workspace(id) {
        return Hyprland.workspaces.values.find(ws => ws.id === id) ?? null
      }

      anchors { top: true; left: true }
      margins { top: root.barTop; left: root.barLeft + 4 }
      implicitWidth: pill.implicitWidth
      implicitHeight: root.barHeight
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore   // Waybar already reserves the space
      // Overlay, not Top: Waybar's own top-layer surface spans the whole width, and whichever
      // was created last took the mouse; after a Waybar reload hover and clicks stopped working
      // (2026-10-05). Overlay is also above full-screen windows, so the pill hides for those.
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "workspaces"
      visible: !(monitor && monitor.activeWorkspace && monitor.activeWorkspace.hasFullscreen)

      Rectangle {
        id: pill
        anchors.fill: parent
        implicitWidth: buttons.implicitWidth + 12
        radius: 12
        color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.92)
        border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
        border.width: 1

        MouseArea {   // wheel anywhere on the pill switches workspace, like Waybar did
          anchors.fill: parent
          acceptedButtons: Qt.NoButton
          onWheel: wheel => Hyprland.dispatch(wheel.angleDelta.y > 0 ? "workspace e-1" : "workspace e+1")
        }

        RowLayout {
          id: buttons
          anchors.centerIn: parent
          spacing: 2

          Repeater {
            model: panel.ids

            Rectangle {
              id: button
              required property int modelData
              readonly property var ws: panel.workspace(modelData)
              readonly property bool active: panel.monitor && panel.monitor.activeWorkspace
                && panel.monitor.activeWorkspace.id === modelData
              readonly property bool occupied: ws !== null && ws.toplevels.values.length > 0
              implicitWidth: label.implicitWidth + 16
              implicitHeight: root.barHeight - 10
              radius: 8
              color: active ? root.accent : area.containsMouse ? root.selection : "transparent"
              Behavior on color { ColorAnimation { duration: 120 } }

              Text {
                id: label
                anchors.centerIn: parent
                text: button.modelData
                color: button.active ? root.background
                  : area.containsMouse ? root.foreground : root.darkForeground
                opacity: button.active || button.occupied || area.containsMouse ? 1 : 0.5
                font.family: root.fontFamily
                font.pixelSize: 12
                font.bold: button.active
              }

              MouseArea {
                id: area
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Hyprland.dispatch("workspace " + button.modelData)
                onContainsMouseChanged: {
                  if (containsMouse) {
                    Hyprland.refreshToplevels()   // fresh window positions for the preview
                    panel.hoveredId = button.modelData
                    panel.hoveredX = button.mapToItem(pill, 0, 0).x
                  } else if (panel.hoveredId === button.modelData) {
                    panel.hoveredId = -1
                  }
                }
              }
            }
          }
        }
      }

      // ---- the preview under the hovered workspace ----
      PopupWindow {
        id: preview
        readonly property var ws: panel.hoveredId > 0 ? panel.workspace(panel.hoveredId) : null
        readonly property var windows: ws ? ws.toplevels.values : []
        // The area to draw: the monitor plus every window of the workspace. With the scrolling
        // layout windows lie beside the screen (negative x, or past its right edge), so the
        // miniature widens to show the whole strip instead of cutting them off.
        readonly property var box: {
          const m = panel.monitor
          if (!m)
            return { x: 0, y: 0, w: 1920, h: 1080 }
          let x1 = m.x, y1 = m.y, x2 = m.x + m.width, y2 = m.y + m.height
          for (const t of windows) {
            const ipc = t.lastIpcObject
            if (!ipc || !ipc.at || !ipc.size)
              continue
            x1 = Math.min(x1, ipc.at[0])
            y1 = Math.min(y1, ipc.at[1])
            x2 = Math.max(x2, ipc.at[0] + ipc.size[0])
            y2 = Math.max(y2, ipc.at[1] + ipc.size[1])
          }
          return { x: x1, y: y1, w: x2 - x1, h: y2 - y1 }
        }
        readonly property real maxWidth: root.previewWidth * 1.8   // wide strips get some extra room
        readonly property real scale: Math.min(maxWidth / box.w, (root.previewWidth * 9 / 16) / box.h)

        visible: panel.hoveredId > 0
        anchor.window: panel
        anchor.rect.x: Math.max(0, panel.hoveredX - 20)
        anchor.rect.y: root.barHeight + 8
        implicitWidth: Math.max(220, box.w * scale) + 24
        implicitHeight: box.h * scale + 58
        color: "transparent"

        Rectangle {
          anchors.fill: parent
          radius: 14
          color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.96)
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
          border.width: 1

          Text {
            id: title
            x: 14
            y: 10
            text: "Workspace " + panel.hoveredId + "  ·  "
              + (preview.windows.length === 0 ? "empty"
                : preview.windows.length + (preview.windows.length === 1 ? " window" : " windows"))
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: 12
            font.bold: true
          }

          // the monitor in miniature
          Rectangle {
            id: screenArea
            x: 12
            anchors.top: title.bottom
            anchors.topMargin: 8
            width: Math.max(196, preview.box.w * preview.scale)
            height: preview.box.h * preview.scale
            radius: 8
            clip: true
            color: Qt.rgba(root.selection.r, root.selection.g, root.selection.b, 0.45)

            Rectangle {   // the part of the strip that's on screen (matters for scrolling layouts)
              visible: panel.monitor && preview.box.w > panel.monitor.width + 1
              x: panel.monitor ? (panel.monitor.x - preview.box.x) * preview.scale : 0
              y: panel.monitor ? (panel.monitor.y - preview.box.y) * preview.scale : 0
              width: panel.monitor ? panel.monitor.width * preview.scale : 0
              height: panel.monitor ? panel.monitor.height * preview.scale : 0
              color: "transparent"
              radius: 6
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.5)
              border.width: 1
              z: 2
            }

            Text {
              anchors.centerIn: parent
              visible: preview.windows.length === 0
              text: "No windows"
              color: root.darkForeground
              font.family: root.fontFamily
              font.pixelSize: 12
            }

            Repeater {
              model: preview.visible ? preview.windows : []

              Rectangle {
                id: tile
                required property var modelData
                readonly property var ipc: modelData.lastIpcObject
                readonly property bool known: ipc && ipc.at && ipc.size
                visible: known
                x: known ? (ipc.at[0] - preview.box.x) * preview.scale : 0
                y: known ? (ipc.at[1] - preview.box.y) * preview.scale : 0
                width: known ? ipc.size[0] * preview.scale : 0
                height: known ? ipc.size[1] * preview.scale : 0
                radius: 4
                color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.9)
                border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.6)
                border.width: 1
                clip: true

                ScreencopyView {
                  anchors.fill: parent
                  anchors.margins: 1
                  captureSource: tile.modelData.wayland
                  live: true
                }

                Text {   // shown until (or if) the live image isn't available
                  anchors.centerIn: parent
                  width: parent.width - 6
                  horizontalAlignment: Text.AlignHCenter
                  elide: Text.ElideRight
                  text: tile.ipc && tile.ipc.class ? tile.ipc.class : ""
                  color: root.darkForeground
                  font.family: root.fontFamily
                  font.pixelSize: 10
                  z: -1
                }
              }
            }
          }
        }
      }
    }
  }
}
