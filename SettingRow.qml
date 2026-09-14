import QtQuick
import qs.Commons
import qs.Ui

// One setting from a plugin manifest's `barWidget.schema`.
//
// Omarchy 4.0.3 renders these nowhere: the shell carries `schema`, `defaults`
// and `settingsForm` as registry metadata and every control they imply exists
// in qs.Ui, but nothing joins the two. So this is the join — one row that
// picks a control from the declared `type`.
//
// `type` is a convention, not an enforced enum (PluginRegistry validates
// neither), so an unknown type falls back to a text field rather than
// rendering nothing and hiding the setting entirely.
Item {
  id: root

  // Lacquer's Motion switch; off makes every fade here instant.
  property bool animated: true

  required property var spec
  property var value: undefined
  property var fallback: undefined
  property bool modified: false
  property bool hasCursor: false
  // The panel's PointerMoveGate, so hover selection ignores synthetic motion.
  property QtObject gate: null
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family

  signal committed(var value)
  signal reset()
  signal focusRequested()
  signal editingDone()

  readonly property string kind: {
    var t = String(root.spec.type || "")
    if (t === "boolean") return "bool"
    if (t === "integer" || t === "number") return "num"
    if (t === "enum") return "enum"
    if (t === "array" || t === "multiselect") return "json"
    return "text"
  }
  readonly property bool popupOpen: enumDrop.popupOpen

  readonly property var effective: root.value !== undefined ? root.value : root.fallback
  readonly property bool boolValue: effective === true || String(effective) === "true"
  property real dragValue: NaN
  readonly property real numValue: {
    if (!isNaN(root.dragValue)) return root.dragValue
    var n = Number(effective)
    return isFinite(n) ? n : (root.spec.min !== undefined ? Number(root.spec.min) : 0)
  }
  readonly property string textValue: {
    if (effective === undefined || effective === null) return ""
    if (root.kind === "json") return JSON.stringify(effective)
    return String(effective)
  }
  readonly property bool hasRange: root.spec.min !== undefined && root.spec.max !== undefined

  readonly property var enumOptions: {
    var raw = root.spec.options || []
    var out = []
    for (var i = 0; i < raw.length; i++) {
      var entry = raw[i]
      if (entry !== null && typeof entry === "object")
        out.push({ value: String(entry.value), label: String(entry.label !== undefined ? entry.label : entry.value) })
      else
        out.push({ value: String(entry), label: String(entry) })
    }
    return out
  }

  implicitHeight: Math.max(labels.implicitHeight, control.implicitHeight) + Style.spacing.xxl

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
        text: root.spec.label || root.spec.key
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
    }

    Text {
      text: root.spec.key
      color: Qt.darker(root.foreground, 1.9)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Text {
      text: root.spec.description || ""
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
        tooltipText: "Back to the plugin's default"
        foreground: root.foreground
        opacity: root.modified ? 1 : 0
        enabled: root.modified
        onClicked: root.reset()
        Behavior on opacity { enabled: root.animated; NumberAnimation { duration: 120 } }
      }
    }

    Text {
      visible: root.kind === "num" && root.hasRange
      text: String(root.numValue) + (root.spec.unit || "")
      color: root.modified ? root.accent : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      horizontalAlignment: Text.AlignRight
      width: Style.space(58)
      anchors.verticalCenter: parent.verticalCenter
    }

    ToggleSwitch {
      visible: root.kind === "bool"
      checked: root.boolValue
      hasCursor: root.hasCursor
      foreground: root.foreground
      accent: root.accent
      anchors.verticalCenter: parent.verticalCenter
      onToggled: root.committed(!root.boolValue)
    }

    PanelSlider {
      visible: root.kind === "num" && root.hasRange
      width: Math.max(Style.space(90), control.width - undoButton.width - Style.space(58) - Style.spacing.lg * 2)
      minimum: Math.min(Number(root.spec.min), root.numValue)
      maximum: Math.max(Number(root.spec.max), root.numValue)
      step: root.spec.step === undefined ? 1 : Number(root.spec.step)
      integer: String(root.spec.type) === "integer"
      value: root.numValue
      fillColor: root.modified ? root.accent : root.foreground
      knobColor: root.modified ? root.accent : root.foreground
      anchors.verticalCenter: parent.verticalCenter
      onMoved: function(v) { root.dragValue = v }
      onReleased: function(v) { root.dragValue = NaN; root.committed(v) }
    }

    Dropdown {
      id: enumDrop
      visible: root.kind === "enum"
      width: Style.space(200)
      options: root.enumOptions
      value: String(root.effective === undefined ? "" : root.effective)
      showLabel: false
      foreground: root.foreground
      accent: root.accent
      fontFamily: root.fontFamily
      anchors.verticalCenter: parent.verticalCenter
      onChanged: function(v) { root.committed(v) }
    }

    // Covers plain strings, paths, unbounded numbers, and JSON arrays. A bad
    // JSON edit is refused rather than written, so a typo cannot corrupt the
    // plugin's settings.
    TextField {
      id: textInput
      visible: root.kind === "text" || root.kind === "json"
        || (root.kind === "num" && !root.hasRange)
      width: Math.max(Style.space(140), control.width - undoButton.width - Style.spacing.lg)
      anchors.verticalCenter: parent.verticalCenter
      foreground: root.foreground
      accent: root.accent
      text: root.textValue

      Connections {
        target: root
        function onTextValueChanged() { textInput.text = root.textValue }
      }

      function commit() {
        if (text === root.textValue) return
        if (root.kind === "json") {
          try {
            root.committed(JSON.parse(text))
          } catch (e) {
            text = root.textValue
          }
          return
        }
        if (root.kind === "num") {
          var n = Number(text)
          if (isFinite(n)) root.committed(n)
          else text = root.textValue
          return
        }
        root.committed(text)
      }

      onEditingFinished: { commit(); root.editingDone() }
      onActiveFocusChanged: if (!activeFocus) commit()
    }
  }
}
