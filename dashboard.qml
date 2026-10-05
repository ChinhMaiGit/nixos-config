// Clock / calendar / weather dashboard, opened by clicking the clock in the top bar (written
// 2026-10-05; layout ideas from the Serpantinum shell, code written fresh). A panel under the
// bar: month calendar on the left; big clock, date and weather on the right.
// Run with `qs -p dashboard.qml`; hyprland.nix's dashboard script passes:
//   DASH_ACCENT, DASH_BACKGROUND, DASH_FOREGROUND, DASH_MUTED   colours of the current theme
//   DASH_FONT                                                  the font chosen in the gear menu
//   DASH_PLACES   JSON list of { name, lat, lon } for the weather, the first one shown large.
//                 Comes from a private file outside the (public) config repo; empty = no weather.
// Weather: Open-Meteo (open-meteo.com), free and without an account, fetched on each opening.
// Keys: Esc closes; a click outside the panel closes it too.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

ShellRoot {
  id: root

  readonly property color accent: Quickshell.env("DASH_ACCENT") || "#54c8cf"
  readonly property color background: Quickshell.env("DASH_BACKGROUND") || "#0b1219"
  readonly property color foreground: Quickshell.env("DASH_FOREGROUND") || "#e0f4f5"
  readonly property color muted: Quickshell.env("DASH_MUTED") || "#4f646b"
  readonly property string fontFamily: Quickshell.env("DASH_FONT") || "JetBrainsMono Nerd Font"
  readonly property var places: {
    try {
      return JSON.parse(Quickshell.env("DASH_PLACES") || "[]")
    } catch (e) {
      return []
    }
  }

  property var now: new Date()
  property var shownMonth: new Date(now.getFullYear(), now.getMonth(), 1)
  property var weather: []        // Open-Meteo answer, one entry per place
  property string weatherState: places.length ? "loading" : "off"

  readonly property var weekdays: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: root.now = new Date()
  }

  // ---- calendar helpers ----

  // 42 days (6 weeks, Monday first) covering the shown month
  function monthCells(first) {
    const offset = (first.getDay() + 6) % 7
    const cells = []
    for (let i = 0; i < 42; i++)
      cells.push(new Date(first.getFullYear(), first.getMonth(), 1 - offset + i))
    return cells
  }

  function isoWeek(d) {
    const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()))
    const day = t.getUTCDay() || 7
    t.setUTCDate(t.getUTCDate() + 4 - day)
    const yearStart = new Date(Date.UTC(t.getUTCFullYear(), 0, 1))
    return Math.ceil(((t - yearStart) / 86400000 + 1) / 7)
  }

  function sameDay(a, b) {
    return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
  }

  function moveMonth(step) {
    shownMonth = new Date(shownMonth.getFullYear(), shownMonth.getMonth() + step, 1)
  }

  // ---- weather ----

  function fetchWeather() {
    if (!places.length)
      return
    const lat = places.map(p => p.lat).join(",")
    const lon = places.map(p => p.lon).join(",")
    const url = "https://api.open-meteo.com/v1/forecast?latitude=" + lat + "&longitude=" + lon
      + "&current=temperature_2m,weather_code,is_day"
      + "&hourly=temperature_2m,weather_code,is_day"
      + "&daily=temperature_2m_max,temperature_2m_min"
      + "&timezone=auto&forecast_days=2"
    const request = new XMLHttpRequest()
    request.onreadystatechange = function() {
      if (request.readyState !== XMLHttpRequest.DONE)
        return
      if (request.status !== 200) {
        root.weatherState = "error"
        return
      }
      const data = JSON.parse(request.responseText)
      root.weather = Array.isArray(data) ? data : [data]   // one place: a single object
      root.weatherState = "ok"
    }
    request.open("GET", url)
    request.send()
  }

  // WMO weather codes (open-meteo.com/en/docs) -> Nerd Font weather glyph and a short text
  function weatherIcon(code, isDay) {
    if (code === 0) return String.fromCodePoint(isDay ? 0xe30d : 0xe32b)
    if (code <= 2) return String.fromCodePoint(isDay ? 0xe302 : 0xe37e)
    if (code === 3) return String.fromCodePoint(0xe312)
    if (code <= 48) return String.fromCodePoint(0xe313)
    if (code <= 57) return String.fromCodePoint(0xe31b)
    if (code <= 67) return String.fromCodePoint(0xe318)
    if (code <= 77) return String.fromCodePoint(0xe31a)
    if (code <= 82) return String.fromCodePoint(0xe319)
    if (code <= 86) return String.fromCodePoint(0xe3ad)
    return String.fromCodePoint(0xe31d)
  }

  function weatherText(code) {
    if (code === 0) return "Clear"
    if (code <= 2) return "Partly cloudy"
    if (code === 3) return "Overcast"
    if (code <= 48) return "Fog"
    if (code <= 57) return "Drizzle"
    if (code <= 67) return "Rain"
    if (code <= 77) return "Snow"
    if (code <= 82) return "Showers"
    if (code <= 86) return "Snow showers"
    return "Thunderstorm"
  }

  // The next `count` hours for one place, starting with the current hour
  function nextHours(place, count) {
    if (!place)
      return []
    const currentHour = place.current.time.slice(0, 13)
    let start = place.hourly.time.findIndex(t => t.slice(0, 13) >= currentHour)
    if (start < 0)
      start = 0
    const hours = []
    for (let i = start; i < Math.min(start + count, place.hourly.time.length); i++) {
      hours.push({
        hour: place.hourly.time[i].slice(11, 13),
        temp: Math.round(place.hourly.temperature_2m[i]),
        code: place.hourly.weather_code[i],
        isDay: place.hourly.is_day[i] === 1,
      })
    }
    return hours
  }

  Component.onCompleted: fetchWeather()

  PanelWindow {
    // Open on the monitor that has focus, like the theme picker.
    screen: Quickshell.screens.find(s => Hyprland.focusedMonitor && s.name === Hyprland.focusedMonitor.name) ?? Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "dashboard"

    // A click anywhere outside the panel (the clock in the bar included) closes it.
    MouseArea {
      anchors.fill: parent
      onClicked: Qt.quit()
    }

    Rectangle {
      id: panel
      width: 880
      height: content.implicitHeight + 48
      anchors.horizontalCenter: parent.horizontalCenter
      y: 50
      radius: 18
      color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.96)
      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
      border.width: 1
      focus: true

      Keys.onEscapePressed: Qt.quit()
      Component.onCompleted: forceActiveFocus()

      // gentle slide-in
      opacity: 0
      transform: Translate { id: slide; y: -12 }
      NumberAnimation on opacity { to: 1; duration: 160; easing.type: Easing.OutCubic }
      NumberAnimation { target: slide; property: "y"; to: 0; duration: 200; easing.type: Easing.OutCubic; running: true }

      MouseArea { anchors.fill: parent }   // clicks inside don't close it

      RowLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 24
        spacing: 28

        // ==== calendar ====
        ColumnLayout {
          Layout.alignment: Qt.AlignTop
          Layout.preferredWidth: 300
          spacing: 10

          RowLayout {
            Layout.fillWidth: true

            Text {
              text: "‹"
              color: prevArea.containsMouse ? root.accent : root.muted
              font.family: root.fontFamily
              font.pixelSize: 22
              MouseArea {
                id: prevArea
                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                onClicked: root.moveMonth(-1)
              }
            }

            Text {
              Layout.fillWidth: true
              horizontalAlignment: Text.AlignHCenter
              text: root.shownMonth.toLocaleDateString(Qt.locale("en_GB"), "MMMM yyyy")
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: 16
              font.bold: true
              MouseArea {   // back to the current month
                anchors.fill: parent
                onClicked: root.shownMonth = new Date(root.now.getFullYear(), root.now.getMonth(), 1)
              }
            }

            Text {
              text: "›"
              color: nextArea.containsMouse ? root.accent : root.muted
              font.family: root.fontFamily
              font.pixelSize: 22
              MouseArea {
                id: nextArea
                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                onClicked: root.moveMonth(1)
              }
            }
          }

          GridLayout {
            columns: 8
            columnSpacing: 2
            rowSpacing: 2

            // header: week-number column, then the weekdays
            Text {
              Layout.preferredWidth: 30
              horizontalAlignment: Text.AlignHCenter
              text: "W"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: 11
            }
            Repeater {
              model: root.weekdays
              Text {
                required property string modelData
                Layout.preferredWidth: 36
                horizontalAlignment: Text.AlignHCenter
                text: modelData
                color: modelData === "Sa" || modelData === "Su" ? root.accent : root.muted
                font.family: root.fontFamily
                font.pixelSize: 12
                font.bold: true
              }
            }

            Repeater {
              model: 6

              delegate: Item {
                id: week
                required property int index
                readonly property var days: root.monthCells(root.shownMonth).slice(index * 7, index * 7 + 7)
                Layout.columnSpan: 8
                Layout.preferredHeight: 36
                Layout.fillWidth: true

                RowLayout {
                  anchors.fill: parent
                  spacing: 2

                  Text {
                    Layout.preferredWidth: 30
                    horizontalAlignment: Text.AlignHCenter
                    text: root.isoWeek(week.days[0])
                    color: root.muted
                    font.family: root.fontFamily
                    font.pixelSize: 11
                  }

                  Repeater {
                    model: week.days

                    Rectangle {
                      required property var modelData
                      readonly property bool isToday: root.sameDay(modelData, root.now)
                      readonly property bool inMonth: modelData.getMonth() === root.shownMonth.getMonth()
                      Layout.preferredWidth: 36
                      Layout.preferredHeight: 32
                      radius: 10
                      color: isToday ? root.accent : "transparent"

                      Text {
                        anchors.centerIn: parent
                        text: parent.modelData.getDate()
                        color: parent.isToday ? root.background
                          : parent.inMonth ? root.foreground : Qt.rgba(root.muted.r, root.muted.g, root.muted.b, 0.6)
                        font.family: root.fontFamily
                        font.pixelSize: 14
                        font.bold: parent.isToday
                      }
                    }
                  }
                }
              }
            }
          }
        }

        Rectangle {   // divider
          Layout.fillHeight: true
          Layout.preferredWidth: 1
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)
        }

        // ==== clock and weather ====
        ColumnLayout {
          Layout.fillWidth: true
          Layout.alignment: Qt.AlignTop
          spacing: 14

          RowLayout {
            spacing: 6
            Text {
              text: Qt.formatTime(root.now, "HH:mm")
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: 68
              font.bold: true
            }
            Text {
              Layout.alignment: Qt.AlignBottom
              Layout.bottomMargin: 14
              text: Qt.formatTime(root.now, "ss")
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: 22
            }
          }

          Text {
            Layout.topMargin: -10
            text: root.now.toLocaleDateString(Qt.locale("en_GB"), "dddd, d MMMM yyyy") + "  ·  Week " + root.isoWeek(root.now)
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: 15
          }

          // ---- weather ----
          Text {
            visible: root.weatherState !== "ok"
            text: root.weatherState === "loading" ? "Loading weather…"
              : root.weatherState === "error" ? "Weather unavailable (offline?)" : ""
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: 13
          }

          // the first place, large, with the next hours
          Rectangle {
            visible: root.weatherState === "ok"
            Layout.fillWidth: true
            Layout.topMargin: 6
            implicitHeight: mainWeather.implicitHeight + 28
            radius: 14
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)

            ColumnLayout {
              id: mainWeather
              readonly property var w: root.weather[0]
              anchors.fill: parent
              anchors.margins: 14
              spacing: 12

              RowLayout {
                spacing: 14
                Text {
                  text: mainWeather.w ? root.weatherIcon(mainWeather.w.current.weather_code, mainWeather.w.current.is_day === 1) : ""
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: 40
                }
                ColumnLayout {
                  spacing: 0
                  Text {
                    text: mainWeather.w ? Math.round(mainWeather.w.current.temperature_2m) + "°  " + root.weatherText(mainWeather.w.current.weather_code) : ""
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: 22
                    font.bold: true
                  }
                  Text {
                    text: root.places[0] && mainWeather.w
                      ? root.places[0].name + "  ·  ↑" + Math.round(mainWeather.w.daily.temperature_2m_max[0]) + "°  ↓" + Math.round(mainWeather.w.daily.temperature_2m_min[0]) + "°"
                      : ""
                    color: root.muted
                    font.family: root.fontFamily
                    font.pixelSize: 13
                  }
                }
              }

              RowLayout {
                Layout.fillWidth: true
                spacing: 4
                Repeater {
                  model: root.nextHours(mainWeather.w, 6)
                  ColumnLayout {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                      Layout.alignment: Qt.AlignHCenter
                      text: parent.index === 0 ? "now" : parent.modelData.hour + ":00"
                      color: parent.index === 0 ? root.accent : root.muted
                      font.family: root.fontFamily
                      font.pixelSize: 13
                    }
                    Text {
                      Layout.alignment: Qt.AlignHCenter
                      text: root.weatherIcon(parent.modelData.code, parent.modelData.isDay)
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: 24
                    }
                    Text {
                      Layout.alignment: Qt.AlignHCenter
                      text: parent.modelData.temp + "°"
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: 15
                    }
                  }
                }
              }
            }
          }

          // the other places, small
          RowLayout {
            visible: root.weatherState === "ok" && root.places.length > 1
            Layout.fillWidth: true
            spacing: 10

            Repeater {
              model: root.weatherState === "ok" ? root.places.slice(1) : []

              Rectangle {
                required property var modelData
                required property int index
                readonly property var w: root.weather[index + 1]
                Layout.fillWidth: true
                implicitHeight: 58
                radius: 12
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)

                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: 14
                  anchors.rightMargin: 14
                  spacing: 12
                  Text {
                    text: parent.parent.w ? root.weatherIcon(parent.parent.w.current.weather_code, parent.parent.w.current.is_day === 1) : ""
                    color: root.accent
                    font.family: root.fontFamily
                    font.pixelSize: 24
                  }
                  ColumnLayout {
                    spacing: 0
                    Layout.fillWidth: true
                    Text {
                      text: parent.parent.parent.modelData.name
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: 13
                      font.bold: true
                    }
                    Text {
                      readonly property var w: parent.parent.parent.w
                      text: w ? Math.round(w.current.temperature_2m) + "°  ↑" + Math.round(w.daily.temperature_2m_max[0]) + "°  ↓" + Math.round(w.daily.temperature_2m_min[0]) + "°" : ""
                      color: root.muted
                      font.family: root.fontFamily
                      font.pixelSize: 12
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
