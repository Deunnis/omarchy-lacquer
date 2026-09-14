import QtQuick
import qs.Commons
import qs.Ui
import "AnimSchema.js" as AnimSchema

// One animation leaf: name and description left, its four Hyprland fields
// right — enabled, speed, bezier, style.
//
// Stateless about the value. `edited` fires continuously while a slider is
// dragged and only drives the live preview; `committed` is the point worth
// recording as a draft change.
//
// A leaf Omarchy ships no value for renders as inherited rather than as a
// made-up number: Hyprland resolves those from the parent at animation time
// and never reports the resolved figure, so any speed shown here would be a
// guess. Overriding materialises it from the parent instead.
Item {
  id: root

  // Lacquer's Motion switch; off makes every fade here instant.
  property bool animated: true

  required property var leafSpec
  property var value: null
  property bool inherited: false
  property bool modified: false
  property bool hasCursor: false
  // The panel's PointerMoveGate, so hover selection ignores synthetic motion.
  property QtObject gate: null
  property var curveNames: []
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family

  signal edited(var value)
  signal committed(var value)
  signal reset()
  signal takeOver()
  signal focusRequested()
  signal editCurve(string name)

  readonly property bool enabled_: !inherited && value && value.enabled !== false
  readonly property bool hasStyles: !!(leafSpec.styles && leafSpec.styles.length > 0)
  readonly property bool popupOpen: bezierDrop.popupOpen || styleDrop.popupOpen

  // A hand-edited block can carry a speed Number() cannot read; 1 ds is the
  // same neutral the schema uses for a leaf with no value at all.
  function safeSpeed() {
    var n = root.value ? Number(root.value.speed) : NaN
    return isFinite(n) ? n : 1
  }

  function withField(field, v) {
    var next = {
      enabled: root.value ? root.value.enabled !== false : true,
      speed: safeSpeed(),
      bezier: root.value ? String(root.value.bezier || "") : "default",
      style: root.value ? String(root.value.style || "") : ""
    }
    next[field] = v
    return next
  }

  function speedText() {
    if (!root.value) return "—"
    var n = Number(root.value.speed)
    if (!isFinite(n)) return "—"
    return n.toFixed(2) + "  ·  " + Math.round(n * 100) + "ms"
  }

  implicitHeight: body.implicitHeight + Style.spacing.xxl

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

  Item {
    id: body
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    implicitHeight: Math.max(labels.implicitHeight, controls.implicitHeight)

    Column {
      id: labels
      anchors.left: parent.left
      anchors.top: parent.top
      width: Math.round(parent.width * 0.34)
      spacing: Style.spacing.xxs

      Row {
        spacing: Style.spacing.sm
        width: parent.width

        Text {
          text: root.leafSpec.label
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }

        // Filled pip = this leaf differs from Omarchy's default.
        Rectangle {
          width: Style.space(5)
          height: width
          radius: width / 2
          color: root.accent
          opacity: root.modified ? 1 : 0
          anchors.verticalCenter: parent.verticalCenter
          Behavior on opacity { enabled: root.animated; NumberAnimation { duration: 120 } }
        }
      }

      Text {
        text: root.leafSpec.name
        color: Qt.darker(root.foreground, 1.9)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        text: root.leafSpec.description
        visible: text !== ""
        color: Qt.darker(root.foreground, 1.55)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        width: parent.width
        wrapMode: Text.WordWrap
      }
    }

    Column {
      id: controls
      anchors.left: labels.right
      anchors.leftMargin: Style.spacing.xxl
      anchors.right: parent.right
      anchors.top: parent.top
      spacing: Style.spacing.md

      // ------------------------------------------------- inherited state

      Row {
        visible: root.inherited
        height: visible ? implicitHeight : 0
        spacing: Style.spacing.lg

        Text {
          text: root.leafSpec.parent === ""
            ? "Not set — Hyprland's own default"
            : "Inherits from " + root.leafSpec.parent
          color: Qt.darker(root.foreground, 1.6)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          anchors.verticalCenter: parent.verticalCenter
        }

        Button {
          text: "Override"
          bordered: true
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          anchors.verticalCenter: parent.verticalCenter
          onClicked: root.takeOver()
        }
      }

      // ------------------------------------------------- enabled + speed

      Item {
        visible: !root.inherited
        width: controls.width
        height: visible ? Math.max(toggle.height, speedSlider.height, undoButton.height) : 0

        ToggleSwitch {
          id: toggle
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          checked: root.enabled_
          hasCursor: root.hasCursor
          foreground: root.foreground
          accent: root.accent
          onToggled: root.committed(root.withField("enabled", !root.enabled_))
        }

        PanelActionButton {
          id: undoButton
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰕌"
          tooltipText: "Reset to Omarchy default"
          foreground: root.foreground
          opacity: root.modified ? 1 : 0
          enabled: root.modified
          onClicked: root.reset()
          Behavior on opacity { enabled: root.animated; NumberAnimation { duration: 120 } }
        }

        Text {
          id: speedValue
          anchors.right: undoButton.left
          anchors.rightMargin: Style.spacing.lg
          anchors.verticalCenter: parent.verticalCenter
          text: root.speedText()
          color: root.modified ? root.accent : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          horizontalAlignment: Text.AlignRight
          width: Style.space(122)
          opacity: root.enabled_ ? 1 : 0.35
        }

        PanelSlider {
          id: speedSlider
          anchors.left: toggle.right
          anchors.leftMargin: Style.spacing.lg
          anchors.right: speedValue.left
          anchors.rightMargin: Style.spacing.lg
          anchors.verticalCenter: parent.verticalCenter
          enabled: root.enabled_
          opacity: root.enabled_ ? 1 : 0.35
          minimum: AnimSchema.SPEED_MIN
          maximum: Math.max(AnimSchema.SPEED_MAX, root.safeSpeed())
          step: 0.01
          value: root.safeSpeed()
          fillColor: root.modified ? root.accent : root.foreground
          knobColor: root.modified ? root.accent : root.foreground
          onMoved: function(v) { root.edited(root.withField("speed", v)) }
          onReleased: function(v) { root.committed(root.withField("speed", v)) }
        }
      }

      // ------------------------------------------------- bezier + style

      Row {
        visible: !root.inherited && root.enabled_
        height: visible ? implicitHeight : 0
        spacing: Style.spacing.lg

        Dropdown {
          id: bezierDrop
          label: "Curve"
          showLabel: true
          width: Style.space(150)
          options: root.curveNames
          value: root.value ? String(root.value.bezier || "") : ""
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          onChanged: function(v) { root.committed(root.withField("bezier", v)) }
        }

        PanelActionButton {
          iconText: "󰓅"
          tooltipText: "Edit this curve"
          foreground: root.foreground
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(3)
          onClicked: root.editCurve(root.value ? String(root.value.bezier || "") : "")
        }

        Dropdown {
          id: styleDrop
          label: "Style"
          showLabel: true
          visible: root.hasStyles
          width: Style.space(170)
          options: root.leafSpec.styles
          value: root.value ? String(root.value.style || "") : ""
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          onChanged: function(v) { root.committed(root.withField("style", v)) }
        }
      }
    }
  }
}
