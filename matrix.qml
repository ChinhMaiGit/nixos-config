// Matrix-rain wallpaper (gear menu > Matrix wallpaper), written 2026-10-05: falling characters
// like cmatrix, drawn behind all windows but in front of the wallpaper, which shows through
// darkened. Colours follow the current theme: bright heads, trails in the accent colour.
// Run with `qs -p matrix.qml` by the matrix-wallpaper user service; it passes:
//   MX_ACCENT, MX_BRIGHT, MX_BACKGROUND   colours of the current theme
//   MX_FONT                               the font chosen in the gear menu
import QtQuick
import Quickshell
import Quickshell.Wayland

ShellRoot {
  id: root

  readonly property color accent: Quickshell.env("MX_ACCENT") || "#54c8cf"
  readonly property color bright: Quickshell.env("MX_BRIGHT") || "#e0f4f5"
  readonly property color background: Quickshell.env("MX_BACKGROUND") || "#0b1219"
  readonly property string fontFamily: Quickshell.env("MX_FONT") || "JetBrainsMono Nerd Font"

  readonly property int cell: 18           // character size in pixels
  readonly property int fps: 16            // cmatrix-like pace; also keeps the load low
  readonly property real dim: 0.78         // how much the wallpaper is darkened
  // cmatrix's default set: letters, digits and symbols
  readonly property string glyphs: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789@#$%&*+=-<>?/|\\:;"

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: win
      required property var modelData
      screen: modelData
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.layer: WlrLayer.Bottom   // above the wallpaper, below every window
      WlrLayershell.namespace: "matrix-wallpaper"
      mask: Region {}                        // clicks go through to the desktop

      Rectangle {   // darkens the wallpaper underneath
        anchors.fill: parent
        color: Qt.rgba(root.background.r, root.background.g, root.background.b, root.dim)
      }

      Canvas {
        id: canvas
        anchors.fill: parent
        renderTarget: Canvas.FramebufferObject   // drawn on the GPU
        renderStrategy: Canvas.Cooperative

        property var drops: []   // per column: current row (fractional) and speed

        function reset() {
          const columns = Math.ceil(width / root.cell)
          const list = []
          for (let i = 0; i < columns; i++)
            list.push({ y: -Math.random() * height / root.cell, speed: 0.35 + Math.random() * 0.75 })
          drops = list
        }

        onWidthChanged: reset()
        onHeightChanged: reset()

        onPaint: {
          const ctx = getContext("2d")
          // Fade what's there toward transparent, so trails dissolve into the darkened wallpaper.
          ctx.globalCompositeOperation = "destination-out"
          ctx.fillStyle = "rgba(0, 0, 0, 0.12)"
          ctx.fillRect(0, 0, width, height)
          ctx.globalCompositeOperation = "source-over"
          ctx.font = "bold " + (root.cell - 3) + "px '" + root.fontFamily + "'"
          ctx.textBaseline = "top"

          const rows = height / root.cell
          for (let i = 0; i < drops.length; i++) {
            const d = drops[i]
            const before = Math.floor(d.y)
            d.y += d.speed
            const row = Math.floor(d.y)
            if (row !== before && row >= 0) {
              const ch = root.glyphs.charAt(Math.floor(Math.random() * root.glyphs.length))
              // the character just behind the head turns accent; the head itself is bright
              if (row > 0) {
                ctx.fillStyle = root.accent
                ctx.clearRect(i * root.cell, (row - 1) * root.cell, root.cell, root.cell)
                ctx.fillText(root.glyphs.charAt(Math.floor(Math.random() * root.glyphs.length)),
                             i * root.cell + 2, (row - 1) * root.cell)
              }
              ctx.fillStyle = root.bright
              ctx.fillText(ch, i * root.cell + 2, row * root.cell)
            }
            if (row > rows && Math.random() > 0.96)
              drops[i] = { y: -Math.random() * 12, speed: 0.35 + Math.random() * 0.75 }
          }
        }

        Timer {
          interval: 1000 / root.fps
          running: true
          repeat: true
          onTriggered: canvas.requestPaint()
        }
      }
    }
  }
}
