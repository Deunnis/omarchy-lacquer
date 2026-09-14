import QtQuick
import qs.Commons
import qs.Ui

// Fonts & text, GTK & icons, and Cursor: three views over DesktopStore.
Item {
  id: section

  required property var app
  property string kind: "fonts"

  readonly property var store: app.desktop
  readonly property var d: store.info

  function moveBy(dx, dy) { choices.moveBy(dx, dy) }
  function activate() { choices.activate() }
  function clearPin() { choices.clearPin() }
  function focusGroupTitle(title) { return choices.focusGroupTitle(title) }

  readonly property var night: app.night
  readonly property var screens: app.screens
  readonly property var menuLook: app.menuLook
  readonly property var apps: app.apps

  function rescanAll() {
    if (kind === "night") night.rescan()
    else if (kind === "lock" || kind === "screensaver") screens.rescan()
    else if (kind === "menu") menuLook.rescan()
    else if (kind === "terminal" || kind === "btop") apps.rescan()
    else store.rescan()
  }

  onVisibleChanged: if (visible) rescanAll()
  // The three Desktop sections share this one view, so switching between them
  // changes the kind without ever hiding it.
  onKindChanged: if (visible) { rescanAll(); Qt.callLater(choices.reset) }

  function chips(list) {
    return (list || []).map(function(v) { return { value: v, label: v } })
  }

  function followNote(key, what) {
    if (!section.d) return ""
    if (section.store.isPinned(key)) return "Held at " + section.store.pins[key] + " through theme switches. The theme would use " + section.d.follows[key] + "."
    return "Following the theme (" + section.d.follows[key] + "). Pick " + what + " to hold it through theme switches."
  }

  readonly property var fontGroups: !section.d ? [] : [
    {
      id: "text-size", kind: "stepper", title: "Text size",
      note: "One knob for the shell, GTK apps and terminals, the same as `omarchy display text size`."
        + (section.d.text.terminalPt ? " Terminals are at " + section.d.text.terminalPt + " pt now; "
           + section.store.textPx + " px sets them to " + Math.floor(section.store.textPx * 9 / 12 + 0.5) + " pt." : ""),
      value: section.store.textPx, unit: "px",
      step: function(delta) { section.store.stepTextSize(delta) },
      reset: function() { section.store.resetTextSize() }, resetLabel: "Default (12)"
    },
    {
      id: "mono", kind: "chips", title: "Terminal & code font",
      note: section.store.confirmMono !== ""
        ? "Pick " + section.store.confirmMono + " again to set it. The shell restarts to load it, and Lacquer reopens here."
        : "Used by terminals and the shell. Setting one restarts the shell.",
      current: section.d.mono.current,
      options: section.d.mono.list.map(function(f) {
        return { value: f, label: section.store.confirmMono === f ? "Set " + f + "?" : f }
      }),
      pick: function(v) { if (v !== section.d.mono.current) section.store.setMonoFont(v) }
    },
    {
      id: "ui-size", kind: "stepper", title: "Interface font size",
      note: "The GTK interface font, before text size scales it.",
      value: section.store.uiSize, unit: "pt",
      step: function(delta) { section.store.setUiFont("", section.store.uiSize + delta) },
      reset: function() { section.store.setUiFont("", 11) }, resetLabel: "Default (11)"
    },
    {
      id: "ui-font", kind: "fonts", title: "Interface font",
      note: "Used by GTK apps and anything following the desktop font. Currently " + section.d.ui.family + ".",
      current: section.d.ui.family,
      options: section.d.uiFonts.map(function(f) { return { value: f, label: f } }),
      pick: function(v) { section.store.setUiFont(v, section.store.uiSize) }
    }
  ]

  readonly property var gtkGroups: !section.d ? [] : [
    {
      id: "scheme", kind: "chips", title: "Light or dark apps",
      note: section.followNote("color-scheme", "one"),
      current: section.d.gsettings["color-scheme"],
      pinned: section.store.isPinned("color-scheme"),
      unpin: function() { section.store.unpin("color-scheme") },
      options: [{ value: "prefer-light", label: "Light" }, { value: "prefer-dark", label: "Dark" }, { value: "default", label: "No preference" }],
      pick: function(v) { section.store.pin("color-scheme", v) }
    },
    {
      id: "gtk", kind: "chips", title: "GTK theme",
      note: section.followNote("gtk-theme", "one"),
      current: section.d.gsettings["gtk-theme"],
      pinned: section.store.isPinned("gtk-theme"),
      unpin: function() { section.store.unpin("gtk-theme") },
      options: section.chips(section.d.gtkThemes),
      pick: function(v) { section.store.pin("gtk-theme", v) }
    },
    {
      id: "icons", kind: "icons", title: "Icon theme",
      note: section.followNote("icon-theme", "a set"),
      current: section.d.gsettings["icon-theme"],
      pinned: section.store.isPinned("icon-theme"),
      unpin: function() { section.store.unpin("icon-theme") },
      options: section.d.iconThemes.map(function(t) { return { value: t.name, label: t.label, icons: t.icons } }),
      pick: function(v) { section.store.pin("icon-theme", v) }
    }
  ]

  readonly property string cursorTheme: section.d ? section.d.gsettings["cursor-theme"] : ""
  readonly property int cursorSize: section.d ? section.d.gsettings["cursor-size"] : 24
  readonly property var savedCursor: section.store.block ? section.store.block.cursor : null

  readonly property var cursorGroups: !section.d ? [] : [
    {
      id: "cursor-theme", kind: "chips", title: "Cursor theme",
      note: section.savedCursor
        ? "Applied live and saved in ~/.config/hypr/autostart.lua, so it survives a restart. Apps already open may keep the old cursor until relaunched."
        : "Using the system default. Picking one applies it live and saves it in ~/.config/hypr/autostart.lua.",
      current: section.cursorTheme,
      pinned: section.savedCursor !== null,
      pinnedText: section.savedCursor ? "saved: " + section.savedCursor.theme + " " + section.savedCursor.size : "",
      unpinLabel: "Back to default",
      unpin: function() { section.store.resetCursor() },
      options: [{ value: "default", label: "Default (" + (section.d.cursorDefault || "Adwaita") + ")" }]
        .concat(section.chips(section.d.cursorThemes)),
      pick: function(v) { section.store.setCursor(v, section.cursorSize) }
    },
    {
      id: "cursor-size", kind: "chips", title: "Cursor size",
      note: "Hyprland and GTK both follow this.",
      current: section.cursorSize,
      options: [16, 20, 24, 32, 40, 48, 64].map(function(n) { return { value: n, label: String(n) } }),
      pick: function(v) { section.store.setCursor(section.cursorTheme, v) }
    }
  ]

  readonly property var ns: section.night.status
  readonly property var nowTemps: [5500, 5000, 4500, 4000, 3500, 3000]

  readonly property var nightGroups: !section.ns ? [] : [
    {
      id: "now", kind: "chips", title: "Right now",
      note: section.ns.running
        ? "hyprsunset is running" + (section.ns.temperature ? " at " + section.ns.temperature + " K." : ".")
          + (section.night.scheduled ? " The schedule takes over again at its next change." : "")
        : "hyprsunset is not running; picking a warmth starts it.",
      current: section.ns.temperature && section.ns.temperature < 6000 ? section.ns.temperature : "off",
      options: [{ value: "off", label: "Off" }].concat(section.nowTemps.map(function(t) { return { value: t, label: t + " K" } })),
      pick: function(v) { section.night.setNow(v) }
    },
    {
      id: "schedule", kind: "chips", title: "Schedule",
      note: section.night.confirmReplace
        ? "hyprsunset.conf has a hand-written schedule. Pick On again to replace it; the old file is kept as a backup."
        : section.night.custom
          ? "hyprsunset.conf has a hand-written schedule, which Lacquer leaves alone."
          : section.night.scheduled
            ? "A warmer screen every evening. hyprsunset starts with Hyprland"
              + (section.ns.autostartElsewhere ? " (from your own autostart line)." : " (added to autostart.lua by Lacquer).")
            : "Off. hyprsunset.conf is Omarchy's default and nothing starts hyprsunset at login.",
      current: section.night.custom ? "" : (section.night.scheduled ? "on" : "off"),
      options: [{ value: "off", label: "Off" }, { value: "on", label: section.night.confirmReplace ? "Replace it?" : "On" }],
      pick: function(v) { section.night.setScheduled(v === "on") }
    },
    {
      id: "evening", kind: "stepper", title: "Warmer from",
      note: section.night.scheduled ? "" : "Used when the schedule is turned on.",
      value: section.night.evening, unit: "",
      step: function(d) { section.night.shiftTime("evening", d * 30) }
    },
    {
      id: "morning", kind: "stepper", title: "Back to normal at",
      value: section.night.morning, unit: "",
      step: function(d) { section.night.shiftTime("morning", d * 30) }
    },
    {
      id: "warmth", kind: "stepper", title: "Evening warmth",
      note: "Lower is warmer. Omarchy's nightlight toggle uses 4000 K.",
      value: section.night.warmth, unit: "K",
      step: function(d) { section.night.stepWarmth(d) }
    }
  ]

  readonly property var sd: section.screens.info
  readonly property var ls: section.sd ? section.sd.status : null

  function secondsChips(list) {
    return list.map(function(n) { return { value: n, label: n === 0 ? "Never" : section.screens.formatSeconds(n) } })
  }

  readonly property var lockGroups: !section.sd ? [] : !section.sd.lockExplorer ? [
    { id: "missing", kind: "chips", title: "Lock screen",
      note: "lock-explorer is not running, so there is nothing to drive. Lacquer controls the lock and boot screens through it.",
      options: [] }
  ] : [
    {
      id: "design", kind: "chips", title: "Lock design",
      note: (function() {
        for (var i = 0; i < section.sd.designs.length; i++)
          if (section.sd.designs[i].active) return section.sd.designs[i].name + ": " + section.sd.designs[i].description + "."
        return ""
      })(),
      current: section.ls.design,
      options: section.sd.designs.map(function(d) { return { value: d.id, label: d.name } }),
      pick: function(v) { section.screens.setDesign(v) }
    },
    {
      id: "try", kind: "chips", title: "Try it",
      note: "Shows the chosen design full screen without locking. Click to close it.",
      options: [{ value: "preview", label: "Preview lock screen" }, { value: "styling", label: "Open lock-explorer" }, { value: "editor", label: "Design editor" }],
      pick: function(v) { if (v === "preview") section.screens.previewDesign(section.ls.design); else section.screens.openExplorer(v) }
    },
    {
      id: "unlock", kind: "chips", title: "Unlock animation",
      current: section.ls.unlockAnimated ? section.ls.unlock : "none",
      options: ["fade", "zoom", "rise", "none"].map(function(a) { return { value: a, label: a.charAt(0).toUpperCase() + a.slice(1) } }),
      pick: function(v) { section.screens.setUnlockAnimation(v) }
    },
    {
      id: "unlock-ms", kind: "stepper", title: "Unlock length",
      value: section.screens.unlockMs, unit: "ms",
      step: function(d) { section.screens.stepUnlockMs(d) }
    },
    {
      id: "clock", kind: "chips", title: "Clock",
      current: section.sd.clock,
      options: [{ value: "24", label: "24-hour" }, { value: "12", label: "12-hour" }],
      pick: function(v) { section.screens.setClock(v) }
    },
    {
      id: "blank", kind: "stepper", title: "Blank the screen after",
      note: section.ls.keepDisplayOn ? "Ignored while the display is kept on." : "How long the lock screen stays lit with no input.",
      value: section.screens.formatSeconds(section.screens.blankMs / 1000), unit: "",
      step: function(d) { section.screens.stepBlank(d) }
    },
    {
      id: "keep-on", kind: "chips", title: "Keep the display on while locked",
      current: section.ls.keepDisplayOn ? "on" : "off",
      options: [{ value: "off", label: "Off" }, { value: "on", label: "On" }],
      pick: function(v) { section.screens.setKeepDisplayOn(v === "on") }
    },
    {
      id: "lock-after", kind: "chips", title: "Lock after",
      note: "Idle time before the session locks (shell.json).",
      current: section.sd.idle.lock,
      options: section.secondsChips([120, 300, 600, 900, 1800, 3600]),
      pick: function(v) { section.screens.setIdle("lock", v) }
    },
    {
      id: "boot", kind: "cards", title: "Boot screen",
      note: section.ls.bootApplying ? "lock-explorer is rebuilding the boot screen…"
        : section.ls.boot !== (section.ls.bootApplied || "stock")
          ? "Chosen: " + section.ls.boot + ", but the boot screen still shows " + (section.ls.bootApplied || "stock")
            + ". Building it needs your password, so it happens in lock-explorer's Boot tab."
          : "This is what shows while the laptop boots. Choosing only marks it; lock-explorer's Boot tab builds it.",
      current: section.ls.boot,
      options: section.sd.bootCards.map(function(c) {
        return { value: c.id, label: c.name, preview: c.preview,
                 sub: c.id === (section.ls.bootApplied || "stock") ? "applied" : "" }
      }),
      pick: function(v) { section.screens.setBoot(v) }
    },
    {
      id: "boot-apply", kind: "chips", title: "Build the boot screen",
      options: [{ value: "boot", label: "Open the Boot tab to apply" }],
      pick: function(v) { section.screens.openExplorer(v) }
    }
  ]

  readonly property var screensaverGroups: !section.sd ? [] : [
    {
      id: "enabled", kind: "chips", title: "Screensaver",
      current: section.sd.screensaverOff ? "off" : "on",
      options: [{ value: "on", label: "On" }, { value: "off", label: "Off" }],
      pick: function(v) { section.screens.setScreensaverEnabled(v === "on") }
    },
    {
      id: "after", kind: "chips", title: "Start after",
      note: "Idle time before the screensaver starts (shell.json). The lock follows at "
        + section.screens.formatSeconds(section.sd.idle.lock) + ".",
      current: section.sd.idle.screensaver,
      options: section.secondsChips([60, 150, 300, 600, 900, 1800]),
      pick: function(v) { section.screens.setIdle("screensaver", v) }
    },
    {
      id: "ss-art", kind: "art", title: "Screensaver art",
      note: section.sd.screensaver.isDefault ? "The Omarchy logo." : "Your own art, in ~/.config/omarchy/branding/screensaver.txt.",
      art: section.sd.screensaver.text,
      options: [{ value: "preview", label: "Preview" }, { value: "image", label: "From an image…" },
                { value: "text", label: "Edit text" }, { value: "reset", label: "Omarchy logo" }],
      pick: function(v) { section.screens.branding("screensaver", v) }
    },
    {
      id: "about-art", kind: "art", title: "About screen art",
      note: section.sd.about.isDefault ? "The Omarchy icon." : "Your own art, in ~/.config/omarchy/branding/about.txt.",
      art: section.sd.about.text,
      options: [{ value: "preview", label: "Preview" }, { value: "image", label: "From an image…" },
                { value: "text", label: "Edit text" }, { value: "reset", label: "Omarchy icon" }],
      pick: function(v) { section.screens.branding("about", v) }
    }
  ]

  readonly property var ml: section.menuLook.look

  readonly property var menuGroups: !section.menuLook.probed ? [] : !section.menuLook.available ? [
    { id: "missing", kind: "chips", title: "Menu look",
      note: "omamenu is not answering. Menu Look needs io.github.omamenu on its local-look-ipc branch.", options: [] }
  ] : [
    {
      id: "scope", kind: "chips", title: "Applies to",
      note: section.ml.scope === "shared"
        ? "Every theme. To give " + section.ml.theme + " its own look, switch scope in the menu's own Menu Look row."
        : section.ml.theme + " only: this theme has its own override. The menu's Menu Look row can fold it back into the shared look.",
      current: section.ml.scope,
      options: [{ value: section.ml.scope, label: section.ml.scope === "shared" ? "All themes" : "This theme" }],
      pick: function(v) { }
    },
    {
      id: "scale", kind: "stepper", title: "Size",
      value: section.ml.scale.toFixed(2), unit: "×",
      step: function(d) { section.menuLook.step("scale", d) }
    },
    {
      id: "corners", kind: "stepper", title: "Corner radius",
      value: section.ml.cornerRadius < 0 ? "theme" : section.ml.cornerRadius, unit: section.ml.cornerRadius < 0 ? "" : "px",
      step: function(d) { section.menuLook.step("cornerRadius", d) }
    },
    {
      id: "border", kind: "stepper", title: "Border width",
      note: "Shell style's [menu] border-width wins over this when it is set.",
      value: section.ml.borderWidth < 0 ? "theme" : section.ml.borderWidth, unit: section.ml.borderWidth < 0 ? "" : "px",
      step: function(d) { section.menuLook.step("borderWidth", d) }
    },
    {
      id: "transparency", kind: "stepper", title: "Transparency",
      note: "Above 0 %, this replaces Shell style's [menu] background-alpha.",
      value: section.ml.transparency, unit: "%",
      step: function(d) { section.menuLook.step("transparency", d) }
    },
    {
      id: "reset", kind: "chips", title: "Reset",
      options: [{ value: "reset", label: section.ml.scope === "shared" ? "Back to the stock menu look" : "Drop this theme's override" }],
      pick: function(v) { section.menuLook.reset() }
    }
  ]

  readonly property var ai: section.apps.info
  readonly property var tv: section.apps.term

  function onOff(v) { return [{ value: "true", label: "On" }, { value: "false", label: "Off" }] }

  // The next preset above (delta > 0) or below the current value, which may
  // itself be off the list after a hand edit.
  function nextIn(list, current, delta) {
    if (delta > 0) {
      for (var i = 0; i < list.length; i++) if (list[i] > current) return list[i]
      return list[list.length - 1]
    }
    for (var j = list.length - 1; j >= 0; j--) if (list[j] < current) return list[j]
    return list[0]
  }

  readonly property var terminalGroups: !section.ai ? [] : !section.tv ? [
    { id: "none", kind: "chips", title: "Terminals", options: [],
      note: "No installed terminal with a config Lacquer knows (foot, alacritty, kitty, ghostty)." }
  ] : [
    {
      id: "which", kind: "chips", title: "Applies to",
      note: "Every installed terminal gets the same settings. The font and its size live in Fonts & text."
        + (section.ai.terminals.some(function(t) { return t.name === "foot" }) ? " foot shows a change in new windows only." : ""),
      current: "",
      options: section.ai.terminals.map(function(t) {
        return { value: t.name, label: t.name + (String(section.ai["default"]).indexOf(t.name) === 0 ? " (default)" : "") }
      }),
      pick: function(v) { }
    },
    {
      id: "padding", kind: "stepper", title: "Padding",
      value: section.apps.shown("terminal", "padding", section.tv.padding), unit: "px",
      step: function(d) {
        var cur = section.apps.shown("terminal", "padding", section.tv.padding)
        section.apps.stepTo("terminal", "padding", Math.max(0, Math.min(60, cur + d * 2)), "Terminal padding")
      }
    },
    {
      id: "cursor", kind: "chips", title: "Cursor",
      current: section.tv.cursor,
      options: [{ value: "block", label: "Block" }, { value: "beam", label: "Beam" }, { value: "underline", label: "Underline" }],
      pick: function(v) { section.apps.set("terminal", "cursor", v, "Terminal cursor: " + v) }
    },
    {
      id: "blink", kind: "chips", title: "Cursor blink",
      current: section.tv.blink ? "on" : "off",
      options: [{ value: "off", label: "Off" }, { value: "on", label: "On" }],
      pick: function(v) { section.apps.set("terminal", "blink", v, v === "on" ? "Cursor blinks" : "Cursor steady") }
    },
    {
      id: "opacity", kind: "stepper", title: "Background opacity",
      note: "Multiplies with Hyprland's window opacity (Windows › Decoration).",
      value: section.apps.shown("terminal", "opacity", section.tv.opacity), unit: "%",
      step: function(d) {
        var cur = section.apps.shown("terminal", "opacity", section.tv.opacity)
        section.apps.stepTo("terminal", "opacity", Math.max(30, Math.min(100, cur + d * 5)), "Terminal opacity")
      }
    }
  ]

  readonly property var btopGroups: !section.ai ? [] : [].concat(!section.ai.btop ? [] : [
    {
      id: "btop-bg", kind: "chips", title: "btop background",
      note: section.ai.btop.running ? "btop is running and reloads each change at once." : "Its colours always follow the theme.",
      current: section.ai.btop.theme_background,
      options: [{ value: "true", label: "Theme colour" }, { value: "false", label: "Transparent" }],
      pick: function(v) { section.apps.set("btop", "theme_background", v, "btop background") }
    },
    {
      id: "btop-corners", kind: "chips", title: "btop rounded corners",
      current: section.ai.btop.rounded_corners, options: section.onOff(),
      pick: function(v) { section.apps.set("btop", "rounded_corners", v, "btop corners") }
    },
    {
      id: "btop-graph", kind: "chips", title: "btop graphs",
      current: section.ai.btop.graph_symbol,
      options: [{ value: "braille", label: "Braille" }, { value: "block", label: "Block" }, { value: "tty", label: "TTY" }],
      pick: function(v) { section.apps.set("btop", "graph_symbol", v, "btop graphs: " + v) }
    },
    {
      id: "btop-update", kind: "stepper", title: "btop refresh",
      value: section.apps.shown("btop", "update_ms", Number(section.ai.btop.update_ms)), unit: "ms",
      step: function(d) {
        var cur = section.apps.shown("btop", "update_ms", Number(section.ai.btop.update_ms))
        section.apps.stepTo("btop", "update_ms", section.nextIn([250, 500, 1000, 1500, 2000, 3000, 5000, 10000], cur, d), "btop refresh")
      }
    },
    {
      id: "btop-vim", kind: "chips", title: "btop vim keys",
      current: section.ai.btop.vim_keys, options: section.onOff(),
      pick: function(v) { section.apps.set("btop", "vim_keys", v, "btop vim keys") }
    }
  ]).concat(!section.ai.starship ? [] : [
    {
      id: "star-newline", kind: "chips", title: "Blank line before the prompt",
      note: "Starship, the shell prompt. New prompts pick changes up straight away.",
      current: section.ai.starship.add_newline, options: section.onOff(),
      pick: function(v) { section.apps.set("starship", "add_newline", v, "Prompt spacing") }
    },
    {
      id: "star-timeout", kind: "stepper", title: "Prompt command timeout",
      note: "How long a slow prompt module may run before starship skips it.",
      value: section.apps.shown("starship", "command_timeout", Number(section.ai.starship.command_timeout)), unit: "ms",
      step: function(d) {
        var cur = section.apps.shown("starship", "command_timeout", Number(section.ai.starship.command_timeout))
        section.apps.stepTo("starship", "command_timeout", section.nextIn([100, 200, 300, 500, 750, 1000, 2000], cur, d), "Prompt timeout")
      }
    }
  ])

  ChoicePane {
    id: choices
    anchors.fill: parent
    app: section.app
    groups: section.kind === "fonts" ? section.fontGroups
      : section.kind === "gtk" ? section.gtkGroups
      : section.kind === "night" ? section.nightGroups
      : section.kind === "lock" ? section.lockGroups
      : section.kind === "screensaver" ? section.screensaverGroups
      : section.kind === "menu" ? section.menuGroups
      : section.kind === "terminal" ? section.terminalGroups
      : section.kind === "btop" ? section.btopGroups : section.cursorGroups
  }

  Text {
    anchors.centerIn: parent
    visible: section.kind === "night" ? !section.ns
      : (section.kind === "lock" || section.kind === "screensaver") ? !section.sd
      : section.kind === "menu" ? !section.menuLook.probed
      : (section.kind === "terminal" || section.kind === "btop") ? !section.ai : !section.d
    text: "Reading desktop settings…"
    color: Qt.darker(section.app.foreground, 1.5)
    font.family: section.app.fontFamily
    font.pixelSize: Style.font.body
  }
}
