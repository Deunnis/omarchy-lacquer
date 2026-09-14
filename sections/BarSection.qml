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

// Bar placement and the three-column widget layout editor.
Item {
  id: section

  // The Lacquer panel; state and actions all live there or in its stores.
  required property var app

  Flickable {
    id: barPane
    anchors.fill: parent
    clip: true
    contentWidth: width
    contentHeight: barColumn.implicitHeight
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: barColumn
      width: barPane.width - Style.spacing.xxl
      spacing: Style.spacing.lg

      PanelSectionHeader {
        text: "Placement"
        foreground: app.foreground
        fontFamily: app.fontFamily
      }

      Row {
        spacing: Style.spacing.lg
        width: parent.width

        Text {
          text: "Position"
          color: app.foreground
          font.family: app.fontFamily
          font.pixelSize: Style.font.body
          width: Style.space(110)
          anchors.verticalCenter: parent.verticalCenter
        }

        ButtonGroup {
          anchors.verticalCenter: parent.verticalCenter
          options: [
            { value: "top", label: "Top" },
            { value: "bottom", label: "Bottom" },
            { value: "left", label: "Left" },
            { value: "right", label: "Right" }
          ]
          value: String(app.sjson.barConfig.bar && app.sjson.barConfig.bar.position
                        ? app.sjson.barConfig.bar.position : "top")
          foreground: app.foreground
          accent: app.accent
          fontFamily: app.fontFamily
          focusable: false
          onChanged: function(v) { app.sjson.setBarPosition(v) }
        }
      }

      Row {
        spacing: Style.spacing.lg
        width: parent.width

        Text {
          text: "Transparent"
          color: app.foreground
          font.family: app.fontFamily
          font.pixelSize: Style.font.body
          width: Style.space(110)
          anchors.verticalCenter: parent.verticalCenter
        }

        ToggleSwitch {
          anchors.verticalCenter: parent.verticalCenter
          checked: app.sjson.barConfig.bar ? app.sjson.barConfig.bar.transparent === true : false
          foreground: app.foreground
          accent: app.accent
          onToggled: app.sjson.setBarTransparent(!(app.sjson.barConfig.bar
                                              && app.sjson.barConfig.bar.transparent === true))
        }

        Text {
          text: "Bar height and colours live under Shell → Surfaces."
          color: Qt.darker(app.foreground, 1.6)
          font.family: app.fontFamily
          font.pixelSize: Style.font.caption
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      PanelSeparator { foreground: app.foreground; width: parent.width }

      PanelSectionHeader {
        text: "Layout"
        foreground: app.foreground
        fontFamily: app.fontFamily
      }

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        text: "◀ ▶ move a widget between sections, ▲ ▼ reorder it, ✕ takes it off the bar."
        color: Qt.darker(app.foreground, 1.55)
        font.family: app.fontFamily
        font.pixelSize: Style.font.caption
      }

      Row {
        width: parent.width
        spacing: Style.spacing.lg

        Repeater {
          model: app.sjson.barSections

          Column {
            required property var modelData
            width: (barColumn.width - Style.spacing.lg * 2) / 3
            spacing: Style.spacing.xs

            PanelSectionHeader {
              text: modelData
              foreground: app.foreground
              fontFamily: app.fontFamily
            }

            Repeater {
              model: app.sjson.barLayout(modelData)

              BorderSurface {
                id: widgetCard
                required property var modelData
                required property int index
                readonly property string widgetId: String(modelData.id)
                readonly property var descriptor: app.sjson.pluginFor(widgetId)

                width: parent.width
                height: widgetRow.implicitHeight + Style.spacing.lg
                radius: Style.cornerRadius
                color: Style.normalFillFor(app.foreground, app.accent)
                borderSpec: Border.controlSpec("normal", app.foreground, app.accent)

                Column {
                  id: widgetRow
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.leftMargin: Style.spacing.md
                  anchors.rightMargin: Style.spacing.md
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.spacing.xxs

                  Text {
                    width: parent.width
                    text: widgetCard.descriptor ? widgetCard.descriptor.displayName : widgetCard.widgetId
                    color: app.foreground
                    font.family: app.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                    elide: Text.ElideRight
                  }

                  Text {
                    width: parent.width
                    text: widgetCard.widgetId
                    color: Qt.darker(app.foreground, 1.9)
                    font.family: app.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }

                  Row {
                    spacing: Style.spacing.xs

                    PanelActionButton {
                      iconText: "󰅁"
                      tooltipText: "Move to the section on the left"
                      foreground: app.foreground
                      enabled: app.sjson.barSections.indexOf(app.sjson.barSectionOf(widgetCard.widgetId)) > 0
                      opacity: enabled ? 1 : 0.3
                      onClicked: app.sjson.shiftWidget(widgetCard.widgetId, -1)
                    }
                    PanelActionButton {
                      iconText: "󰅃"
                      tooltipText: "Move up"
                      foreground: app.foreground
                      enabled: widgetCard.index > 0
                      opacity: enabled ? 1 : 0.3
                      onClicked: app.sjson.nudgeWidget(widgetCard.widgetId, -1)
                    }
                    PanelActionButton {
                      iconText: "󰅀"
                      tooltipText: "Move down"
                      foreground: app.foreground
                      enabled: widgetCard.index
                        < app.sjson.barLayout(app.sjson.barSectionOf(widgetCard.widgetId)).length - 1
                      opacity: enabled ? 1 : 0.3
                      onClicked: app.sjson.nudgeWidget(widgetCard.widgetId, 1)
                    }
                    PanelActionButton {
                      iconText: "󰅂"
                      tooltipText: "Move to the section on the right"
                      foreground: app.foreground
                      enabled: app.sjson.barSections.indexOf(app.sjson.barSectionOf(widgetCard.widgetId)) < 2
                      opacity: enabled ? 1 : 0.3
                      onClicked: app.sjson.shiftWidget(widgetCard.widgetId, 1)
                    }
                    PanelActionButton {
                      iconText: "󰅖"
                      tooltipText: "Take off the bar"
                      foreground: app.foreground
                      onClicked: app.sjson.setWidgetOnBar(widgetCard.widgetId, false)
                    }
                  }
                }
              }
            }
          }
        }
      }

      PanelSeparator { foreground: app.foreground; width: parent.width }

      PanelSectionHeader {
        text: "Not on the bar"
        foreground: app.foreground
        fontFamily: app.fontFamily
      }

      Flow {
        width: parent.width
        spacing: Style.spacing.xs

        Repeater {
          model: {
            var out = []
            for (var i = 0; i < app.sjson.plugins.length; i++) {
              var entry = app.sjson.plugins[i]
              if (!entry.isBarWidget) continue
              if (app.sjson.barSectionOf(entry.id) !== "") continue
              out.push(entry)
            }
            return out
          }

          Button {
            required property var modelData
            text: "+  " + modelData.displayName
            bordered: true
            foreground: app.foreground
            accent: app.accent
            fontFamily: app.fontFamily
            onClicked: app.sjson.setWidgetOnBar(modelData.id, true)
          }
        }
      }
    }
  }
}
