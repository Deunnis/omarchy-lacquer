.pragma library

// A line-based editor for ~/.config/omarchy/shell.toml.
//
// Deliberately not a TOML round-trip. The file is shared: `omarchy display
// text size` writes [font] base-size into it, themes ship their own copy, and
// the user may hand-edit it. Reserialising a parse tree would quietly drop
// comments, reorder keys and normalise values nobody asked us to touch.
//
// So editing works on the text itself: set a key by rewriting its line in
// place, or inserting one into the right section; clear it by deleting that
// line. Everything this file does not understand survives untouched.
//
// Only the flat `key = value` shapes Omarchy's own template uses are handled —
// no arrays of tables, no inline tables, no multi-line strings.

function isSectionHeader(line) {
  return /^\s*\[[^\[\]]+\]\s*(#.*)?$/.test(line)
}

function sectionNameOf(line) {
  var m = line.match(/^\s*\[([^\[\]]+)\]/)
  return m ? m[1].trim() : ""
}

// A commented-out key still counts as documentation, never as a value.
function keyOf(line) {
  var m = line.match(/^\s*([A-Za-z0-9_-]+)\s*=/)
  return m ? m[1] : ""
}

function splitLines(text) {
  return String(text || "").split("\n")
}

// Where each section starts and ends, so an insert lands inside the right one.
function sectionRanges(lines) {
  var ranges = {}
  var current = ""
  var start = -1
  for (var i = 0; i < lines.length; i++) {
    if (!isSectionHeader(lines[i])) continue
    if (current !== "") ranges[current] = { start: start, end: i }
    current = sectionNameOf(lines[i])
    start = i + 1
  }
  if (current !== "") ranges[current] = { start: start, end: lines.length }
  return ranges
}

function findKeyLine(lines, section, key) {
  var ranges = sectionRanges(lines)
  var range = ranges[section]
  if (!range) return -1
  for (var i = range.start; i < range.end; i++)
    if (keyOf(lines[i]) === key) return i
  return -1
}

// -------------------------------------------------------------- values

function stripComment(raw) {
  // Only strips a trailing comment outside quotes, so a "#rrggbb" colour
  // survives: that is exactly the value shape this file carries most.
  var out = ""
  var quote = ""
  for (var i = 0; i < raw.length; i++) {
    var ch = raw.charAt(i)
    if (quote) {
      out += ch
      if (ch === quote && raw.charAt(i - 1) !== "\\") quote = ""
      continue
    }
    if (ch === '"' || ch === "'") { quote = ch; out += ch; continue }
    if (ch === "#") break
    out += ch
  }
  return out.trim()
}

function rawValueAt(lines, index) {
  if (index < 0) return undefined
  var eq = lines[index].indexOf("=")
  if (eq === -1) return undefined
  return stripComment(lines[index].substring(eq + 1))
}

function unquote(raw) {
  if (raw === undefined) return undefined
  var t = String(raw).trim()
  if (t.length >= 2 && (t.charAt(0) === '"' || t.charAt(0) === "'")
      && t.charAt(t.length - 1) === t.charAt(0))
    return t.substring(1, t.length - 1)
  return t
}

function format(value) {
  if (typeof value === "boolean") return value ? "true" : "false"
  if (typeof value === "number") {
    if (!isFinite(value)) return "0"
    var rounded = parseFloat(value.toFixed(4))
    return String(rounded)
  }
  var s = String(value)
  // A bare token like hyprland.active-border is still a TOML string.
  return '"' + s.replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"'
}

// --------------------------------------------------------------- reading

function get(text, section, key) {
  var lines = splitLines(text)
  var at = findKeyLine(lines, section, key)
  if (at === -1) return undefined
  return unquote(rawValueAt(lines, at))
}

function has(text, section, key) {
  return findKeyLine(splitLines(text), section, key) !== -1
}

// Every set key as { "section.key": "value" }, matching how Style.qml keys its
// own override dictionaries.
function values(text) {
  var lines = splitLines(text)
  var out = {}
  var current = ""
  for (var i = 0; i < lines.length; i++) {
    if (isSectionHeader(lines[i])) { current = sectionNameOf(lines[i]); continue }
    var key = keyOf(lines[i])
    if (key === "" || current === "") continue
    out[current + "." + key] = unquote(rawValueAt(lines, i))
  }
  return out
}

// --------------------------------------------------------------- writing

// Preserves the alignment style of the section it lands in, because Omarchy's
// own template pads `=` into a column and a lone ragged line looks like damage.
function padKey(lines, section, key) {
  var ranges = sectionRanges(lines)
  var range = ranges[section]
  var width = key.length
  if (range) {
    for (var i = range.start; i < range.end; i++) {
      var other = keyOf(lines[i])
      if (other === "") continue
      var eq = lines[i].indexOf("=")
      var pad = lines[i].substring(0, eq).replace(/^\s+/, "").length
      if (pad > width) width = pad
    }
  }
  var out = key
  while (out.length < width) out += " "
  return out
}

function set(text, section, key, value) {
  var lines = splitLines(text)
  var at = findKeyLine(lines, section, key)
  var rendered = format(value)

  if (at !== -1) {
    var eq = lines[at].indexOf("=")
    var head = lines[at].substring(0, eq)
    lines[at] = head + "= " + rendered
    return lines.join("\n")
  }

  var ranges = sectionRanges(lines)
  var range = ranges[section]
  var line = padKey(lines, section, key) + " = " + rendered

  if (!range) {
    var prefix = lines.join("\n")
    if (prefix.trim() === "") return "[" + section + "]\n" + line + "\n"
    if (!/\n$/.test(prefix)) prefix += "\n"
    return prefix + "\n[" + section + "]\n" + line + "\n"
  }

  // Insert after the last real key in the section, so a new key joins the
  // block rather than landing under the section's trailing comments.
  var insertAt = range.start
  for (var j = range.start; j < range.end; j++)
    if (keyOf(lines[j]) !== "") insertAt = j + 1
  lines.splice(insertAt, 0, line)
  return lines.join("\n")
}

function unset(text, section, key) {
  var lines = splitLines(text)
  var at = findKeyLine(lines, section, key)
  if (at === -1) return String(text || "")
  lines.splice(at, 1)

  // Drop a section that now holds nothing but its own header.
  var ranges = sectionRanges(lines)
  var range = ranges[section]
  if (range) {
    var empty = true
    for (var i = range.start; i < range.end; i++)
      if (keyOf(lines[i]) !== "") { empty = false; break }
    if (empty) {
      var header = range.start - 1
      var end = range.end
      // Take the blank lines the section owned with it.
      while (end > range.start && lines[end - 1].trim() === "") end--
      lines.splice(header, end - header)
    }
  }
  var out = lines.join("\n")
  return out.replace(/\n{3,}/g, "\n\n").replace(/^\n+/, "")
}
