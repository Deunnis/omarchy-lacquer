.pragma library

// The catalogue of Hyprland look-and-feel options Lacquer exposes.
//
// Adapted from Omaland's Schema.js (MIT, Copyright (c) 2026 Bobby Nicholas —
// https://github.com/bobby-nicholas/omaland). Changes here: options are
// grouped under headings inside each section rather than one flat list, and
// Omaland's animation-speed multiplier is gone because Lacquer edits every
// animation leaf directly instead.
//
// Colors are absent on purpose. Omarchy themes own general:col:* via
// ~/.local/state/omarchy/current/theme/hyprland.lua, which loads *before*
// hypr/looknfeel.lua, so writing colors here would pin them and break
// `omarchy theme set` and the theme tools built on it.
//
// Item fields: key (hyprctl path), type, min/max/step, unit, and needs (key of
// a bool that must be on for the row to be live). Slider bounds are
// comfortable ranges, not Hyprland's limits — the row widens a track when the
// live value sits outside it.

function path(key) {
  return key.split(":")
}

function item(key, label, description, type, extra) {
  var o = {
    key: key,
    lua: path(key),
    label: label,
    description: description || "",
    type: type
  }
  for (var k in extra) o[k] = extra[k]
  return o
}

function group(title, items) {
  return { title: title, items: items }
}

// Synthetic options have no config key of their own. They are backed by the
// Lua they emit, and read back by measuring that Lua.
var OPAQUE_WINDOWS_KEY = "lacquer:opaque_windows"

var SECTIONS = [
  {
    id: "windows",
    icon: "󰆏",
    title: "Windows",
    blurb: "Spacing, borders and how windows are arranged.",
    groups: [
      group("Gaps and borders", [
        item("general:gaps_in", "Inner gaps", "Space between adjacent windows.", "int",
             { min: 0, max: 40, unit: "px" }),
        item("general:gaps_out", "Outer gaps", "Space between windows and the screen edge.", "int",
             { min: 0, max: 80, unit: "px" }),
        item("general:gaps_workspaces", "Workspace gaps", "Extra space between workspaces while they slide.", "int",
             { min: 0, max: 100, unit: "px" }),
        item("general:float_gaps", "Floating gaps", "Gap around floating windows. 0 follows the inner gap.", "int",
             { min: 0, max: 40, unit: "px" }),
        item("general:border_size", "Border width", "Thickness of the window border. Color comes from your theme.", "int",
             { min: 0, max: 12, unit: "px" }),
        item("decoration:border_part_of_window", "Border inside window", "Count the border as part of the window rather than drawing it outside.", "bool")
      ]),
      group("Snapping", [
        item("general:snap:enabled", "Snapping", "Snap floating windows to each other and to screen edges.", "bool"),
        item("general:snap:window_gap", "Snap distance", "How close a floating window gets before it snaps to another.", "int",
             { min: 0, max: 50, unit: "px", needs: "general:snap:enabled" }),
        item("general:snap:monitor_gap", "Snap to edges", "How close a floating window gets before it snaps to a screen edge.", "int",
             { min: 0, max: 50, unit: "px", needs: "general:snap:enabled" })
      ]),
      group("Tiling engine", [
        item("general:layout", "Engine", "Scrolling gives you niri-style side-scrolling columns.", "enum",
             { options: [
                 { value: "dwindle", label: "Dwindle" },
                 { value: "master", label: "Master" },
                 { value: "scrolling", label: "Scrolling" }
               ] }),

        item("dwindle:preserve_split", "Preserve split", "Keep the split direction when a window closes.", "bool",
             { needs: "general:layout", needsValue: "dwindle" }),
        item("dwindle:smart_split", "Smart split", "Pick the split direction from where in the window you drop.", "bool",
             { needs: "general:layout", needsValue: "dwindle" }),
        item("dwindle:force_split", "Split side", "Where a new window lands.", "enum",
             { numeric: true, needs: "general:layout", needsValue: "dwindle",
               options: [
                 { value: 0, label: "Cursor" },
                 { value: 1, label: "Before" },
                 { value: 2, label: "After" }
               ] }),
        item("dwindle:split_width_multiplier", "Split bias", "Above 1.0 favours splitting side by side.", "float",
             { min: 0.5, max: 2.0, step: 0.05, decimals: 2, needs: "general:layout", needsValue: "dwindle" }),
        item("dwindle:default_split_ratio", "Split ratio", "Size of a new split relative to its sibling.", "float",
             { min: 0.5, max: 1.5, step: 0.05, decimals: 2, needs: "general:layout", needsValue: "dwindle" }),

        item("master:mfact", "Master size", "Fraction of the screen the master window takes.", "float",
             { min: 0.1, max: 0.9, step: 0.01, decimals: 2, needs: "general:layout", needsValue: "master" }),
        item("master:orientation", "Master side", "Which edge the master window occupies.", "enum",
             { needs: "general:layout", needsValue: "master",
               options: [
                 { value: "left", label: "Left" },
                 { value: "right", label: "Right" },
                 { value: "top", label: "Top" },
                 { value: "bottom", label: "Bottom" },
                 { value: "center", label: "Center" }
               ] }),
        item("master:new_status", "New windows", "Where a newly opened window goes.", "enum",
             { needs: "general:layout", needsValue: "master",
               options: [
                 { value: "master", label: "Master" },
                 { value: "slave", label: "Slave" },
                 { value: "inherit", label: "Inherit" }
               ] }),

        item("scrolling:column_width", "Column width", "Fraction of the screen one column takes. 0.97 shows one at a time.", "float",
             { min: 0.2, max: 1.0, step: 0.01, decimals: 2, needs: "general:layout", needsValue: "scrolling" }),
        item("scrolling:fullscreen_on_one_column", "Fill on one column", "Let a lone column use the whole screen.", "bool",
             { needs: "general:layout", needsValue: "scrolling" })
      ])
    ]
  },
  {
    id: "decoration",
    icon: "󰝤",
    title: "Decoration",
    blurb: "Corners, transparency and dimming.",
    groups: [
      group("Corners", [
        item("decoration:rounding", "Rounding", "Corner radius. 0 is square. The bar and menus follow this too.", "int",
             { min: 0, max: 30, unit: "px" }),
        item("decoration:rounding_power", "Roundness curve", "2.0 is a circle; higher gets you a squircle.", "float",
             { min: 1.0, max: 10.0, step: 0.1, decimals: 1 })
      ]),
      group("Opacity", [
        // Omarchy tags every window and applies opacity "0.985 0.96" in
        // default/hypr/windows.lua. That rule multiplies with the globals
        // below, so without this switch the sliders top out at 0.985.
        item(OPAQUE_WINDOWS_KEY, "Full opacity", "Cancel Omarchy's blanket window opacity rule so these sliders can reach 1.0.", "bool",
             { synthetic: true, fallback: false }),
        item("decoration:active_opacity", "Focused", "Opacity of the focused window.", "float",
             { min: 0.3, max: 1.0, step: 0.01, decimals: 2 }),
        item("decoration:inactive_opacity", "Unfocused", "Opacity of every other window.", "float",
             { min: 0.3, max: 1.0, step: 0.01, decimals: 2 }),
        item("decoration:fullscreen_opacity", "Fullscreen", "Opacity while a window is fullscreen.", "float",
             { min: 0.3, max: 1.0, step: 0.01, decimals: 2 })
      ]),
      group("Dimming", [
        item("decoration:dim_inactive", "Dim unfocused", "Darken every window except the focused one.", "bool"),
        item("decoration:dim_strength", "Dim strength", "How far unfocused windows are darkened.", "float",
             { min: 0.0, max: 1.0, step: 0.01, decimals: 2, needs: "decoration:dim_inactive" }),
        item("decoration:dim_special", "Special workspace dim", "Dimming applied behind a special workspace.", "float",
             { min: 0.0, max: 1.0, step: 0.01, decimals: 2 }),
        item("decoration:dim_around", "Dim around", "Dimming behind windows using the dimaround window rule.", "float",
             { min: 0.0, max: 1.0, step: 0.01, decimals: 2 }),
        item("decoration:dim_modal", "Dim behind modals", "Darken a window while one of its dialogs is open.", "bool")
      ])
    ]
  },
  {
    id: "effects",
    icon: "󱒛",
    title: "Effects",
    blurb: "Blur, shadow and glow. These cost GPU time.",
    groups: [
      group("Blur", [
        item("decoration:blur:enabled", "Blur", "Master switch for all blur.", "bool"),
        item("decoration:blur:size", "Size", "Blur radius.", "int",
             { min: 1, max: 20, needs: "decoration:blur:enabled" }),
        item("decoration:blur:passes", "Passes", "More passes is smoother and slower. 3 is a good ceiling.", "int",
             { min: 1, max: 5, needs: "decoration:blur:enabled" }),
        item("decoration:blur:noise", "Noise", "Grain mixed into the blur to hide banding.", "float",
             { min: 0.0, max: 0.2, step: 0.005, decimals: 3, needs: "decoration:blur:enabled" }),
        item("decoration:blur:contrast", "Contrast", "Contrast of the blurred image.", "float",
             { min: 0.0, max: 2.0, step: 0.01, decimals: 2, needs: "decoration:blur:enabled" }),
        item("decoration:blur:brightness", "Brightness", "Brightness of the blurred image.", "float",
             { min: 0.0, max: 2.0, step: 0.01, decimals: 2, needs: "decoration:blur:enabled" }),
        item("decoration:blur:vibrancy", "Vibrancy", "Saturation boost for the blurred image.", "float",
             { min: 0.0, max: 1.0, step: 0.01, decimals: 2, needs: "decoration:blur:enabled" }),
        item("decoration:blur:vibrancy_darkness", "Vibrancy darkness", "How much vibrancy applies to dark areas.", "float",
             { min: 0.0, max: 1.0, step: 0.01, decimals: 2, needs: "decoration:blur:enabled" }),
        item("decoration:blur:xray", "X-ray", "Blur the wallpaper instead of the windows underneath.", "bool",
             { needs: "decoration:blur:enabled" }),
        item("decoration:blur:special", "Special workspace", "Blur behind special workspaces.", "bool",
             { needs: "decoration:blur:enabled" }),
        item("decoration:blur:popups", "Popups", "Blur behind menus and tooltips.", "bool",
             { needs: "decoration:blur:enabled" })
      ]),
      group("Shadow", [
        item("decoration:shadow:enabled", "Shadow", "Master switch for window shadows.", "bool"),
        item("decoration:shadow:range", "Range", "How far the shadow reaches.", "int",
             { min: 0, max: 50, unit: "px", needs: "decoration:shadow:enabled" }),
        item("decoration:shadow:render_power", "Falloff", "How sharply the shadow fades out.", "int",
             { min: 1, max: 4, needs: "decoration:shadow:enabled" }),
        item("decoration:shadow:scale", "Scale", "Size of the shadow relative to the window.", "float",
             { min: 0.0, max: 1.0, step: 0.01, decimals: 2, needs: "decoration:shadow:enabled" }),
        item("decoration:shadow:sharp", "Sharp", "Hard-edged shadow with no gradient.", "bool",
             { needs: "decoration:shadow:enabled" })
      ]),
      group("Glow", [
        item("decoration:glow:enabled", "Glow", "Halo around the focused window. Its color is a separate Hyprland option.", "bool"),
        item("decoration:glow:range", "Range", "How far the glow reaches.", "int",
             { min: 0, max: 50, unit: "px", needs: "decoration:glow:enabled" }),
        item("decoration:glow:render_power", "Falloff", "How sharply the glow fades out.", "int",
             { min: 1, max: 4, needs: "decoration:glow:enabled" })
      ])
    ]
  },
  {
    id: "groups",
    icon: "󰓪",
    title: "Groups",
    blurb: "The tab bar on grouped windows. Its colors come from your theme.",
    groups: [
      group("Group bar", [
        item("group:groupbar:enabled", "Group bar", "Show the tab strip on grouped windows.", "bool"),
        item("group:groupbar:height", "Height", "Height of the tab strip.", "int",
             { min: 0, max: 40, unit: "px", needs: "group:groupbar:enabled" }),
        item("group:groupbar:font_size", "Font size", "Size of the tab titles.", "int",
             { min: 6, max: 24, unit: "px", needs: "group:groupbar:enabled" }),
        item("group:groupbar:render_titles", "Show titles", "Draw window titles in the tabs.", "bool",
             { needs: "group:groupbar:enabled" }),
        item("group:groupbar:indicator_height", "Indicator height", "Thickness of the active-tab indicator.", "int",
             { min: 0, max: 12, unit: "px", needs: "group:groupbar:enabled" }),
        item("group:groupbar:rounding", "Rounding", "Corner radius of the tabs.", "int",
             { min: 0, max: 20, unit: "px", needs: "group:groupbar:enabled" }),
        item("group:groupbar:gradients", "Gradients", "Fade the tab backgrounds.", "bool",
             { needs: "group:groupbar:enabled" }),
        item("group:groupbar:stacked", "Stacked", "Lay the tabs out vertically.", "bool",
             { needs: "group:groupbar:enabled" }),
        item("group:groupbar:disable_when_only", "Hide when alone", "Hide the strip when the group has one window.", "bool",
             { needs: "group:groupbar:enabled" })
      ])
    ]
  }
]

// Shown at the top of the Animations section, above the per-leaf editor.
var ANIMATION_MASTER = group("Master", [
  item("animations:enabled", "Animations", "Master switch for every animation.", "bool"),
  item("animations:workspace_wraparound", "Wrap workspaces", "Slide the short way between your lowest and highest open workspace. Hyprland only counts workspaces that exist, so with just two open every switch between them wraps and slides the wrong way.", "bool",
       { needs: "animations:enabled" })
])

function allItems() {
  var out = []
  for (var i = 0; i < SECTIONS.length; i++)
    for (var g = 0; g < SECTIONS[i].groups.length; g++)
      for (var j = 0; j < SECTIONS[i].groups[g].items.length; j++)
        out.push(SECTIONS[i].groups[g].items[j])
  for (var m = 0; m < ANIMATION_MASTER.items.length; m++) out.push(ANIMATION_MASTER.items[m])
  return out
}

function itemFor(key) {
  var items = allItems()
  for (var i = 0; i < items.length; i++)
    if (items[i].key === key) return items[i]
  return null
}

// Everything `hyprctl getoption` can answer for, i.e. all but the synthetics.
function queryKeys() {
  var items = allItems()
  var out = []
  for (var i = 0; i < items.length; i++)
    if (!items[i].synthetic) out.push(items[i].key)
  return out
}

function quantize(item, value) {
  // Type dispatch must come first: a numeric guard up top would run Number()
  // on an enum's name, and Number("dwindle") is NaN, which then writes
  // layout = 0. Hyprland accepts a layout named "0" without a config error.
  if (item.type === "bool") return value === true
  if (item.type === "enum") return item.numeric ? Number(value) : String(value)

  var n = Number(value)
  if (!isFinite(n)) return 0
  if (item.type === "int") return Math.round(n)
  var decimals = item.decimals === undefined ? 2 : item.decimals
  var factor = Math.pow(10, decimals)
  return Math.round(n * factor) / factor
}
