.pragma library

// The catalogue of Hyprland animation leaves Omanimate exposes, grouped the
// way Hyprland's own animation tree is shaped.
//
// A leaf Omarchy does not ship a value for inherits from its parent. Hyprland
// reports those as "not overridden" rather than resolving them, so Omanimate
// shows them as inherited and materialises them from the parent's effective
// values the moment you touch one — there is no honest number to show first.
//
// `styles` are curated strings rather than a parsed grammar: Hyprland's style
// field is free-form per family, and a dropdown of the ones that exist beats
// a text box that accepts typos.

var NO_STYLE = []

var WINDOW_STYLES = [
  { value: "", label: "None" },
  { value: "popin", label: "Pop in" },
  { value: "popin 50%", label: "Pop in 50%" },
  { value: "popin 70%", label: "Pop in 70%" },
  { value: "popin 87%", label: "Pop in 87%" },
  { value: "slide", label: "Slide" },
  { value: "slide left", label: "Slide left" },
  { value: "slide right", label: "Slide right" },
  { value: "slide top", label: "Slide top" },
  { value: "slide bottom", label: "Slide bottom" },
  { value: "gnomed", label: "Gnomed" }
]

var LAYER_STYLES = [
  { value: "", label: "None" },
  { value: "fade", label: "Fade" },
  { value: "slide", label: "Slide" },
  { value: "popin", label: "Pop in" },
  { value: "popin 80%", label: "Pop in 80%" }
]

var WORKSPACE_STYLES = [
  { value: "", label: "None" },
  { value: "slide", label: "Slide" },
  { value: "slidevert", label: "Slide vertical" },
  { value: "fade", label: "Fade" },
  { value: "slidefade", label: "Slide + fade" },
  { value: "slidefade 20%", label: "Slide + fade 20%" },
  { value: "slidefadevert", label: "Slide + fade vertical" },
  { value: "slidefadevert 20%", label: "Slide + fade vert 20%" }
]

var ANGLE_STYLES = [
  { value: "", label: "None" },
  { value: "once", label: "Once" },
  { value: "loop", label: "Loop" }
]

function leaf(name, label, description, parent, styles) {
  return {
    name: name,
    label: label,
    description: description || "",
    parent: parent || "",
    styles: styles || NO_STYLE
  }
}

var SECTIONS = [
  {
    id: "windows",
    icon: "󰆏",
    title: "Windows",
    blurb: "Opening, closing and moving tiled or floating windows.",
    leaves: [
      leaf("windows", "Windows", "Parent of the three below. Setting it sets any leaf you have not overridden.", "global", WINDOW_STYLES),
      leaf("windowsIn", "Window opens", "A window appearing.", "windows", WINDOW_STYLES),
      leaf("windowsOut", "Window closes", "A window disappearing.", "windows", WINDOW_STYLES),
      leaf("windowsMove", "Window moves", "Moving or resizing, including retiling after a close.", "windows", WINDOW_STYLES)
    ]
  },
  {
    id: "layers",
    icon: "󰓪",
    title: "Layers",
    blurb: "Layer surfaces — the bar, menus, notifications and the launcher.",
    leaves: [
      leaf("layers", "Layers", "Parent of the two below.", "global", LAYER_STYLES),
      leaf("layersIn", "Layer opens", "A layer surface appearing, such as the Omarchy menu.", "layers", LAYER_STYLES),
      leaf("layersOut", "Layer closes", "A layer surface disappearing.", "layers", LAYER_STYLES)
    ]
  },
  {
    id: "fade",
    icon: "󰶉",
    title: "Fade",
    blurb: "Opacity transitions. These run alongside the movement animations.",
    leaves: [
      leaf("fade", "Fade", "Parent of every fade below.", "global", NO_STYLE),
      leaf("fadeIn", "Fade in", "A window fading up as it opens.", "fade", NO_STYLE),
      leaf("fadeOut", "Fade out", "A window fading down as it closes.", "fade", NO_STYLE),
      leaf("fadeSwitch", "Focus switch", "Cross-fade when focus moves between windows.", "fade", NO_STYLE),
      leaf("fadeShadow", "Shadow", "Drop shadow fading with focus.", "fade", NO_STYLE),
      leaf("fadeDim", "Dim", "The inactive-window dim fading in and out.", "fade", NO_STYLE),
      leaf("fadeLayers", "Layers", "Parent of the two below.", "fade", NO_STYLE),
      leaf("fadeLayersIn", "Layer fade in", "A layer surface fading up.", "fadeLayers", NO_STYLE),
      leaf("fadeLayersOut", "Layer fade out", "A layer surface fading down.", "fadeLayers", NO_STYLE),
      leaf("fadePopups", "Popups", "Parent of the two below.", "fade", NO_STYLE),
      leaf("fadePopupsIn", "Popup fade in", "An xdg popup fading up.", "fadePopups", NO_STYLE),
      leaf("fadePopupsOut", "Popup fade out", "An xdg popup fading down.", "fadePopups", NO_STYLE),
      leaf("fadeDpms", "Screen wake", "Fading the output back after DPMS blanks it.", "fade", NO_STYLE)
    ]
  },
  {
    id: "workspaces",
    icon: "󰕰",
    title: "Workspaces",
    blurb: "Switching workspaces, and the special (scratchpad) workspace.",
    leaves: [
      leaf("workspaces", "Workspaces", "Parent of the two below. Off in stock Omarchy.", "global", WORKSPACE_STYLES),
      leaf("workspacesIn", "Workspace enters", "The workspace being switched to.", "workspaces", WORKSPACE_STYLES),
      leaf("workspacesOut", "Workspace leaves", "The workspace being switched away from.", "workspaces", WORKSPACE_STYLES),
      leaf("specialWorkspace", "Special workspace", "Parent of the two below.", "workspaces", WORKSPACE_STYLES),
      leaf("specialWorkspaceIn", "Special enters", "The scratchpad sliding in.", "specialWorkspace", WORKSPACE_STYLES),
      leaf("specialWorkspaceOut", "Special leaves", "The scratchpad sliding out.", "specialWorkspace", WORKSPACE_STYLES)
    ]
  },
  {
    id: "borders",
    icon: "󰝤",
    title: "Borders",
    blurb: "Border colour transitions. The colours themselves come from your theme.",
    leaves: [
      leaf("border", "Border colour", "Border easing between focused and unfocused.", "global", NO_STYLE),
      leaf("borderangle", "Gradient angle", "Rotation of a gradient border. Loop makes it spin forever.", "global", ANGLE_STYLES),
      leaf("glowangle", "Glow angle", "Rotation of a gradient glow.", "global", ANGLE_STYLES),
      leaf("shadowangle", "Shadow angle", "Rotation of a gradient shadow.", "global", ANGLE_STYLES)
    ]
  },
  {
    id: "global",
    icon: "󱐋",
    title: "Global",
    blurb: "The root of the tree, and the leaves that hang off it directly.",
    leaves: [
      leaf("global", "Global", "Turning this off disables every animation at once.", "", NO_STYLE),
      leaf("zoomFactor", "Zoom", "The compositor zoom easing.", "global", NO_STYLE),
      leaf("monitorAdded", "Monitor added", "A display being plugged in.", "global", NO_STYLE)
    ]
  }
]

var CURVES_SECTION = { id: "curves", icon: "󰓅", title: "Curves", blurb: "Named bezier curves. Drag either handle; every leaf using the curve follows." }

function sectionFor(id) {
  for (var i = 0; i < SECTIONS.length; i++)
    if (SECTIONS[i].id === id) return SECTIONS[i]
  return null
}

function leafFor(name) {
  for (var i = 0; i < SECTIONS.length; i++)
    for (var j = 0; j < SECTIONS[i].leaves.length; j++)
      if (SECTIONS[i].leaves[j].name === name) return SECTIONS[i].leaves[j]
  return null
}

// Speed is a duration in deciseconds, so a bigger number is a slower
// animation. 0.1 ds (10 ms) is instant; 20 ds (2 s) is glacial.
var SPEED_MIN = 0.1
var SPEED_MAX = 12
var SPEED_STEP = 0.01
