import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "../LookSchema.js" as LookSchema
import "../AnimSchema.js" as AnimSchema
import "../StyleLua.js" as StyleLua
import "../ShellSchema.js" as ShellSchema
import "../TomlEdit.js" as TomlEdit

// Everything Lacquer writes into Hyprland's own config: the managed blocks in
// ~/.config/hypr/looknfeel.lua and hyprland.lua, live preview through
// `hyprctl eval`, debounced persistence, and the opt-in import from Omaland.
Item {
  id: root
  visible: false

  // The panel that owns this store; everything outside the store goes through it.
  required property var app

  readonly property alias configFileRef: configFile
  readonly property alias defaultsFileRef: defaultsFile
  readonly property alias persistTimerRef: persistTimer
  readonly property alias windowsFileRef: windowsFile

  readonly property string configPath: app.home + "/.config/hypr/looknfeel.lua"

  // Omarchy tags every window with opacity "0.985 0.96" in
  // default/hypr/windows.lua, which multiplies with the decoration:*_opacity
  // globals and stops those sliders reaching 1.0. Cancelling it means a window
  // rule, and window rules belong in hyprland.lua — a second file, so a second
  // managed block.
  readonly property string windowsPath: app.home + "/.config/hypr/hyprland.lua"

  // Omarchy's shipped values — the reference every pip and reset measures against.
  property var baseOverrides: ({})

  property var baseLeaves: ({})

  property var baseCurves: ({})

  // What Hyprland reports right now, for keys we have not overridden.
  property var effective: ({})

  // What Lacquer's block says.
  property var overrides: ({})

  property var leaves: ({})

  property var curves: ({})

  property bool migrationWaiting: false

  property string migrationNotice: ""

  property bool previewPending: false

  property bool selfWrite: false

  property bool baselineReady: false

  property bool blockRead: false

  property bool opaqueWindows: false

  property int pendingSaves: 0

  readonly property var hyprDefaultCurve: [0, 0.75, 0.15, 1]

  readonly property var curveNames: {
    var names = { "default": true }
    var k
    for (k in baseCurves) names[k] = true
    for (k in curves) names[k] = true
    return Object.keys(names).sort()
  }

  // ---------------------------------------------------------------- values

  function curveBaseline(name) {
    if (name === "default") return root.hyprDefaultCurve
    return root.baseCurves[name] || null
  }

  function valueFor(item) {
    if (item.key === StyleLua.OPAQUE_WINDOWS_KEY) return root.opaqueWindows
    if (root.overrides[item.key] !== undefined) return root.overrides[item.key]
    if (root.effective[item.key] !== undefined) return root.effective[item.key]
    if (item.fallback !== undefined) return item.fallback
    if (item.type === "bool") return false
    // An enum must never fall back to a number — it would be written out as an
    // option name that does not exist.
    if (item.type === "enum") return (item.options && item.options.length > 0) ? item.options[0].value : ""
    return 0
  }

  function isModified(key) {
    if (key === StyleLua.OPAQUE_WINDOWS_KEY) return root.opaqueWindows === true
    return root.overrides[key] !== undefined
  }

  function isAvailable(item) {
    if (!item.needs || item.needsValue !== undefined) return true
    var dep = LookSchema.itemFor(item.needs)
    return dep ? valueFor(dep) === true : true
  }

  function leafValue(name) {
    if (root.leaves[name]) return root.leaves[name]
    if (root.baseLeaves[name]) return root.baseLeaves[name]
    return null
  }

  function leafModified(name) {
    if (!root.leaves[name]) return false
    if (!root.baseLeaves[name]) return true
    return !StyleLua.sameLeaf(root.leaves[name], root.baseLeaves[name])
  }

  function leafInherited(name) {
    return !root.leaves[name] && !root.baseLeaves[name]
  }

  function curveValue(name) {
    if (root.curves[name]) return root.curves[name]
    var base = curveBaseline(name)
    return base ? base : [0.25, 0.1, 0.25, 1]
  }

  function curveModified(name) {
    if (!root.curves[name]) return false
    var base = curveBaseline(name)
    if (!base) return true
    return !StyleLua.sameCurve(root.curves[name], base)
  }

  // Walk up the animation tree for something concrete to start from, so
  // overriding an inherited leaf lands on the values that were in effect.
  function inheritedFrom(spec) {
    var at = spec
    var guard = 0
    while (at && guard++ < 8) {
      var value = root.leaves[at.name] || root.baseLeaves[at.name]
      if (value) return StyleLua.cloneLeaf(value)
      at = at.parent ? AnimSchema.leafFor(at.parent) : null
    }
    return StyleLua.emptyLeaf()
  }

  // ---------------------------------------------------------------- edits

  function setValue(item, value, commit) {
    app.beginEdit()
    if (item.key === StyleLua.OPAQUE_WINDOWS_KEY) {
      root.opaqueWindows = value === true
      // A window rule cannot be evaluated into place; it only exists once the
      // file is written and reloaded.
      if (commit) { app.commitEdit(item.label); persistNow() }
      return
    }
    var next = StyleLua.cloneOverrides(root.overrides)
    next[item.key] = LookSchema.quantize(item, value)
    root.overrides = next
    livePreview()
    if (commit) app.commitEdit(item.label)
  }

  function resetKeys(keys, label) {
    app.beginEdit()
    var next = StyleLua.cloneOverrides(root.overrides)
    for (var i = 0; i < keys.length; i++) {
      if (keys[i] === StyleLua.OPAQUE_WINDOWS_KEY) root.opaqueWindows = false
      delete next[keys[i]]
    }
    root.overrides = next
    app.commitEdit(label)
    // Dropping a key cannot be previewed — Hyprland has no "unset this" — so
    // the only route back to a default is to write the file and reload it.
    persistNow()
  }

  function setLeaf(name, value, commit) {
    app.beginEdit()
    var next = StyleLua.cloneLeafMap(root.leaves)
    next[name] = StyleLua.cloneLeaf(value)
    root.leaves = next
    livePreview()
    if (commit) app.commitEdit(name)
  }

  function resetLeaf(name) {
    app.beginEdit()
    var next = StyleLua.cloneLeafMap(root.leaves)
    delete next[name]
    root.leaves = next
    app.commitEdit(name)
    livePreview()
  }

  function setCurve(name, points, commit) {
    app.beginEdit()
    var next = StyleLua.cloneCurveMap(root.curves)
    next[name] = StyleLua.cloneCurve(points)
    root.curves = next
    livePreview()
    if (commit) app.commitEdit(name + " curve")
  }

  function resetCurve(name) {
    app.beginEdit()
    var next = StyleLua.cloneCurveMap(root.curves)
    delete next[name]
    root.curves = next
    app.commitEdit(name + " curve")
    livePreview()
  }

  // --------------------------------------------------------------- writing

  function livePreview() {
    if (!root.baselineReady) return
    var body = StyleLua.renderPreviewBody(root.overrides, root.curves, root.leaves,
                                          root.baseCurves, root.baseLeaves)
    if (!body) return
    // One eval in flight at a time with the newest state queued behind it, so
    // a slider drag cannot outrun hyprctl.
    if (evalProc.running) { root.previewPending = true; return }
    evalProc.command = ["timeout", "-k", "1", "5", "hyprctl", "eval", body]
    evalProc.running = true
  }

  function persistNow() {
    persistTimer.stop()
    if (!root.baselineReady || !root.blockRead) return

    var current = configFile.text()
    var body = StyleLua.renderLooknfeelBody(root.overrides, root.curves, root.leaves,
                                            root.baseCurves, root.baseLeaves)
    var next = StyleLua.applyBlock(current, body)

    var windowsCurrent = windowsFile.text()
    if (windowsReader.failed) {
      // Leave a block we could not read strictly alone.
      var configOnly = next !== current
      if (!configOnly) return
      root.pendingSaves = 1
      app.statusText = "Saving…"
      root.selfWrite = true
      configFile.setText(next)
      return
    }
    var synthetic = {}
    synthetic[StyleLua.OPAQUE_WINDOWS_KEY] = root.opaqueWindows
    var windowsNext = StyleLua.applyBlock(windowsCurrent, StyleLua.renderWindowsBody(synthetic))

    var writeConfig = next !== current
    var writeWindows = windowsNext !== windowsCurrent
    if (!writeConfig && !writeWindows) return

    // Reload only once both files have landed, so Hyprland never reads a
    // half-written pair.
    root.pendingSaves = (writeConfig ? 1 : 0) + (writeWindows ? 1 : 0)
    app.statusText = "Saving…"
    root.selfWrite = true
    if (writeConfig) configFile.setText(next)
    if (writeWindows) windowsFile.setText(windowsNext)
  }

  function noteSaved() {
    root.pendingSaves = Math.max(0, root.pendingSaves - 1)
    if (root.pendingSaves > 0) return
    root.selfWrite = false
    reloadProc.running = true
  }

  // ------------------------------------------------------------- migration

  // Omaland's block, found in looknfeel.lua. Nothing is imported until the user
  // asks (importLegacy), and nothing is ever uninstalled from here.
  property var legacyBlocks: []

  function detectLegacy(text) {
    var found = []
    for (var i = 0; i < StyleLua.LEGACY_FENCES.length; i++) {
      var fence = StyleLua.LEGACY_FENCES[i]
      var split = StyleLua.splitFences(text, fence.begin, fence.end)
      if (split.found && split.body.replace(/\s/g, "") !== "") found.push(fence.name)
    }
    root.legacyBlocks = found
  }

  function importLegacy() {
    if (root.legacyBlocks.length === 0 || !root.blockRead) return
    migrate(configFile.text())
  }

  // Adopts the legacy blocks into Lacquer's own on top of what Lacquer already
  // holds, then drops their fences.
  function migrate(text) {
    var pending = []
    for (var i = 0; i < StyleLua.LEGACY_FENCES.length; i++) {
      var fence = StyleLua.LEGACY_FENCES[i]
      var split = StyleLua.splitFences(text, fence.begin, fence.end)
      if (split.found && split.body.replace(/\s/g, "") !== "") pending.push(fence)
    }
    if (pending.length === 0) return false

    migrationQueue = pending
    migrationIndex = 0
    migrationText = text
    migrationOverrides = StyleLua.cloneOverrides(root.overrides)
    migrationLeaves = StyleLua.cloneLeafMap(root.leaves)
    migrationCurves = StyleLua.cloneCurveMap(root.curves)
    migrationNames = []
    readNextLegacy()
    return true
  }

  property var migrationQueue: []

  property int migrationIndex: 0

  property string migrationText: ""

  property var migrationOverrides: ({})

  property var migrationLeaves: ({})

  property var migrationCurves: ({})

  property var migrationNames: []

  function readNextLegacy() {
    if (migrationIndex >= migrationQueue.length) { finishMigration(); return }
    var fence = migrationQueue[migrationIndex]
    var split = StyleLua.splitFences(migrationText, fence.begin, fence.end)
    legacyReader.command = ["timeout", "-k", "2", "10", "lua", app.pluginDir + "/read.lua", "-e", split.body]
    legacyReader.running = true
  }

  function absorbLegacy(out) {
    var parsed = StyleLua.parseHarness(out)
    var k
    for (k in parsed.overrides) migrationOverrides[k] = parsed.overrides[k]
    for (k in parsed.leaves) migrationLeaves[k] = parsed.leaves[k]
    for (k in parsed.curves) migrationCurves[k] = parsed.curves[k]
    if (parsed.opaque) root.opaqueWindows = true
    migrationNames.push(migrationQueue[migrationIndex].name)
    migrationIndex++
    readNextLegacy()
  }

  function finishMigration() {
    if (!app.backupsDone) { root.migrationWaiting = true; return }
    applyMigration()
  }

  // A legacy block in hyprland.lua is only ever the blanket-opacity rule.
  function migrateWindowsFile() {
    var text = windowsFile.text()
    var found = false
    for (var i = 0; i < StyleLua.LEGACY_FENCES.length; i++) {
      var fence = StyleLua.LEGACY_FENCES[i]
      var split = StyleLua.splitFences(text, fence.begin, fence.end)
      if (!split.found) continue
      if (split.body.indexOf("o.window") !== -1 || split.body.indexOf("opacity") !== -1)
        root.opaqueWindows = true
      text = StyleLua.removeFences(text, fence.begin, fence.end)
      found = true
    }
    if (!found) return
    var synthetic = {}
    synthetic[StyleLua.OPAQUE_WINDOWS_KEY] = root.opaqueWindows
    windowsFile.setText(StyleLua.applyBlock(text, StyleLua.renderWindowsBody(synthetic)))
  }

  function applyMigration() {
    migrateWindowsFile()
    root.overrides = migrationOverrides
    root.leaves = migrationLeaves
    root.curves = migrationCurves
    root.blockRead = true

    var next = migrationText
    for (var i = 0; i < migrationQueue.length; i++)
      next = StyleLua.removeFences(next, migrationQueue[i].begin, migrationQueue[i].end)
    var body = StyleLua.renderLooknfeelBody(root.overrides, root.curves, root.leaves,
                                            root.baseCurves, root.baseLeaves)
    next = StyleLua.applyBlock(next, body)

    root.migrationNotice = "Imported your settings from " + migrationNames.join(" and ") + "."
    root.legacyBlocks = []
    root.selfWrite = true
    configFile.setText(next)
  }

  // ------------------------------------------------------------- processes

  function refresh() {
    var keys = LookSchema.queryKeys()
    var batch = []
    for (var i = 0; i < keys.length; i++) batch.push("getoption " + keys[i])
    readProc.command = ["timeout", "-k", "1", "10", "hyprctl", "-j", "--batch", batch.join(" ; ")]
    readProc.running = true
  }

  function readOption(entry) {
    if (entry.int !== undefined) return entry.int
    if (entry.bool !== undefined) return entry.bool
    if (entry.float !== undefined) return entry.float
    if (entry.str !== undefined) return entry.str
    // A css gap reads back as "5 5 5 5". Lacquer only writes uniform gaps, so
    // the first component is the one it can round-trip.
    if (entry.css !== undefined) {
      var parts = String(entry.css).match(/-?\d+(?:\.\d+)?/g) || []
      return parts.length > 0 ? Number(parts[0]) : 0
    }
    return undefined
  }

  function applyOptions(raw) {
    var next = {}
    var objects = String(raw || "").match(/\{[^{}]*\}/g) || []
    for (var i = 0; i < objects.length; i++) {
      try {
        var entry = JSON.parse(objects[i])
        if (!entry.option) continue
        var value = readOption(entry)
        if (value !== undefined) next[entry.option] = value
      } catch (e) {
      }
    }
    root.effective = next
  }

  function readBlock(text) {
    detectLegacy(text)
    var split = StyleLua.splitBlock(text)
    if (!split.found) {
      root.overrides = ({}); root.leaves = ({}); root.curves = ({})
      root.blockRead = true
      return
    }
    if (split.body.replace(/\s/g, "") === "") {
      root.overrides = ({}); root.leaves = ({}); root.curves = ({})
      root.blockRead = true
      return
    }
    blockReader.command = ["timeout", "-k", "2", "10", "lua", app.pluginDir + "/read.lua", "-e", split.body]
    blockReader.running = true
  }

  // Applied on exit, not on stdout: a block that fails to run leaves stdout
  // empty, and treating that as "no overrides" meant the next save rewrote the
  // block from nothing — destroying whatever the user had hand-edited into it.
  // A failed read leaves blockRead false, and persistNow refuses to write.
  Process {
    id: blockReader
    property string out: ""
    property string err: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: blockReader.out = text }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: blockReader.err = text }
    onExited: function(code) {
      if (code !== 0) {
        root.blockRead = false
        app.errorText = "The block in looknfeel.lua could not be read, so Lacquer will not "
          + "overwrite it. " + String(blockReader.err || "").trim()
        return
      }
      var parsed = StyleLua.parseHarness(blockReader.out)
      root.overrides = parsed.overrides
      root.leaves = parsed.leaves
      root.curves = parsed.curves
      root.blockRead = true
      app.errorText = ""
    }
  }

  // Same contract as blockReader: an unreadable block must not be replaced.
  Process {
    id: windowsReader
    property string out: ""
    property string err: ""
    property bool failed: false
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: windowsReader.out = text }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: windowsReader.err = text }
    onExited: function(code) {
      windowsReader.failed = code !== 0
      if (code !== 0) {
        app.errorText = "The block in hyprland.lua could not be read, so Lacquer will not "
          + "overwrite it. " + String(windowsReader.err || "").trim()
        return
      }
      root.opaqueWindows = StyleLua.parseHarness(windowsReader.out).opaque === true
    }
  }

  Process {
    id: legacyReader
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.absorbLegacy(text) }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text || "").trim() !== "") app.errorText = "migration: " + String(text).trim()
    }
  }

  Process {
    id: baselineReader
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = StyleLua.parseHarness(text)
        root.baseOverrides = parsed.overrides
        root.baseLeaves = parsed.leaves
        root.baseCurves = parsed.curves
        root.baselineReady = true
        // The block was parsed before the baseline landed, so nothing could be
        // compared against a default yet.
        configFile.reload()
        root.refresh()
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text || "").trim() !== "") app.errorText = "defaults: " + String(text).trim()
    }
  }

  Process {
    id: readProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyOptions(text) }
  }

  Process {
    id: evalProc
    onExited: {
      if (!root.previewPending) return
      root.previewPending = false
      Qt.callLater(root.livePreview)
    }
  }

  Process {
    id: reloadProc
    command: ["timeout", "-k", "1", "10", "hyprctl", "reload"]
    onExited: { errorsProc.running = true; root.refresh() }
  }

  // Lua config errors surface at load time, not write time, so this is what
  // turns "Lacquer wrote something" into "Hyprland accepted it".
  Process {
    id: errorsProc
    command: ["timeout", "-k", "1", "5", "hyprctl", "configerrors"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var out = String(text || "").trim()
        app.errorText = (out === "" || out === "no errors") ? "" : out
        if (app.errorText === "" && app.statusText === "Saving…") app.statusText = "Saved"
      }
    }
  }

  Timer {
    id: persistTimer
    interval: 400
    onTriggered: root.persistNow()
  }

  FileView {
    id: configFile
    path: root.configPath
    atomicWrites: true
    printErrors: false
    watchChanges: true
    onLoaded: if (root.baselineReady) root.readBlock(text())
    onLoadFailed: { root.overrides = ({}); root.leaves = ({}); root.curves = ({}); root.blockRead = true }
    onSaved: root.noteSaved()
    onSaveFailed: { root.selfWrite = false; app.errorText = "Could not write ~/.config/hypr/looknfeel.lua" }
    // Adopt an external edit rather than overwriting it from a stale copy —
    // but never mid-edit, or a re-read would yank a slider out from under the
    // user.
    onFileChanged: {
      if (root.selfWrite || persistTimer.running) return
      reload()
    }
  }

  FileView {
    id: windowsFile
    path: root.windowsPath
    atomicWrites: true
    printErrors: false
    watchChanges: true
    onLoaded: {
      var split = StyleLua.splitBlock(text())
      if (!split.found || split.body.replace(/\s/g, "") === "") {
        root.opaqueWindows = false
        return
      }
      windowsReader.command = ["timeout", "-k", "2", "10", "lua", app.pluginDir + "/read.lua", "-e", split.body]
      windowsReader.running = true
    }
    onLoadFailed: root.opaqueWindows = false
    onSaved: root.noteSaved()
    onSaveFailed: {
      root.selfWrite = false
      root.pendingSaves = 0
      app.errorText = "Could not write ~/.config/hypr/hyprland.lua"
    }
    onFileChanged: {
      if (root.selfWrite || persistTimer.running) return
      reload()
    }
  }

  FileView {
    id: defaultsFile
    path: app.omarchyPath + "/default/hypr/looknfeel.lua"
    printErrors: false
    // Without the baseline nothing can be compared against a default, so every
    // edit would be refused. Say why rather than sitting there inert.
    onLoadFailed: app.errorText = "Could not read " + app.omarchyPath
      + "/default/hypr/looknfeel.lua — is OMARCHY_PATH set?"
    // Run the packaged file directly rather than its text: it is Omarchy's own
    // and only needs reading once.
    onLoaded: {
      baselineReader.command = ["timeout", "-k", "2", "10", "lua", app.pluginDir + "/read.lua", path]
      baselineReader.running = true
    }
  }
}
