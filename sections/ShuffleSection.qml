import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// The theme shuffle: which themes rotate, whether a new one is drawn on every
// boot, and the Day & Night slots that follow local sunrise and sunset.
//
// The engine lives in Lacquer's service (it must run with the panel closed).
// While OmaShuffle is still installed that engine is dormant and OmaShuffle
// owns the state, so everything here is shown read-only and the banner offers
// the hand-over. Editing OmaShuffle's file from outside would be overwritten by
// its next save from memory.
Item {
  id: section

  required property var app

  readonly property var engine: app.shuffle
  readonly property bool ready: engine !== null && engine.stateLoaded
  readonly property bool live: !!(ready && engine.active)
  readonly property var st: ready ? engine.st : null

  // Nothing about the schedule is a property, so bindings that show times
  // re-read it on this tick.
  property int tick: 0
  Timer { interval: 30000; repeat: true; running: section.visible; onTriggered: section.tick++ }

  readonly property var info: {
    section.tick
    if (!section.ready) return { hasLocation: false }
    section.engine.st
    return section.engine.scheduleInfo()
  }

  function hhmm(ms) {
    if (!ms) return "—"
    var d = new Date(ms)
    return (d.getHours() < 10 ? "0" : "") + d.getHours() + ":" + (d.getMinutes() < 10 ? "0" : "") + d.getMinutes()
  }

  function statusLine() {
    if (!section.ready) return "Loading the shuffle…"
    var cur = section.engine.displayFor(section.engine.currentThemeSlug)
    if (section.st.schedule.enabled) {
      if (!section.info.hasLocation) return "Now: " + cur + " — Day & Night needs a location"
      var act = section.info.active ? section.info.active.label : "—"
      var nxt = section.info.next ? section.info.next.label : "—"
      return "Now: " + cur + " (" + act + ")   ·   Next: " + nxt + " at " + section.hhmm(section.info.nextBoundaryTs)
    }
    if (section.st.enabled) {
      var upcoming = (section.st.deck && section.st.deck.length > 0) ? section.engine.displayFor(section.st.deck[0]) : "a fresh draw"
      return "Now: " + cur + "   ·   Next boot: " + upcoming
    }
    return "Now: " + cur + "   ·   Shuffle is off"
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
      spacing: Style.spacing.lg

      // ---------------------------------------------------------- hand-over

      BorderSurface {
        width: parent.width
        height: handover.implicitHeight + Style.spacing.xxl
        visible: section.ready && section.engine.dormant === true
        radius: Style.cornerRadius
        color: Style.selectedFillFor(section.app.accent, section.app.accent)
        borderSpec: Border.controlSpec("normal", section.app.accent, section.app.accent)

        Row {
          id: handover
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.margins: Style.spacing.lg
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.lg

          Text {
            width: parent.width - moveButton.width - (cancelButton.visible ? cancelButton.width + Style.spacing.lg : 0) - Style.spacing.lg
            anchors.verticalCenter: parent.verticalCenter
            wrapMode: Text.WordWrap
            color: section.app.foreground
            font.family: section.app.fontFamily
            font.pixelSize: Style.font.caption
            text: section.app.confirmShuffleMove
              ? "Remove OmaShuffle and let Lacquer run the shuffle? Your rotation, schedule and history "
                + "come across exactly. OmaShuffle's own state file is left in place as a backup."
              : "OmaShuffle is still running your shuffle, so these settings are read-only here. "
                + "Move it to Lacquer to edit them — nothing about how it behaves changes."
          }

          Button {
            id: moveButton
            anchors.verticalCenter: parent.verticalCenter
            text: section.app.confirmShuffleMove ? "Yes, move it" : "Move to Lacquer"
            bordered: true
            foreground: section.app.foreground
            accent: section.app.accent
            fontFamily: section.app.fontFamily
            onClicked: {
              if (section.app.confirmShuffleMove) section.app.moveShuffleToLacquer()
              else section.app.confirmShuffleMove = true
            }
          }

          Button {
            id: cancelButton
            visible: section.app.confirmShuffleMove
            anchors.verticalCenter: parent.verticalCenter
            text: "Cancel"
            bordered: true
            foreground: section.app.foreground
            accent: section.app.accent
            fontFamily: section.app.fontFamily
            onClicked: section.app.confirmShuffleMove = false
          }
        }
      }

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        text: section.statusLine()
        color: section.app.foreground
        font.family: section.app.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }

      // Everything below is inert until the engine is live.
      Column {
        width: parent.width
        spacing: Style.spacing.lg
        enabled: section.live
        opacity: section.live ? 1 : 0.55
        visible: section.ready

        // ---------------------------------------------------------- modes

        PanelSectionHeader { text: "Mode"; foreground: section.app.foreground; fontFamily: section.app.fontFamily }

        Repeater {
          model: [
            { key: "boot", label: "New theme on every boot", desc: "Draws the next theme from the rotation each time the laptop starts. Dormant while Day & Night is on." },
            { key: "daynight", label: "Day & Night", desc: "Switches theme at sunrise and sunset (or your own slots), drawing light or dark themes from the rotation." },
            { key: "notify", label: "Notifications", desc: "Say which theme was picked. Day & Night switches are always quiet." }
          ]

          Item {
            required property var modelData
            width: column.width
            height: Math.max(modeText.implicitHeight, modeSwitch.implicitHeight) + Style.spacing.lg

            Column {
              id: modeText
              anchors.left: parent.left
              anchors.right: modeSwitch.left
              anchors.rightMargin: Style.spacing.xxl
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.xxs
              Text { text: modelData.label; color: section.app.foreground; font.family: section.app.fontFamily; font.pixelSize: Style.font.subtitle; font.bold: true }
              Text { width: parent.width; wrapMode: Text.WordWrap; text: modelData.desc; color: Qt.darker(section.app.foreground, 1.55); font.family: section.app.fontFamily; font.pixelSize: Style.font.caption }
            }

            ToggleSwitch {
              id: modeSwitch
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              foreground: section.app.foreground
              accent: section.app.accent
              checked: !section.st ? false
                : modelData.key === "boot" ? section.st.enabled
                : modelData.key === "daynight" ? section.st.schedule.enabled
                : section.st.notify
              onToggled: {
                if (modelData.key === "boot") section.engine.setEnabled(!section.st.enabled)
                else if (modelData.key === "daynight") section.engine.setScheduleEnabled(!section.st.schedule.enabled)
                else section.engine.setNotify(!section.st.notify)
              }
            }
          }
        }

        Row {
          spacing: Style.spacing.lg
          Button { text: "Shuffle now"; iconText: "󰒝"; bordered: true; foreground: section.app.foreground; accent: section.app.accent; fontFamily: section.app.fontFamily; onClicked: section.engine.shuffleNow() }
          Button { text: "Reshuffle deck"; bordered: true; foreground: section.app.foreground; accent: section.app.accent; fontFamily: section.app.fontFamily; onClicked: section.engine.reshuffleDeck() }
        }

        PanelSeparator { foreground: section.app.foreground; width: parent.width }

        // ---------------------------------------------------------- rotation

        Item {
          width: parent.width
          height: rotationHeader.implicitHeight

          PanelSectionHeader {
            id: rotationHeader
            text: "Rotation"
            foreground: section.app.foreground
            fontFamily: section.app.fontFamily
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: rotationHeader.verticalCenter
            text: section.st ? section.st.pool.length + " of " + section.engine.themes.length + " in rotation   ·   "
              + (section.st.deck || []).length + " left in this shuffle" : ""
            color: Qt.darker(section.app.foreground, 1.6)
            font.family: section.app.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Row {
          spacing: Style.spacing.sm
          Repeater {
            model: [
              { label: "All", act: "all" }, { label: "None", act: "none" },
              { label: "All dark", act: "dark" }, { label: "All light", act: "light" }
            ]
            Button {
              required property var modelData
              text: modelData.label
              bordered: true
              foreground: section.app.foreground
              accent: section.app.accent
              fontFamily: section.app.fontFamily
              onClicked: {
                if (modelData.act === "all") section.engine.selectAll()
                else if (modelData.act === "none") section.engine.selectNone()
                else section.engine.selectByMode(modelData.act)
              }
            }
          }
        }

        Flow {
          width: parent.width
          spacing: Style.spacing.xs

          Repeater {
            model: section.ready ? section.engine.themes : []

            Button {
              required property var modelData
              readonly property bool picked: !!(section.st && section.st.pool.indexOf(modelData.slug) !== -1)
              text: (picked ? "✓  " : "") + modelData.display
              iconText: modelData.mode === "light" ? "󰖨" : "󰖔"
              selected: picked
              bordered: true
              foreground: section.app.foreground
              accent: section.app.accent
              fontFamily: section.app.fontFamily
              onClicked: section.engine.togglePool(modelData.slug)
            }
          }
        }

        PanelSeparator { foreground: section.app.foreground; width: parent.width; visible: section.st && section.st.schedule.enabled }

        // ---------------------------------------------------------- schedule

        Column {
          width: parent.width
          spacing: Style.spacing.lg
          visible: section.st !== null && section.st.schedule.enabled

          PanelSectionHeader { text: "Day & Night"; foreground: section.app.foreground; fontFamily: section.app.fontFamily }

          Row {
            spacing: Style.spacing.lg

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "Location"
              color: section.app.foreground
              font.family: section.app.fontFamily
              font.pixelSize: Style.font.body
              width: Style.space(90)
            }

            ButtonGroup {
              anchors.verticalCenter: parent.verticalCenter
              options: [{ value: "auto", label: "From weather" }, { value: "manual", label: "Manual" }]
              value: section.st ? section.st.schedule.locationMode : "auto"
              foreground: section.app.foreground
              accent: section.app.accent
              fontFamily: section.app.fontFamily
              focusable: false
              onChanged: function(v) { section.engine.setLocationMode(v) }
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              visible: section.st && section.st.schedule.locationMode === "auto"
              text: section.ready && isFinite(section.engine.detectedLat)
                ? (section.engine.detectedLocationLabel || "Detected") + "  (" + section.engine.detectedLat.toFixed(2) + ", " + section.engine.detectedLon.toFixed(2) + ")"
                : "No weather location set in Omarchy"
              color: Qt.darker(section.app.foreground, 1.5)
              font.family: section.app.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Row {
            spacing: Style.spacing.lg
            visible: section.st && section.st.schedule.locationMode === "manual"

            Text { anchors.verticalCenter: parent.verticalCenter; text: "Latitude"; color: section.app.foreground; font.family: section.app.fontFamily; font.pixelSize: Style.font.body; width: Style.space(90) }
            TextField {
              width: Style.space(110)
              foreground: section.app.foreground
              accent: section.app.accent
              text: section.st && typeof section.st.schedule.latitude === "number" ? String(section.st.schedule.latitude) : ""
              onEditingFinished: { section.engine.setManualLatitude(text); section.app.focusPanel() }
            }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "Longitude"; color: section.app.foreground; font.family: section.app.fontFamily; font.pixelSize: Style.font.body }
            TextField {
              width: Style.space(110)
              foreground: section.app.foreground
              accent: section.app.accent
              text: section.st && typeof section.st.schedule.longitude === "number" ? String(section.st.schedule.longitude) : ""
              onEditingFinished: { section.engine.setManualLongitude(text); section.app.focusPanel() }
            }
          }

          Repeater {
            model: section.st ? section.st.schedule.slots : []

            BorderSurface {
              id: slotCard
              required property var modelData
              // info.active is undefined without a location; a bool must not get undefined.
              readonly property bool isActive: !!(section.info.active && section.info.active.id === modelData.id)
              width: column.width
              height: slotRow.implicitHeight + Style.spacing.xxl
              radius: Style.cornerRadius
              color: Style.normalFillFor(section.app.foreground, section.app.accent)
              borderSpec: Border.controlSpec(slotCard.isActive ? "focus" : "normal", section.app.foreground, section.app.accent)

              Column {
                id: slotRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Style.spacing.lg
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacing.md

                Row {
                  spacing: Style.spacing.lg

                  TextField {
                    width: Style.space(140)
                    foreground: section.app.foreground
                    accent: section.app.accent
                    text: slotCard.modelData.label
                    onEditingFinished: {
                      if (text.trim() !== "" && text !== slotCard.modelData.label)
                        section.engine.updateSlot(slotCard.modelData.id, { label: text.trim().slice(0, 40) })
                      section.app.focusPanel()
                    }
                  }

                  ButtonGroup {
                    anchors.verticalCenter: parent.verticalCenter
                    options: [{ value: "light", label: "Light" }, { value: "dark", label: "Dark" }]
                    value: slotCard.modelData.mode
                    foreground: section.app.foreground
                    accent: section.app.accent
                    fontFamily: section.app.fontFamily
                    focusable: false
                    onChanged: function(v) { section.engine.updateSlot(slotCard.modelData.id, { mode: v }) }
                  }

                  ButtonGroup {
                    anchors.verticalCenter: parent.verticalCenter
                    options: [{ value: "sunrise", label: "Sunrise" }, { value: "sunset", label: "Sunset" }]
                    value: slotCard.modelData.anchor
                    foreground: section.app.foreground
                    accent: section.app.accent
                    fontFamily: section.app.fontFamily
                    focusable: false
                    onChanged: function(v) { section.engine.updateSlot(slotCard.modelData.id, { anchor: v }) }
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: slotCard.isActive
                    text: "active now"
                    color: section.app.accent
                    font.family: section.app.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Item {
                  width: parent.width
                  height: Math.max(offsetSlider.height, removeSlot.height)

                  Text {
                    id: offsetLabel
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(170)
                    text: {
                      var m = slotCard.modelData.offsetMin
                      var when = m === 0 ? "at " + slotCard.modelData.anchor
                        : Math.abs(m) + " min " + (m < 0 ? "before " : "after ") + slotCard.modelData.anchor
                      return "Starts " + when
                    }
                    color: section.app.foreground
                    font.family: section.app.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  PanelSlider {
                    id: offsetSlider
                    anchors.left: offsetLabel.right
                    anchors.leftMargin: Style.spacing.lg
                    anchors.right: removeSlot.left
                    anchors.rightMargin: Style.spacing.lg
                    anchors.verticalCenter: parent.verticalCenter
                    minimum: -720
                    maximum: 720
                    step: 15
                    integer: true
                    value: slotCard.modelData.offsetMin
                    fillColor: section.app.foreground
                    knobColor: section.app.foreground
                    onReleased: function(v) { section.engine.updateSlot(slotCard.modelData.id, { offsetMin: Math.round(v / 15) * 15 }) }
                  }

                  PanelActionButton {
                    id: removeSlot
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    iconText: "󰅖"
                    tooltipText: "Remove this slot"
                    foreground: section.app.foreground
                    visible: section.st && section.st.schedule.slots.length > 1
                    onClicked: section.engine.removeSlot(slotCard.modelData.id)
                  }
                }
              }
            }
          }

          Button {
            text: "Add slot"
            iconText: "󰐕"
            bordered: true
            visible: section.st && section.st.schedule.slots.length < 6
            foreground: section.app.foreground
            accent: section.app.accent
            fontFamily: section.app.fontFamily
            onClicked: section.engine.addSlot()
          }
        }

        PanelSeparator { foreground: section.app.foreground; width: parent.width }

        // ---------------------------------------------------------- history

        PanelSectionHeader { text: "Recent"; foreground: section.app.foreground; fontFamily: section.app.fontFamily }

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          color: Qt.darker(section.app.foreground, 1.5)
          font.family: section.app.fontFamily
          font.pixelSize: Style.font.caption
          text: {
            section.tick
            if (!section.st || section.st.history.length === 0) return "Nothing yet."
            var now = Date.now() / 1000
            var parts = []
            for (var i = 0; i < Math.min(8, section.st.history.length); i++) {
              var h = section.st.history[i]
              var age = Math.max(0, now - h.ts)
              var ago = age < 3600 ? Math.round(age / 60) + "m" : age < 86400 ? Math.round(age / 3600) + "h" : Math.round(age / 86400) + "d"
              parts.push(h.display + " (" + ago + (h.auto ? ", auto" : "") + ")")
            }
            return parts.join("   ·   ")
          }
        }
      }
    }
  }
}
