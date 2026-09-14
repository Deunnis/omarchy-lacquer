.pragma library

// The catalogue of ~/.config/omarchy/shell.toml options Lacquer exposes.
//
// This file is the whole-shell styling surface and nothing in Omarchy has a UI
// for it. Values here are layered on top of whatever the active theme ships in
// ~/.local/state/omarchy/current/theme/shell.toml, user wins, and the shell
// watches the user file — so every change applies with no restart and survives
// a theme switch.
//
// Which is exactly why colour rows are marked. Pinning a colour here means a
// theme change will no longer move it, and colour belongs to the theme. Structural rows (sizes, widths, alphas, spacing,
// font) carry no such tension and are unmarked.
//
// Key catalogue and defaults come from
// /usr/share/omarchy/default/themed/shell.toml.tpl.

// `fallback` is Omarchy's documented default for the key, from
// /usr/share/omarchy/default/themed/shell.toml.tpl. Many of those keys ship
// commented out, so there is no theme value to read and a row would otherwise
// show its slider minimum — a number that is simply untrue.
function num(section, key, label, description, min, max, step, unit, fallback) {
  return { section: section, key: key, label: label, description: description || "",
           type: "num", min: min, max: max, step: step === undefined ? 1 : step,
           unit: unit || "", fallback: fallback, id: section + "." + key }
}

function alpha(section, key, label, description, fallback) {
  return num(section, key, label, description, 0, 1, 0.01, "", fallback)
}

function bool(section, key, label, description, fallback) {
  return { section: section, key: key, label: label, description: description || "",
           type: "bool", fallback: fallback, id: section + "." + key }
}

// `theme: true` marks a value the active theme would otherwise supply.
function color(section, key, label, description) {
  return { section: section, key: key, label: label, description: description || "",
           type: "color", theme: true, id: section + "." + key }
}

function group(title, items) {
  return { title: title, items: items }
}

// Every surface shares the same shape, so the colour groups are generated
// rather than typed out nine times.
function surface(section, title, extras) {
  var items = [
    color(section, "background", "Background", ""),
    alpha(section, "background-alpha", "Background opacity", ""),
    color(section, "text", "Text", ""),
    color(section, "border", "Border", "A solid color, or a token like hyprland.active-border."),
    alpha(section, "border-alpha", "Border opacity", "")
  ]
  // omamenu's Menu Look transparency, when above 0 %, replaces this opacity.
  if (section === "menu")
    items[1].description = "Menu look's transparency replaces this while it is above 0 %."
  for (var i = 0; i < (extras || []).length; i++) items.push(extras[i])
  return group(title, items)
}

var TABS = [
  {
    id: "text",
    title: "Text",
    blurb: "Font sizes across the whole shell. Base size is the root every other token scales from.",
    groups: [
      group("Size", [
        num("font", "base-size", "Base size", "The root size. `omarchy display text size` writes this too.", 8, 24, 1, "px", 12)
      ]),
      group("Per-token pins", [
        num("font", "caption", "Caption", "Smallest label text.", 6, 30, 1, "px", 10),
        num("font", "body-small", "Body small", "", 6, 30, 1, "px", 11),
        num("font", "body", "Body", "", 6, 30, 1, "px", 12),
        num("font", "subtitle", "Subtitle", "", 6, 34, 1, "px", 13),
        num("font", "title", "Title", "", 6, 34, 1, "px", 14),
        num("font", "heading", "Heading", "", 8, 40, 1, "px", 16),
        num("font", "display", "Display", "", 10, 60, 1, "px", 24),
        num("font", "display-large", "Display large", "", 10, 72, 1, "px", 28),
        num("font", "icon-small", "Icon small", "", 6, 30, 1, "px", 11),
        num("font", "icon", "Icon", "", 6, 34, 1, "px", 14),
        num("font", "icon-large", "Icon large", "", 8, 40, 1, "px", 18)
      ])
    ]
  },
  {
    id: "spacing",
    title: "Spacing",
    blurb: "How tight or airy every panel, row and control is. Scale multiplies every token at once.",
    groups: [
      group("Scale", [
        num("spacing", "scale", "Scale", "Multiplies every spacing token.", 0.5, 2.0, 0.05, "x", 1.0),
        bool("spacing", "scale-with-font", "Scale with font", "Grow spacing when the base font size grows.", true)
      ]),
      group("Tokens", [
        num("spacing", "xxs", "xxs", "", 0, 20, 1, "px", 2),
        num("spacing", "xs", "xs", "", 0, 20, 1, "px", 3),
        num("spacing", "sm", "sm", "", 0, 24, 1, "px", 4),
        num("spacing", "md", "md", "", 0, 28, 1, "px", 6),
        num("spacing", "lg", "lg", "", 0, 32, 1, "px", 8),
        num("spacing", "xl", "xl", "", 0, 36, 1, "px", 10),
        num("spacing", "xxl", "xxl", "", 0, 40, 1, "px", 12),
        num("spacing", "xxxl", "xxxl", "", 0, 48, 1, "px", 14),
        num("spacing", "huge", "huge", "", 0, 64, 1, "px", 18)
      ]),
      group("Controls and rows", [
        num("spacing", "control-gap", "Control gap", "", 0, 32, 1, "px", 8),
        num("spacing", "control-padding-x", "Control padding X", "", 0, 40, 1, "px", 10),
        num("spacing", "control-padding-y", "Control padding Y", "", 0, 32, 1, "px", 6),
        num("spacing", "input-padding-y", "Input padding Y", "", 0, 32, 1, "px", 7),
        num("spacing", "control-height", "Control height", "", 16, 60, 1, "px", 28),
        num("spacing", "popup-row-height", "Popup row height", "", 16, 60, 1, "px", 28),
        num("spacing", "row-gap", "Row gap", "", 0, 32, 1, "px", 8),
        num("spacing", "row-padding-x", "Row padding X", "", 0, 40, 1, "px", 12),
        num("spacing", "label-gap", "Label gap", "", 0, 24, 1, "px", 4)
      ]),
      group("Panels and popups", [
        num("spacing", "panel-gap", "Panel gap", "", 0, 48, 1, "px", 14),
        num("spacing", "panel-padding", "Panel padding", "", 0, 60, 1, "px", 18),
        num("spacing", "popup-padding", "Popup padding", "", 0, 48, 1, "px", 14),
        num("spacing", "dropdown-width", "Dropdown width", "", 120, 480, 5, "px", 240),
        num("spacing", "searchable-dropdown-width", "Searchable width", "", 120, 480, 5, "px", 260),
        num("spacing", "number-field-width", "Number field width", "", 60, 320, 5, "px", 120),
        num("spacing", "searchable-popup-min-height", "Searchable min height", "", 100, 600, 10, "px", 220)
      ])
    ]
  },
  {
    id: "controls",
    title: "Controls",
    blurb: "The chrome every button, switch, slider and field shares, in each of its states.",
    groups: [
      group("Normal", [
        color("controls", "normal-color", "Color", ""),
        alpha("controls", "normal-fill-alpha", "Fill opacity", "", 0.04),
        color("controls", "normal-border", "Border", ""),
        num("controls", "normal-border-width", "Border width", "", 0, 6, 1, "px", 1),
        alpha("controls", "normal-border-alpha", "Border opacity", "", 0.4)
      ]),
      group("Hover", [
        color("controls", "hover-cursor-color", "Color", ""),
        alpha("controls", "hover-cursor-fill-alpha", "Fill opacity", "", 0.08),
        color("controls", "hover-cursor-border", "Border", ""),
        num("controls", "hover-cursor-border-width", "Border width", "", 0, 6, 1, "px", 1),
        alpha("controls", "hover-cursor-border-alpha", "Border opacity", "", 0.25)
      ]),
      group("Focus", [
        color("controls", "focus-color", "Color", ""),
        alpha("controls", "focus-fill-alpha", "Fill opacity", "", 0.08),
        color("controls", "focus-border", "Border", ""),
        num("controls", "focus-border-width", "Border width", "", 0, 6, 1, "px", 1),
        alpha("controls", "focus-border-alpha", "Border opacity", "", 0.25)
      ]),
      group("Selected", [
        color("controls", "selected-color", "Color", ""),
        alpha("controls", "selected-fill-alpha", "Fill opacity", "", 0.18),
        color("controls", "selected-border", "Border", ""),
        num("controls", "selected-border-width", "Border width", "", 0, 6, 1, "px", 0),
        alpha("controls", "selected-border-alpha", "Border opacity", "", 1.0)
      ]),
      group("Other states", [
        alpha("controls", "pressed-fill-alpha", "Pressed fill opacity", "", 0.22),
        alpha("controls", "selection-fill-alpha", "Text selection opacity", "", 0.35)
      ])
    ]
  },
  {
    id: "surfaces",
    title: "Surfaces",
    blurb: "The bar and every overlay. Colors here pin themselves against your theme.",
    groups: [
      group("Bar", [
        color("bar", "background", "Background", ""),
        alpha("bar", "background-alpha", "Background opacity", ""),
        color("bar", "text", "Text", ""),
        color("bar", "active", "Active", "Colour of the active/urgent state."),
        num("bar", "size-horizontal", "Height", "Height of a top or bottom bar.", 16, 72, 1, "px", 26),
        num("bar", "size-vertical", "Width", "Width of a left or right bar.", 16, 96, 1, "px", 28),
        bool("bar", "scale-with-font", "Scale with font", "Grow the bar when the base font size grows.", true)
      ]),
      surface("menu", "Menu", [
        color("menu", "scrim", "Scrim", "The full-screen dim behind the card."),
        alpha("menu", "scrim-alpha", "Scrim opacity", ""),
        color("menu", "selected-background", "Selected row", ""),
        alpha("menu", "selected-background-alpha", "Selected row opacity", ""),
        color("menu", "selected-text", "Selected text", "")
      ]),
      surface("launcher", "Launcher", [
        color("launcher", "scrim", "Scrim", ""),
        alpha("launcher", "scrim-alpha", "Scrim opacity", ""),
        color("launcher", "selected-background", "Selected row", ""),
        alpha("launcher", "selected-background-alpha", "Selected row opacity", ""),
        color("launcher", "selected-text", "Selected text", "")
      ]),
      surface("popups", "Popups", [
        num("popups", "border-width", "Border width", "", 0, 8, 1, "px")
      ]),
      surface("tooltip", "Tooltips", []),
      surface("notifications", "Notifications", [
        num("notifications", "border-width", "Border width", "", 0, 8, 1, "px"),
        color("notifications", "countdown", "Countdown", "")
      ]),
      surface("polkit", "Password prompt", [
        color("polkit", "text-error", "Error text", ""),
        color("polkit", "border-error", "Error border", ""),
        color("polkit", "scrim", "Scrim", ""),
        alpha("polkit", "scrim-alpha", "Scrim opacity", ""),
        color("polkit", "accent", "Accent", "")
      ]),
      surface("lock", "Lock screen", [
        color("lock", "placeholder", "Placeholder", ""),
        color("lock", "text-error", "Error text", ""),
        color("lock", "border-active", "Typing border", ""),
        color("lock", "border-error", "Error border", ""),
        color("lock", "selection", "Selection", ""),
        alpha("lock", "selection-alpha", "Selection opacity", "")
      ]),
      group("Image picker", [
        color("image-picker", "scrim", "Scrim", ""),
        alpha("image-picker", "scrim-alpha", "Scrim opacity", ""),
        color("image-picker", "text", "Text", ""),
        color("image-picker", "selected-border", "Selected border", ""),
        alpha("image-picker", "selected-border-alpha", "Selected border opacity", ""),
        color("image-picker", "unselected-border", "Unselected border", ""),
        alpha("image-picker", "unselected-border-alpha", "Unselected border opacity", "")
      ])
    ]
  }
]

function tabFor(id) {
  for (var i = 0; i < TABS.length; i++)
    if (TABS[i].id === id) return TABS[i]
  return null
}

function allItems() {
  var out = []
  for (var t = 0; t < TABS.length; t++)
    for (var g = 0; g < TABS[t].groups.length; g++)
      for (var i = 0; i < TABS[t].groups[g].items.length; i++)
        out.push(TABS[t].groups[g].items[i])
  return out
}

function quantize(item, value) {
  if (item.type === "bool") return value === true
  if (item.type === "color") return String(value)
  var n = Number(value)
  if (!isFinite(n)) return 0
  var step = item.step === undefined ? 1 : item.step
  if (step >= 1) return Math.round(n)
  var factor = Math.round(1 / step)
  return Math.round(n * factor) / factor
}
