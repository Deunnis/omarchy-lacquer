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

// Settings for every installed plugin, rendered from its manifest schema.
Item {
  id: section

  // The Lacquer panel; state and actions all live there or in its stores.
  required property var app

  Flickable {
    id: pluginPane
    anchors.fill: parent
    clip: true
    contentWidth: width
    contentHeight: pluginColumn.implicitHeight
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: pluginColumn
      width: pluginPane.width - Style.spacing.xxl
      spacing: Style.spacing.lg

      readonly property var configurable: {
        var out = []
        for (var i = 0; i < app.sjson.plugins.length; i++)
          if ((app.sjson.plugins[i].schema || []).length > 0) out.push(app.sjson.plugins[i])
        return out
      }
      readonly property var current: app.sjson.pluginFor(app.selectedPlugin)

      Flow {
        width: parent.width
        spacing: Style.spacing.xs

        Repeater {
          model: pluginColumn.configurable

          Button {
            required property var modelData
            text: modelData.displayName + (app.sjson.pluginTouched(modelData) ? "  ·" : "")
            selected: app.selectedPlugin === modelData.id
            bordered: true
            foreground: app.foreground
            accent: app.accent
            fontFamily: app.fontFamily
            onClicked: app.selectedPlugin = modelData.id
          }
        }
      }

      PanelSeparator { foreground: app.foreground; width: parent.width }

      Column {
        width: parent.width
        spacing: Style.spacing.xxs
        visible: pluginColumn.current !== null

        Text {
          text: pluginColumn.current ? pluginColumn.current.name : ""
          color: app.foreground
          font.family: app.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Text {
          text: pluginColumn.current
            ? pluginColumn.current.id + "   ·   " + pluginColumn.current.kinds.join(", ")
              + (app.sjson.barSectionOf(pluginColumn.current.id) !== ""
                 ? "   ·   on the bar (" + app.sjson.barSectionOf(pluginColumn.current.id) + ")"
                 : (app.sjson.pluginEnabled(pluginColumn.current) ? "   ·   enabled" : "   ·   not enabled"))
            : ""
          color: Qt.darker(app.foreground, 1.7)
          font.family: app.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          width: parent.width
          text: pluginColumn.current ? pluginColumn.current.description : ""
          visible: text !== ""
          color: Qt.darker(app.foreground, 1.55)
          font.family: app.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }

      Column {
        width: parent.width
        spacing: 0

        Repeater {
          model: pluginColumn.current ? (pluginColumn.current.schema || []) : []

          SettingRow {
            required property var modelData
            width: pluginColumn.width
            spec: modelData
            value: app.sjson.settingValue(pluginColumn.current, modelData.key)
            fallback: modelData.defaultValue !== undefined
              ? modelData.defaultValue
              : ((pluginColumn.current && pluginColumn.current.defaults) || {})[modelData.key]
            modified: app.sjson.settingModified(pluginColumn.current, modelData.key)
            foreground: app.foreground
            accent: app.accent
            fontFamily: app.fontFamily
            gate: app.pointerGate
            animated: app.motion
            onCommitted: function(v) { app.sjson.setSetting(pluginColumn.current, modelData, v) }
            onReset: app.sjson.resetSetting(pluginColumn.current, modelData)
            onEditingDone: Qt.callLater(function() { app.focusPanel() })
            // An enum dropdown in this pane had no handler, so closing
            // one left the keyboard stranded in the popup.
            onPopupOpenChanged: if (!popupOpen) Qt.callLater(function() { app.focusPanel() })
          }
        }
      }

      Text {
        width: parent.width
        visible: pluginColumn.configurable.length === 0
        text: "No installed plugin declares settings in its manifest."
        color: Qt.darker(app.foreground, 1.55)
        font.family: app.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
