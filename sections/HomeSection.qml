import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Ui
import "../LookSchema.js" as LookSchema
import "../AnimSchema.js" as AnimSchema
import "../ShellSchema.js" as ShellSchema

// The landing page: a live miniature of the desktop drawn from the user's own
// settings, the theme's palette drifting behind everything, a search across
// every option, and every section with what it is set to right now.
//
// Everything that moves runs only while the page is on screen, and all of it
// is native scene-graph animation with no per-frame JavaScript or blur.
Item {
  id: home

  required property var app

  readonly property bool live: visible && app.opened
  // Live and allowed to move: the Motion switch stills everything below.
  readonly property bool moving: live && app.motion
  property string query: ""
  property int cursorAt: 0

  // ---------------------------------------------------------------- theme

  readonly property var themeInfo: app.theme.themeFor(app.theme.current) || ({})
  readonly property color accent: themeInfo.accent || app.accent
  readonly property var palette: {
    var out = []
    var seen = {}
    var raw = [themeInfo.accent].concat(themeInfo.colors || [])
    for (var i = 0; i < raw.length && out.length < 7; i++) {
      var c = String(raw[i] || "").toLowerCase()
      if (!c || seen[c]) continue
      seen[c] = true
      out.push(c)
    }
    if (out.length === 0) out = [String(app.accent), String(app.foreground)]
    return out
  }

  // ---------------------------------------------------------------- settings read for the miniature

  function hyprNum(key, fallback) {
    var item = LookSchema.itemFor(key)
    if (!item) return fallback
    var v = Number(app.hypr.valueFor(item))
    return isFinite(v) ? v : fallback
  }

  function hyprBool(key) {
    var item = LookSchema.itemFor(key)
    return item ? app.hypr.valueFor(item) === true : false
  }

  // A leaf inherits from its parents until one is set.
  function leafFor(chain) {
    for (var i = 0; i < chain.length; i++) {
      var v = app.hypr.leafValue(chain[i])
      if (v) return v
    }
    return { enabled: true, speed: 5, bezier: "default", style: "" }
  }

  readonly property int gapsIn: hyprNum("general:gaps_in", 5)
  readonly property int gapsOut: hyprNum("general:gaps_out", 10)
  readonly property int borderSize: hyprNum("general:border_size", 2)
  readonly property int rounding: hyprNum("decoration:rounding", 0)
  readonly property real activeOpacity: hyprNum("decoration:active_opacity", 1)
  readonly property real inactiveOpacity: hyprNum("decoration:inactive_opacity", 1)
  readonly property bool animationsOn: {
    var item = LookSchema.itemFor("animations:enabled")
    return item ? app.hypr.valueFor(item) !== false : true
  }
  readonly property var moveLeaf: leafFor(["windowsMove", "windows", "global"])
  readonly property var openLeaf: leafFor(["windowsIn", "windows", "global"])
  readonly property var moveCurve: app.hypr.curveValue(moveLeaf.bezier || "default")
  readonly property var openCurve: app.hypr.curveValue(openLeaf.bezier || "default")
  // Hyprland speeds are in deciseconds.
  readonly property int moveMs: !animationsOn || moveLeaf.enabled === false ? 0 : Math.max(120, Math.min(1400, Number(moveLeaf.speed) * 100))
  readonly property int openMs: !animationsOn || openLeaf.enabled === false ? 0 : Math.max(120, Math.min(1400, Number(openLeaf.speed) * 100))
  readonly property string barPosition: {
    var bar = app.sjson.barConfig && app.sjson.barConfig.bar
    return bar && bar.position ? String(bar.position) : "top"
  }

  // ---------------------------------------------------------------- summaries

  function formatSeconds(s) { return app.screens.formatSeconds(s) }

  function summaryFor(id) {
    var d = app.desktop.info
    var sh = app.shuffle
    switch (id) {
    case "theme": return (themeInfo.display || app.theme.current || "—") + (themeInfo.mode ? " · " + themeInfo.mode : "")
    case "shuffle":
      if (!sh || !sh.st) return "Boot and day-night shuffle"
      var mode = sh.st.schedule && sh.st.schedule.enabled ? "Day & Night" : sh.st.enabled ? "Every boot" : "Off"
      return mode + (sh.dormant ? " · run by OmaShuffle" : "")
    case "generate": return app.aether.blueprints.length > 0 ? app.aether.blueprints.length + " blueprints" : "A theme from any wallpaper"
    case "fonts": return d ? d.mono.current + " · " + (d.text.px || 12) + " px" : "Text size and fonts"
    case "gtk":
      if (!d) return "Apps, GTK and icons"
      var pins = 0
      for (var p in app.desktop.pins) pins++
      return d.gsettings["icon-theme"] + (pins > 0 ? " · " + pins + " pinned" : " · follows theme")
    case "cursor": return d ? d.gsettings["cursor-theme"] + " · " + d.gsettings["cursor-size"] + " px" : "Pointer theme and size"
    case "nightlight":
      var ns = app.night.status
      if (!ns) return "Warmer screen"
      if (ns.schedule) return "Warmer from " + ns.schedule.evening
      return ns.temperature && ns.temperature < 6000 ? "On · " + ns.temperature + " K" : "Off"
    case "windows": return "Gaps " + gapsIn + " / " + gapsOut + " · border " + borderSize
    case "decoration": return "Rounding " + rounding + " · " + Math.round(activeOpacity * 100) + " % opaque"
    case "effects": return "Blur " + (hyprBool("decoration:blur:enabled") ? "on" : "off") + " · shadow " + (hyprBool("decoration:shadow:enabled") ? "on" : "off")
    case "groups": return "Tabbed window groups"
    case "animations": return animationsOn ? "On · windows at " + Number(moveLeaf.speed).toFixed(1) : "Off"
    case "curves": return app.hypr.curveNames.length + " curves"
    case "shell": return "Base text " + (app.toml.shellUser.font && app.toml.shellUser.font["base-size"] ? app.toml.shellUser.font["base-size"] : 12) + " px"
    case "bar": return barPosition.charAt(0).toUpperCase() + barPosition.slice(1) + (app.sjson.barConfig && app.sjson.barConfig.bar && app.sjson.barConfig.bar.transparent ? " · transparent" : "")
    case "menulook":
      var ml = app.menuLook.look
      return ml ? Number(ml.scale).toFixed(2) + "× · " + ml.transparency + " % see-through" : "Omarchy menu"
    case "lock":
      var si = app.screens.info
      if (!si || !si.designs) return "Lock and boot screens"
      for (var i = 0; i < si.designs.length; i++) if (si.designs[i].active) return si.designs[i].name + " · boot " + (si.status.boot || "stock")
      return "Lock and boot screens"
    case "screensaver":
      var ss = app.screens.info
      return ss ? (ss.screensaverOff ? "Off" : "After " + formatSeconds(ss.idle.screensaver)) : "Screensaver and art"
    case "terminals":
      var tv = app.apps.term
      return tv ? tv.cursor + " cursor · " + tv.padding + " px padding" : "Padding, cursor, opacity"
    case "btop":
      var ai = app.apps.info
      return ai && ai.btop ? ai.btop.graph_symbol + " graphs · " + ai.btop.update_ms + " ms" : "btop and the prompt"
    case "plugins": return app.sjson.plugins.length + " plugins"
    }
    return ""
  }

  // ---------------------------------------------------------------- the grid

  readonly property var groups: {
    var out = []
    var byName = {}
    for (var i = 0; i < app.sections.length; i++) {
      var s = app.sections[i]
      if (s.pane === "home") continue
      if (!byName[s.group]) {
        byName[s.group] = { title: s.group, entries: [] }
        out.push(byName[s.group])
      }
      byName[s.group].entries.push(s)
    }
    return out
  }

  // Grid order, flattened, so the keyboard walks it like reading.
  readonly property var tiles: {
    var out = []
    for (var g = 0; g < groups.length; g++)
      for (var e = 0; e < groups[g].entries.length; e++) out.push({ group: g, section: groups[g].entries[e] })
    return out
  }

  function tileIndex(sectionId) {
    for (var i = 0; i < tiles.length; i++) if (tiles[i].section.id === sectionId) return i
    return -1
  }

  // ---------------------------------------------------------------- search

  // Only the labels a person would look for; groups in the Desktop, Screens
  // and Apps views are listed by their visible titles.
  readonly property var choiceGroups: ({
    fonts: ["Text size", "Terminal & code font", "Interface font size", "Interface font"],
    gtk: ["Light or dark apps", "GTK theme", "Icon theme"],
    cursor: ["Cursor theme", "Cursor size"],
    nightlight: ["Right now", "Schedule", "Warmer from", "Back to normal at", "Evening warmth"],
    lock: ["Lock design", "Try it", "Unlock animation", "Unlock length", "Clock", "Blank the screen after", "Keep the display on while locked", "Lock after", "Boot screen", "Build the boot screen"],
    screensaver: ["Screensaver", "Start after", "Screensaver art", "About screen art"],
    menulook: ["Size", "Corner radius", "Border width", "Transparency"],
    terminals: ["Padding", "Cursor", "Cursor blink", "Background opacity"],
    btop: ["btop background", "btop rounded corners", "btop graphs", "btop refresh", "btop vim keys", "Blank line before the prompt", "Prompt command timeout"],
    theme: ["Themes", "Wallpaper", "Light and dark filter"],
    shuffle: ["Shuffle on boot", "Day & Night", "Location", "Rotation", "History"],
    generate: ["Palette from a wallpaper", "Light or dark palette", "Zed, VS Code and Neovim", "Blueprints", "Open aether"],
    bar: ["Bar position", "Transparent bar", "Bar widgets", "Widget layout"],
    plugins: ["Plugin settings"]
  })

  function iconOf(id) { var s = sectionById(id); return s ? s.icon : "" }

  function sectionById(id) {
    for (var i = 0; i < app.sections.length; i++) if (app.sections[i].id === id) return app.sections[i]
    return null
  }

  readonly property var searchIndex: {
    var out = []
    function add(entry) { entry.hay = (entry.title + " " + (entry.path || "") + " " + (entry.detail || "")).toLowerCase(); out.push(entry) }
    for (var i = 0; i < app.sections.length; i++) {
      var s = app.sections[i]
      if (s.pane === "home") continue
      add({ kind: "section", section: s.id, icon: s.icon, title: s.title, path: s.group, detail: s.blurb })
      var titles = choiceGroups[s.id] || []
      for (var c = 0; c < titles.length; c++)
        add({ kind: "choice", section: s.id, icon: s.icon, title: titles[c], path: s.group + " › " + s.title, group: titles[c] })
    }
    for (var l = 0; l < LookSchema.SECTIONS.length; l++) {
      var ls = LookSchema.SECTIONS[l]
      for (var g = 0; g < ls.groups.length; g++)
        for (var it = 0; it < ls.groups[g].items.length; it++) {
          var item = ls.groups[g].items[it]
          add({ kind: "row", section: ls.id, icon: ls.icon, title: item.label, path: ls.title + " › " + ls.groups[g].title, detail: item.description, key: item.key })
        }
    }
    var master = LookSchema.ANIMATION_MASTER.items
    for (var m = 0; m < master.length; m++)
      add({ kind: "row", section: "animations", icon: "󱐋", title: master[m].label, path: "Animations › Master", detail: master[m].description, key: master[m].key, animTab: 0 })
    for (var a = 0; a < AnimSchema.SECTIONS.length; a++) {
      var as = AnimSchema.SECTIONS[a]
      for (var lf = 0; lf < as.leaves.length; lf++)
        add({ kind: "row", section: "animations", icon: "󱐋", title: as.leaves[lf].label, path: "Animations › " + as.title, detail: as.leaves[lf].description, leaf: as.leaves[lf].name, animTab: a + 1 })
    }
    for (var t = 0; t < ShellSchema.TABS.length; t++) {
      var tab = ShellSchema.TABS[t]
      for (var sg = 0; sg < tab.groups.length; sg++)
        for (var si = 0; si < tab.groups[sg].items.length; si++) {
          var sitem = tab.groups[sg].items[si]
          add({ kind: "row", section: "shell", icon: "󰒓", title: sitem.label, path: "Shell style › " + tab.title + " › " + tab.groups[sg].title, detail: sitem.description, key: sitem.id, shellTab: t })
        }
    }
    return out
  }

  readonly property var results: {
    var q = query.trim().toLowerCase()
    if (q === "") return []
    var words = q.split(/\s+/)
    var scored = []
    for (var i = 0; i < searchIndex.length; i++) {
      var e = searchIndex[i]
      var title = e.title.toLowerCase()
      var score = 0
      var ok = true
      for (var w = 0; w < words.length; w++) {
        if (e.hay.indexOf(words[w]) === -1) { ok = false; break }
        if (title.indexOf(words[w]) === 0) score += 6
        else if (title.indexOf(" " + words[w]) !== -1) score += 4
        else if (title.indexOf(words[w]) !== -1) score += 3
        else score += 1
      }
      if (!ok) continue
      if (e.kind === "section") score += 2
      scored.push({ entry: e, score: score })
    }
    scored.sort(function(x, y) { return y.score - x.score || x.entry.title.length - y.entry.title.length })
    return scored.slice(0, 60).map(function(s) { return s.entry })
  }

  readonly property int optionCount: searchIndex.length

  // ---------------------------------------------------------------- keyboard

  function typeText(t) { home.query += t; home.cursorAt = 0 }
  function backspace() { if (home.query.length > 0) { home.query = home.query.slice(0, -1); home.cursorAt = 0 } }
  function clearQuery() { if (home.query === "") return false; home.query = ""; home.cursorAt = 0; return true }

  function moveBy(dx, dy) {
    if (home.query !== "") {
      home.cursorAt = Math.max(0, Math.min(results.length - 1, home.cursorAt + dy + dx))
      resultList.positionViewAtIndex(home.cursorAt, ListView.Contain)
      return
    }
    if (tiles.length === 0) return
    if (dy !== 0) {
      home.cursorAt = Math.max(0, Math.min(tiles.length - 1, home.cursorAt + dy))
    } else {
      var g = tiles[home.cursorAt].group + dx
      if (g < 0 || g >= groups.length) return
      for (var i = 0; i < tiles.length; i++) if (tiles[i].group === g) { home.cursorAt = i; break }
    }
    revealTile()
  }

  function activate() {
    if (home.query !== "") {
      if (results[home.cursorAt]) app.jumpTo(results[home.cursorAt])
      return
    }
    if (tiles[home.cursorAt]) app.showSectionById(tiles[home.cursorAt].section.id)
  }

  // Card items by group index, filled in as they are created.
  property var cards: ({})

  function revealTile() {
    var card = home.cards[tiles[home.cursorAt].group]
    if (!card) return
    var top = card.mapToItem(pageColumn, 0, 0).y
    var bottom = top + card.height
    if (top < page.contentY) page.contentY = Math.max(0, top - Style.spacing.lg)
    else if (bottom > page.contentY + page.height) page.contentY = Math.min(page.contentHeight - page.height, bottom - page.height + Style.spacing.lg)
  }

  property int entrance: 0
  onLiveChanged: {
    if (!live) return
    home.query = ""
    home.cursorAt = 0
    page.contentY = 0
    home.entrance++
    app.desktop.rescan()
    app.night.rescan()
    app.screens.rescan()
    app.menuLook.rescan()
    app.apps.rescan()
  }

  // ================================================================ aurora

  // One slow clock for everything that moves continuously. Measured on a
  // Ryzen 5 4500U laptop: anything animating at the display rate without pause makes the
  // shell redraw the panel 60 times a second, about 12 % of a core, whatever
  // it animates. The drift and the palette bob are slow enough to step at
  // ~15 frames a second (roughly 2 %) and look the same.
  property real tick: 0
  Timer {
    interval: 66
    repeat: true
    running: home.moving
    onTriggered: home.tick += 0.066
  }

  // Soft radial-gradient discs in the theme's colours.
  Item {
    id: blobs
    anchors.fill: parent
    opacity: home.themeInfo.mode === "light" ? 0.2 : 0.34

    Repeater {
      model: Math.min(5, home.palette.length)
      Shape {
        id: blob
        required property int index
        readonly property real size: blobs.width * (0.5 + 0.12 * (index % 3))
        readonly property color tint: home.palette[index % home.palette.length]
        readonly property real cx: blobs.width * (0.1 + 0.8 * ((index * 0.29) % 1)) - size / 2
        readonly property real cy: blobs.height * (0.15 + 0.7 * ((index * 0.43) % 1)) - size / 2
        readonly property real dx: blobs.width * 0.18
        readonly property real dy: blobs.height * 0.16
        width: size
        height: size
        // Periods of 70-110 s across and 55-80 s down, so the discs never line up.
        x: cx + Math.sin(home.tick * (6.283 / (70 + index * 10)) + index * 1.7) * dx
        y: cy + Math.cos(home.tick * (6.283 / (55 + index * 6)) + index) * dy

        ShapePath {
          strokeWidth: -1
          fillGradient: RadialGradient {
            centerX: blob.size / 2; centerY: blob.size / 2; centerRadius: blob.size / 2
            focalX: blob.size / 2; focalY: blob.size / 2
            GradientStop { position: 0.0; color: Qt.rgba(blob.tint.r, blob.tint.g, blob.tint.b, 0.9) }
            GradientStop { position: 0.45; color: Qt.rgba(blob.tint.r, blob.tint.g, blob.tint.b, 0.45) }
            GradientStop { position: 1.0; color: Qt.rgba(blob.tint.r, blob.tint.g, blob.tint.b, 0) }
          }
          PathAngleArc {
            centerX: blob.size / 2; centerY: blob.size / 2
            radiusX: blob.size / 2; radiusY: blob.size / 2
            startAngle: 0; sweepAngle: 360
          }
        }

      }
    }
  }

  // ================================================================ page

  Flickable {
    id: page
    anchors.fill: parent
    clip: true
    contentWidth: width
    contentHeight: pageColumn.implicitHeight + Style.spacing.lg
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: pageColumn
      width: page.width - Style.spacing.md
      spacing: Style.spacing.xl

      // ------------------------------------------------------------ hero
      Row {
        id: hero
        width: parent.width
        spacing: Style.spacing.xxl

        // A miniature of this desktop, drawn from the live settings.
        Column {
          id: miniColumn
          width: Math.round(hero.width * 0.47)
          spacing: Style.spacing.sm

          Rectangle {
            id: mini
            width: parent.width
            height: Math.round(width * 10 / 16)
            radius: Math.max(4, Style.cornerRadius)
            color: home.themeInfo.background || home.app.background
            clip: true
            border.width: 1
            border.color: Qt.rgba(home.app.foreground.r, home.app.foreground.g, home.app.foreground.b, 0.25)

            // Drawn at twice the scale of the real screen, so a gap of 5
            // reads as a gap rather than a hairline.
            readonly property real k: width / 960

            Image {
              anchors.fill: parent
              source: home.app.theme.currentWallpaper ? "file://" + encodeURI(home.app.theme.currentWallpaper) : ""
              sourceSize.width: 520
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
            }

            Rectangle {
              id: miniBar
              x: 0
              y: home.barPosition === "bottom" ? parent.height - height : 0
              width: parent.width
              height: Math.max(8, Math.round(26 * mini.k * 1.4))
              color: Qt.rgba(0, 0, 0, 0)
              Rectangle {
                anchors.fill: parent
                color: home.themeInfo.background || home.app.background
                opacity: 0.9
              }
              Row {
                anchors.left: parent.left
                anchors.leftMargin: height
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height * 0.34
                spacing: height * 0.9
                Repeater {
                  model: 4
                  Rectangle {
                    required property int index
                    width: parent.height * (index === miniArea.activeWs ? 2.2 : 1)
                    height: parent.height
                    radius: height / 2
                    color: index === miniArea.activeWs ? home.accent : (home.themeInfo.foreground || home.app.foreground)
                    opacity: index === miniArea.activeWs ? 1 : 0.45
                    Behavior on width { enabled: home.app.motion; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                  }
                }
              }
              Rectangle {
                anchors.centerIn: parent
                width: parent.height * 2.6
                height: parent.height * 0.34
                radius: height / 2
                color: home.themeInfo.foreground || home.app.foreground
                opacity: 0.5
              }
            }

            Item {
              id: miniArea
              readonly property real gOut: Math.max(1, home.gapsOut * mini.k)
              readonly property real gIn: Math.max(1, home.gapsIn * mini.k)
              x: gOut
              y: (home.barPosition === "bottom" ? 0 : miniBar.height) + gOut
              width: mini.width - gOut * 2
              height: mini.height - miniBar.height - gOut * 2

              property int phase: 0
              property int activeWs: 0

              // Layouts in fractions of the area; the gaps are applied below.
              readonly property var layouts: [
                [[0, 0, 1, 1], null, null],
                [[0, 0, 0.5, 1], [0.5, 0, 0.5, 1], null],
                [[0, 0, 0.5, 1], [0.5, 0, 0.5, 0.5], [0.5, 0.5, 0.5, 0.5]],
                [[0.5, 0, 0.5, 1], [0, 0, 0.5, 0.5], [0, 0.5, 0.5, 0.5]],
                [[0, 0, 0.62, 1], [0.62, 0, 0.38, 1], null]
              ]
              readonly property var focusOrder: [0, 1, 2, 0, 1]

              Timer {
                // Each re-tile is a burst of full-rate frames; a few seconds of
                // stillness between them keeps the page cheap.
                interval: Math.max(3000, home.moveMs + 2400)
                repeat: true
                running: home.moving
                onTriggered: {
                  miniArea.phase = (miniArea.phase + 1) % miniArea.layouts.length
                  if (miniArea.phase === 0) miniArea.activeWs = (miniArea.activeWs + 1) % 4
                }
              }

              // The pointer drifts to whichever window has focus.
              Text {
                id: miniPointer
                z: 10
                readonly property var focusSlot: miniArea.layouts[miniArea.phase][miniArea.focusOrder[miniArea.phase]] || [0, 0, 1, 1]
                x: (focusSlot[0] + focusSlot[2] * 0.62) * miniArea.width
                y: (focusSlot[1] + focusSlot[3] * 0.58) * miniArea.height
                text: "󰇀"
                color: home.themeInfo.foreground || home.app.foreground
                style: Text.Outline
                styleColor: home.themeInfo.background || home.app.background
                font.pixelSize: Math.max(10, Style.space(13))
                Behavior on x { enabled: home.app.motion; NumberAnimation { duration: Math.max(300, home.moveMs); easing.type: Easing.InOutCubic } }
                Behavior on y { enabled: home.app.motion; NumberAnimation { duration: Math.max(300, home.moveMs); easing.type: Easing.InOutCubic } }
              }

              Repeater {
                model: 3
                Item {
                  id: win
                  required property int index
                  readonly property var slot: miniArea.layouts[miniArea.phase][index]
                  readonly property var lastSlot: {
                    for (var p = miniArea.layouts.length - 1; p >= 0; p--) {
                      var s = miniArea.layouts[(miniArea.phase + p) % miniArea.layouts.length][index]
                      if (s) return s
                    }
                    return [0, 0, 1, 1]
                  }
                  readonly property var r: slot || lastSlot
                  readonly property real half: miniArea.gIn / 2
                  readonly property bool shown: slot !== null
                  readonly property bool focused: miniArea.focusOrder[miniArea.phase] === index

                  x: r[0] * miniArea.width + (r[0] > 0 ? half : 0)
                  y: r[1] * miniArea.height + (r[1] > 0 ? half : 0)
                  width: r[2] * miniArea.width - (r[0] > 0 ? half : 0) - (r[0] + r[2] < 0.999 ? half : 0)
                  height: r[3] * miniArea.height - (r[1] > 0 ? half : 0) - (r[1] + r[3] < 0.999 ? half : 0)
                  opacity: shown ? (focused ? home.activeOpacity : home.inactiveOpacity) : 0
                  scale: shown ? 1 : 0.82

                  Behavior on x { enabled: home.moveMs > 0 && home.app.motion; NumberAnimation { duration: home.moveMs; easing.type: Easing.BezierSpline; easing.bezierCurve: [home.moveCurve[0], home.moveCurve[1], home.moveCurve[2], home.moveCurve[3], 1, 1] } }
                  Behavior on y { enabled: home.moveMs > 0 && home.app.motion; NumberAnimation { duration: home.moveMs; easing.type: Easing.BezierSpline; easing.bezierCurve: [home.moveCurve[0], home.moveCurve[1], home.moveCurve[2], home.moveCurve[3], 1, 1] } }
                  Behavior on width { enabled: home.moveMs > 0 && home.app.motion; NumberAnimation { duration: home.moveMs; easing.type: Easing.BezierSpline; easing.bezierCurve: [home.moveCurve[0], home.moveCurve[1], home.moveCurve[2], home.moveCurve[3], 1, 1] } }
                  Behavior on height { enabled: home.moveMs > 0 && home.app.motion; NumberAnimation { duration: home.moveMs; easing.type: Easing.BezierSpline; easing.bezierCurve: [home.moveCurve[0], home.moveCurve[1], home.moveCurve[2], home.moveCurve[3], 1, 1] } }
                  Behavior on opacity { enabled: home.openMs > 0 && home.app.motion; NumberAnimation { duration: home.openMs; easing.type: Easing.BezierSpline; easing.bezierCurve: [home.openCurve[0], home.openCurve[1], home.openCurve[2], home.openCurve[3], 1, 1] } }
                  Behavior on scale { enabled: home.openMs > 0 && home.app.motion; NumberAnimation { duration: home.openMs; easing.type: Easing.BezierSpline; easing.bezierCurve: [home.openCurve[0], home.openCurve[1], home.openCurve[2], home.openCurve[3], 1, 1] } }

                  Rectangle {
                    anchors.fill: parent
                    radius: home.rounding * mini.k
                    color: home.themeInfo.background || home.app.background
                    border.width: home.borderSize > 0 ? Math.max(1, Math.round(home.borderSize * mini.k)) : 0
                    border.color: win.focused ? home.accent
                      : Qt.rgba(home.app.foreground.r, home.app.foreground.g, home.app.foreground.b, 0.3)
                    Behavior on border.color { enabled: home.app.motion; ColorAnimation { duration: 180 } }
                    clip: true

                    // Skeleton content, in the theme's own colours.
                    Column {
                      x: Math.max(3, parent.width * 0.08)
                      y: Math.max(3, parent.height * 0.1)
                      width: parent.width - x * 2
                      spacing: Math.max(2, parent.height * 0.06)
                      Repeater {
                        model: 4
                        Rectangle {
                          required property int index
                          width: parent.width * [0.55, 0.85, 0.7, 0.4][index]
                          height: Math.max(2, Math.min(5, win.height * 0.045))
                          radius: height / 2
                          color: index === 0 ? home.palette[(win.index + 1) % home.palette.length] : (home.themeInfo.foreground || home.app.foreground)
                          opacity: index === 0 ? 0.9 : 0.28
                        }
                      }
                    }
                  }
                }
              }
            }
          }

          Text {
            width: parent.width
            elide: Text.ElideRight
            text: home.moveMs > 0
              ? "Live · " + (home.moveLeaf.bezier || "default") + " · " + home.moveMs + " ms"
              : "Live · animations off"
            color: Qt.darker(home.app.foreground, 1.6)
            font.family: home.app.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // Greeting and the state of things.
        Column {
          width: hero.width - miniColumn.width - hero.spacing
          spacing: Style.spacing.md

          Text {
            id: greeting
            property date now: new Date()
            text: {
              var h = now.getHours()
              var part = h < 5 ? "Late night" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
              return part.toUpperCase() + "   ·   " + Qt.formatTime(now, "HH:mm")
            }
            color: home.accent
            font.family: home.app.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.2
            Timer { interval: 20000; repeat: true; running: home.live; onTriggered: greeting.now = new Date() }
          }

          Text {
            width: parent.width
            elide: Text.ElideRight
            text: home.themeInfo.display || "Lacquer"
            color: home.app.foreground
            font.family: home.app.fontFamily
            font.pixelSize: Style.font.display
            font.bold: true
          }

          // The palette, breathing.
          Item {
            width: parent.width
            height: Style.space(26)
            id: waveRow
            Row {
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.sm
              Repeater {
                model: home.palette
                Rectangle {
                  id: swatch
                  required property var modelData
                  required property int index
                  // A wave along the row, on the shared slow clock.
                  readonly property real lift: Math.sin(home.tick * 1.75 - index * 0.75)
                  width: Style.space(16)
                  height: width
                  radius: width / 2
                  color: modelData
                  border.width: 1
                  border.color: Qt.rgba(home.app.foreground.r, home.app.foreground.g, home.app.foreground.b, 0.2)
                  transform: Translate { y: -swatch.lift * Style.space(3) }
                }
              }
            }
          }

          Repeater {
            model: [
              { icon: home.iconOf("theme"), id: "theme", text: (home.themeInfo.mode ? home.themeInfo.mode + " theme · " : "") + home.app.theme.themes.length + " to choose from" },
              { icon: home.iconOf("shuffle"), id: "shuffle", text: "Shuffle: " + home.summaryFor("shuffle") },
              { icon: home.iconOf("nightlight"), id: "nightlight", text: "Nightlight: " + home.summaryFor("nightlight") },
              { icon: home.iconOf("fonts"), id: "fonts", text: home.summaryFor("fonts") }
            ]
            Row {
              required property var modelData
              spacing: Style.spacing.md
              Text {
                width: Style.space(18)
                text: modelData.icon
                color: home.accent
                font.family: home.app.fontFamily
                font.pixelSize: Style.font.body
              }
              Text {
                text: modelData.text
                color: home.app.foreground
                font.family: home.app.fontFamily
                font.pixelSize: Style.font.caption
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: home.app.showSectionById(modelData.id)
                }
              }
            }
          }
        }
      }

      // ------------------------------------------------------------ search
      Rectangle {
        id: searchBox
        width: parent.width
        height: Style.space(40)
        radius: Style.cornerRadius
        color: Qt.rgba(home.app.background.r, home.app.background.g, home.app.background.b, 0.85)
        border.width: home.query !== "" ? Math.max(2, Style.space(2)) : 1
        border.color: home.query !== "" ? home.accent : Qt.rgba(home.app.foreground.r, home.app.foreground.g, home.app.foreground.b, 0.3)

        Text {
          id: searchIcon
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.lg
          anchors.verticalCenter: parent.verticalCenter
          text: "󰍉"
          color: home.query !== "" ? home.accent : Qt.darker(home.app.foreground, 1.5)
          font.family: home.app.fontFamily
          font.pixelSize: Style.font.subtitle
        }

        Text {
          id: typed
          anchors.left: searchIcon.right
          anchors.leftMargin: Style.spacing.md
          anchors.verticalCenter: parent.verticalCenter
          text: home.query
          color: home.app.foreground
          font.family: home.app.fontFamily
          font.pixelSize: Style.font.body
        }

        Rectangle {
          anchors.left: typed.right
          anchors.leftMargin: 1
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(1, Style.space(2))
          height: Style.font.body * 1.2
          color: home.accent
          // A hard blink: two redraws a second instead of a fade's sixty.
          Timer {
            interval: 530
            repeat: true
            running: home.moving
            onTriggered: parent.visible = !parent.visible
            onRunningChanged: if (!running) parent.visible = true
          }
        }

        Text {
          anchors.left: typed.right
          anchors.leftMargin: Style.spacing.md
          anchors.verticalCenter: parent.verticalCenter
          visible: home.query === ""
          text: "Search " + home.optionCount + " settings — just start typing"
          color: Qt.darker(home.app.foreground, 1.7)
          font.family: home.app.fontFamily
          font.pixelSize: Style.font.body
        }

        Text {
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.lg
          anchors.verticalCenter: parent.verticalCenter
          visible: home.query !== ""
          text: home.results.length === 0 ? "nothing matches" : home.results.length + (home.results.length === 60 ? "+" : "") + " found · Enter opens · Esc clears"
          color: Qt.darker(home.app.foreground, 1.6)
          font.family: home.app.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      // ------------------------------------------------------------ results
      Rectangle {
        visible: home.query !== ""
        width: parent.width
        height: resultList.height + Style.spacing.sm * 2
        radius: Math.max(4, Style.cornerRadius)
        color: Qt.rgba(home.app.background.r, home.app.background.g, home.app.background.b, 0.86)
        border.width: 1
        border.color: Qt.rgba(home.app.foreground.r, home.app.foreground.g, home.app.foreground.b, 0.16)

      ListView {
        id: resultList
        x: Style.spacing.sm
        y: Style.spacing.sm
        visible: home.query !== ""
        width: parent.width - Style.spacing.sm * 2
        height: visible ? Math.max(Style.space(60), Math.min(contentHeight, page.height - searchBox.y - searchBox.height - Style.spacing.xl * 2)) : 0
        interactive: contentHeight > height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: home.results
        spacing: Style.spacing.xxs

        delegate: CursorSurface {
          id: resultRow
          required property var modelData
          required property int index
          width: resultList.width
          height: resultColumn.implicitHeight + Style.spacing.md * 2
          radius: Style.cornerRadius
          hasCursor: home.cursorAt === index
          foreground: home.app.foreground
          accent: home.accent

          Text {
            id: resultIcon
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.lg
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(22)
            text: resultRow.modelData.icon || ""
            color: home.accent
            font.family: home.app.fontFamily
            font.pixelSize: Style.font.subtitle
          }
          Column {
            id: resultColumn
            anchors.left: resultIcon.right
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.lg
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.xxs
            Text {
              width: parent.width
              elide: Text.ElideRight
              text: resultRow.modelData.title
              color: home.app.foreground
              font.family: home.app.fontFamily
              font.pixelSize: Style.font.body
              font.bold: resultRow.modelData.kind === "section"
            }
            Text {
              width: parent.width
              elide: Text.ElideRight
              text: resultRow.modelData.path + (resultRow.modelData.detail && resultRow.modelData.kind !== "section" ? "  —  " + resultRow.modelData.detail : "")
              color: Qt.darker(home.app.foreground, 1.6)
              font.family: home.app.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: home.app.jumpTo(resultRow.modelData)
          }
        }
      }
      }

      // ------------------------------------------------------------ groups
      // Masonry: groups are dealt across the columns in order and each column
      // stacks tightly, so a short card never leaves a hole beside a tall one.
      Row {
        id: grid
        visible: home.query === ""
        width: parent.width
        readonly property int columns: width > Style.space(560) ? 3 : 2
        spacing: Style.spacing.lg

        Repeater {
          model: grid.columns

          Column {
            id: gridColumn
            required property int index
            readonly property int column: index
            width: (grid.width - grid.spacing * (grid.columns - 1)) / grid.columns
            spacing: Style.spacing.lg

        Repeater {
          model: home.groups

          Rectangle {
            id: card
            required property var modelData
            required property int index
            visible: index % grid.columns === gridColumn.column
            // Every column instantiates every group and shows only its own,
            // so only the visible copy is registered for scrolling to.
            Component.onCompleted: if (visible) home.cards[index] = card
            onVisibleChanged: if (visible) home.cards[index] = card
            width: gridColumn.width
            height: cardColumn.implicitHeight + Style.spacing.lg * 2
            radius: Math.max(4, Style.cornerRadius)
            color: Qt.rgba(home.app.background.r, home.app.background.g, home.app.background.b, 0.82)
            border.width: 1
            border.color: Qt.rgba(home.app.foreground.r, home.app.foreground.g, home.app.foreground.b, 0.16)
            readonly property color tint: home.palette[index % home.palette.length]

            // Cards rise in one after another each time Home opens.
            property real appear: 1
            opacity: appear
            transform: Translate { y: (1 - card.appear) * Style.space(14) }
            Connections {
              target: home
              function onEntranceChanged() { if (!home.app.motion) return; card.appear = 0; rise.restart() }
            }
            SequentialAnimation {
              id: rise
              PauseAnimation { duration: 60 + card.index * 70 }
              NumberAnimation { target: card; property: "appear"; to: 1; duration: 420; easing.type: Easing.OutCubic }
            }

            Rectangle {
              x: Style.spacing.lg
              y: 0
              width: Style.space(28)
              height: Math.max(2, Style.space(3))
              radius: height / 2
              color: card.tint
            }

            Column {
              id: cardColumn
              x: Style.spacing.lg
              y: Style.spacing.lg
              width: card.width - Style.spacing.lg * 2
              spacing: Style.spacing.xs

              Text {
                text: card.modelData.title.toUpperCase()
                color: Qt.darker(home.app.foreground, 1.3)
                font.family: home.app.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.1
                bottomPadding: Style.spacing.xs
              }

              Repeater {
                model: card.modelData.entries
                CursorSurface {
                  id: tile
                  required property var modelData
                  readonly property int flat: home.tileIndex(modelData.id)
                  width: cardColumn.width
                  height: tileColumn.implicitHeight + Style.spacing.sm * 2
                  radius: Math.max(3, Style.cornerRadius - 2)
                  hasCursor: home.query === "" && home.cursorAt === flat
                  foreground: home.app.foreground
                  accent: home.accent

                  Text {
                    id: tileIcon
                    x: Style.spacing.sm
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(20)
                    text: tile.modelData.icon
                    color: tile.hasCursor ? home.accent : card.tint
                    font.family: home.app.fontFamily
                    font.pixelSize: Style.font.subtitle
                    scale: tile.hasCursor ? 1.18 : 1
                    Behavior on scale { enabled: home.app.motion; NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                  }
                  Column {
                    id: tileColumn
                    anchors.left: tileIcon.right
                    anchors.leftMargin: Style.spacing.xs
                    anchors.right: parent.right
                    anchors.rightMargin: Style.spacing.sm
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                      width: parent.width
                      elide: Text.ElideRight
                      text: tile.modelData.title
                      color: home.app.foreground
                      font.family: home.app.fontFamily
                      font.pixelSize: Style.font.body
                    }
                    Text {
                      width: parent.width
                      elide: Text.ElideRight
                      text: home.summaryFor(tile.modelData.id)
                      color: Qt.darker(home.app.foreground, 1.6)
                      font.family: home.app.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPositionChanged: function(mouse) { if (home.app.pointerGate.moved(tile, mouse)) home.cursorAt = tile.flat }
                    onClicked: home.app.showSectionById(tile.modelData.id)
                  }
                }
              }
            }
          }
        }
          }
        }
      }
    }
  }
}
