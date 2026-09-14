import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import ".."
import "../LookSchema.js" as LookSchema
import "../AnimSchema.js" as AnimSchema
import "../StyleLua.js" as StyleLua
import "../ShellSchema.js" as ShellSchema
import "../TomlEdit.js" as TomlEdit

// The named bezier curves and the curve editor.
Item {
  id: section

  // The Lacquer panel; state and actions all live there or in its stores.
  required property var app

  // The panel's P key plays the curve through this.
  function play() { curveEditor.play() }

  Flickable {
    id: curvePane
    anchors.fill: parent
    clip: true
    contentWidth: width
    contentHeight: curveColumn.implicitHeight
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: curveColumn
      width: curvePane.width - Style.spacing.xxl
      spacing: Style.spacing.lg

      Flow {
        width: parent.width
        spacing: Style.spacing.xs

        Repeater {
          model: app.hypr.curveNames

          Button {
            required property var modelData
            text: String(modelData) + (app.hypr.curveModified(String(modelData)) ? "  ·" : "")
            selected: app.curveName === String(modelData)
            bordered: true
            foreground: app.foreground
            accent: app.accent
            fontFamily: app.fontFamily
            onClicked: app.curveName = String(modelData)
          }
        }
      }

      CurveEditor {
        id: curveEditor
        width: parent.width
        points: app.hypr.curveValue(app.curveName)
        previewSpeed: {
          // Play at the speed of the first leaf using this curve, so
          // the strip runs for the duration it will really run for.
          for (var i = 0; i < AnimSchema.SECTIONS.length; i++) {
            var group = AnimSchema.SECTIONS[i].leaves
            for (var j = 0; j < group.length; j++) {
              var v = app.hypr.leafValue(group[j].name)
              if (v && v.enabled !== false && String(v.bezier) === app.curveName)
                return Number(v.speed)
            }
          }
          return 3
        }
        foreground: app.foreground
        accent: app.accent
        fontFamily: app.fontFamily
        onChanged: function(p) { app.hypr.setCurve(app.curveName, p, false) }
        onCommitted: function(p) { app.hypr.setCurve(app.curveName, p, true) }
      }

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        color: Qt.darker(app.foreground, 1.55)
        font.family: app.fontFamily
        font.pixelSize: Style.font.caption
        text: {
          var users = []
          for (var i = 0; i < AnimSchema.SECTIONS.length; i++) {
            var group = AnimSchema.SECTIONS[i].leaves
            for (var j = 0; j < group.length; j++) {
              var v = app.hypr.leafValue(group[j].name)
              if (v && v.enabled !== false && String(v.bezier) === app.curveName)
                users.push(group[j].name)
            }
          }
          if (users.length === 0) return "No enabled leaf uses this curve right now."
          return "Used by  " + users.join(", ")
        }
      }
    }
  }
}
