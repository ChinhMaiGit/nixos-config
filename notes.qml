// Quick notes window (SUPER + N, or "Notes" in the launcher): one plain-text / Markdown file,
// saved automatically shortly after typing stops, in the current theme's colours and font.
// Run with `qs -p notes.qml`; hyprland.nix's notes script passes:
//   NOTES_FILE                         the file to edit (~/Notes/notes.md)
//   NOTES_ACCENT, NOTES_BACKGROUND,
//   NOTES_FOREGROUND, NOTES_MUTED      colours of the current theme
//   NOTES_FONT                         the font chosen in the gear menu
// Keys: Esc closes (after saving), Ctrl+S saves at once. Closing the window also saves.
import QtQuick
import QtQuick.Controls.Basic   // not the desktop style: KDE's needs Kirigami, which isn't here
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ShellRoot {
  id: root

  readonly property string path: Quickshell.env("NOTES_FILE") || ""
  readonly property color accent: Quickshell.env("NOTES_ACCENT") || "#54c8cf"
  readonly property color background: Quickshell.env("NOTES_BACKGROUND") || "#0b1219"
  readonly property color foreground: Quickshell.env("NOTES_FOREGROUND") || "#e0f4f5"
  readonly property color muted: Quickshell.env("NOTES_MUTED") || "#4f646b"
  readonly property string fontFamily: Quickshell.env("NOTES_FONT") || "JetBrainsMono Nerd Font"
  property bool loaded: false
  property bool dirty: false

  function save() {
    if (!dirty)
      return
    file.setText(editor.text)
    dirty = false
  }

  function close() {
    save()
    Qt.quit()
  }

  FileView {
    id: file
    path: root.path
    blockLoading: true   // read before the editor shows, so it never opens empty
    blockWrites: true    // finish writing before Qt.quit()
    atomicWrites: true   // write a temp file and rename it: a crash never leaves half a file
    printErrors: true
  }

  // Save shortly after the last keystroke instead of on every key
  Timer {
    id: saveTimer
    interval: 400
    onTriggered: root.save()
  }

  FloatingWindow {
    id: window
    title: "Quick Notes"
    implicitWidth: 900
    implicitHeight: 640
    color: root.background
    visible: true

    // Closed by the compositor (SUPER + W, SUPER + N again): save before going
    onVisibleChanged: if (!visible) root.close()

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: 22
      spacing: 12

      RowLayout {
        Layout.fillWidth: true

        Text {
          text: "  Notes"   // Font Awesome sticky note
          color: root.accent
          font.family: root.fontFamily
          font.pixelSize: 20
          font.bold: true
        }

        Item { Layout.fillWidth: true }

        Text {
          text: root.dirty ? "saving…" : "saved"
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: 13
        }
      }

      Rectangle {
        Layout.fillWidth: true
        implicitHeight: 2
        color: root.accent
        opacity: 0.6
      }

      ScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true

        TextArea {
          id: editor
          text: file.text()
          wrapMode: TextArea.Wrap
          color: root.foreground
          selectionColor: root.accent
          selectedTextColor: root.background
          placeholderText: "Write something…"
          placeholderTextColor: root.muted
          font.family: root.fontFamily
          font.pixelSize: 16
          background: null
          focus: true

          onTextChanged: {
            if (!root.loaded)
              return
            root.dirty = true
            saveTimer.restart()
          }

          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              root.close()
              event.accepted = true
            } else if (event.key === Qt.Key_S && (event.modifiers & Qt.ControlModifier)) {
              root.save()
              event.accepted = true
            }
          }

          Component.onCompleted: {
            cursorPosition = length   // continue where the notes end
            forceActiveFocus()
            root.loaded = true
          }
        }
      }
    }
  }
}
