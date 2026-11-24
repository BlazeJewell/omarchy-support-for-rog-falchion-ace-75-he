import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons

// Keyboard light: colour and effect for the ROG Falchion Ace 75 HE, through kbd.py.
// Every change is sent at once; it is saved to the keyboard a moment after the
// last change, so it survives unplugging without writing on every slider step.
Panel {
  id: root
  moduleName: "jake.keyboard-light"
  ipcTarget: "jake.keyboard-light"

  readonly property string helper: Qt.resolvedUrl("kbd.py").toString().replace(/^file:\/\//, "")

  // what kbd.py status reported
  property bool found: false
  property bool access: false
  property bool checked: false
  property string firmware: ""

  // current settings (mirrors ~/.config/omarchy/keyboard-light.json)
  property string mode: "static"
  property string color: "00b3b3"
  property int speed: 50
  property int brightness: 4
  property string direction: "left"
  property bool rainbow: false
  // keys: actuation point (mm) and Rapid Trigger, read from the keyboard
  property real travel: 0
  property bool rapidTrigger: false
  property bool hasKeys: false

  readonly property var effects: [
    { id: "static",    label: "Static" },
    { id: "breathing", label: "Breathing" },
    { id: "cycle",     label: "Colour cycle" },
    { id: "wave",      label: "Wave" },
    { id: "ripple",    label: "Ripple" },
    { id: "reactive",  label: "Reactive" },
    { id: "starry",    label: "Starry night" },
    { id: "rain",      label: "Rain drop" }
  ]
  readonly property var swatches: ["00b3b3", "ff0000", "ff6000", "ffd000", "00ff40", "0060ff", "8000ff", "ff00a0", "ffffff"]
  readonly property bool usesColor: mode !== "cycle" && !(rainbow && hasRainbow)
  readonly property bool hasRainbow: ["breathing", "wave", "ripple", "reactive", "starry", "rain"].indexOf(mode) !== -1
  readonly property bool hasSpeed: mode !== "static"
  readonly property bool hasDirection: mode === "wave"
  readonly property string effectLabel: {
    for (var i = 0; i < effects.length; i++) if (effects[i].id === mode) return effects[i].label
    return mode
  }

  function hexToColor(h) { return "#" + h }
  function hueOf(h) { var c = Qt.color("#" + h); return c.hslHue < 0 ? 0 : Math.round(c.hslHue * 360) }
  function hueToHex(deg) {
    var c = Qt.hsla(deg / 360, 1, 0.5, 1)
    function two(v) { var s = Math.round(v * 255).toString(16); return s.length < 2 ? "0" + s : s }
    return two(c.r) + two(c.g) + two(c.b)
  }

  function set(key, value) {
    root[key] = value
    applyTimer.restart()
  }
  function apply() {
    if (!root.found || !root.access) return
    if (applyProc.running) { root.applyQueued = true; return }
    applyProc.command = ["python3", "-I", root.helper, "apply",
      "mode=" + root.mode, "color=" + root.color, "speed=" + root.speed,
      "brightness=" + root.brightness, "direction=" + root.direction,
      "rainbow=" + (root.rainbow ? 1 : 0)]
    applyProc.running = true
    saveTimer.restart()
  }
  property bool applyQueued: false
  function setTravel(mm) {
    root.travel = Math.round(mm * 10) / 10
    travelTimer.restart()
  }
  function refresh() { if (!statusProc.running) statusProc.running = true }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  Component.onCompleted: refresh()
  onOpenedChanged: if (opened) refresh()

  Process {
    id: statusProc
    command: ["python3", "-I", root.helper, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var d = JSON.parse(String(text))
          root.found = !!d.found
          root.access = !!d.access
          root.firmware = String(d.firmware || "")
          root.hasKeys = typeof d.travel === "number"
          if (root.hasKeys && !travelTimer.running && !travelProc.running) root.travel = d.travel
          if (typeof d.rapidTrigger === "boolean") root.rapidTrigger = d.rapidTrigger
          var s = d.settings || {}
          if (!applyTimer.running && !applyProc.running) {
            root.mode = String(s.mode || "static")
            root.color = String(s.color || "00b3b3")
            root.speed = Number(s.speed) || 0
            root.brightness = Number(s.brightness)
            root.direction = String(s.direction || "left")
            root.rainbow = Number(s.rainbow) === 1
          }
        } catch (e) {
          root.found = false
        }
        root.checked = true
      }
    }
  }
  Timer { id: applyTimer; interval: 90; onTriggered: root.apply() }
  Process {
    id: applyProc
    onRunningChanged: if (!running && root.applyQueued) { root.applyQueued = false; root.apply() }
  }
  Timer {
    id: travelTimer; interval: 150
    onTriggered: {
      if (travelProc.running) { restart(); return }
      travelProc.command = ["python3", "-I", root.helper, "travel", root.travel.toFixed(2), "--preview"]
      travelProc.running = true
      saveTimer.stop()
      restoreTimer.restart()
    }
  }
  Process { id: travelProc }
  // the light bar shows the travel while it changes, like the keyboard's own
  // control; then the lighting effect comes back and everything is saved
  Timer {
    id: restoreTimer; interval: 1200
    onTriggered: {
      if (travelProc.running || travelTimer.running) { restart(); return }
      restoreProc.command = ["python3", "-I", root.helper, "restore"]
      restoreProc.running = true
      saveTimer.restart()
    }
  }
  Process { id: restoreProc }
  // Rapid Trigger is the keyboard's own switch (the firmware refuses it from
  // software, and Gear Link only reads it), so follow it while the panel is open
  Timer { interval: 1500; repeat: true; running: root.opened && root.hasKeys; onTriggered: root.refresh() }
  // save to the keyboard once changes have settled
  Timer { id: saveTimer; interval: 1500; onTriggered: { saveProc.command = ["python3", "-I", root.helper, "save"]; saveProc.running = true } }
  Process { id: saveProc }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰌌"
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(600))

    content: PanelKeyCatcher {
      id: keyCatcher
      implicitHeight: panelColumn.implicitHeight
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        Column {
          id: panelColumn
          width: scrollArea.availableWidth
          spacing: Style.space(14)

          // ---------- hero ----------
          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)
            Text {
              id: heroIcon
              textFormat: Text.PlainText
              text: "󰌌"
              color: root.found && root.access && root.usesColor ? root.hexToColor(root.color) : root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.display
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }
            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)
              Text {
                textFormat: Text.PlainText
                text: "Keyboard light"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                width: parent.width
                elide: Text.ElideRight
              }
              Text {
                textFormat: Text.PlainText
                text: !root.checked ? "LOOKING…"
                  : !root.found ? "KEYBOARD NOT FOUND"
                  : !root.access ? "NO PERMISSION · SEE README"
                  : root.brightness === 0 ? "OFF"
                  : root.effectLabel.toUpperCase()
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                width: parent.width
                elide: Text.ElideRight
              }
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(14)
            visible: root.found && root.access

            // ---------- effect ----------
            PanelSeparator { foreground: root.bar.foreground }
            PanelSectionHeader {
              text: "Effect"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
            }
            Flow {
              width: parent.width
              spacing: Style.space(6)
              Repeater {
                model: root.effects
                delegate: Button {
                  required property var modelData
                  text: modelData.label
                  fontSize: Style.font.caption
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  horizontalPadding: Style.spacing.sm
                  verticalPadding: Style.spacing.controlPaddingY
                  bordered: true
                  active: root.mode === modelData.id
                  onClicked: root.set("mode", modelData.id)
                }
              }
            }

            // ---------- colour ----------
            PanelSeparator { foreground: root.bar.foreground; visible: root.mode !== "cycle" }
            Item {
              width: parent.width
              visible: root.mode !== "cycle"
              implicitHeight: colourHeader.implicitHeight
              PanelSectionHeader {
                id: colourHeader
                text: "Colour"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }
              Row {
                visible: root.hasRainbow
                spacing: Style.space(8)
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                Text {
                  textFormat: Text.PlainText
                  text: "Rainbow"
                  color: Qt.darker(root.bar.foreground, 1.4)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  anchors.verticalCenter: parent.verticalCenter
                }
                ToggleSwitch {
                  checked: root.rainbow
                  foreground: root.bar.foreground
                  anchors.verticalCenter: parent.verticalCenter
                  onToggled: root.set("rainbow", !root.rainbow)
                }
              }
            }
            Flow {
              width: parent.width
              spacing: Style.space(8)
              visible: root.mode !== "cycle"
              opacity: root.usesColor ? 1 : 0.35
              Repeater {
                model: root.swatches
                delegate: Rectangle {
                  required property string modelData
                  width: Style.space(26); height: width
                  radius: Style.cornerRadius > 0 ? width / 2 : 0
                  color: "#" + modelData
                  border.width: root.color === modelData ? 2 : 1
                  border.color: root.color === modelData ? root.bar.foreground : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.25)
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    enabled: root.usesColor
                    onClicked: root.set("color", parent.modelData)
                  }
                }
              }
            }
            // any colour: a hue slider over a rainbow track
            Item {
              width: parent.width
              visible: root.mode !== "cycle"
              opacity: root.usesColor ? 1 : 0.35
              implicitHeight: hueSlider.implicitHeight + Style.spacing.controlGap
              Rectangle {
                anchors.left: parent.left; anchors.right: parent.right
                anchors.leftMargin: Style.space(6); anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                height: Math.max(6, hueSlider.trackHeight + 2)
                radius: height / 2
                gradient: Gradient {
                  orientation: Gradient.Horizontal
                  GradientStop { position: 0.000; color: "#ff0000" }
                  GradientStop { position: 0.167; color: "#ffff00" }
                  GradientStop { position: 0.333; color: "#00ff00" }
                  GradientStop { position: 0.500; color: "#00ffff" }
                  GradientStop { position: 0.667; color: "#0000ff" }
                  GradientStop { position: 0.833; color: "#ff00ff" }
                  GradientStop { position: 1.000; color: "#ff0000" }
                }
              }
              PanelSlider {
                id: hueSlider
                bar: root.bar
                enabled: root.usesColor
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                minimum: 0; maximum: 359; step: 1; integer: true
                value: root.hueOf(root.color)
                trackColor: "transparent"
                fillColor: "transparent"
                knobColor: root.hexToColor(root.color)
                onMoved: function(v) { root.set("color", root.hueToHex(v)) }
                onReleased: function(v) { root.set("color", root.hueToHex(v)) }
              }
            }

            // ---------- speed ----------
            PanelSeparator { foreground: root.bar.foreground; visible: root.hasSpeed }
            Column {
              width: parent.width
              spacing: Style.space(6)
              visible: root.hasSpeed
              PanelSectionHeader {
                text: "Speed"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
              }
              Item {
                width: parent.width
                implicitHeight: speedSlider.implicitHeight + Style.spacing.controlGap
                PanelSlider {
                  id: speedSlider
                  bar: root.bar
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(6)
                  anchors.rightMargin: Style.space(6)
                  minimum: 0; maximum: 100; step: 5; integer: true
                  value: root.speed
                  onMoved: function(v) { root.set("speed", Math.round(v)) }
                  onReleased: function(v) { root.set("speed", Math.round(v)) }
                }
              }
            }

            // ---------- direction (wave) ----------
            Row {
              visible: root.hasDirection
              spacing: Style.space(6)
              Repeater {
                model: [{ id: "left", label: "← Left" }, { id: "right", label: "Right →" }, { id: "up", label: "↑ Up" }, { id: "down", label: "Down ↓" }]
                delegate: Button {
                  required property var modelData
                  text: modelData.label
                  fontSize: Style.font.caption
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  horizontalPadding: Style.spacing.sm
                  verticalPadding: Style.spacing.controlPaddingY
                  bordered: true
                  active: root.direction === modelData.id
                  onClicked: root.set("direction", modelData.id)
                }
              }
            }

            // ---------- brightness ----------
            PanelSeparator { foreground: root.bar.foreground }
            Item {
              width: parent.width
              implicitHeight: brightHeader.implicitHeight
              PanelSectionHeader {
                id: brightHeader
                text: "Brightness"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                textFormat: Text.PlainText
                text: root.brightness === 0 ? "Off" : Commons.I18n.formatNumber(root.brightness * 25) + "%"
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }
            }
            Item {
              width: parent.width
              implicitHeight: brightSlider.implicitHeight + Style.spacing.controlGap
              PanelSlider {
                id: brightSlider
                bar: root.bar
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                minimum: 0; maximum: 4; step: 1; integer: true
                tickCount: 5
                value: root.brightness
                onMoved: function(v) { root.set("brightness", Math.round(v)) }
                onReleased: function(v) { root.set("brightness", Math.round(v)) }
              }
            }

            // ---------- keys: travel + Rapid Trigger ----------
            PanelSeparator { foreground: root.bar.foreground; visible: root.hasKeys }
            Item {
              width: parent.width
              visible: root.hasKeys
              implicitHeight: travelHeader.implicitHeight
              PanelSectionHeader {
                id: travelHeader
                text: "Key travel"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                textFormat: Text.PlainText
                text: Commons.I18n.formatNumber(travelSlider.dragging ? Math.round(travelSlider.liveValue * 10) / 10 : root.travel, 1) + " mm"
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }
            }
            Item {
              width: parent.width
              visible: root.hasKeys
              implicitHeight: travelSlider.implicitHeight + Style.spacing.controlGap
              PanelSlider {
                id: travelSlider
                bar: root.bar
                anchors.fill: parent
                anchors.leftMargin: Style.space(6)
                anchors.rightMargin: Style.space(6)
                minimum: 0.1; maximum: 3.5; step: 0.1
                value: root.travel
                onMoved: function(v) { root.setTravel(v) }
                onReleased: function(v) { root.setTravel(v) }
              }
            }
            Item {
              width: parent.width
              visible: root.hasKeys
              implicitHeight: travelHint.implicitHeight
              Text {
                id: travelHint
                textFormat: Text.PlainText
                text: "Shallow · fast"
                color: Qt.darker(root.bar.foreground, 1.6)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                anchors.left: parent.left
                anchors.leftMargin: Style.space(6)
              }
              Text {
                textFormat: Text.PlainText
                text: "Deep · deliberate"
                color: Qt.darker(root.bar.foreground, 1.6)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
              }
            }
            Item {
              width: parent.width
              visible: root.hasKeys
              implicitHeight: Math.max(rtLabels.implicitHeight, rtSwitch.implicitHeight)
              Column {
                id: rtLabels
                anchors.left: parent.left
                anchors.right: rtSwitch.left
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)
                PanelSectionHeader {
                  text: "Rapid Trigger"
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                }
                Text {
                  textFormat: Text.PlainText
                  text: "Set with the switch on the keyboard"
                  color: Qt.darker(root.bar.foreground, 1.6)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  width: parent.width
                  wrapMode: Text.WordWrap
                }
              }
              Text {
                id: rtSwitch
                textFormat: Text.PlainText
                text: root.rapidTrigger ? "ON" : "OFF"
                color: root.rapidTrigger ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.6)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Text {
              textFormat: Text.PlainText
              text: "ROG Falchion Ace 75 HE" + (root.firmware ? " · firmware " + root.firmware : "")
              color: Qt.darker(root.bar.foreground, 1.6)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              width: parent.width
              elide: Text.ElideRight
            }
          }
        }
      }
    }
  }
}
