import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// Every installed Omarchy theme as a card, and the active theme's wallpapers.
//
// Cards show the theme's own preview (the image omarchy-theme-switcher would
// use) over a strip painted in the theme's own background, foreground and
// accent, so a card reads as the theme before it is applied.
//
// Previews are full wallpapers, some several megabytes. `sourceSize` makes Qt
// decode them at card size, which matters with 59 of them on an 8 GB machine.
Item {
  id: section

  required property var app

  property string filter: "all"

  readonly property var store: app.theme
  readonly property var shown: {
    var out = []
    var list = store.themes
    for (var i = 0; i < list.length; i++)
      if (filter === "all" || list[i].mode === filter) out.push(list[i])
    return out
  }

  // Keyboard cursor over the grid; Enter applies. Starts on the active theme.
  property int cursor: 0

  function syncCursor() {
    for (var i = 0; i < shown.length; i++)
      if (shown[i].slug === store.current) { cursor = i; grid.positionViewAtIndex(i, GridView.Contain); return }
    cursor = Math.max(0, Math.min(cursor, shown.length - 1))
  }

  function moveBy(dx, dy) {
    if (shown.length === 0) return
    var next = cursor + dx + dy * grid.columns
    cursor = Math.max(0, Math.min(shown.length - 1, next))
    grid.positionViewAtIndex(cursor, GridView.Contain)
  }

  function activate() {
    if (cursor >= 0 && cursor < shown.length) store.apply(shown[cursor].slug)
  }

  onShownChanged: Qt.callLater(syncCursor)
  onVisibleChanged: if (visible) Qt.callLater(syncCursor)

  function fileUrl(path) {
    return path ? "file://" + encodeURI(path) : ""
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.spacing.lg

    Item {
      Layout.fillWidth: true
      Layout.preferredHeight: Math.max(currentLabel.implicitHeight, filterGroup.implicitHeight)

      Column {
        id: currentLabel
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.xxs

        Text {
          text: section.store.current ? section.store.displayOf(section.store.current) : "—"
          color: section.app.foreground
          font.family: section.app.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }
        Text {
          text: section.store.applyingTheme !== ""
            ? "Applying " + section.store.displayOf(section.store.applyingTheme) + "…"
            : section.shown.length + " of " + section.store.themes.length + " themes"
          color: section.store.applyingTheme !== "" ? section.app.accent : Qt.darker(section.app.foreground, 1.6)
          font.family: section.app.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      ButtonGroup {
        id: filterGroup
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        options: [
          { value: "all", label: "All" },
          { value: "dark", label: "Dark" },
          { value: "light", label: "Light" }
        ]
        value: section.filter
        foreground: section.app.foreground
        accent: section.app.accent
        fontFamily: section.app.fontFamily
        focusable: false
        onChanged: function(v) { section.filter = v }
      }
    }

    GridView {
      id: grid
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      model: section.shown
      readonly property int columns: Math.max(2, Math.floor(width / Style.space(190)))
      cellWidth: Math.floor(width / columns)
      cellHeight: Math.round(cellWidth * 0.78)

      delegate: Item {
        id: cell
        required property var modelData
        readonly property bool isCurrent: modelData.slug === section.store.current
        readonly property bool isApplying: modelData.slug === section.store.applyingTheme
        required property int index
        readonly property bool hasCursor: index === section.cursor

        width: grid.cellWidth
        height: grid.cellHeight

        Rectangle {
          id: card
          anchors.fill: parent
          anchors.margins: Style.spacing.md
          radius: Style.cornerRadius
          color: cell.modelData.background || section.app.background
          border.width: cell.isCurrent || cell.hasCursor ? Math.max(2, Style.space(2)) : (hover.hovered ? 1 : 0)
          border.color: cell.isCurrent ? section.app.accent
            : Qt.rgba(section.app.foreground.r, section.app.foreground.g, section.app.foreground.b, cell.hasCursor ? 0.9 : 0.4)
          clip: true

          Image {
            id: preview
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: strip.top
            anchors.margins: card.border.width
            source: section.fileUrl(cell.modelData.preview)
            sourceSize.width: 360
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
          }

          Rectangle {
            id: strip
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: card.border.width
            height: Math.round(card.height * 0.30)
            color: cell.modelData.background || section.app.background

            Column {
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.md
              anchors.right: badge.left
              anchors.rightMargin: Style.spacing.sm
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.xxs

              Text {
                width: parent.width
                text: cell.modelData.display
                color: cell.modelData.foreground || section.app.foreground
                font.family: section.app.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                elide: Text.ElideRight
              }

              Row {
                spacing: 2
                Repeater {
                  model: cell.modelData.colors
                  Rectangle {
                    required property var modelData
                    width: Style.space(10)
                    height: Style.space(6)
                    radius: 1
                    color: modelData
                  }
                }
              }
            }

            Text {
              id: badge
              anchors.right: parent.right
              anchors.rightMargin: Style.spacing.md
              anchors.verticalCenter: parent.verticalCenter
              text: cell.isCurrent ? "current" : (cell.modelData.mode === "light" ? "light" : "dark")
              color: cell.isCurrent ? (cell.modelData.accent || section.app.accent)
                : (cell.modelData.foreground || section.app.foreground)
              opacity: cell.isCurrent ? 1 : 0.6
              font.family: section.app.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Rectangle {
            anchors.fill: parent
            visible: cell.isApplying
            color: Qt.rgba(0, 0, 0, 0.55)
            Text {
              anchors.centerIn: parent
              text: "Applying…"
              color: "white"
              font.family: section.app.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }
          }

          HoverHandler { id: hover }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: { section.cursor = cell.index; section.store.apply(cell.modelData.slug) }
          }
        }
      }

      Rectangle {
        anchors.right: parent.right
        width: Style.space(3)
        radius: width / 2
        color: Qt.rgba(section.app.foreground.r, section.app.foreground.g, section.app.foreground.b, 0.25)
        visible: grid.contentHeight > grid.height
        height: Math.max(Style.space(24), grid.height * (grid.height / Math.max(1, grid.contentHeight)))
        y: (grid.height - height) * (grid.contentY / Math.max(1, grid.contentHeight - grid.height))
      }
    }

    PanelSeparator { foreground: section.app.foreground; Layout.fillWidth: true }

    Item {
      Layout.fillWidth: true
      Layout.preferredHeight: wallHeader.implicitHeight

      PanelSectionHeader {
        id: wallHeader
        anchors.left: parent.left
        text: "Wallpaper — " + (section.store.current ? section.store.displayOf(section.store.current) : "")
        foreground: section.app.foreground
        fontFamily: section.app.fontFamily
      }

      Text {
        anchors.right: parent.right
        anchors.verticalCenter: wallHeader.verticalCenter
        text: section.store.wallpapers.length + (section.store.wallpapers.length === 1 ? " wallpaper" : " wallpapers")
        color: Qt.darker(section.app.foreground, 1.6)
        font.family: section.app.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    ListView {
      id: walls
      Layout.fillWidth: true
      Layout.preferredHeight: Style.space(92)
      orientation: ListView.Horizontal
      spacing: Style.spacing.md
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      model: section.store.wallpapers

      delegate: Rectangle {
        id: wall
        required property var modelData
        readonly property bool isCurrent: modelData.path === section.store.currentWallpaper
        height: walls.height
        width: Math.round(height * 16 / 9)
        radius: Style.cornerRadius
        color: section.app.background
        border.width: isCurrent ? Math.max(2, Style.space(2)) : 0
        border.color: section.app.accent
        clip: true

        Image {
          anchors.fill: parent
          anchors.margins: wall.border.width
          source: section.fileUrl(wall.modelData.path)
          sourceSize.width: 320
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
        }

        Rectangle {
          anchors.fill: parent
          visible: wall.modelData.path === section.store.applyingWallpaper
          color: Qt.rgba(0, 0, 0, 0.5)
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: section.store.setWallpaper(wall.modelData.path)
        }
      }

      Text {
        anchors.centerIn: parent
        visible: walls.count === 0
        text: "This theme ships no wallpapers. Add images to ~/.config/omarchy/backgrounds/"
          + section.store.current + "/"
        color: Qt.darker(section.app.foreground, 1.6)
        font.family: section.app.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
