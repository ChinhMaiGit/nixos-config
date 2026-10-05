// Login screen (SDDM theme "omarchy", installed by sddm-theme.nix). Rewritten 2026-10-05 in the
// style Chinh liked in the Serpantinum shell (code written fresh): the wallpaper blurred and
// dimmed, a big clock and date, a rounded password field, pills for session and keyboard
// layout, and a power menu. Kept from the earlier Omarchy-based version (basecamp/omarchy,
// MIT): the Hyprland (UWSM) session is picked by default and F2 switches sessions, so Plasma
// stays reachable; session names come from the model's "name" role.
// SDDM runs as its own user and can't read Chinh's theme, so the Cyan colours are fixed here
// and the wallpaper is copied in by sddm-theme.nix.
import QtQuick
import QtQuick.Effects
import SddmComponents 2.0

Rectangle {
  id: root
  width: 1920
  height: 1080
  color: palette.background

  // Cyan theme (themes/cyan/colors.toml)
  readonly property QtObject palette: QtObject {
    readonly property color background: "#0b1219"
    readonly property color accent: "#54c8cf"
    readonly property color foreground: "#e0f4f5"
    readonly property color muted: "#8fb0b5"
    readonly property color error: "#e06c75"
  }
  readonly property string fontFamily: "JetBrainsMono Nerd Font"

  // The last user to log in; on a fresh start that can be empty, then the first user listed.
  property var userNames: []
  property string currentUser: userModel.lastUser || (userNames.length ? userNames[0] : "")
  property bool loginFailed: false
  property bool powerOpen: false
  property var now: new Date()

  // Session names via the model's "name" role (Qt.DisplayRole is empty with this SDDM).
  property var sessionNames: []
  property int sessionIndex: {
    for (var i = 0; i < sessionNames.length; i++) {
      if (sessionNames[i].indexOf("uwsm") !== -1)
        return i
    }
    return sessionModel.lastIndex
  }

  function icon(code) {
    return String.fromCodePoint(code)
  }

  function nextSession() {
    // Skip plain "Hyprland": the desktop's services start only in the UWSM session.
    var next = sessionIndex
    do {
      next = (next + 1) % sessionNames.length
    } while (sessionNames[next] === "Hyprland" && next !== sessionIndex)
    sessionIndex = next
  }

  Repeater {
    model: userModel
    delegate: Item {
      required property int index
      required property string name
      Component.onCompleted: {
        var names = root.userNames.slice()
        names[index] = name
        root.userNames = names
      }
    }
  }

  Repeater {
    model: sessionModel
    delegate: Item {
      required property int index
      required property string name
      Component.onCompleted: {
        var names = root.sessionNames.slice()
        names[index] = name
        root.sessionNames = names
      }
    }
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: root.now = new Date()
  }

  Connections {
    target: sddm
    function onLoginFailed() {
      root.loginFailed = true
      password.text = ""
      password.forceActiveFocus()
      shake.start()
    }
    function onLoginSucceeded() {
      root.loginFailed = false
    }
  }

  // ==== background: blurred, dimmed wallpaper with a soft round glow ====
  Image {
    id: wallpaper
    anchors.fill: parent
    source: "background.jpg"
    fillMode: Image.PreserveAspectCrop
    visible: false
  }

  MultiEffect {
    anchors.fill: parent
    source: wallpaper
    blurEnabled: true
    blur: 1.0
    blurMax: 64
    brightness: -0.12
  }

  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0.04, 0.07, 0.1, 0.35)
  }

  Rectangle {   // the round "lens" in the middle
    width: Math.min(parent.width, parent.height) * 1.15
    height: width
    radius: width / 2
    anchors.centerIn: parent
    color: Qt.rgba(1, 1, 1, 0.035)
    border.color: Qt.rgba(1, 1, 1, 0.06)
    border.width: 1
  }

  // a click on the background closes the power menu
  MouseArea {
    anchors.fill: parent
    onClicked: {
      root.powerOpen = false
      password.forceActiveFocus()
    }
  }

  // ==== clock, date, password ====
  Column {
    anchors.centerIn: parent
    anchors.verticalCenterOffset: -30
    spacing: 14

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 6
      Text {
        text: Qt.formatTime(root.now, "HH")
        color: root.palette.foreground
        font.family: root.fontFamily
        font.pixelSize: 150
        font.weight: Font.Bold
      }
      Text {   // the colon breathes once a second
        text: ":"
        color: root.palette.accent
        opacity: root.now.getSeconds() % 2 === 0 ? 1 : 0.35
        font.family: root.fontFamily
        font.pixelSize: 150
        font.weight: Font.Bold
        Behavior on opacity { NumberAnimation { duration: 400 } }
      }
      Text {
        text: Qt.formatTime(root.now, "mm")
        color: root.palette.foreground
        font.family: root.fontFamily
        font.pixelSize: 150
        font.weight: Font.Bold
      }
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.now.toLocaleDateString(Qt.locale("en_GB"), "dddd, d MMMM")
      color: root.palette.foreground
      opacity: 0.85
      font.family: root.fontFamily
      font.pixelSize: 24
    }

    Item { width: 1; height: 40 }

    // password pill
    Rectangle {
      id: field
      anchors.horizontalCenter: parent.horizontalCenter
      width: 380
      height: 52
      radius: 26
      color: Qt.rgba(0.04, 0.07, 0.1, 0.55)
      border.width: 1.5
      border.color: root.loginFailed ? root.palette.error
        : password.text.length > 0 ? root.palette.accent : Qt.rgba(1, 1, 1, 0.18)
      Behavior on border.color { ColorAnimation { duration: 150 } }

      transform: Translate { id: shakeOffset }
      SequentialAnimation {
        id: shake
        loops: 2
        NumberAnimation { target: shakeOffset; property: "x"; to: -10; duration: 50 }
        NumberAnimation { target: shakeOffset; property: "x"; to: 10; duration: 80 }
        NumberAnimation { target: shakeOffset; property: "x"; to: 0; duration: 50 }
      }

      Text {
        id: lockIcon
        anchors.left: parent.left
        anchors.leftMargin: 22
        anchors.verticalCenter: parent.verticalCenter
        text: root.icon(0xf023)   // lock
        color: root.loginFailed ? root.palette.error : root.palette.accent
        font.family: root.fontFamily
        font.pixelSize: 18
      }

      Text {
        anchors.left: lockIcon.right
        anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        visible: password.text.length === 0
        text: root.loginFailed ? "Wrong password, try again" : "Password for " + root.currentUser
        color: root.loginFailed ? root.palette.error : root.palette.muted
        font.family: root.fontFamily
        font.pixelSize: 15
      }

      TextInput {
        id: password
        anchors.left: lockIcon.right
        anchors.leftMargin: 16
        anchors.right: parent.right
        anchors.rightMargin: 22
        anchors.verticalCenter: parent.verticalCenter
        echoMode: TextInput.Password
        passwordCharacter: "•"
        color: root.palette.foreground
        selectionColor: root.palette.accent
        font.family: root.fontFamily
        font.pixelSize: 20
        font.letterSpacing: 4
        clip: true
        focus: true

        onTextChanged: root.loginFailed = false

        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_F2) {
            root.nextSession()
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            sddm.login(root.currentUser, password.text, root.sessionIndex)
            event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
            root.powerOpen = false
            password.text = ""
            event.accepted = true
          }
        }
      }
    }
  }

  // ==== bottom pills: session and keyboard layout ====
  component Pill: Rectangle {
    property alias label: pillText.text
    property bool hovered: pillArea.containsMouse
    signal clicked()
    height: 36
    width: pillText.implicitWidth + 32
    radius: 18
    color: hovered ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0.04, 0.07, 0.1, 0.5)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.12)
    Text {
      id: pillText
      anchors.centerIn: parent
      color: root.palette.foreground
      font.family: root.fontFamily
      font.pixelSize: 13
    }
    MouseArea {
      id: pillArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: parent.clicked()
    }
  }

  Row {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 36
    spacing: 12

    Pill {
      label: root.icon(0xf108) + "  " + (root.sessionNames[root.sessionIndex] || "") + "   F2"
      onClicked: {
        root.nextSession()
        password.forceActiveFocus()
      }
    }

    Pill {
      visible: keyboard.layouts.length > 0
      label: root.icon(0xf11c) + "  " + (keyboard.layouts.length > 0 ? keyboard.layouts[keyboard.currentLayout].shortName.toUpperCase() : "")
      onClicked: {   // next layout, if there are several
        if (keyboard.layouts.length > 1)
          keyboard.currentLayout = (keyboard.currentLayout + 1) % keyboard.layouts.length
        password.forceActiveFocus()
      }
    }
  }

  // ==== power menu, bottom right ====
  Row {
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.rightMargin: 36
    anchors.bottomMargin: 36
    spacing: 10
    layoutDirection: Qt.RightToLeft

    Pill {
      label: root.icon(0xf011)
      width: 44
      onClicked: root.powerOpen = !root.powerOpen
    }

    Pill {
      visible: root.powerOpen && sddm.canPowerOff
      label: root.icon(0xf011) + "  Shut down"
      onClicked: sddm.powerOff()
    }
    Pill {
      visible: root.powerOpen && sddm.canReboot
      label: root.icon(0xf01e) + "  Restart"
      onClicked: sddm.reboot()
    }
    Pill {
      visible: root.powerOpen && sddm.canSuspend
      label: root.icon(0xf186) + "  Sleep"
      onClicked: sddm.suspend()
    }
  }

  Component.onCompleted: password.forceActiveFocus()
}
