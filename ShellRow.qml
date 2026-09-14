import QtQuick
import qs.Commons
import qs.Ui

// One ~/.config/omarchy/shell.toml option.
//
// Colour rows carry a warning the other rows do not: this file beats the
// theme's own shell.toml and survives theme switches, so pinning a colour here
// means aether and OmaShuffle can no longer move it. That is worth saying on
// the row rather than burying in a README, hence the "pins theme" chip and the
// one-click clear.
//
// A colour is free text because the value is not always a colour: Omarchy's
// own defaults use tokens like `hyprland.active-border`. The swatch renders
// whatever Qt can parse and steps aside when it cannot.
Item {
  id: root

  // Lacquer's Motion switch; off makes every fade here instant.
  property bool animated: true

  required property var item
  property var value: undefined
  property var themeValue: undefined
  property bool modified: false
  property bool hasCursor: false
  // The panel's PointerMoveGate, so hover selection ignores synthetic motion.
  property QtObject gate: null
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family

  signal edited(var value)
  signal committed(var value)
  signal reset()
  signal focusRequested()
  signal editingDone()

  readonly property bool isBool: item.type === "bool"
  readonly property bool isColor: item.type === "color"
  readonly property bool isNum: item.type === "num"

  readonly property real numValue: {
    var n = Number(root.value)
    if (isFinite(n)) return n
    var t = Number(root.themeValue)
    return isFinite(t) ? t : (root.item.min || 0)
  }
  readonly property bool boolValue: {
    if (root.value !== undefined) return String(root.value) === "true"
    return String(root.themeValue) === "true"
  }
  readonly property string colorText: {
    if (root.value !== undefined) return String(root.value)
    if (root.themeValue !== undefined) return String(root.themeValue)
    return ""
  }

  function formatted() {
    if (!isNum) return ""
    var step = root.item.step === undefined ? 1 : root.item.step
    var text = step >= 1 ? String(Math.round(numValue))
      : numValue.toFixed(String(step).split(".")[1].length)
    return text + (root.item.unit || "")
  }

  implicitHeight: Math.max(labels.implicitHeight, control.implicitHeight) + Style.spacing.xxl
  Behavior on opacity { enabled: root.animated; NumberAnimation { duration: 120 } }

  Rectangle {
    anchors.fill: parent
    anchors.leftMargin: -Style.spacing.md
    anchors.rightMargin: -Style.spacing.md
    radius: Style.cornerRadius
    color: root.hasCursor ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
    Behavior on color { enabled: root.animated; ColorAnimation { duration: 100 } }
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.NoButton
    hoverEnabled: true
    // Only real pointer motion moves the cursor. A row sliding under a mouse
    // that is just resting on the panel — which happens every time the list
    // changes, and the panel opens centred — must not steal keyboard focus.
    onPositionChanged: function(mouse) {
      if (!root.gate || root.gate.moved(this, mouse)) root.focusRequested()
    }
  }

  Column {
    id: labels
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: Math.round(parent.width * 0.40)
    spacing: Style.spacing.xxs

    Row {
      spacing: Style.spacing.sm
      width: parent.width

      Text {
        text: root.item.label
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      Rectangle {
        width: Style.space(5)
        height: width
        radius: width / 2
        color: root.accent
        opacity: root.modified ? 1 : 0
        anchors.verticalCenter: parent.verticalCenter
        Behavior on opacity { enabled: root.animated; NumberAnimation { duration: 120 } }
      }

      // Only shown once the colour is actually pinned, so the warning appears
      // at the moment it becomes true rather than nagging on every row.
      Rectangle {
        visible: root.isColor && root.modified
        anchors.verticalCenter: parent.verticalCenter
        radius: Style.cornerRadius
        color: Style.selectedFillFor(Color.urgent, Color.urgent)
        width: pinLabel.implicitWidth + Style.spacing.md
        height: pinLabel.implicitHeight + Style.spacing.xs

        Text {
          id: pinLabel
          anchors.centerIn: parent
          text: "pins theme"
          color: Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }

    Text {
      text: root.item.description
      visible: text !== ""
      color: Qt.darker(root.foreground, 1.55)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      width: parent.width
      wrapMode: Text.WordWrap
    }
  }

  Row {
    id: control
    anchors.right: parent.right
    anchors.left: labels.right
    anchors.leftMargin: Style.spacing.xxl
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.spacing.lg
    layoutDirection: Qt.RightToLeft

    Item {
      width: undoButton.width
      height: undoButton.height
      anchors.verticalCenter: parent.verticalCenter

      PanelActionButton {
        id: undoButton
        iconText: "󰕌"
        tooltipText: root.isColor ? "Clear — hand this back to your theme" : "Clear — follow your theme"
        foreground: root.foreground
        opacity: root.modified ? 1 : 0
        enabled: root.modified
        onClicked: root.reset()
        Behavior on opacity { enabled: root.animated; NumberAnimation { duration: 120 } }
      }
    }

    Text {
      visible: root.isNum
      text: root.formatted()
      color: root.modified ? root.accent : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      horizontalAlignment: Text.AlignRight
      width: Style.space(58)
      anchors.verticalCenter: parent.verticalCenter
    }

    ToggleSwitch {
      visible: root.isBool
      checked: root.boolValue
      hasCursor: root.hasCursor
      foreground: root.foreground
      accent: root.accent
      anchors.verticalCenter: parent.verticalCenter
      onToggled: root.committed(!root.boolValue)
    }

    PanelSlider {
      visible: root.isNum
      width: Math.max(Style.space(90), control.width - undoButton.width - Style.space(58) - Style.spacing.lg * 2)
      minimum: Math.min(root.item.min, root.numValue)
      maximum: Math.max(root.item.max, root.numValue)
      step: root.item.step === undefined ? 1 : root.item.step
      integer: (root.item.step === undefined ? 1 : root.item.step) >= 1
      value: root.numValue
      fillColor: root.modified ? root.accent : root.foreground
      knobColor: root.modified ? root.accent : root.foreground
      anchors.verticalCenter: parent.verticalCenter
      onMoved: function(v) { root.edited(v) }
      onReleased: function(v) { root.committed(v) }
    }

    TextField {
      id: colorField
      visible: root.isColor
      width: Math.max(Style.space(120), control.width - undoButton.width - swatch.width - Style.spacing.lg * 2)
      anchors.verticalCenter: parent.verticalCenter
      foreground: root.foreground
      accent: root.accent
      text: root.colorText

      Connections {
        target: root
        function onColorTextChanged() { colorField.text = root.colorText }
      }

      onEditingFinished: {
        if (text !== root.colorText) root.committed(text)
        root.editingDone()
      }
      onActiveFocusChanged: if (!activeFocus && text !== root.colorText) root.committed(text)
    }

    // Steps aside for a token the palette cannot resolve, rather than
    // painting a misleading black square.
    Rectangle {
      id: swatch
      visible: root.isColor
      width: Style.space(26)
      height: Style.space(20)
      radius: Style.cornerRadius
      anchors.verticalCenter: parent.verticalCenter
      border.width: 1
      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.35)
      color: {
        var t = root.colorText
        if (/^#([0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(t)) return t
        return "transparent"
      }

      Text {
        anchors.centerIn: parent
        visible: parent.color.a === 0
        text: "—"
        color: Qt.darker(root.foreground, 1.6)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
