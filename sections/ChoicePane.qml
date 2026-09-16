import QtQuick
import qs.Commons
import qs.Ui

// A scrollable column of choice groups, shared by the Desktop sections.
//
// Each entry in `groups` describes one group:
//   { id, title, note, kind: "chips" | "icons" | "fonts" | "stepper",
//     options: [{ value, label, sub, icons, family }], current,
//     pinned, pinnedText, unpinLabel, pick(value), unpin(),
//     value, unit, step(delta), reset(), resetLabel }
// Keyboard: up/down moves between groups (and through a font list), left/right
// moves along a group or steps a stepper, Enter picks.
Item {
  id: pane

  required property var app
  property var groups: []
  // The groups binding can be briefly undefined while the section builds.
  readonly property var list: Array.isArray(groups) ? groups : []

  property int cursorGroup: 0
  property int cursorOption: 0
  property string filterText: ""

  function optionsOf(g) {
    if (!g) return []
    if (g.kind !== "fonts" || pane.filterText === "") return g.options || []
    var needle = pane.filterText.toLowerCase()
    return (g.options || []).filter(function(o) { return String(o.label).toLowerCase().indexOf(needle) !== -1 })
  }

  function currentIndex(g) {
    var opts = optionsOf(g)
    for (var i = 0; i < opts.length; i++) if (opts[i].value === g.current) return i
    return 0
  }

  function enterGroup(index, fromBelow) {
    pane.cursorGroup = Math.max(0, Math.min(pane.list.length - 1, index))
    var g = pane.list[pane.cursorGroup]
    var opts = optionsOf(g)
    if (g && g.kind === "fonts" && opts.length > 0)
      pane.cursorOption = fromBelow ? opts.length - 1 : currentIndex(g)
    else pane.cursorOption = currentIndex(g)
    Qt.callLater(pane.reveal)
  }

  function moveBy(dx, dy) {
    if (pane.list.length === 0) return
    var g = pane.list[pane.cursorGroup]
    var opts = optionsOf(g)
    if (dx !== 0) {
      if (g.kind === "stepper") { if (g.step) g.step(dx) }
      else if (g.kind !== "fonts") pane.cursorOption = Math.max(0, Math.min(opts.length - 1, pane.cursorOption + dx))
      Qt.callLater(pane.reveal)
      return
    }
    if (g.kind === "fonts") {
      var next = pane.cursorOption + dy
      if (next >= 0 && next < opts.length) { pane.cursorOption = next; Qt.callLater(pane.reveal); return }
    }
    var target = pane.cursorGroup + dy
    if (target < 0 || target >= pane.list.length) return
    enterGroup(target, dy < 0)
  }

  function activate() {
    var g = pane.list[pane.cursorGroup]
    if (!g) return
    // A stray Enter should never throw away a size someone dialled in.
    if (g.kind === "stepper") return
    var opts = optionsOf(g)
    var o = opts[pane.cursorOption]
    if (o && g.pick) g.pick(o.value)
  }

  // Search on Home lands here with a group title to put the cursor on.
  function focusGroupTitle(title) {
    for (var i = 0; i < pane.list.length; i++) {
      if (pane.list[i].title !== title) continue
      enterGroup(i, false)
      return true
    }
    return false
  }

  function clearPin() {
    var g = pane.list[pane.cursorGroup]
    if (g && g.pinned && g.unpin) g.unpin()
  }

  function reveal() {
    var item = groupRepeater.itemAt(pane.cursorGroup)
    if (!item) return
    // Show the whole group; a group taller than the view shows from its top.
    var top = item.y
    var bottom = Math.min(item.y + item.height, top + flick.height)
    if (top < flick.contentY) flick.contentY = Math.max(0, top)
    else if (bottom > flick.contentY + flick.height)
      flick.contentY = Math.min(Math.max(0, flick.contentHeight - flick.height), bottom - flick.height)
  }

  signal cascadeRequested()

  function reset() { pane.filterText = ""; pane.seenCount = 0; enterGroup(0, false); flick.contentY = 0; cascadeRequested() }

  onVisibleChanged: if (visible) reset()
  // Groups often arrive after the pane is shown; the first real set places the
  // cursor on the current choice rather than wherever an empty list left it.
  property int seenCount: 0
  onListChanged: {
    var first = pane.seenCount === 0 && pane.list.length > 0
    pane.seenCount = pane.list.length
    if (first || pane.cursorGroup < 0 || pane.cursorGroup >= pane.list.length) enterGroup(0, false)
  }

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
      spacing: Style.spacing.xl

      Repeater {
        id: groupRepeater
        // A count, not the array: the groups are rebuilt on every value change,
        // and an array model would tear down every delegate (and the font
        // list's scroll position) each time.
        model: pane.list.length

        Column {
          id: groupItem
          required property int index
          readonly property var modelData: pane.list[index] || ({})
          readonly property bool groupHasCursor: index === pane.cursorGroup
          readonly property var shown: pane.optionsOf(modelData)

          width: column.width
          spacing: Style.spacing.md

          property real appear: 1
          opacity: appear
          transform: Translate { y: (1 - groupItem.appear) * Style.space(12) }
          Connections {
            target: pane
            function onCascadeRequested() {
              if (!pane.app.motion || groupItem.index > 10) return
              groupItem.appear = 0
              groupCascade.restart()
            }
          }
          SequentialAnimation {
            id: groupCascade
            PauseAnimation { duration: 30 + groupItem.index * 45 }
            NumberAnimation { target: groupItem; property: "appear"; to: 1; duration: 340; easing.type: Easing.OutCubic }
          }

          Item {
            width: parent.width
            height: Math.max(titleText.implicitHeight, pinChip.visible ? pinChip.implicitHeight : 0)

            PanelSectionHeader {
              id: titleText
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: groupItem.modelData.title
              foreground: groupItem.groupHasCursor ? pane.app.accent : pane.app.foreground
              fontFamily: pane.app.fontFamily
            }

            Row {
              id: pinChip
              visible: groupItem.modelData.pinned === true
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.md
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: groupItem.modelData.pinnedText || "pinned — overrides theme"
                color: pane.app.accent
                font.family: pane.app.fontFamily
                font.pixelSize: Style.font.caption
              }
              Button {
                text: groupItem.modelData.unpinLabel || "Follow theme"
                bordered: true
                foreground: pane.app.foreground
                accent: pane.app.accent
                fontFamily: pane.app.fontFamily
                fontSize: Style.font.caption
                onClicked: if (groupItem.modelData.unpin) groupItem.modelData.unpin()
              }
            }
          }

          Text {
            visible: !!groupItem.modelData.note
            width: parent.width
            wrapMode: Text.WordWrap
            text: groupItem.modelData.note || ""
            color: Qt.darker(pane.app.foreground, 1.55)
            font.family: pane.app.fontFamily
            font.pixelSize: Style.font.caption
          }

          // ------------------------------------------------ chips
          Flow {
            visible: groupItem.modelData.kind === "chips"
            width: parent.width
            spacing: Style.spacing.xs
            Repeater {
              model: groupItem.modelData.kind === "chips" ? groupItem.shown : []
              Button {
                required property var modelData
                required property int index
                text: modelData.label
                bordered: true
                selected: modelData.value === groupItem.modelData.current
                hasCursor: groupItem.groupHasCursor && index === pane.cursorOption
                foreground: pane.app.foreground
                accent: pane.app.accent
                fontFamily: groupItem.modelData.id === "mono" ? modelData.value : pane.app.fontFamily
                onClicked: {
                  pane.cursorGroup = groupItem.index
                  pane.cursorOption = index
                  if (groupItem.modelData.pick) groupItem.modelData.pick(modelData.value)
                }
              }
            }
          }

          // ------------------------------------------------ stepper
          Row {
            visible: groupItem.modelData.kind === "stepper"
            spacing: Style.spacing.md
            Button {
              text: "−"
              bordered: true
              hasCursor: groupItem.groupHasCursor
              foreground: pane.app.foreground
              accent: pane.app.accent
              fontFamily: pane.app.fontFamily
              onClicked: { pane.cursorGroup = groupItem.index; if (groupItem.modelData.step) groupItem.modelData.step(-1) }
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(70)
              horizontalAlignment: Text.AlignHCenter
              text: String(groupItem.modelData.value === undefined ? "" : groupItem.modelData.value) + " " + (groupItem.modelData.unit || "")
              color: pane.app.foreground
              font.family: pane.app.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }
            Button {
              text: "+"
              bordered: true
              hasCursor: groupItem.groupHasCursor
              foreground: pane.app.foreground
              accent: pane.app.accent
              fontFamily: pane.app.fontFamily
              onClicked: { pane.cursorGroup = groupItem.index; if (groupItem.modelData.step) groupItem.modelData.step(1) }
            }
            Button {
              visible: !!groupItem.modelData.reset
              text: groupItem.modelData.resetLabel || "Reset"
              foreground: pane.app.foreground
              accent: pane.app.accent
              fontFamily: pane.app.fontFamily
              onClicked: groupItem.modelData.reset()
            }
          }

          // ------------------------------------------------ icon themes
          Flow {
            visible: groupItem.modelData.kind === "icons"
            width: parent.width
            spacing: Style.spacing.md
            Repeater {
              model: groupItem.modelData.kind === "icons" ? groupItem.shown : []
              CursorSurface {
                id: tile
                required property var modelData
                required property int index
                width: Style.space(196)
                height: tileColumn.implicitHeight + Style.spacing.lg * 2
                radius: Style.cornerRadius
                bordered: true
                current: modelData.value === groupItem.modelData.current
                hasCursor: groupItem.groupHasCursor && index === pane.cursorOption
                foreground: pane.app.foreground
                accent: pane.app.accent

                Column {
                  id: tileColumn
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.margins: Style.spacing.lg
                  spacing: Style.spacing.sm

                  Row {
                    spacing: Style.spacing.xs
                    height: Style.space(26)
                    Repeater {
                      model: tile.modelData.icons || []
                      Image {
                        required property var modelData
                        width: Style.space(26)
                        height: Style.space(26)
                        source: "file://" + encodeURI(modelData)
                        sourceSize.width: 52
                        sourceSize.height: 52
                        asynchronous: true
                        fillMode: Image.PreserveAspectFit
                      }
                    }
                  }
                  Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: tile.modelData.label
                    color: pane.app.foreground
                    font.family: pane.app.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    pane.cursorGroup = groupItem.index
                    pane.cursorOption = tile.index
                    if (groupItem.modelData.pick) groupItem.modelData.pick(tile.modelData.value)
                  }
                }
              }
            }
          }

          // ------------------------------------------------ art preview
          Rectangle {
            visible: groupItem.modelData.kind === "art"
            width: parent.width
            height: visible ? Math.min(Style.space(180), artText.implicitHeight + Style.spacing.lg * 2) : 0
            radius: Style.cornerRadius
            color: Qt.rgba(0, 0, 0, 0.85)
            clip: true
            Text {
              id: artText
              anchors.centerIn: parent
              text: groupItem.modelData.kind === "art" ? String(groupItem.modelData.art || "") : ""
              color: "#e8e8e8"
              textFormat: Text.PlainText
              font.family: "monospace"
              // Shrink tall art to fit the box rather than cropping it.
              readonly property int artLines: Math.max(1, text.split("\n").length)
              font.pixelSize: Math.max(3, Math.min(Math.round(Style.space(7)), Math.floor((Style.space(180) - Style.spacing.lg * 2) / (artLines * 0.95))))
              lineHeight: 0.95
            }
          }
          Flow {
            visible: groupItem.modelData.kind === "art"
            width: parent.width
            spacing: Style.spacing.xs
            Repeater {
              model: groupItem.modelData.kind === "art" ? groupItem.shown : []
              Button {
                required property var modelData
                required property int index
                text: modelData.label
                bordered: true
                hasCursor: groupItem.groupHasCursor && index === pane.cursorOption
                foreground: pane.app.foreground
                accent: pane.app.accent
                fontFamily: pane.app.fontFamily
                onClicked: {
                  pane.cursorGroup = groupItem.index
                  pane.cursorOption = index
                  if (groupItem.modelData.pick) groupItem.modelData.pick(modelData.value)
                }
              }
            }
          }

          // ------------------------------------------------ preview cards
          Flow {
            visible: groupItem.modelData.kind === "cards"
            width: parent.width
            spacing: Style.spacing.md
            Repeater {
              model: groupItem.modelData.kind === "cards" ? groupItem.shown : []
              CursorSurface {
                id: card
                required property var modelData
                required property int index
                width: Style.space(196)
                height: cardColumn.implicitHeight + Style.spacing.md * 2
                radius: Style.cornerRadius
                bordered: true
                current: modelData.value === groupItem.modelData.current
                hasCursor: groupItem.groupHasCursor && index === pane.cursorOption
                foreground: pane.app.foreground
                accent: pane.app.accent

                Column {
                  id: cardColumn
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.margins: Style.spacing.md
                  spacing: Style.spacing.sm
                  Rectangle {
                    width: parent.width
                    height: Math.round(width * 9 / 16)
                    radius: Math.max(0, Style.cornerRadius - 2)
                    color: "#000000"
                    clip: true
                    Image {
                      anchors.fill: parent
                      visible: !!card.modelData.preview
                      source: card.modelData.preview ? "file://" + encodeURI(card.modelData.preview) : ""
                      sourceSize.width: 360
                      fillMode: Image.PreserveAspectCrop
                      asynchronous: true
                    }
                  }
                  Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: card.modelData.label + (card.modelData.sub ? "  ·  " + card.modelData.sub : "")
                    color: pane.app.foreground
                    font.family: pane.app.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    pane.cursorGroup = groupItem.index
                    pane.cursorOption = card.index
                    if (groupItem.modelData.pick) groupItem.modelData.pick(card.modelData.value)
                  }
                }
              }
            }
          }

          // ------------------------------------------------ font list
          TextField {
            visible: groupItem.modelData.kind === "fonts"
            width: Style.space(300)
            foreground: pane.app.foreground
            accent: pane.app.accent
            placeholderText: "Filter fonts"
            text: pane.filterText
            onTextChanged: if (text !== pane.filterText) { pane.filterText = text; pane.cursorOption = 0 }
            onEditingFinished: pane.app.focusPanel()
          }

          ListView {
            id: fontList
            visible: groupItem.modelData.kind === "fonts"
            width: parent.width
            height: visible ? Style.space(230) : 0
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: groupItem.modelData.kind === "fonts" ? groupItem.shown : []
            currentIndex: groupItem.groupHasCursor ? pane.cursorOption : -1
            highlightFollowsCurrentItem: false
            onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
            onModelChanged: if (currentIndex >= 0) Qt.callLater(function() { fontList.positionViewAtIndex(fontList.currentIndex, ListView.Contain) })

            delegate: CursorSurface {
              id: fontRow
              required property var modelData
              required property int index
              width: fontList.width
              height: Style.space(34)
              radius: Style.cornerRadius
              current: modelData.value === groupItem.modelData.current
              hasCursor: groupItem.groupHasCursor && index === pane.cursorOption
              foreground: pane.app.foreground
              accent: pane.app.accent

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.spacing.lg
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * 0.42
                elide: Text.ElideRight
                text: fontRow.modelData.label
                color: pane.app.foreground
                font.family: pane.app.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.lg
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * 0.52
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignRight
                text: fontRow.modelData.sub || "The quick brown fox 0123"
                color: pane.app.foreground
                font.family: fontRow.modelData.value
                font.pixelSize: Style.font.body
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  pane.cursorGroup = groupItem.index
                  pane.cursorOption = fontRow.index
                  if (groupItem.modelData.pick) groupItem.modelData.pick(fontRow.modelData.value)
                }
              }
            }
          }
        }
      }
    }
  }
}
