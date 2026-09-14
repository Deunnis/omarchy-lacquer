import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// A theme generated from a wallpaper by aether, and aether's saved blueprints.
Item {
  id: section

  required property var app

  readonly property var store: app.aether

  function fileUrl(path) { return path ? "file://" + encodeURI(path) : "" }

  onVisibleChanged: if (visible) store.refresh()

  Flickable {
    id: flick
    anchors.fill: parent
    clip: true
    contentWidth: width
    contentHeight: column.implicitHeight
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: column
      width: flick.width - Style.spacing.xxl
      spacing: Style.spacing.lg

      PanelSectionHeader { text: "From a wallpaper"; foreground: section.app.foreground; fontFamily: section.app.fontFamily }

      Row {
        width: parent.width
        spacing: Style.spacing.xxl

        Rectangle {
          id: sourcePreview
          width: Style.space(260)
          height: Math.round(width * 9 / 16)
          radius: Style.cornerRadius
          color: section.app.background
          clip: true
          border.width: 1
          border.color: Qt.rgba(section.app.foreground.r, section.app.foreground.g, section.app.foreground.b, 0.3)

          Image {
            anchors.fill: parent
            anchors.margins: 1
            source: section.fileUrl(section.store.source)
            sourceSize.width: 520
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
          }

          // The preview itself opens the picker.
          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: previewHint.implicitHeight + Style.spacing.md * 2
            color: Qt.rgba(0, 0, 0, previewMouse.containsMouse ? 0.62 : 0.42)
            Text {
              id: previewHint
              anchors.centerIn: parent
              text: "󰸉  Choose wallpaper…"
              color: "#ffffff"
              font.family: section.app.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          MouseArea {
            id: previewMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: section.store.pick("wallpapers")
          }
        }

        Column {
          width: parent.width - sourcePreview.width - Style.spacing.xxl
          spacing: Style.spacing.lg

          Text {
            width: parent.width
            elide: Text.ElideMiddle
            text: section.store.source || "No wallpaper chosen"
            color: Qt.darker(section.app.foreground, 1.5)
            font.family: section.app.fontFamily
            font.pixelSize: Style.font.caption
          }

          ButtonGroup {
            options: [{ value: "dark", label: "Dark" }, { value: "light", label: "Light" }]
            value: section.store.light ? "light" : "dark"
            foreground: section.app.foreground
            accent: section.app.accent
            fontFamily: section.app.fontFamily
            focusable: false
            onChanged: function(v) { section.store.setLight(v === "light") }
          }

          // The palette aether would build, read without applying anything.
          Flow {
            width: parent.width
            spacing: 3
            Repeater {
              model: section.store.palette
              Rectangle {
                required property var modelData
                width: Style.space(26)
                height: Style.space(26)
                radius: Math.min(Style.cornerRadius, 4)
                color: modelData
                border.width: 1
                border.color: Qt.rgba(0, 0, 0, 0.15)
              }
            }
          }

          Text {
            text: section.store.extracting ? "Reading the palette…"
              : section.store.paletteError !== "" ? section.store.paletteError
              : section.store.palette.length + " colours"
            color: section.store.paletteError !== "" ? Color.urgent : Qt.darker(section.app.foreground, 1.6)
            font.family: section.app.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      PanelSectionHeader { text: "This theme's wallpapers"; foreground: section.app.foreground; fontFamily: section.app.fontFamily }

      ListView {
        id: walls
        width: parent.width
        height: Style.space(78)
        orientation: ListView.Horizontal
        spacing: Style.spacing.md
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: section.app.theme.wallpapers

        delegate: Rectangle {
          id: wall
          required property var modelData
          height: walls.height
          width: Math.round(height * 16 / 9)
          radius: Style.cornerRadius
          color: section.app.background
          border.width: modelData.path === section.store.source ? Math.max(2, Style.space(2)) : 0
          border.color: section.app.accent
          clip: true

          Image {
            anchors.fill: parent
            anchors.margins: wall.border.width
            source: section.fileUrl(wall.modelData.path)
            sourceSize.width: 280
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: section.store.setSource(wall.modelData.path)
          }
        }
      }

      Row {
        spacing: Style.spacing.md
        Button {
          text: "All wallpapers…"
          iconText: "󰸉"
          tooltipText: "Every installed theme's wallpapers  ·  w"
          bordered: true
          foreground: section.app.foreground
          accent: section.app.accent
          fontFamily: section.app.fontFamily
          onClicked: section.store.pick("wallpapers")
        }
        Button {
          text: "Other image…"
          iconText: "󰉋"
          tooltipText: "Any image on your computer  ·  f"
          bordered: true
          foreground: section.app.foreground
          accent: section.app.accent
          fontFamily: section.app.fontFamily
          onClicked: section.store.pick("file")
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "Lacquer closes while you pick, and comes back here."
          color: Qt.darker(section.app.foreground, 1.6)
          font.family: section.app.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      PanelSeparator { foreground: section.app.foreground; width: parent.width }

      PanelSectionHeader { text: "Also theme"; foreground: section.app.foreground; fontFamily: section.app.fontFamily }

      Row {
        spacing: Style.spacing.xxl
        Repeater {
          model: [{ key: "zed", label: "Zed" }, { key: "vscode", label: "VS Code" }, { key: "neovim", label: "Neovim" }]
          Row {
            required property var modelData
            spacing: Style.spacing.md
            ToggleSwitch {
              anchors.verticalCenter: parent.verticalCenter
              foreground: section.app.foreground
              accent: section.app.accent
              checked: modelData.key === "zed" ? section.store.includeZed
                : modelData.key === "vscode" ? section.store.includeVscode : section.store.includeNeovim
              onToggled: {
                if (modelData.key === "zed") section.store.includeZed = !section.store.includeZed
                else if (modelData.key === "vscode") section.store.includeVscode = !section.store.includeVscode
                else section.store.includeNeovim = !section.store.includeNeovim
              }
            }
            Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.label; color: section.app.foreground; font.family: section.app.fontFamily; font.pixelSize: Style.font.body }
          }
        }
      }

      BorderSurface {
        width: parent.width
        height: generateRow.implicitHeight + Style.spacing.xxl
        radius: Style.cornerRadius
        color: section.app.confirmGenerate ? Style.selectedFillFor(Color.urgent, Color.urgent) : "transparent"
        borderSpec: Border.controlSpec("normal", section.app.foreground, section.app.accent)

        Row {
          id: generateRow
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.margins: Style.spacing.lg
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.lg

          Text {
            width: parent.width - generateButton.width - (generateCancel.visible ? generateCancel.width + Style.spacing.lg : 0) - Style.spacing.lg
            anchors.verticalCenter: parent.verticalCenter
            wrapMode: Text.WordWrap
            color: section.app.foreground
            font.family: section.app.fontFamily
            font.pixelSize: Style.font.caption
            text: section.store.generating ? "aether is working…"
              : section.app.confirmGenerate
                ? "This switches your whole desktop to a new theme called “aether” and sets this wallpaper"
                  + ((section.store.includeZed || section.store.includeVscode || section.store.includeNeovim)
                     ? ", and writes theme files into the editors ticked above." : ".")
                : "Builds an Omarchy theme from this palette and applies it."
          }

          Button {
            id: generateButton
            anchors.verticalCenter: parent.verticalCenter
            text: section.app.confirmGenerate ? "Yes, generate" : "Generate & apply"
            enabled: !section.store.generating && section.store.source !== "" && section.store.available
            opacity: enabled ? 1 : 0.4
            bordered: true
            selected: section.app.confirmGenerate
            foreground: section.app.foreground
            accent: section.app.accent
            fontFamily: section.app.fontFamily
            onClicked: {
              if (section.app.confirmGenerate) { section.app.confirmGenerate = false; section.store.generate() }
              else section.app.confirmGenerate = true
            }
          }

          Button {
            id: generateCancel
            visible: section.app.confirmGenerate
            anchors.verticalCenter: parent.verticalCenter
            text: "Cancel"
            bordered: true
            foreground: section.app.foreground
            accent: section.app.accent
            fontFamily: section.app.fontFamily
            onClicked: section.app.confirmGenerate = false
          }
        }
      }

      PanelSeparator { foreground: section.app.foreground; width: parent.width }

      Item {
        width: parent.width
        height: bpHeader.implicitHeight
        PanelSectionHeader { id: bpHeader; text: "Saved blueprints"; foreground: section.app.foreground; fontFamily: section.app.fontFamily }
        Button {
          anchors.right: parent.right
          anchors.verticalCenter: bpHeader.verticalCenter
          text: "Open aether"
          iconText: "󰏘"
          bordered: true
          foreground: section.app.foreground
          accent: section.app.accent
          fontFamily: section.app.fontFamily
          onClicked: section.store.openAether()
        }
      }

      Text {
        visible: section.store.blueprints.length === 0
        width: parent.width
        wrapMode: Text.WordWrap
        text: "No blueprints yet. Save one from aether's own window and it will appear here, ready to apply without opening aether."
        color: Qt.darker(section.app.foreground, 1.55)
        font.family: section.app.fontFamily
        font.pixelSize: Style.font.caption
      }

      Flow {
        width: parent.width
        spacing: Style.spacing.xs
        Repeater {
          model: section.store.blueprints
          Button {
            required property var modelData
            readonly property string bpName: typeof modelData === "string" ? modelData : String(modelData.name || "")
            text: section.store.applyingBlueprint === bpName ? bpName + "  …" : bpName
            bordered: true
            enabled: !section.store.generating
            foreground: section.app.foreground
            accent: section.app.accent
            fontFamily: section.app.fontFamily
            onClicked: section.store.applyBlueprint(bpName)
          }
        }
      }
    }
  }
}
