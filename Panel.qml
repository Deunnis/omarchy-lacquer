import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "LookSchema.js" as LookSchema
import "AnimSchema.js" as AnimSchema
import "StyleLua.js" as StyleLua
import "ShellSchema.js" as ShellSchema
import "TomlEdit.js" as TomlEdit
import "stores"
import "sections"

// Lacquer — one app for how Omarchy looks.
//
// This file owns the Hyprland half: everything that lands in a single managed
// block in ~/.config/hypr/looknfeel.lua. Theme and background are deliberately
// absent; aether and OmaShuffle own those.
//
// Changes apply live and persist themselves:
//
//   during a drag   `hyprctl eval` only — nothing touches disk
//   on release      debounced write of the block, then `hyprctl reload`
//
// That split is why dragging a slider does not fire dozens of reloads. Undo is
// a stack of whole-state snapshots taken at each commit, which is cheap at
// this size and cannot get out of step with the file the way a stack of
// inverse operations can.
//
// `hyprctl keyword` is not usable — Hyprland rejects it under the Lua parser
// ("keyword can't work with non-legacy parsers, use eval").
Item {
  id: root

  // Domain stores. Each owns its files, processes and state; the panel keeps
  // navigation, undo, status and the UI.
  HyprStore { id: hyprStore; app: root }
  ShellTomlStore { id: tomlStore; app: root }
  ShellJsonStore { id: sjsonStore; app: root }
  ThemeStore { id: themeStore; app: root }
  AetherStore { id: aetherStore; app: root }
  DesktopStore { id: desktopStore; app: root }
  NightStore { id: nightStore; app: root }
  ScreensStore { id: screensStore; app: root }
  MenuLookStore { id: menuLookStore; app: root; Component.onCompleted: rescan() }

  // Sections can appear after load (Menu look, once OmaMenu answers); keep the
  // page the user is on rather than the index it used to have.
  property string currentSectionId: "home"
  onSectionsChanged: {
    for (var i = 0; i < root.sections.length; i++) {
      if (root.sections[i].id !== root.currentSectionId) continue
      if (i !== root.sectionIndex) { root.lastSectionIndex = i; root.sectionIndex = i }
      return
    }
  }
  AppsStore { id: appsStore; app: root }
  readonly property alias hypr: hyprStore
  readonly property alias pointerGate: pointerGateObj

  PointerMoveGate {
    id: pointerGateObj
    referenceItem: card
  }
  readonly property alias toml: tomlStore
  readonly property alias sjson: sjsonStore
  readonly property alias theme: themeStore
  readonly property alias aether: aetherStore
  readonly property alias desktop: desktopStore
  readonly property alias night: nightStore
  readonly property alias screens: screensStore
  readonly property alias menuLook: menuLookStore
  readonly property alias apps: appsStore
  // Lacquer's own service, which owns the shuffle engine (it has to run
  // whether or not this panel has been opened). The host injects it when it
  // summons the panel (shell.qml: `item.service = shell.serviceFor(...)`), so this
  // must stay writable — declaring it readonly made every summon throw and the
  // panel never appeared. The binding is only a fallback until that assignment.
  property var service: root.shell && typeof root.shell.serviceFor === "function"
    ? root.shell.serviceFor((root.manifest && root.manifest.id) || "io.github.deunnis.lacquer") : null
  readonly property var shuffle: root.service ? root.service.shuffle : null

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  property var shell: null

  property var manifest: null

  readonly property string home: Quickshell.env("HOME")

  // 4.0.3 strips __sourceDir from every third-party manifest
  // (shell.qml publicPluginManifest), so the plugin's own directory has to
  // come from the QML file's own URL rather than from the host.
  readonly property string pluginDir: {
    var url = String(Qt.resolvedUrl("."))
    if (url.indexOf("file://") === 0) url = url.substring(7)
    return decodeURIComponent(url).replace(/\/+$/, "")
  }

  property bool opened: false

  property int shellTab: 0

  // ------------------------------------------------------------------ motion
  //
  // One switch for every animation Lacquer itself draws: page transitions,
  // the rail marker, row cascades, Home's live miniature and palette, and the
  // rows' small fades. Saved in ui.json so it holds across restarts. (The
  // curve preview's Play still plays: that is the feature, not decoration.)
  property bool motion: true
  property bool motionLoaded: false
  readonly property string uiStatePath: root.home + "/.local/state/omarchy/io.github.deunnis.lacquer/ui.json"

  function setMotion(on) {
    root.motion = on === true
    uiStateFile.setText(JSON.stringify({ motion: root.motion }, null, 2) + "\n")
    root.statusText = root.motion ? "Animations on" : "Animations off"
  }

  // Written through FileView, read through the bounded reader.
  FileView {
    id: uiStateFile
    path: root.uiStatePath
    preload: false
    printErrors: false
    atomicWrites: true
  }

  Process {
    id: uiStateRead
    command: ["timeout", "-k", "1", "5", root.pluginDir + "/read-state", root.uiStatePath, "4096"]
    running: true
    stdout: StdioCollector { id: uiStateOut; waitForEnd: true }
    onExited: function(code) {
      if (code === 0) {
        try {
          var parsed = JSON.parse(uiStateOut.text)
          if (parsed && typeof parsed.motion === "boolean") root.motion = parsed.motion
        } catch (e) { }
      }
      root.motionLoaded = true
    }
  }

  // Set for a moment after a section or sub-tab change, so the rows created
  // for the new page cascade in while rows scrolled into view later do not.
  property bool cascadeArmed: false
  property int lastSectionIndex: 0
  property int lastSubTab: 0

  Timer {
    id: cascadeWindow
    interval: 450
    onTriggered: root.cascadeArmed = false
  }

  function playTransition(axis, dir) {
    if (!root.motion || !root.opened) return
    root.cascadeArmed = true
    cascadeWindow.restart()
    pageEnter.axis = axis
    pageEnter.dir = dir
    pageEnter.restart()
  }

  onSectionIndexChanged: {
    if (root.sections[root.sectionIndex]) root.currentSectionId = root.sections[root.sectionIndex].id
    var dir = root.sectionIndex > root.lastSectionIndex ? 1 : -1
    root.lastSectionIndex = root.sectionIndex
    root.playTransition("y", dir)
    Qt.callLater(rail.placeMarker)
  }
  onShellTabChanged: {
    var dir = root.shellTab > root.lastSubTab ? 1 : -1
    root.lastSubTab = root.shellTab
    root.playTransition("x", dir)
  }
  onAnimTabChanged: {
    var dir = root.animTab > root.lastSubTab ? 1 : -1
    root.lastSubTab = root.animTab
    root.playTransition("x", dir)
  }

  property string selectedPlugin: ""

  property string backupStamp: ""

  property bool backupsDone: false

  property var undoStack: []

  property var pendingUndo: null

  property int sectionIndex: 0

  property int cursorIndex: 0

  property int animTab: 0

  property string curveName: "easeOutQuint"

  property string errorText: ""

  property string statusText: ""

  property var legacyPresent: []
  // "Not now" on the Omaland banner, for this session.
  property bool legacyDismissed: false

  property bool confirmRemove: false

  property bool confirmResetAll: false
  property bool confirmShuffleMove: false
  property bool confirmGenerate: false

  property color background: Color.menu.background

  property color foreground: Color.menu.text

  property color accent: Color.accent

  property color scrim: Color.menu.scrim

  property string fontFamily: Style.font.menuFamily

  // `group` is the rail heading a section sits under; `pane` is which view
  // renders it. Keyboard Tab order is simply this order.
  readonly property var sections: {
    var out = [
      { id: "home", group: "", pane: "home", icon: "󰋜", title: "Home",
        blurb: "Everything Lacquer can change, and what it is set to now." },
      { id: "theme", group: "Theme", pane: "theme", icon: "", title: "Theme & wallpaper",
        blurb: "Every installed theme and the active theme's wallpapers. A theme retints the whole desktop." },
      { id: "shuffle", group: "Theme", pane: "shuffle", icon: "󰒝", title: "Shuffle",
        blurb: "A new theme on every boot, or light and dark themes that follow sunrise and sunset." },
      { id: "generate", group: "Theme", pane: "generate", icon: "󰏘", title: "Generate",
        blurb: "Build a theme from any wallpaper with aether, or apply one of its saved blueprints." },
      { id: "fonts", group: "Desktop", pane: "desktop", kind: "fonts", icon: "󰛖", title: "Fonts & text",
        blurb: "Text size everywhere, the terminal font and the interface font." },
      { id: "gtk", group: "Desktop", pane: "desktop", kind: "gtk", icon: "󰉼", title: "GTK & icons",
        blurb: "Light or dark apps, the GTK theme and the icon set. A pick here is held through theme switches." },
      { id: "cursor", group: "Desktop", pane: "desktop", kind: "cursor", icon: "󰇀", title: "Cursor",
        blurb: "Pointer theme and size, applied live and kept across restarts." },
      { id: "nightlight", group: "Desktop", pane: "desktop", kind: "night", icon: "󰖔", title: "Nightlight",
        blurb: "A warmer screen now, or every evening on a schedule." }
    ]
    for (var i = 0; i < LookSchema.SECTIONS.length; i++) {
      var look = LookSchema.SECTIONS[i]
      out.push({ id: look.id, group: "Windows", pane: "rows", icon: look.icon, title: look.title,
                 blurb: look.blurb, groups: look.groups })
    }
    out.push({ id: "animations", group: "Windows", pane: "rows", icon: "󱐋", title: "Animations",
               blurb: "Speed, curve and style for every animation Hyprland can play." })
    out.push({ id: "curves", group: "Windows", pane: "curves", icon: "󰓅", title: "Curves",
               blurb: "Named bezier curves. Drag either handle; every leaf using the curve follows." })
    out.push({ id: "shell", group: "Shell", pane: "rows", icon: "󰒓", title: "Shell style",
               blurb: "Type, spacing and chrome for the bar, menus and every panel." })
    out.push({ id: "bar", group: "Shell", pane: "bar", icon: "󰞍", title: "Bar",
               blurb: "Where the bar sits, and which widgets it carries." })
    // Needs OmaMenu with its Menu Look IPC; without it the section is left out.
    if (menuLookStore.available)
    out.push({ id: "menulook", group: "Shell", pane: "desktop", kind: "menu", icon: "󰍜", title: "Menu look",
               blurb: "The Omarchy menu's size, corners, border and transparency, live." })
    out.push({ id: "lock", group: "Screens", pane: "desktop", kind: "lock", icon: "󰌾", title: "Lock & boot",
               blurb: "The lock screen design and timings, and the boot screen, through lock-explorer." })
    out.push({ id: "screensaver", group: "Screens", pane: "desktop", kind: "screensaver", icon: "󱄄", title: "Screensaver",
               blurb: "When the screensaver starts, and the art it and the About screen show." })
    out.push({ id: "terminals", group: "Apps", pane: "desktop", kind: "terminal", icon: "󰆍", title: "Terminals",
               blurb: "Padding, cursor and background opacity for every installed terminal." })
    out.push({ id: "btop", group: "Apps", pane: "desktop", kind: "btop", icon: "󰄨", title: "btop & prompt",
               blurb: "How btop draws, and the starship prompt's spacing. Colours stay with the theme." })
    out.push({ id: "plugins", group: "Apps", pane: "plugins", icon: "󰏖", title: "Plugins",
               blurb: "Settings for every installed plugin, from its own manifest." })
    return out
  }

  // The rail interleaves group headings with sections.
  readonly property var railEntries: {
    var out = []
    var last = ""
    for (var i = 0; i < sections.length; i++) {
      if (sections[i].group !== last && sections[i].group !== "") {
        out.push({ kind: "group", title: sections[i].group })
        last = sections[i].group
      }
      out.push({ kind: "section", index: i })
    }
    return out
  }

  readonly property var section: sections[Math.max(0, Math.min(sections.length - 1, sectionIndex))]

  readonly property bool isTheme: section.id === "theme"
  readonly property bool isShuffle: section.id === "shuffle"
  readonly property bool isGenerate: section.id === "generate"
  readonly property bool isDesktop: section.pane === "desktop"
  readonly property bool isHome: section.pane === "home"

  readonly property bool isAnimations: section.id === "animations"

  readonly property bool isCurves: section.id === "curves"

  readonly property bool isShell: section.id === "shell"

  readonly property bool isBar: section.id === "bar"

  readonly property bool isPlugins: section.id === "plugins"

  readonly property var animTabs: {
    var out = [{ title: "Master" }]
    for (var i = 0; i < AnimSchema.SECTIONS.length; i++) out.push(AnimSchema.SECTIONS[i])
    return out
  }

  // A flat list of { kind } records, so one ListView can render headers,
  // config rows and animation-leaf rows without three parallel views.
  readonly property var rows: {
    var out = []
    if (section.pane !== "rows") return out

    if (isShell) {
      var tab = ShellSchema.TABS[shellTab]
      for (var sg = 0; sg < tab.groups.length; sg++) {
        out.push({ kind: "header", title: tab.groups[sg].title })
        for (var si = 0; si < tab.groups[sg].items.length; si++)
          out.push({ kind: "shell", item: tab.groups[sg].items[si] })
      }
      return out
    }

    if (isAnimations) {
      if (animTab === 0) {
        out.push({ kind: "header", title: LookSchema.ANIMATION_MASTER.title })
        var master = LookSchema.ANIMATION_MASTER.items
        for (var m = 0; m < master.length; m++) out.push({ kind: "item", item: master[m] })
        return out
      }
      var leafGroup = AnimSchema.SECTIONS[animTab - 1]
      out.push({ kind: "header", title: leafGroup.title })
      for (var l = 0; l < leafGroup.leaves.length; l++)
        out.push({ kind: "leaf", leaf: leafGroup.leaves[l] })
      return out
    }

    var groups = section.groups || []
    for (var g = 0; g < groups.length; g++) {
      var visible = []
      for (var i = 0; i < groups[g].items.length; i++) {
        var entry = groups[g].items[i]
        // A `needs` + `needsValue` drops the row entirely, so the Tiling
        // engine group only ever shows the active engine's knobs instead of
        // three greyed-out sets.
        if (entry.needsValue !== undefined) {
          var dep = LookSchema.itemFor(entry.needs)
          if (dep && String(hypr.valueFor(dep)) !== String(entry.needsValue)) continue
        }
        visible.push(entry)
      }
      if (visible.length === 0) continue
      out.push({ kind: "header", title: groups[g].title })
      for (var v = 0; v < visible.length; v++) out.push({ kind: "item", item: visible[v] })
    }
    return out
  }

  readonly property bool sectionModified: {
    if (isCurves) return hypr.curveModified(curveName)
    for (var i = 0; i < rows.length; i++) {
      var entry = rows[i]
      if (entry.kind === "item" && hypr.isModified(entry.item.key)) return true
      if (entry.kind === "leaf" && hypr.leafModified(entry.leaf.name)) return true
      if (entry.kind === "shell" && toml.shellModified(entry.item)) return true
    }
    return false
  }

  readonly property int overrideCount: {
    var n = hypr.opaqueWindows ? 1 : 0
    var k
    for (k in hypr.overrides) n++
    for (k in hypr.leaves) if (!hypr.baseLeaves[k] || !StyleLua.sameLeaf(hypr.leaves[k], hypr.baseLeaves[k])) n++
    for (k in hypr.curves) if (!hypr.curveBaseline(k) || !StyleLua.sameCurve(hypr.curves[k], hypr.curveBaseline(k))) n++
    var known = ShellSchema.allItems()
    for (var i = 0; i < known.length; i++)
      if (toml.shellUser[known[i].id] !== undefined) n++
    return n
  }

  // ------------------------------------------------------------- lifecycle

  // Removes OmaShuffle and lets Lacquer's engine take the shuffle over. Only ever
  // reached through the Shuffle section's two-step confirmation.
  function moveShuffleToLacquer() {
    root.confirmShuffleMove = false
    if (shuffleMoveProc.running) return
    root.errorText = ""
    root.statusText = "Moving the shuffle to Lacquer…"
    shuffleMoveProc.running = true
  }

  // Sections hand keyboard focus back to the panel through this.
  function focusPanel() { keyCatcher.forceActiveFocus() }

  function open(payloadJson) {
    root.opened = true
    root.errorText = ""
    root.confirmRemove = false
    hypr.defaultsFileRef.reload()
    hypr.configFileRef.reload()
    hypr.windowsFileRef.reload()
    toml.shellUserFileRef.reload()
    toml.shellThemeFileRef.reload()
    toml.themeNameFileRef.reload()
    sjson.shellJsonFileRef.reload()
    sjson.scanProcRef.command = ["timeout", "-k", "2", "20", "python3", root.pluginDir + "/scan-plugins.py"]
    sjson.scanProcRef.running = true
    legacyProbe.running = true
    themeStore.rescan()
    pointerGateObj.reset()
    // Never start on a group header, where the first arrow key would do nothing.
    if (!root.rowIsFocusable(root.cursorRow())) { root.cursorIndex = 0; root.moveCursor(1) }
    var target = "home"
    try {
      var payload = JSON.parse(payloadJson || "{}")
      if (payload && typeof payload.section === "string") target = payload.section
    } catch (e) { }
    if (!root.showSectionById(target)) root.showSectionById("home")
    // A pick from the wallpaper picker that Generate opened.
    if (payload && typeof payload.aetherSource === "string" && root.isImagePath(payload.aetherSource))
      aetherStore.setSource(payload.aetherSource)
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    // A pending edit is already live on the compositor, so it has to reach the
    // file rather than evaporate at the next reload.
    if (hypr.persistTimerRef.running) hypr.persistNow()
    toml.clearDraft()
    root.opened = false
    root.confirmRemove = false
    root.confirmResetAll = false
  }

  function dismiss() {
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "lacquer")
    else close()
  }

  function toggle() {
    if (root.opened) { close(); dismiss() }
    else root.open("{}")
  }

  // ------------------------------------------------------------------ undo

  function snapshot() {
    return {
      overrides: StyleLua.cloneOverrides(hypr.overrides),
      leaves: StyleLua.cloneLeafMap(hypr.leaves),
      curves: StyleLua.cloneCurveMap(hypr.curves),
      shell: toml.shellUserText,
      opaque: hypr.opaqueWindows
    }
  }

  function restore(state) {
    hypr.overrides = StyleLua.cloneOverrides(state.overrides)
    hypr.leaves = StyleLua.cloneLeafMap(state.leaves)
    hypr.curves = StyleLua.cloneCurveMap(state.curves)
    if (state.opaque !== undefined) hypr.opaqueWindows = state.opaque === true
    if (state.shell !== undefined) toml.writeShell(state.shell)
  }

  // Captured before the first edit of a gesture, pushed when that gesture
  // commits, so undoing a slider drag goes back to where the drag started
  // rather than to the previous animation frame.
  function beginEdit() {
    if (!root.pendingUndo) root.pendingUndo = snapshot()
  }

  function commitEdit(label) {
    var before = root.pendingUndo || snapshot()
    root.pendingUndo = null
    var next = root.undoStack.slice()
    next.push({ label: label, state: before })
    if (next.length > 50) next.shift()
    root.undoStack = next
    hypr.persistTimerRef.restart()
  }

  function undo() {
    if (root.undoStack.length === 0) return
    var next = root.undoStack.slice()
    var entry = next.pop()
    root.undoStack = next
    restore(entry.state)
    root.pendingUndo = null
    root.statusText = "Undid " + entry.label
    hypr.persistNow()
  }

  function resetSection() {
    if (root.isCurves) { hypr.resetCurve(root.curveName); return }
    if (root.isShell) {
      beginEdit()
      var text = toml.shellUserText
      for (var i = 0; i < root.rows.length; i++)
        if (root.rows[i].kind === "shell")
          text = TomlEdit.unset(text, root.rows[i].item.section, root.rows[i].item.key)
      toml.writeShell(text)
      commitEdit(ShellSchema.TABS[root.shellTab].title)
      return
    }
    if (root.isAnimations && root.animTab > 0) {
      beginEdit()
      var nextLeaves = StyleLua.cloneLeafMap(hypr.leaves)
      var group = AnimSchema.SECTIONS[root.animTab - 1]
      for (var l = 0; l < group.leaves.length; l++) delete nextLeaves[group.leaves[l].name]
      hypr.leaves = nextLeaves
      commitEdit(group.title)
      hypr.persistNow()
      return
    }
    var keys = []
    for (var i = 0; i < root.rows.length; i++)
      if (root.rows[i].kind === "item") keys.push(root.rows[i].item.key)
    hypr.resetKeys(keys, root.section.title)
  }

  function resetAll() {
    beginEdit()
    hypr.overrides = ({})
    hypr.leaves = ({})
    hypr.curves = ({})
    hypr.opaqueWindows = false
    var text = toml.shellUserText
    var all = ShellSchema.allItems()
    for (var i = 0; i < all.length; i++) text = TomlEdit.unset(text, all[i].section, all[i].key)
    toml.writeShell(text)
    commitEdit("everything")
    hypr.persistNow()
  }

  function removeLegacyPlugins() {
    var ids = root.legacyPresent
    if (ids.length === 0) return
    removeProc.command = ["sh", "-c", 'for id in "$@"; do omarchy plugin remove "$id" --yes; done', "lacquer-remove"].concat(ids)
    removeProc.running = true
    root.confirmRemove = false
    hypr.migrationNotice = ""
    root.statusText = "Removing " + ids.join(", ") + "…"
  }

  // ------------------------------------------------------------- keyboard

  function rowIsFocusable(entry) {
    return entry && entry.kind !== "header"
  }

  function moveCursor(delta) {
    pointerGateObj.reset()
    var count = root.rows.length
    if (count === 0) return
    var at = root.cursorIndex
    for (var guard = 0; guard < count; guard++) {
      at = (at + delta + count) % count
      if (rowIsFocusable(root.rows[at])) break
    }
    root.cursorIndex = at
    rowsSection.positionAt(at, ListView.Contain)
  }

  // Sub-tabs were reachable only by mouse, which strands the keyboard in the
  // first tab of a section that has 134 rows behind three others.
  function moveSubTab(delta) {
    pointerGateObj.reset()
    if (isShell) {
      var n = ShellSchema.TABS.length
      root.shellTab = (root.shellTab + delta + n) % n
    } else if (isAnimations) {
      var m = root.animTabs.length
      root.animTab = (root.animTab + delta + m) % m
    } else if (isPlugins) {
      var ids = []
      for (var i = 0; i < sjson.plugins.length; i++)
        if ((sjson.plugins[i].schema || []).length > 0) ids.push(sjson.plugins[i].id)
      if (ids.length === 0) return
      var at = ids.indexOf(root.selectedPlugin)
      root.selectedPlugin = ids[(at + delta + ids.length) % ids.length]
      return
    } else {
      return
    }
    toml.clearDraft()
    root.cursorIndex = 0
    moveCursor(1)
  }

  // Opens a search result from Home: the section, its sub-tab, then the row
  // or choice group, once the section's rows exist.
  function jumpTo(entry) {
    if (!entry || !root.showSectionById(entry.section)) return
    if (entry.shellTab !== undefined) root.shellTab = entry.shellTab
    if (entry.animTab !== undefined) root.animTab = entry.animTab
    Qt.callLater(function() {
      if (entry.group && root.isDesktop) { desktopSection.focusGroupTitle(entry.group); return }
      if (!entry.key && !entry.leaf) return
      for (var i = 0; i < root.rows.length; i++) {
        var r = root.rows[i]
        var hit = (entry.leaf && r.leaf && r.leaf.name === entry.leaf)
          || (entry.key && r.item && (r.item.key === entry.key || r.item.id === entry.key))
        if (!hit) continue
        root.cursorIndex = i
        rowsSection.positionAt(i, ListView.Center)
        return
      }
    })
  }

  // An absolute path to an image, with nothing odd in it. The file itself is
  // only ever handed to aether as a single argument.
  function isImagePath(p) {
    return typeof p === "string" && p.length < 4096 && p.charAt(0) === "/"
      && !/[\u0000-\u001f\u007f]/.test(p) && /\.(png|jpe?g|webp|gif|bmp)$/i.test(p)
  }

  function showSectionById(id) {
    for (var i = 0; i < root.sections.length; i++) {
      if (root.sections[i].id !== id) continue
      if (i !== root.sectionIndex) root.moveSection(i - root.sectionIndex)
      return true
    }
    return false
  }

  function moveSection(delta) {
    pointerGateObj.reset()
    Qt.callLater(function() { rail.ensureVisible(root.sectionIndex) })
    var count = root.sections.length
    root.sectionIndex = (root.sectionIndex + delta + count) % count
    toml.clearDraft()
    root.confirmResetAll = false
    root.confirmGenerate = false
    desktopStore.confirmMono = ""
    nightStore.confirmReplace = false
    root.cursorIndex = 0
    moveCursor(1)
  }

  function cursorRow() {
    if (root.cursorIndex < 0 || root.cursorIndex >= root.rows.length) return null
    return root.rows[root.cursorIndex]
  }

  function nudge(direction) {
    var entry = cursorRow()
    if (!entry) return

    if (entry.kind === "leaf") {
      var value = hypr.leafValue(entry.leaf.name)
      if (!value) { hypr.setLeaf(entry.leaf.name, hypr.inheritedFrom(entry.leaf), true); return }
      if (value.enabled === false) return
      var speed = Math.max(AnimSchema.SPEED_MIN, Number(value.speed) + direction * 0.1)
      hypr.setLeaf(entry.leaf.name, { enabled: true, speed: speed, bezier: value.bezier, style: value.style }, true)
      return
    }

    if (entry.kind === "shell") {
      var spec = entry.item
      if (spec.type === "color") return
      if (spec.type === "bool") {
        toml.setShell(spec, direction > 0, true)
        return
      }
      var raw = toml.shellValue(spec)
      if (raw === undefined) raw = toml.shellDefault(spec)
      var n = Number(raw)
      if (!isFinite(n)) n = spec.min
      var shellStep = spec.step === undefined ? 1 : spec.step
      toml.setShell(spec, Math.max(spec.min, Math.min(spec.max, n + shellStep * direction)), true)
      return
    }

    var item = entry.item
    if (!item || !hypr.isAvailable(item)) return
    var current = hypr.valueFor(item)
    if (item.type === "bool") { hypr.setValue(item, direction > 0, true); return }
    if (item.type === "enum") {
      var options = item.options || []
      if (options.length === 0) return
      var at = 0
      for (var i = 0; i < options.length; i++)
        if (String(options[i].value) === String(current)) at = i
      hypr.setValue(item, options[(at + direction + options.length) % options.length].value, true)
      return
    }
    var step = item.step === undefined ? 1 : item.step
    var min = Math.min(item.min, Number(current))
    var max = Math.max(item.max, Number(current))
    hypr.setValue(item, Math.max(min, Math.min(max, Number(current) + step * direction)), true)
  }

  function activateCursor() {
    var entry = cursorRow()
    if (!entry) return
    if (entry.kind === "leaf") {
      var value = hypr.leafValue(entry.leaf.name)
      if (!value) { hypr.setLeaf(entry.leaf.name, hypr.inheritedFrom(entry.leaf), true); return }
      hypr.setLeaf(entry.leaf.name, { enabled: value.enabled === false, speed: value.speed,
                                 bezier: value.bezier, style: value.style }, true)
      return
    }
    if (entry.kind === "shell") {
      if (entry.item.type !== "bool") return
      var current = toml.shellValue(entry.item)
      if (current === undefined) current = toml.shellDefault(entry.item)
      toml.setShell(entry.item, String(current) !== "true", true)
      return
    }
    var item = entry.item
    if (!item || !hypr.isAvailable(item)) return
    if (item.type === "bool") hypr.setValue(item, hypr.valueFor(item) !== true, true)
    else if (item.type === "enum") nudge(1)
  }

  function resetCursor() {
    var entry = cursorRow()
    if (!entry) return
    if (entry.kind === "leaf") { if (hypr.leafModified(entry.leaf.name)) hypr.resetLeaf(entry.leaf.name); return }
    if (entry.kind === "shell") { if (toml.shellModified(entry.item)) toml.resetShellItem(entry.item); return }
    if (entry.item && hypr.isModified(entry.item.key)) hypr.resetKeys([entry.item.key], entry.item.label)
  }

  function jumpToCurve(name) {
    if (!name) return
    root.curveName = name
    for (var i = 0; i < root.sections.length; i++)
      if (root.sections[i].id === "curves") root.sectionIndex = i
  }

  Process {
    id: legacyProbe
    command: ["sh", "-c",
      'for p in bobbynicholas.omaland; do '
      + '[ -d "$HOME/.config/omarchy/plugins/$p" ] && echo "$p"; done; true']
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var found = []
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++)
          if (lines[i].trim() !== "") found.push(lines[i].trim())
        root.legacyPresent = found
      }
    }
  }

  Process {
    id: removeProc
    onExited: function(code) {
      root.statusText = code === 0 ? "Removed" : ""
      if (code !== 0) root.errorText = "Could not remove the old plugins"
      legacyProbe.running = true
    }
  }

  // A confirm that waits forever is a trap for the next click.
  Timer {
    id: resetAllTimeout
    interval: 4000
    onTriggered: root.confirmResetAll = false
  }

  Timer {
    id: statusClear
    interval: 2200
    running: root.statusText !== "" && root.statusText !== "Saving…"
    onTriggered: root.statusText = ""
  }

  // QML cannot glob, and the host's registry snapshot covers only bar widgets,
  // so the manifests are read off disk instead — the one source that also sees
  // panel, service and overlay plugins.
  // Live apply means a mistake reaches disk, so the first time Lacquer ever
  // loads it snapshots the three files it can write. Once only — a marker in
  // the state dir — so the snapshot is of the state before Lacquer, not of
  // whatever it wrote yesterday.
  Process {
    id: backupProc
    command: ["sh", "-c",
      'state="$HOME/.local/state/omarchy"; marker="$state/lacquer-backups-made"\n'
      + 'mkdir -p "$state" || exit 0\n'
      + '[ -e "$marker" ] && exit 0\n'
      + 'stamp=$(date +%Y%m%d-%H%M%S)\n'
      + 'made=""\n'
      + 'for f in "$HOME/.config/hypr/looknfeel.lua" "$HOME/.config/omarchy/shell.toml" '
      + '"$HOME/.config/omarchy/shell.json"; do\n'
      + '  [ -f "$f" ] || continue\n'
      + '  cp -a "$f" "$f.lacquer-backup-$stamp" 2>/dev/null && made="$made $f"\n'
      + 'done\n'
      + '[ -n "$made" ] && printf %s "$stamp"\n'
      + 'touch "$marker"\n']
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var stamp = String(text || "").trim()
        if (stamp !== "") root.backupStamp = stamp
      }
    }
    onExited: {
      root.backupsDone = true
      if (!hypr.migrationWaiting) return
      hypr.migrationWaiting = false
      hypr.applyMigration()
    }
  }

  // ------------------------------------------------------------------- UI

  PanelWindow {
    id: window
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "lacquer"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Rectangle {
      anchors.fill: parent
      color: root.scrim
      MouseArea { anchors.fill: parent; onClicked: root.dismiss() }
    }

    BorderSurface {
      id: card
      anchors.centerIn: parent
      width: Math.min(Style.space(880), window.width - Style.gapsOut * 4)
      height: Math.min(Style.space(680), window.height - Style.gapsOut * 4)
      radius: Style.cornerRadius
      color: root.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.panelPadding

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.onPressed: function(event) {
          var plain = !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))

          if (event.modifiers & Qt.ControlModifier) {
            if (event.key === Qt.Key_Z) { root.undo(); event.accepted = true }
            else if (event.key === Qt.Key_M) { root.setMotion(!root.motion); event.accepted = true }
            else if (event.key === Qt.Key_I && hypr.legacyBlocks.length > 0 && !root.legacyDismissed) { hypr.importLegacy(); event.accepted = true }
            return
          }

          if (root.isHome) {
            if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
              // fall through to section switching below
            } else if (event.key === Qt.Key_Escape) {
              if (!homeSection.clearQuery()) root.dismiss()
              event.accepted = true; return
            } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Down || event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
              homeSection.moveBy(event.key === Qt.Key_Left ? -1 : event.key === Qt.Key_Right ? 1 : 0,
                                 event.key === Qt.Key_Up ? -1 : event.key === Qt.Key_Down ? 1 : 0)
              event.accepted = true; return
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              homeSection.activate(); event.accepted = true; return
            } else if (event.key === Qt.Key_Backspace) {
              homeSection.backspace(); event.accepted = true; return
            } else if (plain && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
              homeSection.typeText(event.text); event.accepted = true; return
            }
          }

          if (root.isTheme || root.isDesktop) {
            var target = root.isTheme ? themeSection : desktopSection
            var dx = 0, dy = 0
            if (event.key === Qt.Key_Right || (plain && event.key === Qt.Key_L)) dx = 1
            else if (event.key === Qt.Key_Left || (plain && event.key === Qt.Key_H)) dx = -1
            else if (event.key === Qt.Key_Down || (plain && event.key === Qt.Key_J)) dy = 1
            else if (event.key === Qt.Key_Up || (plain && event.key === Qt.Key_K)) dy = -1
            if (dx !== 0 || dy !== 0) { target.moveBy(dx, dy); event.accepted = true; return }
            if (root.isDesktop && (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace)) {
              target.clearPin(); event.accepted = true; return
            }
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
              target.activate(); event.accepted = true; return
            }
          }

          if (root.isGenerate && plain) {
            if (event.key === Qt.Key_Escape && root.confirmGenerate) { root.confirmGenerate = false; event.accepted = true; return }
            if (event.key === Qt.Key_L) { aetherStore.setLight(!aetherStore.light); event.accepted = true; return }
            if (event.key === Qt.Key_O) { aetherStore.openAether(); event.accepted = true; return }
            if (event.key === Qt.Key_W) { aetherStore.pick("wallpapers"); event.accepted = true; return }
            if (event.key === Qt.Key_F) { aetherStore.pick("file"); event.accepted = true; return }
            if (event.key === Qt.Key_G) {
              if (root.confirmGenerate) { root.confirmGenerate = false; aetherStore.generate() }
              else if (!aetherStore.generating && aetherStore.source !== "") root.confirmGenerate = true
              event.accepted = true; return
            }
          }

          if (event.key === Qt.Key_Escape) { root.dismiss(); event.accepted = true }
          else if (event.key === Qt.Key_Down || (plain && event.key === Qt.Key_J)) {
            root.moveCursor(1); event.accepted = true
          }
          else if (event.key === Qt.Key_Up || (plain && event.key === Qt.Key_K)) {
            root.moveCursor(-1); event.accepted = true
          }
          else if (event.key === Qt.Key_Right || (plain && event.key === Qt.Key_L)) {
            root.nudge(1); event.accepted = true
          }
          else if (event.key === Qt.Key_Left || (plain && event.key === Qt.Key_H)) {
            root.nudge(-1); event.accepted = true
          }
          else if (plain && event.key === Qt.Key_BracketLeft) {
            root.moveSubTab(-1); event.accepted = true
          }
          else if (plain && event.key === Qt.Key_BracketRight) {
            root.moveSubTab(1); event.accepted = true
          }
          else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            var back = event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier)
            root.moveSection(back ? -1 : 1)
            event.accepted = true
          }
          else if (plain && event.key === Qt.Key_P && root.isCurves) {
            curvesSection.play(); event.accepted = true
          }
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                   || event.key === Qt.Key_Space) { root.activateCursor(); event.accepted = true }
          else if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) {
            root.resetCursor(); event.accepted = true
          }
        }
      }

      ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.spacing.panelGap

        // ------------------------------------------------------ header

        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: Math.max(titleBlock.implicitHeight, headerActions.implicitHeight)

          Column {
            id: titleBlock
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.xxs

            Text {
              text: "Lacquer"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
            }

            Text {
              text: root.isTheme ? "omarchy theme set"
                : root.isShuffle ? "~/.local/state/omarchy/io.github.deunnis.lacquer/shuffle.json"
                : root.isGenerate ? "aether"
                : root.isHome ? "every look-and-feel setting, in one place"
                : root.section.id === "fonts" ? "omarchy font · omarchy display text size · gsettings"
                : root.section.id === "gtk" ? "gsettings · pins.json · hooks/theme-set.d"
                : root.section.id === "cursor" ? "hyprctl setcursor · gsettings · hypr/autostart.lua"
                : root.section.id === "nightlight" ? "hypr/hyprsunset.conf · hypr/autostart.lua"
                : root.section.id === "lock" ? "omarchy-shell lock · shell.json idle"
                : root.section.id === "menulook" ? "omarchy-shell omamenu · io.github.omamenu/style.json"
                : root.section.id === "terminals" ? "foot.ini · alacritty.toml · kitty.conf · ghostty/config"
                : root.section.id === "btop" ? "btop/btop.conf · starship.toml"
                : root.section.id === "screensaver" ? "shell.json idle · omarchy/branding"
                : root.isShell ? "~/.config/omarchy/shell.toml"
                : (root.isBar || root.isPlugins) ? "~/.config/omarchy/shell.json"
                : "~/.config/hypr/looknfeel.lua"
              color: Qt.darker(root.foreground, 1.6)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Row {
            id: headerActions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.lg

            Text {
              text: root.overrideCount === 0
                ? "Following Omarchy defaults"
                : root.overrideCount + (root.overrideCount === 1 ? " override" : " overrides")
              color: root.overrideCount === 0 ? Qt.darker(root.foreground, 1.6) : root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
            }

            Button {
              text: root.motion ? "Motion" : "Still"
              iconText: "󱐋"
              tooltipText: (root.motion ? "App animations are on" : "App animations are off") + "  ·  Ctrl+M"
              bordered: true
              selected: root.motion
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              anchors.verticalCenter: parent.verticalCenter
              onClicked: root.setMotion(!root.motion)
            }

            Button {
              text: "Undo"
              iconText: "󰕌"
              enabled: root.undoStack.length > 0
              opacity: enabled ? 1 : 0.4
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              anchors.verticalCenter: parent.verticalCenter
              onClicked: root.undo()
            }

            Button {
              text: root.confirmResetAll ? "Reset everything?" : "Reset all"
              enabled: root.overrideCount > 0
              opacity: enabled ? 1 : 0.4
              bordered: true
              selected: root.confirmResetAll
              foreground: root.confirmResetAll ? Color.urgent : root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              anchors.verticalCenter: parent.verticalCenter
              onClicked: {
                if (root.confirmResetAll) {
                  root.confirmResetAll = false
                  root.resetAll()
                } else {
                  root.confirmResetAll = true
                  resetAllTimeout.restart()
                }
              }
            }

            PanelActionButton {
              iconText: "󰅖"
              tooltipText: "Close  ·  Esc"
              foreground: root.foreground
              anchors.verticalCenter: parent.verticalCenter
              onClicked: root.dismiss()
            }
          }
        }

        // ------------------------------------------- migration banner

        BorderSurface {
          Layout.fillWidth: true
          readonly property bool showing: !root.legacyDismissed && (hypr.legacyBlocks.length > 0 || root.legacyPresent.length > 0)
          Layout.preferredHeight: showing ? migrationRow.implicitHeight + Style.spacing.xxl : 0
          visible: showing
          radius: Style.cornerRadius
          color: Style.selectedFillFor(root.accent, root.accent)
          borderSpec: Border.controlSpec("normal", root.accent, root.accent)

          Row {
            id: migrationRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Style.spacing.lg
            anchors.rightMargin: Style.spacing.lg
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.lg

            Text {
              width: parent.width - keepButton.width - Style.spacing.lg
                - (importButton.visible ? importButton.width + Style.spacing.lg : 0)
                - (removeButton.visible ? removeButton.width + Style.spacing.lg : 0)
              text: {
                var names = root.legacyPresent.join(" and ")
                if (root.confirmRemove) return "Uninstall " + names + "? Its settings stay in looknfeel.lua unless you imported them."
                if (hypr.legacyBlocks.length > 0)
                  return "Omaland settings found in looknfeel.lua. Import them to edit them here; nothing changes until you do."
                if (hypr.migrationNotice !== "") return hypr.migrationNotice
                  + (names ? " " + names + " is still installed and rewrites its block when opened." : "")
                return names + " is installed too. Both write to looknfeel.lua, so opening it can undo changes made here."
              }
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              anchors.verticalCenter: parent.verticalCenter
            }

            Button {
              id: importButton
              visible: hypr.legacyBlocks.length > 0 && !root.confirmRemove
              text: "Import settings"
              tooltipText: "Ctrl+I"
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              anchors.verticalCenter: parent.verticalCenter
              onClicked: hypr.importLegacy()
            }

            Button {
              id: removeButton
              visible: root.legacyPresent.length > 0
              text: root.confirmRemove ? "Yes, uninstall" : "Uninstall Omaland"
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              anchors.verticalCenter: parent.verticalCenter
              onClicked: {
                if (root.confirmRemove) root.removeLegacyPlugins()
                else root.confirmRemove = true
              }
            }

            Button {
              id: keepButton
              text: root.confirmRemove ? "Cancel" : "Not now"
              bordered: true
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              anchors.verticalCenter: parent.verticalCenter
              onClicked: {
                if (root.confirmRemove) root.confirmRemove = false
                else root.legacyDismissed = true
              }
            }
          }
        }

        PanelSeparator { foreground: root.foreground; Layout.fillWidth: true }

        // ------------------------------------------------------ body

        RowLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: Style.spacing.panelGap

          // Grouped and scrollable: the section list outgrows the card height.
          Flickable {
            id: rail
            Layout.preferredWidth: Style.space(170)
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: railColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            // A short accent bar that slides to the selected entry and
            // stretches on the way, like a drop of ink.
            function placeMarker() {
              for (var i = 0; i < railRepeater.count; i++) {
                var item = railRepeater.itemAt(i)
                if (!item || item.sectionIndex !== root.sectionIndex) continue
                var targetY = item.y + item.height * 0.2
                var targetH = item.height * 0.6
                if (!root.motion || railMarker.height === 0) {
                  markerMove.stop()
                  railMarker.y = targetY
                  railMarker.height = targetH
                  return
                }
                markerMove.targetY = targetY
                markerMove.targetH = targetH
                markerMove.restart()
                return
              }
            }

            Rectangle {
              id: railMarker
              z: 2
              x: 0
              width: Math.max(2, Style.space(3))
              height: 0
              radius: width / 2
              color: root.accent

              ParallelAnimation {
                id: markerMove
                property real targetY: 0
                property real targetH: 0
                NumberAnimation { target: railMarker; property: "y"; to: markerMove.targetY; duration: 420; easing.type: Easing.OutQuint }
                SequentialAnimation {
                  NumberAnimation { target: railMarker; property: "height"; to: markerMove.targetH * 2.2; duration: 140; easing.type: Easing.OutQuad }
                  NumberAnimation { target: railMarker; property: "height"; to: markerMove.targetH; duration: 360; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                }
              }
            }

            Connections {
              target: railColumn
              function onImplicitHeightChanged() { Qt.callLater(rail.placeMarker) }
            }

            // A panel that was just created has no height yet; scrolling
            // then would push the selected entry off the top.
            onHeightChanged: if (height > 0) { ensureVisible(root.sectionIndex); placeMarker() }

            function ensureVisible(sectionIndex) {
              if (rail.height <= 0) return
              for (var i = 0; i < railRepeater.count; i++) {
                var item = railRepeater.itemAt(i)
                if (!item || item.sectionIndex !== sectionIndex) continue
                if (item.y < rail.contentY) rail.contentY = item.y
                else if (item.y + item.height > rail.contentY + rail.height)
                  rail.contentY = item.y + item.height - rail.height
                return
              }
            }

            Column {
              id: railColumn
              width: rail.width
              spacing: Style.spacing.xs

              Repeater {
                id: railRepeater
                model: root.railEntries

                Item {
                  id: railEntry
                  required property var modelData
                  readonly property int sectionIndex: modelData.kind === "section" ? modelData.index : -1
                  width: railColumn.width
                  height: modelData.kind === "group" ? groupLabel.implicitHeight + Style.spacing.md
                                                     : railButton.implicitHeight

                  PanelSectionHeader {
                    id: groupLabel
                    visible: railEntry.modelData.kind === "group"
                    anchors.left: parent.left
                    anchors.leftMargin: Style.spacing.sm
                    anchors.bottom: parent.bottom
                    text: railEntry.modelData.kind === "group" ? railEntry.modelData.title : ""
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                  }

                  Button {
                    id: railButton
                    visible: railEntry.modelData.kind === "section"
                    width: parent.width
                    text: visible ? root.sections[railEntry.sectionIndex].title : ""
                    iconText: visible ? root.sections[railEntry.sectionIndex].icon : ""
                    leftAlign: true
                    selected: root.sectionIndex === railEntry.sectionIndex
                    foreground: root.foreground
                    accent: root.accent
                    fontFamily: root.fontFamily
                    onClicked: {
                      if (railEntry.sectionIndex !== root.sectionIndex) root.moveSection(railEntry.sectionIndex - root.sectionIndex)
                    }
                  }
                }
              }
            }
          }

          Rectangle {
            Layout.preferredWidth: 1
            Layout.fillHeight: true
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
          }

          ColumnLayout {
            id: pageContent
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Style.spacing.sm

            // Page transition: sections glide in along the rail's direction,
            // sub-tabs from the side, with a fade and a small settle.
            transform: [
              Translate { id: pageShift },
              Scale { id: pageScale; origin.x: pageContent.width / 2; origin.y: Style.space(40) }
            ]

            ParallelAnimation {
              id: pageEnter
              property string axis: "y"
              property int dir: 1
              NumberAnimation { target: pageShift; property: pageEnter.axis; from: pageEnter.dir * Style.space(pageEnter.axis === "y" ? 26 : 34); to: 0; duration: 380; easing.type: Easing.OutQuint }
              NumberAnimation { target: pageContent; property: "opacity"; from: 0; to: 1; duration: 240; easing.type: Easing.OutCubic }
              NumberAnimation { target: pageScale; property: "xScale"; from: 0.985; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
              NumberAnimation { target: pageScale; property: "yScale"; from: 0.985; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
              onStopped: { pageShift.x = 0; pageShift.y = 0; pageContent.opacity = 1; pageScale.xScale = 1; pageScale.yScale = 1 }
            }

            Item {
              Layout.fillWidth: true
              Layout.preferredHeight: sectionBlurb.implicitHeight + Style.spacing.md
              visible: !root.isHome

              Text {
                id: sectionBlurb
                anchors.left: parent.left
                anchors.right: sectionReset.left
                anchors.rightMargin: Style.spacing.lg
                anchors.verticalCenter: parent.verticalCenter
                text: root.isShell ? ShellSchema.TABS[root.shellTab].blurb : root.section.blurb
                color: Qt.darker(root.foreground, 1.55)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }

              PanelActionButton {
                id: sectionReset
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰕌"
                tooltipText: root.isCurves ? "Reset this curve" : "Reset this section"
                foreground: root.foreground
                visible: root.sectionModified && root.section.pane !== "bar" && root.section.pane !== "plugins" && root.section.pane !== "theme" && root.section.pane !== "shuffle" && root.section.pane !== "generate" && root.section.pane !== "desktop"
                onClicked: root.resetSection()
              }
            }

            // Sub-tabs, so 35 animation leaves or 134 shell tokens do not
            // become one scroll.
            ButtonGroup {
              Layout.fillWidth: true
              visible: root.isAnimations || root.isShell
              options: {
                var out = []
                if (root.isShell) {
                  for (var t = 0; t < ShellSchema.TABS.length; t++) out.push(ShellSchema.TABS[t].title)
                  return out
                }
                for (var i = 0; i < root.animTabs.length; i++) out.push(root.animTabs[i].title)
                return out
              }
              value: root.isShell ? ShellSchema.TABS[root.shellTab].title
                                  : root.animTabs[root.animTab].title
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              focusable: false
              onChanged: function(v) {
                if (root.isShell) {
                  for (var t = 0; t < ShellSchema.TABS.length; t++)
                    if (ShellSchema.TABS[t].title === v) root.shellTab = t
                } else {
                  for (var i = 0; i < root.animTabs.length; i++)
                    if (root.animTabs[i].title === v) root.animTab = i
                }
                root.cursorIndex = 0
                root.moveCursor(1)
              }
            }

            PanelSeparator { foreground: root.foreground; Layout.fillWidth: true }

            // ------------------------------------------------ rows

            RowsSection {
              id: rowsSection
              app: root
              visible: root.section.pane === "rows"
              Layout.fillWidth: true
              Layout.fillHeight: true
            }

            HomeSection {
              id: homeSection
              app: root
              visible: root.section.pane === "home"
              Layout.fillWidth: true
              Layout.fillHeight: true
            }

            DesktopSection {
              id: desktopSection
              app: root
              kind: root.section.kind || "fonts"
              visible: root.section.pane === "desktop"
              Layout.fillWidth: true
              Layout.fillHeight: true
            }
            GenerateSection {
              app: root
              visible: root.section.pane === "generate"
              Layout.fillWidth: true
              Layout.fillHeight: true
            }

            ShuffleSection {
              app: root
              visible: root.section.pane === "shuffle"
              Layout.fillWidth: true
              Layout.fillHeight: true
            }

            ThemeSection {
              id: themeSection
              app: root
              visible: root.section.pane === "theme"
              Layout.fillWidth: true
              Layout.fillHeight: true
            }

            BarSection {
              app: root
              visible: root.section.pane === "bar"
              Layout.fillWidth: true
              Layout.fillHeight: true
            }

            // ------------------------------------------------ plugins

            PluginsSection {
              app: root
              visible: root.section.pane === "plugins"
              Layout.fillWidth: true
              Layout.fillHeight: true
            }

            // ------------------------------------------------ curves

            CurvesSection {
              id: curvesSection
              app: root
              visible: root.section.pane === "curves"
              Layout.fillWidth: true
              Layout.fillHeight: true
            }
          }
        }

        PanelSeparator { foreground: root.foreground; Layout.fillWidth: true }

        // ------------------------------------------------------ footer

        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: footerText.implicitHeight + Style.spacing.md

          Text {
            id: footerText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: {
              if (root.errorText !== "") return root.errorText
              if (root.statusText !== "") return root.statusText
              if (root.backupStamp !== "")
                return "Backed up looknfeel.lua, shell.toml and shell.json as *.lacquer-backup-"
                  + root.backupStamp
              if (root.isHome) return homeSection.query !== ""
                ? "↑↓ choose · Enter open · Backspace edit · Esc clear"
                : "type to search · ←→ group · ↑↓ section · Enter open · Tab next section · Esc close"
              if (root.isGenerate) return (root.confirmGenerate ? "g again to generate and apply · Esc cancel" : "w pick wallpaper · f any image · l light/dark · g generate (asks first) · o open aether · Esc close")
              if (root.isShuffle) return "the shuffle keeps running with Lacquer closed · Tab section · Esc close"
              if (root.section.id === "lock" || root.section.id === "screensaver" || root.section.id === "menulook" || root.section.id === "terminals" || root.section.id === "btop") return "↑↓ group · ←→ choose or step · Enter pick · Tab section · Esc close"
              if (root.section.id === "nightlight") return "↑↓ group · ←→ choose or step · Enter pick · Tab section · Esc close"
              if (root.isDesktop) return "↑↓ group · ←→ choose or step a size · Enter pick · Del follow theme / default · Tab section · Esc close"
              if (root.isTheme) return "←→↑↓ hjkl choose · Enter apply · click a wallpaper to set it · Tab section · Esc close"
              if (root.isBar) return "◀ ▶ section · ▲ ▼ order · ✕ off the bar · Tab section · Esc close"
              if (root.isPlugins) return "[ ] pick a plugin, then edit its settings with the mouse · Tab section · Esc close"
              var hint = root.isCurves
                ? "drag a handle · P play · Tab section"
                : "↑↓ kj row · ←→ hl adjust · Space toggle · Backspace reset · Tab section"
                  + ((root.isShell || root.isAnimations) ? " · [ ] sub-tab" : "")
              return hint + " · Ctrl+Z undo · Esc close   —   colors stay with your theme"
            }
            color: root.errorText !== "" ? Color.urgent : Qt.darker(root.foreground, 1.6)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            maximumLineCount: 2
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }

  Component.onCompleted: backupProc.running = true

  // OmaShuffle's service builds its launcher-entry path from manifest.__sourceDir,
  // which Omarchy 4.0.3 strips from third-party manifests, so its removal can
  // orphan the entry (exactly what happened with Omaland). Only a file carrying
  // OmaShuffle's own marker, with the plugin really gone, is deleted.
  Process {
    id: shuffleMoveProc
    command: ["sh", "-c",
      'mkdir -p "$HOME/.local/state/omarchy/io.github.deunnis.lacquer" && touch "$HOME/.local/state/omarchy/io.github.deunnis.lacquer/adopt-omashuffle"\n'
      + 'omarchy plugin remove io.github.omashuffle --yes >/dev/null 2>&1 || { rm -f "$HOME/.local/state/omarchy/io.github.deunnis.lacquer/adopt-omashuffle"; exit 1; }\n'
      + 'f="$HOME/.local/share/applications/omashuffle.desktop"\n'
      + 'if [ -f "$f" ] && grep -q "^X-OmaShuffle-Managed=true$" "$f" '
      + '&& [ ! -d "$HOME/.config/omarchy/plugins/io.github.omashuffle" ]; then rm -f "$f"; fi\n']
    onExited: function(code) {
      if (code !== 0) {
        root.statusText = ""
        root.errorText = "Could not remove OmaShuffle — the shuffle is still running there"
        return
      }
      root.statusText = "The shuffle now runs in Lacquer"
      if (root.shuffle) root.shuffle.wake()
    }
  }

  IpcHandler {
    target: "lacquer"
    function open(): void { root.open("{}") }
    function close(): void { root.close(); root.dismiss() }
    function toggle(): void { root.toggle() }
    function applyTheme(slug: string): void { themeStore.apply(slug) }
    // Only a wallpaper Lacquer itself lists for the active theme.
    function setWallpaper(path: string): void {
      var list = themeStore.wallpapers || []
      for (var i = 0; i < list.length; i++)
        if (list[i].path === path) { themeStore.setWallpaper(path); return }
    }
    function currentTheme(): string { return themeStore.current }
    function showSection(id: string): bool { return root.showSectionById(id) }
    function shuffleStatus(): string {
      var e = root.shuffle
      if (!e) return JSON.stringify({ engine: null })
      return JSON.stringify({ dormant: e.dormant, active: e.active, stateLoaded: e.stateLoaded,
                              bootEnabled: e.st.enabled, dayNight: e.st.schedule.enabled,
                              pool: (e.st.pool || []).length, themes: e.themes.length,
                              lastBootId: e.st.lastBootId, currentBootId: e.currentBootId })
    }
  }
}
