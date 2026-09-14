.pragma library

// Renders and parses Lacquer's managed block.
//
//   hypr/looknfeel.lua   hl.config + hl.curve + hl.animation
//   hypr/hyprland.lua    o.window rules, where the stock template's own
//                        example puts personal window rules
//
// Only what is between the fences is ever rewritten, so the block is safe to
// hand-edit and safe to sit alongside anything else in the file.
//
// One renderer feeds both paths so preview and saved state cannot drift:
//
//   preview  `hyprctl eval` — config overrides, plus every curve and leaf at
//            its effective value. Emitting the whole animation set is what
//            makes resetting one leaf previewable; Hyprland has no "unset".
//   persist  only what differs from Omarchy's shipped defaults.
//
// `hyprctl keyword` is not usable — Hyprland rejects it under the Lua parser
// ("keyword can't work with non-legacy parsers, use eval").
//
// The hl.config rendering (nest/renderTable) is adapted from Omaland's
// LuaConfig.js — MIT, Copyright (c) 2026 Bobby Nicholas.

var BEGIN_FENCE = "-- >>> lacquer managed block >>>"
var END_FENCE = "-- <<< lacquer managed block <<<"

var OPAQUE_WINDOWS_KEY = "lacquer:opaque_windows"
var SYNTHETIC_KEYS = [OPAQUE_WINDOWS_KEY]

// Fences Lacquer adopts from and then removes on migration.
var LEGACY_FENCES = [
  { begin: "-- >>> omaland managed block >>>",   end: "-- <<< omaland managed block <<<",   name: "Omaland" },
  { begin: "-- >>> omanimate managed block >>>", end: "-- <<< omanimate managed block <<<", name: "Omanimate" }
]

// ---------------------------------------------------------------- numbers

function num(n, decimals) {
  var v = Number(n)
  if (!isFinite(v)) return "0"
  var rounded = parseFloat(v.toFixed(decimals === undefined ? 2 : decimals))
  if (Math.abs(rounded - Math.round(rounded)) < 1e-9) return String(Math.round(rounded))
  return String(rounded)
}

function quote(s) {
  return '"' + String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"'
}

function luaValue(value) {
  if (typeof value === "boolean") return value ? "true" : "false"
  if (typeof value === "number") return num(value, 4)
  return quote(value)
}

function isSynthetic(key) {
  return SYNTHETIC_KEYS.indexOf(key) !== -1
}

// ------------------------------------------------------------ hl.config

function nest(overrides) {
  var tree = {}
  for (var key in overrides) {
    if (isSynthetic(key)) continue
    var parts = key.split(":")
    var node = tree
    for (var i = 0; i < parts.length - 1; i++) {
      if (!node[parts[i]] || typeof node[parts[i]] !== "object") node[parts[i]] = {}
      node = node[parts[i]]
    }
    node[parts[parts.length - 1]] = overrides[key]
  }
  return tree
}

function isPlainObject(v) {
  return v !== null && typeof v === "object" && !Array.isArray(v)
}

// Scalars first, then nested tables — the shape Omarchy's own looknfeel.lua uses.
function renderTable(node, indent) {
  var pad = new Array(indent + 1).join(" ")
  var inner = new Array(indent + 3).join(" ")
  var keys = Object.keys(node).sort()
  var lines = []
  for (var i = 0; i < keys.length; i++)
    if (!isPlainObject(node[keys[i]]))
      lines.push(inner + keys[i] + " = " + luaValue(node[keys[i]]) + ",")
  for (var j = 0; j < keys.length; j++) {
    if (!isPlainObject(node[keys[j]])) continue
    if (lines.length > 0) lines.push("")
    lines.push(inner + keys[j] + " = " + renderTable(node[keys[j]], indent + 2).replace(/^\s+/, "") + ",")
  }
  return pad + "{\n" + lines.join("\n") + "\n" + pad + "}"
}

function renderConfig(overrides) {
  var tree = nest(overrides)
  if (Object.keys(tree).length === 0) return ""
  return "hl.config(" + renderTable(tree, 0) + ")"
}

// -------------------------------------------------- curves and animations

function emptyLeaf() {
  return { enabled: true, speed: 1, bezier: "default", style: "" }
}

function cloneLeaf(v) {
  return { enabled: v.enabled !== false, speed: Number(v.speed), bezier: String(v.bezier || ""), style: String(v.style || "") }
}

function cloneCurve(p) {
  return [Number(p[0]), Number(p[1]), Number(p[2]), Number(p[3])]
}

function sameLeaf(a, b) {
  if (!a || !b) return false
  if ((a.enabled !== false) !== (b.enabled !== false)) return false
  // A disabled leaf carries no other meaningful field.
  if (a.enabled === false) return true
  return Math.abs(Number(a.speed) - Number(b.speed)) < 1e-6
    && String(a.bezier || "") === String(b.bezier || "")
    && String(a.style || "") === String(b.style || "")
}

function sameCurve(a, b) {
  if (!a || !b) return false
  for (var i = 0; i < 4; i++)
    if (Math.abs(Number(a[i]) - Number(b[i])) > 1e-6) return false
  return true
}

function cloneLeafMap(map) {
  var out = {}
  for (var k in map) out[k] = cloneLeaf(map[k])
  return out
}

function cloneCurveMap(map) {
  var out = {}
  for (var k in map) out[k] = cloneCurve(map[k])
  return out
}

function cloneOverrides(map) {
  var out = {}
  for (var k in map) out[k] = map[k]
  return out
}

function renderCurve(name, points) {
  return "hl.curve(" + quote(name) + ", { type = \"bezier\", points = { { "
    + num(points[0], 3) + ", " + num(points[1], 3) + " }, { "
    + num(points[2], 3) + ", " + num(points[3], 3) + " } } })"
}

function renderLeaf(name, value) {
  var parts = ["leaf = " + quote(name), "enabled = " + (value.enabled !== false ? "true" : "false")]
  if (value.enabled !== false) {
    parts.push("speed = " + num(value.speed, 2))
    if (value.bezier) parts.push("bezier = " + quote(value.bezier))
    if (value.style) parts.push("style = " + quote(value.style))
  }
  return "hl.animation({ " + parts.join(", ") + " })"
}

function renderAnimationLines(curves, curveOrder, leaves, leafOrder) {
  var lines = []
  for (var i = 0; i < curveOrder.length; i++)
    if (curves[curveOrder[i]]) lines.push(renderCurve(curveOrder[i], curves[curveOrder[i]]))
  if (lines.length > 0 && leafOrder.length > 0) lines.push("")
  for (var j = 0; j < leafOrder.length; j++)
    if (leaves[leafOrder[j]]) lines.push(renderLeaf(leafOrder[j], leaves[leafOrder[j]]))
  return lines.join("\n")
}

function diffedAnimations(draftCurves, draftLeaves, baseCurves, baseLeaves) {
  var curves = {}, curveOrder = []
  for (var c in draftCurves) {
    if (baseCurves[c] && sameCurve(draftCurves[c], baseCurves[c])) continue
    curves[c] = draftCurves[c]
    curveOrder.push(c)
  }
  curveOrder.sort()

  var leaves = {}, leafOrder = []
  for (var l in draftLeaves) {
    if (baseLeaves[l] && sameLeaf(draftLeaves[l], baseLeaves[l])) continue
    leaves[l] = draftLeaves[l]
    leafOrder.push(l)
  }
  leafOrder.sort()

  return renderAnimationLines(curves, curveOrder, leaves, leafOrder)
}

function allAnimations(draftCurves, draftLeaves, baseCurves, baseLeaves) {
  var curves = {}, curveOrder = []
  var c
  for (c in baseCurves) { curves[c] = baseCurves[c]; curveOrder.push(c) }
  for (c in draftCurves) {
    if (!curves[c]) curveOrder.push(c)
    curves[c] = draftCurves[c]
  }
  curveOrder.sort()

  var leaves = {}, leafOrder = []
  var l
  for (l in baseLeaves) { leaves[l] = baseLeaves[l]; leafOrder.push(l) }
  for (l in draftLeaves) {
    if (!leaves[l]) leafOrder.push(l)
    leaves[l] = draftLeaves[l]
  }
  leafOrder.sort()

  return renderAnimationLines(curves, curveOrder, leaves, leafOrder)
}

// ------------------------------------------------------------- bodies

function join(chunks) {
  var kept = []
  for (var i = 0; i < chunks.length; i++) if (chunks[i]) kept.push(chunks[i])
  return kept.join("\n\n")
}

function renderLooknfeelBody(overrides, draftCurves, draftLeaves, baseCurves, baseLeaves) {
  return join([renderConfig(overrides),
               diffedAnimations(draftCurves, draftLeaves, baseCurves, baseLeaves)])
}

function renderPreviewBody(overrides, draftCurves, draftLeaves, baseCurves, baseLeaves) {
  return join([renderConfig(overrides),
               allAnimations(draftCurves, draftLeaves, baseCurves, baseLeaves)])
}

// Re-applies Omarchy's blanket opacity rule at 1.0. Registered after
// default/hypr/windows.lua, so it wins; the decoration:*_opacity globals still
// multiply on top, which is what keeps the opacity sliders meaningful.
function renderWindowsBody(overrides) {
  if (overrides[OPAQUE_WINDOWS_KEY] !== true) return ""
  return 'o.window(".*", { opacity = "1 1" })'
}

function renderBlock(body) {
  var header = BEGIN_FENCE + "\n"
    + "-- Written by Lacquer. Safe to hand-edit: Lacquer re-reads this block\n"
    + "-- every time it opens, and only ever rewrites what's between the fences.\n"
  if (!body) return header + END_FENCE
  return header + body + "\n" + END_FENCE
}

// ------------------------------------------------------------------ parsing

// read.lua runs a chunk against recording stubs and prints one tab-separated
// record per line. Turning that into state is a split, not a parser.
//
//   k  <key:path>  <type>  <value>
//   a  <leaf>  <enabled>  <speed>  <bezier>  <style>
//   c  <name>  <x0>  <y0>  <x1>  <y1>
//   w  <opacity>
// The block is documented as safe to hand-edit, so it can carry a value Lua
// accepts but arithmetic does not — `speed = "fast"`. Coercing at the parse
// boundary keeps every number downstream real: without it a bad speed was
// silently rewritten as 0 (an instant animation) on the next unrelated save,
// and a NaN inside a curve made sameCurve() false forever, so the curve
// showed as modified no matter what.
function finite(raw, fallback) {
  if (raw === "" || raw === undefined) return fallback
  var n = Number(raw)
  return isFinite(n) ? n : fallback
}

function parseHarness(stdout) {
  var result = { overrides: {}, leaves: {}, curves: {}, opaque: false }
  var lines = String(stdout || "").split("\n")

  for (var i = 0; i < lines.length; i++) {
    var f = lines[i].split("\t")
    if (f[0] === "k" && f.length >= 4) {
      result.overrides[f[1]] = f[2] === "number" ? Number(f[3])
        : f[2] === "boolean" ? f[3] === "true"
        : f[3]
    } else if (f[0] === "a" && f.length >= 6 && f[1] !== "") {
      result.leaves[f[1]] = {
        enabled: f[2] === "true",
        speed: finite(f[3], 1),
        bezier: f[4],
        style: f[5]
      }
    } else if (f[0] === "c" && f.length >= 6 && f[1] !== "") {
      result.curves[f[1]] = [finite(f[2], 0), finite(f[3], 0), finite(f[4], 1), finite(f[5], 1)]
    } else if (f[0] === "w") {
      result.opaque = true
    }
  }
  return result
}

// ------------------------------------------------------------------ splice

function splitFences(text, beginFence, endFence) {
  var source = String(text || "")
  var begin = source.indexOf(beginFence)
  if (begin === -1) return { found: false, before: source, body: "", after: "" }
  var endAt = source.indexOf(endFence, begin)
  if (endAt === -1) return { found: false, before: source, body: "", after: "" }
  return {
    found: true,
    before: source.substring(0, begin),
    body: source.substring(begin + beginFence.length, endAt),
    after: source.substring(endAt + endFence.length)
  }
}

function splitBlock(text) {
  return splitFences(text, BEGIN_FENCE, END_FENCE)
}

function stripSplit(split) {
  var joined = split.before.replace(/\n+$/, "\n") + split.after.replace(/^\n+/, "")
  return joined.replace(/\n{3,}$/, "\n")
}

// An empty body removes the block rather than leaving an empty husk.
function applyFences(text, body, beginFence, endFence, header) {
  var split = splitFences(text, beginFence, endFence)

  if (!body) {
    if (!split.found) return String(text || "")
    return stripSplit(split)
  }

  var block = header
  if (split.found) return split.before + block + split.after

  var head = String(text || "")
  if (head.length > 0 && head.charAt(head.length - 1) !== "\n") head += "\n"
  return head + "\n" + block + "\n"
}

function applyBlock(text, body) {
  return applyFences(text, body, BEGIN_FENCE, END_FENCE, renderBlock(body))
}

// Removes a legacy tool's block entirely, leaving the rest of the file alone.
function removeFences(text, beginFence, endFence) {
  var split = splitFences(text, beginFence, endFence)
  if (!split.found) return String(text || "")
  return stripSplit(split)
}
