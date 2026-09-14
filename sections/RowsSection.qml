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

// The generic row list: headers, look-and-feel options, animation leaves and
// shell.toml tokens, depending on the active section.
Item {
  id: section

  // The Lacquer panel; state and actions all live there or in its stores.
  required property var app

  // The panel's keyboard cursor scrolls rows into view through this.
  function positionAt(index, mode) { rowList.positionViewAtIndex(index, mode) }

  ListView {
    id: rowList
    anchors.fill: parent
    clip: true
    model: app.rows
    boundsBehavior: Flickable.StopAtBounds
    currentIndex: app.cursorIndex
    spacing: 0

    delegate: Loader {
      id: rowLoader
      required property var modelData
      required property int index

      width: rowList.width - Style.spacing.xxl

      // Rows of a page just switched to cascade in; rows scrolled into view
      // later appear as they always did.
      property real appear: 1
      opacity: appear
      transform: Translate { x: (1 - rowLoader.appear) * Style.space(18) }
      Component.onCompleted: {
        if (!app.motion || !app.cascadeArmed || index > 16) return
        appear = 0
        rowCascade.start()
      }
      SequentialAnimation {
        id: rowCascade
        PauseAnimation { duration: 40 + rowLoader.index * 24 }
        NumberAnimation { target: rowLoader; property: "appear"; to: 1; duration: 320; easing.type: Easing.OutCubic }
      }
      sourceComponent: modelData.kind === "header" ? headerRow
        : modelData.kind === "leaf" ? leafRow
        : modelData.kind === "shell" ? shellRow : configRow

      Component {
        id: headerRow
        Item {
          implicitHeight: headerText.implicitHeight + Style.spacing.xxl
          PanelSectionHeader {
            id: headerText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.spacing.xs
            text: modelData.title
            foreground: app.foreground
            fontFamily: app.fontFamily
          }
        }
      }

      Component {
        id: configRow
        ConfigRow {
          item: modelData.item
          value: app.hypr.valueFor(modelData.item)
          modified: app.hypr.isModified(modelData.item.key)
          available: app.hypr.isAvailable(modelData.item)
          hasCursor: app.cursorIndex === index
          foreground: app.foreground
          accent: app.accent
          fontFamily: app.fontFamily
          onEdited: function(v) { app.hypr.setValue(modelData.item, v, false) }
          onCommitted: function(v) { app.hypr.setValue(modelData.item, v, true) }
          onReset: app.hypr.resetKeys([modelData.item.key], modelData.item.label)
          gate: app.pointerGate
          animated: app.motion
          onFocusRequested: app.cursorIndex = index
        }
      }

      Component {
        id: shellRow
        ShellRow {
          item: modelData.item
          value: app.toml.shellValue(modelData.item)
          themeValue: app.toml.shellDefault(modelData.item)
          modified: app.toml.shellModified(modelData.item)
          hasCursor: app.cursorIndex === index
          foreground: app.foreground
          accent: app.accent
          fontFamily: app.fontFamily
          onEdited: function(v) { app.toml.setShell(modelData.item, v, false) }
          onCommitted: function(v) { app.toml.setShell(modelData.item, v, true) }
          onReset: app.toml.resetShellItem(modelData.item)
          gate: app.pointerGate
          animated: app.motion
          onFocusRequested: app.cursorIndex = index
          onEditingDone: Qt.callLater(function() { app.focusPanel() })
        }
      }

      Component {
        id: leafRow
        LeafRow {
          leafSpec: modelData.leaf
          value: app.hypr.leafValue(modelData.leaf.name)
          inherited: app.hypr.leafInherited(modelData.leaf.name)
          modified: app.hypr.leafModified(modelData.leaf.name)
          hasCursor: app.cursorIndex === index
          curveNames: app.hypr.curveNames
          foreground: app.foreground
          accent: app.accent
          fontFamily: app.fontFamily
          onEdited: function(v) { app.hypr.setLeaf(modelData.leaf.name, v, false) }
          onCommitted: function(v) { app.hypr.setLeaf(modelData.leaf.name, v, true) }
          onReset: app.hypr.resetLeaf(modelData.leaf.name)
          onTakeOver: app.hypr.setLeaf(modelData.leaf.name, app.hypr.inheritedFrom(modelData.leaf), true)
          gate: app.pointerGate
          animated: app.motion
          onFocusRequested: app.cursorIndex = index
          onEditCurve: function(name) { app.jumpToCurve(name) }
          onPopupOpenChanged: if (!popupOpen) Qt.callLater(function() { app.focusPanel() })
        }
      }
    }

    Rectangle {
      anchors.right: parent.right
      width: Style.space(3)
      radius: width / 2
      color: Qt.rgba(app.foreground.r, app.foreground.g, app.foreground.b, 0.25)
      visible: rowList.contentHeight > rowList.height
      height: Math.max(Style.space(24),
                       rowList.height * (rowList.height / Math.max(1, rowList.contentHeight)))
      y: (rowList.height - height)
         * (rowList.contentY / Math.max(1, rowList.contentHeight - rowList.height))
    }
  }
}
