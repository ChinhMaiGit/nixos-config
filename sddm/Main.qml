// Omarchy's SDDM login theme (basecamp/omarchy default/sddm/omarchy/Main.qml, MIT,
// (c) David Heinemeier Hansson), with one addition for Chinh: the session is shown at the
// bottom and F2 switches it, so Plasma stays reachable while it's kept as a fallback.
// Also for Chinh: "Welcome back" instead of the Omarchy logo, and his Wallpaper.jpg behind a
// half-transparent dark layer instead of the solid colour (copied in by sddm-theme.nix; SDDM
// runs as its own user and can't read the current wallpaper from his home folder).
import QtQuick 2.0
import SddmComponents 2.0

Rectangle {
  id: root
  width: 640
  height: 480
  color: "#1a1b26"

  Image {
    anchors.fill: parent
    source: "background.jpg"
    fillMode: Image.PreserveAspectCrop
  }

  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0.102, 0.106, 0.149, 0.5)   // #1a1b26 at 50 %
  }

  property string currentUser: userModel.lastUser
  property bool loginFailed: false
  // Session names via the model's "name" role (Qt.DisplayRole, which Omarchy's original reads,
  // is empty with this SDDM, so its uwsm auto-pick fell back to the last session).
  property var sessionNames: []
  property int sessionIndex: {
    for (var i = 0; i < sessionNames.length; i++) {
      if (sessionNames[i].indexOf("uwsm") !== -1)
        return i
    }
    return sessionModel.lastIndex
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

  Connections {
    target: sddm
    function onLoginFailed() {
      root.loginFailed = true
      password.text = ""
      password.focus = true
    }
    function onLoginSucceeded() {
      root.loginFailed = false
    }
  }

  Column {
    anchors.centerIn: parent
    spacing: 40

    Text {
      text: "Welcome back"
      color: "#c0caf5"
      font.family: "JetBrainsMono Nerd Font"
      font.pixelSize: 56
      font.weight: Font.DemiBold
      style: Text.Raised
      styleColor: Qt.rgba(0, 0, 0, 0.4)
      anchors.horizontalCenter: parent.horizontalCenter
    }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 15

      Image {
        source: root.loginFailed ? "lock-failed.png" : "lock.png"
        width: 34
        height: 38
        fillMode: Image.PreserveAspectFit
        anchors.verticalCenter: parent.verticalCenter
      }

      Item {
        width: entry.width
        height: entry.height

        Image {
          id: entry
          source: root.loginFailed ? "entry-failed.png" : "entry.png"
          anchors.centerIn: parent
        }

        Row {
          anchors.left: parent.left
          anchors.leftMargin: 20
          anchors.verticalCenter: parent.verticalCenter
          spacing: 5

          Repeater {
            model: Math.min(password.text.length, 21)

            Image {
              source: "bullet.png"
              width: 7
              height: 7
            }
          }
        }

        TextInput {
          id: password
          anchors.fill: parent
          anchors.leftMargin: 20
          anchors.rightMargin: 20
          verticalAlignment: TextInput.AlignVCenter
          echoMode: TextInput.Password
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: 24
          font.letterSpacing: 5
          passwordCharacter: "\u2022"
          color: "transparent"
          selectionColor: "transparent"
          selectedTextColor: "transparent"
          cursorDelegate: Item {}
          focus: true

          onTextChanged: root.loginFailed = false

          Keys.onPressed: function(event) {   // explicit parameter; Qt 6 deprecates the injected one
            if (event.key === Qt.Key_F2) {
              // Skip plain "Hyprland": the desktop's services start only in the UWSM session.
              var next = root.sessionIndex
              do {
                next = (next + 1) % root.sessionNames.length
              } while (root.sessionNames[next] === "Hyprland" && next !== root.sessionIndex)
              root.sessionIndex = next
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              sddm.login(root.currentUser, password.text, root.sessionIndex)
              event.accepted = true
            }
          }
        }
      }
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: (root.sessionNames[root.sessionIndex] || "") + "   ·   F2 to switch"
      color: "#a9b1d6"
      style: Text.Outline                        // readable over bright parts of the wallpaper
      styleColor: Qt.rgba(0, 0, 0, 0.6)
      font.family: "JetBrainsMono Nerd Font"
      font.pixelSize: 14
    }

  }

  Component.onCompleted: password.forceActiveFocus()
}
