.pragma library

// Ported from OmaShuffle's ThemeDeck.js (same author, MIT). One change, marked
// at clampFloatOrNull.

// Pure deck logic for OmaShuffle. No QML, no I/O - just state in, state out,
// so it can be reasoned about and tested on its own.

var STATE_VERSION = 2
var MAX_HISTORY = 40
var MAX_POOL = 500      // far above any real installed-theme count; a sanity cap
var SLUG_RE = /^[a-z0-9][a-z0-9._-]*$/
var MAX_SLOTS = 6        // Day & Night slots; plenty for morning/day/evening/night + a couple more
var MIN_OFFSET_MIN = -720   // a slot can sit up to 12h either side of its sun anchor
var MAX_OFFSET_MIN = 720

// omarchy-theme-set's own rules: lowercase, no leading dot, no slash.
function sanitizeSlug(s) {
  if (typeof s !== "string") return ""
  if (s.length === 0 || s.length > 128) return ""
  if (s.indexOf("/") !== -1 || s.indexOf("..") !== -1) return ""
  return SLUG_RE.test(s) ? s : ""
}

function sanitizeSlugList(arr) {
  var out = []
  if (!Array.isArray(arr)) return out
  for (var i = 0; i < arr.length && out.length < MAX_POOL; i++) {
    var s = sanitizeSlug(arr[i])
    if (s && out.indexOf(s) === -1) out.push(s)
  }
  return out
}

// Fisher-Yates on a copy. Math.random is fine in the QML JS engine.
function shuffle(arr) {
  var a = arr.slice()
  for (var i = a.length - 1; i > 0; i--) {
    var j = Math.floor(Math.random() * (i + 1))
    var t = a[i]; a[i] = a[j]; a[j] = t
  }
  return a
}

// Normalize whatever came off disk into a known-good state object.
function normalizeState(raw) {
  var s = (raw && typeof raw === "object") ? raw : {}
  var pool = sanitizeSlugList(s.pool)
  var st = {
    version: STATE_VERSION,
    enabled: s.enabled !== false,
    notify: s.notify !== false,
    poolInitialized: s.poolInitialized === true,
    // "pick some themes" reminders left to show on an empty rotation
    nagsLeft: clampInt(s.nagsLeft, 0, 3, 3),
    pool: pool,
    deck: sanitizeSlugList(s.deck).filter(function (x) { return pool.indexOf(x) !== -1 }),
    lastAppliedSlug: sanitizeSlug(s.lastAppliedSlug),
    lastBootId: (typeof s.lastBootId === "string" && s.lastBootId.length <= 128) ? s.lastBootId : "",
    history: [],
    // card chrome, mirrored from OmaDeezer's ranges/defaults
    transparency: clampInt(s.transparency, 0, 100, 0),
    cornerRadius: clampInt(s.cornerRadius, 0, 20, 8),
    borderWidth: clampInt(s.borderWidth, 0, 6, 2),
    schedule: normalizeSchedule(s.schedule)
  }
  if (Array.isArray(s.history)) {
    for (var i = 0; i < s.history.length && st.history.length < MAX_HISTORY; i++) {
      var h = s.history[i]
      if (!h || typeof h !== "object") continue
      var slug = sanitizeSlug(h.slug)
      if (!slug) continue
      st.history.push({
        slug: slug,
        display: (typeof h.display === "string") ? h.display.slice(0, 120) : slug,
        ts: (typeof h.ts === "number" && isFinite(h.ts)) ? Math.floor(h.ts) : 0,
        auto: h.auto === true
      })
    }
  }
  return st
}

function clampInt(v, lo, hi, dflt) {
  var n = Math.round(Number(v))
  if (!isFinite(n)) return dflt
  return Math.max(lo, Math.min(hi, n))
}

// -------------------------------------------------------- Day & Night

function clampFloatOrNull(v, lo, hi) {
  // Fixed from OmaShuffle: Number(null) and Number("") are 0, so a manual
  // location that was never entered round-tripped through save/load as 0,0 —
  // a real point in the Gulf of Guinea — instead of staying unset.
  if (v === null || v === undefined || v === "") return null
  var n = Number(v)
  if (!isFinite(n)) return null
  return Math.max(lo, Math.min(hi, n))
}

function defaultSlots() {
  return [
    { id: "day", label: "Day", mode: "light", anchor: "sunrise", offsetMin: 0, deck: [], lastAppliedSlug: "" },
    { id: "night", label: "Night", mode: "dark", anchor: "sunset", offsetMin: 0, deck: [], lastAppliedSlug: "" }
  ]
}

function normalizeSlot(raw, fallbackId) {
  var s = (raw && typeof raw === "object") ? raw : {}
  var id = sanitizeSlug(typeof s.id === "string" ? s.id.toLowerCase() : "") || fallbackId
  return {
    id: id,
    label: (typeof s.label === "string" && s.label.trim()) ? s.label.slice(0, 40) : id,
    mode: (s.mode === "dark") ? "dark" : "light",
    anchor: (s.anchor === "sunset") ? "sunset" : "sunrise",
    offsetMin: clampInt(s.offsetMin, MIN_OFFSET_MIN, MAX_OFFSET_MIN, 0),
    deck: sanitizeSlugList(s.deck),
    lastAppliedSlug: sanitizeSlug(s.lastAppliedSlug)
  }
}

function normalizeSlots(raw) {
  if (!Array.isArray(raw) || raw.length === 0) return defaultSlots()
  var out = []
  var seenIds = {}
  for (var i = 0; i < raw.length && out.length < MAX_SLOTS; i++) {
    var slot = normalizeSlot(raw[i], "slot" + (i + 1))
    while (seenIds[slot.id]) slot.id = slot.id + "-" + (out.length + 1)
    seenIds[slot.id] = true
    out.push(slot)
  }
  return out.length > 0 ? out : defaultSlots()
}

// Day & Night: an independent, opt-in (default off) schedule that applies a
// theme by time of day instead of once per boot. See SunTimes.js for the
// sun-position math this drives on.
function normalizeSchedule(raw) {
  var s = (raw && typeof raw === "object") ? raw : {}
  var override = (s.override && typeof s.override === "object") ? s.override : {}
  var untilTs = Number(override.untilTs)
  return {
    enabled: s.enabled === true,
    locationMode: (s.locationMode === "manual") ? "manual" : "auto",
    latitude: clampFloatOrNull(s.latitude, -90, 90),
    longitude: clampFloatOrNull(s.longitude, -180, 180),
    locationLabel: (typeof s.locationLabel === "string") ? s.locationLabel.slice(0, 120) : "",
    slots: normalizeSlots(s.slots),
    lastAppliedSlotId: sanitizeSlug(typeof s.lastAppliedSlotId === "string" ? s.lastAppliedSlotId.toLowerCase() : ""),
    override: {
      slug: sanitizeSlug(override.slug),
      untilTs: (isFinite(untilTs) && untilTs > 0) ? Math.floor(untilTs) : 0
    },
    notifiedEmptyModeFor: sanitizeSlug(typeof s.notifiedEmptyModeFor === "string" ? s.notifiedEmptyModeFor.toLowerCase() : "")
  }
}

// Pick the next theme to apply. Returns { slug, deck } where deck is the
// remaining deck AFTER taking slug. slug is "" when the pool is empty.
// `pool` is the authoritative current selection (state.pool may lag a tick).
function drawNext(state, pool) {
  var live = sanitizeSlugList(pool)
  if (live.length === 0) return { slug: "", deck: [] }

  var deck = (state && Array.isArray(state.deck) ? state.deck : [])
    .filter(function (x) { return live.indexOf(x) !== -1 })

  if (deck.length === 0) {
    deck = shuffle(live)
    // Avoid repeating the theme we just came from when there's a choice.
    var last = state ? state.lastAppliedSlug : ""
    if (deck.length > 1 && deck[0] === last) {
      deck.push(deck.shift())
    }
  }

  var slug = deck[0]
  return { slug: slug, deck: deck.slice(1) }
}

// Fold an applied theme into state (used for both auto and manual applies).
function recordApplied(state, slug, display, nowSec, auto, newDeck) {
  var next = shallowClone(state)
  next.lastAppliedSlug = slug
  if (Array.isArray(newDeck)) next.deck = newDeck
  var entry = { slug: slug, display: display || slug, ts: Math.floor(nowSec) || 0, auto: auto === true }
  next.history = [entry].concat(state.history || []).slice(0, MAX_HISTORY)
  return next
}

function shallowClone(o) {
  var n = {}
  for (var k in o) n[k] = o[k]
  return n
}

// "3 boots ago" style label is unreliable (we don't track boot count), so
// history uses elapsed wall-clock time instead.
function relativeAge(tsSec, nowSec) {
  if (!tsSec) return ""
  var d = Math.max(0, Math.floor(nowSec - tsSec))
  if (d < 45) return "just now"
  if (d < 90) return "a minute ago"
  if (d < 3600) return Math.round(d / 60) + " min ago"
  if (d < 7200) return "an hour ago"
  if (d < 86400) return Math.round(d / 3600) + " hours ago"
  if (d < 172800) return "yesterday"
  return Math.round(d / 86400) + " days ago"
}
