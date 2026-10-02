// Image carousel overlay for picking a theme or a wallpaper, modelled on Omarchy 4's image
// picker (basecamp/omarchy shell/plugins/image-picker/ImagePicker.qml, MIT): a large preview
// of the selected image between slanted, dimmed slices of its neighbours, label below.
// Run with `qs -p picker.qml`; theme.nix's picker script passes:
//   PICKER_ITEMS     JSON list of { label, image, value }
//   PICKER_SELECTED  value selected on open
//   PICKER_COMMAND   program run with the chosen value as its only argument
//   PICKER_ACCENT, PICKER_BACKGROUND, PICKER_FOREGROUND  colours of the current theme
// Keys: Left/Right or Tab/Shift+Tab move, Enter applies, Esc or a click outside closes.
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

ShellRoot {
  id: root

  readonly property var items: JSON.parse(Quickshell.env("PICKER_ITEMS") || "[]")
  readonly property string command: Quickshell.env("PICKER_COMMAND") || ""
  readonly property color accent: Quickshell.env("PICKER_ACCENT") || "#7aa2f7"
  readonly property color dimColor: Quickshell.env("PICKER_BACKGROUND") || "#1a1b26"
  readonly property color foreground: Quickshell.env("PICKER_FOREGROUND") || "#c0caf5"
  property int selectedIndex: Math.max(0, items.findIndex(item => item.value === Quickshell.env("PICKER_SELECTED")))

  // Omarchy's dimensions
  readonly property int expandedWidth: 768
  readonly property int expandedHeight: 475
  readonly property int sliceWidth: 108
  readonly property int sliceHeight: 432
  readonly property int sliceSpacing: -30
  readonly property int skewOffset: 28

  function move(step) {
    selectedIndex = Math.min(items.length - 1, Math.max(0, selectedIndex + step))
  }

  function apply() {
    if (command !== "" && items.length > 0)
      Quickshell.execDetached([command, items[selectedIndex].value])
    Qt.quit()
  }

  PanelWindow {
    // Open on the monitor that has focus.
    screen: Quickshell.screens.find(s => Hyprland.focusedMonitor && s.name === Hyprland.focusedMonitor.name) ?? Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "picker"

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.55)
    }

    MouseArea {
      anchors.fill: parent
      onClicked: Qt.quit()
    }

    Item {
      id: card
      width: Math.min(parent.width - 80, root.expandedWidth + 13 * (root.sliceWidth + root.sliceSpacing) + 40)
      height: root.expandedHeight + 30 + 74
      anchors.centerIn: parent

      MouseArea { anchors.fill: parent }   // clicks between items don't close

      Item {
        id: carousel
        anchors.top: parent.top
        anchors.topMargin: 30
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.expandedWidth + 13 * (root.sliceWidth + root.sliceSpacing)
        height: root.expandedHeight
        focus: true

        readonly property real itemStep: root.sliceWidth + root.sliceSpacing
        readonly property real previewX: (width - root.expandedWidth) / 2

        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            Qt.quit()
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.apply()
          } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab) {
            root.move(-1)
          } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) {
            root.move(1)
          } else {
            return
          }
          event.accepted = true
        }

        Component.onCompleted: forceActiveFocus()

        Repeater {
          model: root.items.length

          delegate: Item {
            id: item
            required property int index

            readonly property int relativeIndex: index - root.selectedIndex
            readonly property bool selected: relativeIndex === 0

            visible: Math.abs(relativeIndex) <= 16
            x: selected ? carousel.previewX
              : (relativeIndex < 0 ? carousel.previewX + relativeIndex * carousel.itemStep
                : carousel.previewX + root.expandedWidth + root.sliceSpacing + (relativeIndex - 1) * carousel.itemStep)
            y: selected ? 0 : (root.expandedHeight - root.sliceHeight) / 2
            width: selected ? root.expandedWidth : root.sliceWidth
            height: selected ? root.expandedHeight : root.sliceHeight
            z: selected ? 100 : 50 - Math.min(Math.abs(relativeIndex), 40)

            // Slide instead of jumping (Omarchy moves without animation).
            Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

            // Parallelogram outline: top edge shifted right by skewOffset
            readonly property real topLeft: root.skewOffset
            readonly property real topRight: width
            readonly property real bottomRight: width - root.skewOffset
            readonly property real bottomLeft: 0

            Item {
              id: maskShape
              anchors.fill: parent
              visible: false
              layer.enabled: true

              Shape {
                anchors.fill: parent
                antialiasing: true
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                  fillColor: "white"
                  strokeColor: "transparent"
                  startX: item.topLeft; startY: 0
                  PathLine { x: item.topRight; y: 0 }
                  PathLine { x: item.bottomRight; y: item.height }
                  PathLine { x: item.bottomLeft; y: item.height }
                  PathLine { x: item.topLeft; y: 0 }
                }
              }
            }

            Item {
              anchors.fill: parent
              layer.enabled: true
              layer.smooth: true
              layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: maskShape
                maskThresholdMin: 0.3
                maskSpreadAtMin: 0.3
              }

              Image {
                anchors.fill: parent
                source: "file://" + root.items[item.index].image
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                smooth: true
              }

              Rectangle {
                anchors.fill: parent
                color: Qt.rgba(root.dimColor.r, root.dimColor.g, root.dimColor.b, item.selected ? 0 : 0.42)
              }
            }

            Shape {
              anchors.fill: parent
              antialiasing: true
              preferredRendererType: Shape.CurveRenderer
              ShapePath {
                fillColor: "transparent"
                strokeColor: item.selected ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
                strokeWidth: item.selected ? 3 : 1
                startX: item.topLeft; startY: 0
                PathLine { x: item.topRight; y: 0 }
                PathLine { x: item.bottomRight; y: item.height }
                PathLine { x: item.bottomLeft; y: item.height }
                PathLine { x: item.topLeft; y: 0 }
              }
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: item.selected ? root.apply() : (root.selectedIndex = item.index)
            }
          }
        }
      }

      Text {
        anchors.top: carousel.bottom
        anchors.topMargin: 16
        anchors.horizontalCenter: carousel.horizontalCenter
        width: root.expandedWidth
        text: root.items.length > 0 ? root.items[root.selectedIndex].label : ""
        color: root.foreground
        style: Text.Outline
        styleColor: Qt.rgba(root.dimColor.r, root.dimColor.g, root.dimColor.b, 0.7)
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 28
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
      }
    }
  }
}
