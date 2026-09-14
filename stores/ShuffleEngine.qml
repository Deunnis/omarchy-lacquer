import QtQuick
import Quickshell
import Quickshell.Io
import "../ShuffleDeck.js" as Deck
import "../SunTimes.js" as Sun

// The theme shuffle: a new theme on every real boot, and/or Day & Night slots
// keyed to local sunrise and sunset.
//
// Ported from OmaShuffle's OmaShuffle.qml (same author, MIT), engine only — the
// picker, settings and schedule views live in Lacquer's Shuffle section. The
// logic below is deliberately kept line-for-line where it can be; the pure
// parts (ShuffleDeck.js, SunTimes.js) are golden-tested against the originals.
//
// It runs inside Lacquer's service, which starts with the shell, so it works
// whether or not the Lacquer panel has ever been opened.
//
// Three things are new here:
//
//   dormant    While io.github.omashuffle is still installed, this engine does
//              nothing at all: two engines would both react to the same boot
//              and the same slot boundary. It only reads OmaShuffle's state so
//              the UI can show it.
//   adoption   With OmaShuffle gone and no state of its own yet, it copies
//              OmaShuffle's state.json — lastBootId included, so the shell
//              restart that follows a removal is not mistaken for a new boot.
//   override   A manual pick pauses Day & Night until the next boundary. In
//              OmaShuffle only its own picks could clear that pause; here a
//              theme applied from anywhere (a terminal, the Omarchy menu) does.
Item {
  id: root
  visible: false

  readonly property string home: Quickshell.env("HOME")
  readonly property string ownDir: root.home + "/.local/state/omarchy/io.github.deunnis.lacquer"
  readonly property string ownState: root.ownDir + "/shuffle.json"
  readonly property string legacyDir: root.home + "/.config/omarchy/plugins/io.github.omashuffle"
  readonly property string legacyState: root.home + "/.local/state/omarchy/io.github.omashuffle/state.json"
  readonly property string pluginDir: {
    var url = String(Qt.resolvedUrl(".."))
    if (url.indexOf("file://") === 0) url = url.substring(7)
    return decodeURIComponent(url).replace(/\/+$/, "")
  }
  readonly property string currentNamePath: root.home + "/.local/state/omarchy/current/theme.name"
  readonly property string weatherLocationPath: root.home + "/.local/state/omarchy/settings/weather.json"

  // null until the first probe answers, so nothing runs on a guess.
  property var dormant: null

  property var st: Deck.normalizeState(null)
  property bool stateLoaded: false
  property string currentBootId: ""
  property bool bootChecked: false
  property bool bootReshufflePending: false

  property var themes: []
  property var themeBySlug: ({})
  property string currentThemeSlug: ""

  property string pendingAutoSlug: ""
  property string applyingSlug: ""
  property double lastApplyMs: 0
  property bool verifying: false

  property real detectedLat: NaN
  property real detectedLon: NaN
  property string detectedLocationLabel: ""

  readonly property bool active: root.dormant === false && root.stateLoaded

  // ============================================================ lifecycle

  Component.onCompleted: {
    bootIdProc.running = true
    themeScanProc.running = true
    currentNameProc.running = true
    weatherLocationProc.running = true
    probeProc.running = true
  }

  // Is OmaShuffle still installed?
  Process {
    id: probeProc
    command: ["test", "-d", root.legacyDir]
    onExited: function(code) {
      var nowDormant = code === 0
      var changed = root.dormant !== nowDormant
      root.dormant = nowDormant
      if (changed) root.loadFromDisk()
    }
  }

  // While dormant, keep asking — OmaShuffle may be removed outside Lacquer.
  Timer {
    interval: 60000
    repeat: true
    running: root.dormant === true
    onTriggered: if (!probeProc.running) probeProc.running = true
  }

  function wake() {
    if (!probeProc.running) probeProc.running = true
  }

  function loadFromDisk() {
    root.stateLoaded = false
    root.bootChecked = false
    if (root.dormant) {
      stateReadProc.command = ["python3", "-c", root.stateReaderScript, root.legacyState, String(root.maxStateBytes)]
      stateReadProc.running = true
      return
    }
    adoptProc.running = true
  }

  // Adopt OmaShuffle's state only if Lacquer has none of its own yet.
  Process {
    id: adoptProc
    command: ["sh", "-c",
      'mkdir -p "$1" || exit 0\n'
      + '[ -e "$2" ] && exit 0\n'
      + '[ -f "$3" ] && [ ! -L "$3" ] && cp "$3" "$2" && echo adopted\n'
      + 'exit 0\n', "sh", root.ownDir, root.ownState, root.legacyState]
    stdout: StdioCollector { id: adoptOut; waitForEnd: true }
    onExited: {
      if (String(adoptOut.text || "").indexOf("adopted") !== -1)
        console.log("Lacquer: adopted OmaShuffle's shuffle state")
      stateReadProc.command = ["python3", "-c", root.stateReaderScript, root.ownState, String(root.maxStateBytes)]
      stateReadProc.running = true
    }
  }

  FileView {
    id: stateFile
    path: root.ownState
    preload: false
    printErrors: false
    atomicWrites: true
  }

  // Bounded, descriptor-pinned reader (from OmaShuffle): opens once with
  // O_NOFOLLOW|O_NONBLOCK, requires a regular file, reads at most limit+1
  // bytes. Exit codes: 2 missing/symlink/unopenable, 3 not a regular file,
  // 4 too big.
  readonly property int maxStateBytes: 262144
  readonly property string stateReaderScript: [
    "import os,sys,stat",
    "path=sys.argv[1]; limit=int(sys.argv[2])",
    "try:",
    "    fd=os.open(path, os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK)",
    "except OSError:",
    "    sys.exit(2)",
    "try:",
    "    if not stat.S_ISREG(os.fstat(fd).st_mode):",
    "        sys.exit(3)",
    "    chunks=[]; total=0",
    "    while total <= limit:",
    "        chunk=os.read(fd, (limit + 1) - total)",
    "        if not chunk: break",
    "        chunks.append(chunk); total += len(chunk)",
    "    if total > limit:",
    "        sys.exit(4)",
    "    sys.stdout.buffer.write(b''.join(chunks))",
    "finally:",
    "    os.close(fd)"
  ].join("\n")

  Process {
    id: stateReadProc
    stdout: StdioCollector { id: stateReadOut; waitForEnd: true }
    onExited: function(code) {
      if (code === 3) console.warn("Lacquer: shuffle state is not a regular file - ignoring it")
      if (code === 4) console.warn("Lacquer: shuffle state exceeds " + root.maxStateBytes + " bytes - ignoring it")
      root.loadState(code === 0 ? stateReadOut.text : "")
    }
  }

  Process {
    id: bootIdProc
    command: ["cat", "/proc/sys/kernel/random/boot_id"]
    stdout: StdioCollector { id: bootIdOut; waitForEnd: true }
    onExited: {
      root.currentBootId = String(bootIdOut.text || "").trim()
      root.maybeBootSwitch()
    }
  }

  Process {
    id: currentNameProc
    command: ["python3", "-c", root.stateReaderScript, root.currentNamePath, "4096"]
    stdout: StdioCollector { id: currentNameOut; waitForEnd: true }
    onExited: function(code) {
      var live = code === 0 ? Deck.sanitizeSlug(String(currentNameOut.text || "").trim()) : ""
      root.currentThemeSlug = live
      if (root.verifying) {
        root.verifying = false
        if (root.applyingSlug && live && live !== root.applyingSlug && root.st.notify)
          root.notify("Theme may not have applied: " + root.displayFor(root.applyingSlug))
        root.applyingSlug = ""
      }
    }
  }

  // Know about themes applied from anywhere, for the override fix below.
  FileView {
    path: root.currentNamePath
    printErrors: false
    watchChanges: true
    onFileChanged: { reload(); if (!currentNameProc.running) currentNameProc.running = true }
  }

  Process {
    id: weatherLocationProc
    command: ["python3", "-c", root.stateReaderScript, root.weatherLocationPath, "4096"]
    stdout: StdioCollector { id: weatherLocationOut; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0) return
      var parsed = null
      try { parsed = JSON.parse(weatherLocationOut.text) } catch (e) { parsed = null }
      if (!parsed || typeof parsed !== "object") return
      var lat = Number(parsed.latitude), lon = Number(parsed.longitude)
      if (isFinite(lat) && lat >= -90 && lat <= 90 && isFinite(lon) && lon >= -180 && lon <= 180) {
        root.detectedLat = lat
        root.detectedLon = lon
      }
      if (typeof parsed.name === "string") root.detectedLocationLabel = parsed.name.slice(0, 120)
      root.checkSchedule()
    }
  }

  Process {
    id: themeScanProc
    command: ["timeout", "-k", "2", "12", "python3", root.pluginDir + "/scan-themes"]
    stdout: StdioCollector { id: themeScanOut; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0) { console.warn("Lacquer: theme scan exited " + code); return }
      root.ingestThemes(themeScanOut.text)
    }
  }

  function rescanThemes() {
    if (!themeScanProc.running) themeScanProc.running = true
  }

  // Fire-and-forget: `omarchy theme set` leaves a background child on its
  // stdout, so exit tracking is not dependable. verifyTimer re-reads
  // theme.name a few seconds later instead.
  Process { id: themeSetProc }
  Process { id: notifyProc }

  Timer {
    id: scheduleTimer
    interval: 60000
    repeat: true
    running: root.active && root.st.schedule.enabled
    triggeredOnStart: false
    onTriggered: root.checkSchedule()
  }

  function loadState(raw) {
    var parsed = null
    if (raw) { try { parsed = JSON.parse(raw) } catch (e) { parsed = null } }
    root.st = Deck.normalizeState(parsed)
    root.stateLoaded = true
    root.maybeBootSwitch()
    root.checkSchedule()
  }

  function persist() {
    // Never write while dormant: OmaShuffle owns its state then, and its next
    // save would overwrite anything written here from its in-memory copy.
    if (root.dormant !== false) return
    stateFile.setText(JSON.stringify(root.st, null, 2) + "\n")
  }

  function setState(next) { root.st = next; root.persist() }

  // ============================================================ boot switch

  function maybeBootSwitch() {
    if (!root.active) return
    if (root.bootChecked) return
    if (root.currentBootId === "") return
    root.bootChecked = true

    // Same boot id as last run -> shell restart / relogin, not a fresh boot.
    if (root.st.lastBootId === root.currentBootId) return

    var next = Deck.shallowClone(root.st)
    next.lastBootId = root.currentBootId

    if (root.st.schedule.enabled) {
      next.schedule = Deck.shallowClone(next.schedule)
      next.schedule.override = { slug: "", untilTs: 0 }
      root.bootReshufflePending = true
      root.setState(next)
      root.checkSchedule()
      return
    }
    if (!root.st.enabled) { root.setState(next); return }

    var draw = Deck.drawNext(root.st, root.st.pool)
    if (!draw.slug) {
      if (root.st.notify && !root.st.poolInitialized && next.nagsLeft > 0) {
        next.nagsLeft = next.nagsLeft - 1
        root.notify("Pick some themes to shuffle in Lacquer → Shuffle")
      }
      root.setState(next)
      return
    }

    next.deck = draw.deck
    root.setState(next)
    root.pendingAutoSlug = draw.slug
    bootSwitchTimer.restart()
  }

  Timer {
    id: bootSwitchTimer
    interval: 2500
    repeat: false
    onTriggered: if (root.pendingAutoSlug) root.applyTheme(root.pendingAutoSlug, true)
  }

  // ============================================================ apply

  function applyTheme(slug, auto, quiet) {
    if (!root.active) return false
    var clean = Deck.sanitizeSlug(slug)
    if (!clean) { console.warn("Lacquer: refusing invalid theme slug: " + slug); return false }

    var nowMs = Date.now()
    if (clean === root.st.lastAppliedSlug && nowMs - root.lastApplyMs < 3000) return true
    root.lastApplyMs = nowMs
    root.applyingSlug = clean

    var disp = root.displayFor(clean)
    var newDeck = auto ? null : (root.st.deck || []).filter(function(x) { return x !== clean })
    var next = Deck.recordApplied(root.st, clean, disp, Date.now() / 1000, auto === true, newDeck)

    if (!auto && next.schedule.enabled) {
      var loc = root.effectiveLocation()
      var sched = Sun.computeSchedule(next.schedule.slots, loc.lat, loc.lon, new Date())
      next = Deck.shallowClone(next)
      next.schedule = Deck.shallowClone(next.schedule)
      next.schedule.override = { slug: clean, untilTs: sched.nextBoundaryTs || 0 }
    }

    root.setState(next)
    root.currentThemeSlug = clean

    themeSetProc.command = ["omarchy", "theme", "set", clean]
    themeSetProc.startDetached()

    if (root.st.notify && !quiet) root.notify((auto ? "This boot's theme: " : "Applied: ") + disp)
    verifyTimer.restart()
    return true
  }

  Timer {
    id: verifyTimer
    interval: 5000
    repeat: false
    onTriggered: { root.verifying = true; if (!currentNameProc.running) currentNameProc.running = true }
  }

  function shuffleNow() {
    if (!root.active) return
    if (root.st.schedule.enabled) {
      var act = root.activeSlot()
      if (!act) { root.notify("No active Day & Night slot yet"); return }
      root.applyForSlot(act.id, true, false)
      return
    }
    var draw = Deck.drawNext(root.st, root.st.pool)
    if (!draw.slug) { root.notify("Pick at least one theme first"); return }
    var next = Deck.shallowClone(root.st)
    next.deck = draw.deck
    root.setState(next)
    root.applyTheme(draw.slug, false)
  }

  function reshuffleDeck() {
    if (!root.active) return
    if (root.st.schedule.enabled) {
      var act = root.activeSlot()
      if (!act) return
      root.updateSlot(act.id, { deck: [] })
      return
    }
    var next = Deck.shallowClone(root.st)
    next.deck = []
    root.setState(next)
  }

  // ============================================================ pool editing

  function inPool(slug) { return (root.st.pool || []).indexOf(slug) !== -1 }

  function togglePool(slug) {
    if (!root.active) return
    var clean = Deck.sanitizeSlug(slug)
    if (!clean) return
    var pool = (root.st.pool || []).slice()
    var i = pool.indexOf(clean)
    if (i === -1) pool.push(clean); else pool.splice(i, 1)
    var next = Deck.shallowClone(root.st)
    next.pool = pool
    next.poolInitialized = true
    next.deck = (next.deck || []).filter(function(x) { return pool.indexOf(x) !== -1 })
    root.setState(next)
  }

  function selectAll() {
    if (!root.active || root.themes.length === 0) return
    var next = Deck.shallowClone(root.st)
    next.pool = root.themes.map(function(t) { return t.slug })
    next.poolInitialized = true
    root.setState(next)
  }

  function selectNone() {
    if (!root.active) return
    var next = Deck.shallowClone(root.st)
    next.pool = []
    next.deck = []
    next.poolInitialized = true
    root.setState(next)
  }

  function selectByMode(mode) {
    if (!root.active || root.themes.length === 0) return
    var pool = (root.st.pool || []).slice()
    var matched = 0, added = 0
    for (var i = 0; i < root.themes.length; i++) {
      var t = root.themes[i]
      if (t.mode !== mode) continue
      matched++
      if (pool.indexOf(t.slug) === -1) { pool.push(t.slug); added++ }
    }
    if (added === 0) {
      root.notify(matched === 0 ? "No " + mode + " themes installed"
                                : "Every " + mode + " theme is already in the rotation")
      return
    }
    var next = Deck.shallowClone(root.st)
    next.pool = pool
    next.poolInitialized = true
    root.setState(next)
  }

  function setEnabled(v) { if (!root.active) return; var n = Deck.shallowClone(root.st); n.enabled = v === true; root.setState(n) }
  function setNotify(v) { if (!root.active) return; var n = Deck.shallowClone(root.st); n.notify = v === true; root.setState(n) }

  // ============================================================ day & night

  function effectiveLocation() {
    var sch = root.st.schedule
    if (sch.locationMode === "manual") {
      return {
        lat: (typeof sch.latitude === "number") ? sch.latitude : NaN,
        lon: (typeof sch.longitude === "number") ? sch.longitude : NaN
      }
    }
    return { lat: root.detectedLat, lon: root.detectedLon }
  }

  function poolForMode(mode) {
    return (root.st.pool || []).filter(function(slug) {
      var t = root.themeBySlug[slug]
      return t && t.mode === mode
    })
  }

  function findSlot(slots, id) {
    for (var i = 0; i < slots.length; i++) if (slots[i].id === id) return slots[i]
    return null
  }

  function activeSlot() {
    var sch = root.st.schedule
    var loc = root.effectiveLocation()
    return Sun.computeSchedule(sch.slots, loc.lat, loc.lon, new Date()).activeSlot
  }

  // For the UI: the active slot, the next one and when it starts.
  function scheduleInfo() {
    var loc = root.effectiveLocation()
    if (!isFinite(loc.lat) || !isFinite(loc.lon)) return { hasLocation: false }
    var r = Sun.computeSchedule(root.st.schedule.slots, loc.lat, loc.lon, new Date())
    return { hasLocation: true, active: r.activeSlot, next: r.nextSlot, nextBoundaryTs: r.nextBoundaryTs }
  }

  function updateSchedule(patch) {
    var next = Deck.shallowClone(root.st)
    next.schedule = Deck.shallowClone(root.st.schedule)
    for (var k in patch) next.schedule[k] = patch[k]
    root.setState(next)
  }

  function setScheduleEnabled(v) { if (!root.active) return; root.updateSchedule({ enabled: v === true }); root.checkSchedule() }
  function setLocationMode(mode) { if (!root.active) return; root.updateSchedule({ locationMode: mode === "manual" ? "manual" : "auto" }); root.checkSchedule() }

  function setManualLatitude(text) {
    if (!root.active) return
    var v = parseFloat(text)
    if (!isFinite(v)) return
    root.updateSchedule({ latitude: Math.max(-90, Math.min(90, v)), locationMode: "manual" })
    root.checkSchedule()
  }
  function setManualLongitude(text) {
    if (!root.active) return
    var v = parseFloat(text)
    if (!isFinite(v)) return
    root.updateSchedule({ longitude: Math.max(-180, Math.min(180, v)), locationMode: "manual" })
    root.checkSchedule()
  }

  function updateSlot(id, patch) {
    if (!root.active) return
    var next = Deck.shallowClone(root.st)
    next.schedule = Deck.shallowClone(root.st.schedule)
    next.schedule.slots = root.st.schedule.slots.map(function(s) {
      if (s.id !== id) return s
      var merged = Deck.shallowClone(s)
      for (var k in patch) merged[k] = patch[k]
      return merged
    })
    root.setState(next)
  }

  function addSlot() {
    if (!root.active) return
    var slots = root.st.schedule.slots
    if (slots.length >= 6) return
    var id = "slot-" + Date.now().toString(36) + "-" + Math.floor(Math.random() * 1000)
    var next = Deck.shallowClone(root.st)
    next.schedule = Deck.shallowClone(root.st.schedule)
    next.schedule.slots = slots.concat([{
      id: id, label: "New slot", mode: "dark", anchor: "sunset", offsetMin: 0, deck: [], lastAppliedSlug: ""
    }])
    root.setState(next)
  }

  function removeSlot(id) {
    if (!root.active) return
    var slots = root.st.schedule.slots
    if (slots.length <= 1) return
    var next = Deck.shallowClone(root.st)
    next.schedule = Deck.shallowClone(root.st.schedule)
    next.schedule.slots = slots.filter(function(s) { return s.id !== id })
    if (next.schedule.lastAppliedSlotId === id) next.schedule.lastAppliedSlotId = ""
    root.setState(next)
  }

  function applyForSlot(slotId, drawNew, quiet) {
    var sch = root.st.schedule
    var slot = root.findSlot(sch.slots, slotId)
    if (!slot) return

    var slug = slot.lastAppliedSlug
    var newDeck = slot.deck

    if (drawNew || !slug) {
      var draw = Deck.drawNext({ deck: slot.deck, lastAppliedSlug: slot.lastAppliedSlug }, root.poolForMode(slot.mode))
      if (!draw.slug) {
        if (sch.notifiedEmptyModeFor !== slot.id) {
          root.notify("No " + slot.mode + " themes in your rotation for the \"" + slot.label + "\" slot")
          root.updateSchedule({ notifiedEmptyModeFor: slot.id })
        }
        return
      }
      slug = draw.slug
      newDeck = draw.deck
    }

    var next = Deck.shallowClone(root.st)
    next.schedule = Deck.shallowClone(sch)
    next.schedule.slots = sch.slots.map(function(s) {
      if (s.id !== slot.id) return s
      var s2 = Deck.shallowClone(s); s2.lastAppliedSlug = slug; s2.deck = newDeck; return s2
    })
    next.schedule.lastAppliedSlotId = slot.id
    next.schedule.notifiedEmptyModeFor = ""
    root.st = next
    root.applyTheme(slug, true, quiet !== false)
  }

  function checkSchedule() {
    if (!root.active) return
    var sch = root.st.schedule
    if (!sch.enabled) return
    if (root.themes.length === 0) return

    var loc = root.effectiveLocation()
    if (!isFinite(loc.lat) || !isFinite(loc.lon)) return

    var result = Sun.computeSchedule(sch.slots, loc.lat, loc.lon, new Date())
    if (!result.activeSlot) return

    var now = Date.now()
    // From OmaShuffle: an override whose theme is no longer the one this
    // engine applied is stale.
    if (sch.override.slug && sch.override.slug !== root.st.lastAppliedSlug) {
      root.updateSchedule({ override: { slug: "", untilTs: 0 } })
      sch = root.st.schedule
    }
    // Fixed from OmaShuffle: the same is true when a theme was applied from
    // outside the engine. The grace period covers theme.name not having
    // caught up with a pick made a moment ago.
    if (sch.override.slug && root.currentThemeSlug && root.currentThemeSlug !== sch.override.slug
        && now - root.lastApplyMs > 15000) {
      root.updateSchedule({ override: { slug: "", untilTs: 0 } })
      sch = root.st.schedule
    }
    if (sch.override.untilTs > 0 && sch.override.untilTs <= now) {
      root.updateSchedule({ override: { slug: "", untilTs: 0 } })
      sch = root.st.schedule
    }
    if (sch.override.untilTs > now) return

    if (root.bootReshufflePending) {
      root.bootReshufflePending = false
      root.applyForSlot(result.activeSlot.id, true)
      return
    }

    if (sch.lastAppliedSlotId !== result.activeSlot.id) {
      root.applyForSlot(result.activeSlot.id, true)
    }
  }

  // ============================================================ helpers

  function displayFor(slug) {
    var t = root.themeBySlug[slug]
    return (t && t.display) ? t.display : slug
  }
  function isHex(s) { return typeof s === "string" && /^#[0-9a-fA-F]{3,8}$/.test(s) }
  function hexOr(s, dflt) { return root.isHex(s) ? s : dflt }

  function notify(body) {
    notifyProc.command = ["omarchy-notification-send", "-t", "4000", "Lacquer", String(body)]
    notifyProc.startDetached()
  }

  readonly property int maxThemes: 600
  readonly property int maxScanChars: 1048576

  function ingestThemes(raw) {
    if (typeof raw !== "string" || raw.length > root.maxScanChars) {
      console.warn("Lacquer: theme scan output missing or too large - ignoring")
      return
    }
    var arr = []
    try { arr = JSON.parse(raw) } catch (e) { arr = [] }
    if (!Array.isArray(arr)) arr = []
    var map = ({})
    var clean = []
    for (var i = 0; i < arr.length && clean.length < root.maxThemes; i++) {
      var t = arr[i]
      var slug = Deck.sanitizeSlug(t && t.slug)
      // A theme with no colors.toml would apply broken; never shuffle into it.
      if (!slug || map[slug] || (t && t.hasColors === false)) continue
      var entry = {
        slug: slug,
        source: (t.source === "user") ? "user" : "system",
        display: (typeof t.display === "string" && t.display) ? String(t.display).slice(0, 120) : slug,
        mode: (t.mode === "light") ? "light" : "dark"
      }
      map[slug] = entry
      clean.push(entry)
    }
    clean.sort(function(a, b) {
      var x = a.display.toLowerCase(), y = b.display.toLowerCase()
      return x < y ? -1 : (x > y ? 1 : 0)
    })
    root.themes = clean
    root.themeBySlug = map
    root.checkSchedule()
  }
}
