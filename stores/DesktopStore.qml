import QtQuick
import Quickshell
import Quickshell.Io

// Fonts, text size, GTK theme, colour scheme, icons and cursor.
//
// Everything is applied through the tool that already owns it: omarchy's font
// and text-size commands, gsettings, `hyprctl setcursor`. What Omarchy resets
// on every theme switch (GTK theme, colour scheme, icons) is only held when the
// user picks it here: those picks are "pins", kept in pins.json and put back by
// the theme-set hook. Anything not pinned keeps following the theme.
Item {
  id: root
  visible: false

  required property var app

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: home + "/.local/state/omarchy/io.github.deunnis.lacquer"
  readonly property string pinnedKeys: "color-scheme gtk-theme icon-theme"

  property var info: null
  property bool loaded: false
  property var pins: ({})
  property var block: ({ cursor: null, sunset: false })

  // Optimistic values, so a stepper answers at once while its command runs.
  property int textPx: 12
  property real uiSize: 11
  property string confirmMono: ""

  readonly property var gs: info ? info.gsettings : ({})
  readonly property var follows: info ? info.follows : ({})

  function rescan() {
    if (!scanProc.running) scanProc.running = true
    else root.rescanPending = true
    if (!blockProc.running) { blockProc.command = ["timeout", "-k", "1", "10", root.app.pluginDir + "/desktop-block", "print"]; blockProc.running = true }
  }
  property bool rescanPending: false

  function isPinned(key) { return root.pins[key] !== undefined && root.pins[key] !== "" }

  // ---------------------------------------------------------------- pins

  function writePins(next) {
    root.pins = next
    pinsFile.setText(JSON.stringify(next, null, 2) + "\n")
  }

  function pin(key, value) {
    var next = JSON.parse(JSON.stringify(root.pins))
    next[key] = value
    writePins(next)
    run(["gsettings", "set", "org.gnome.desktop.interface", key, value], "Pinned " + value)
  }

  function unpin(key) {
    var next = JSON.parse(JSON.stringify(root.pins))
    delete next[key]
    writePins(next)
    var value = root.follows[key]
    if (value) run(["gsettings", "set", "org.gnome.desktop.interface", key, value], "Following the theme again")
  }

  // ---------------------------------------------------------------- fonts & text

  function stepTextSize(delta) {
    var next = Math.max(9, Math.min(20, root.textPx + delta))
    if (next === root.textPx) return
    root.textPx = next
    textTimer.restart()
  }

  function resetTextSize() {
    textTimer.stop()
    root.textPx = 12
    run(["omarchy-display-text-size", "reset"], "Text size reset")
  }

  // Omarchy's font command restarts the shell, which closes this panel, and
  // hard-codes foot back to 9 pt. Foot's own size is put back afterwards with
  // the same substitution `display text size` uses. Re-running text size
  // instead would also re-derive every terminal's size from the px value and
  // flatten a hand-tuned one. A marker asks the service to reopen here.
  // omarchy-font-set's alacritty substitution is greedy (`family = ".*"`), so
  // on a one-line inline table it also eats `, style = "Bold" }`. The file is
  // kept aside and the family replaced inside its quotes only.
  readonly property string monoScript:
      'foot=$HOME/.config/foot/foot.ini\n'
    + 'ala=$HOME/.config/alacritty/alacritty.toml\n'
    + 'pt=$(grep -oP ":size=\\K[0-9.]+" "$foot" 2>/dev/null | head -1)\n'
    + 'keep=""\n'
    + 'if [ -f "$ala" ]; then keep=$(mktemp) && cat "$ala" > "$keep"; fi\n'
    + 'omarchy-font-set "$1" || { [ -n "$keep" ] && rm -f "$keep"; exit 1; }\n'
    + 'if [ -n "$keep" ]; then\n'
    + '  esc=$(printf "%s" "$1" | sed "s/[\\\\\\/&]/\\\\&/g")\n'
    + '  new=$(mktemp) && if sed "s/family = \\"[^\\"]*\\"/family = \\"$esc\\"/g" "$keep" > "$new"; then cat "$new" > "$(realpath "$ala")"; fi\n'
    + '  rm -f "$keep" "$new"\n'
    + 'fi\n'
    + 'if [ -n "$pt" ] && [ -f "$foot" ]; then sed -i -E "s/(:size=)[0-9.]+/\\1$pt/" "$foot"; fi\n'

  function setMonoFont(family) {
    if (!family) return
    if (root.confirmMono !== family) { root.confirmMono = family; return }
    root.confirmMono = ""
    reopenFile.setText("fonts\n")
    Quickshell.execDetached(["bash", "-c", root.monoScript, "lacquer-font", family])
    root.app.statusText = "Setting " + family + " — the shell restarts"
  }

  function setUiFont(family, size) {
    var f = family || (root.info ? root.info.ui.family : "Adwaita Sans")
    var s = Math.max(8, Math.min(20, Math.round(size || root.uiSize)))
    root.uiSize = s
    // Only the font. The text-scaling-factor is left exactly as it is, even
    // though `display text size` quantises it against this point size: re-running
    // that would also reset hand-tuned terminal sizes.
    run(["gsettings", "set", "org.gnome.desktop.interface", "font-name", f + " " + s], "Interface font: " + f + " " + s)
  }

  // ---------------------------------------------------------------- cursor

  // setcursor changes the live cursor and also writes gsettings cursor-theme;
  // the block makes it survive a Hyprland restart.
  function setCursor(theme, size) {
    var t = theme || root.gs["cursor-theme"] || "Adwaita"
    var s = Math.max(16, Math.min(96, Math.round(size || root.gs["cursor-size"] || 24)))
    var live = t === "default" ? (root.info.cursorDefault || "Adwaita") : t
    run(["bash", "-c",
      'hyprctl setcursor "$1" "$2" >/dev/null; '
      + 'gsettings set org.gnome.desktop.interface cursor-theme "$3"; '
      + 'gsettings set org.gnome.desktop.interface cursor-size "$2"; '
      + '"$4" set --cursor "$3" "$2" >/dev/null',
      "lacquer-cursor", live, String(s), t, root.app.pluginDir + "/desktop-block"], "Cursor: " + t + " " + s)
  }

  function resetCursor() {
    var live = (root.info && root.info.cursorDefault) || "Adwaita"
    run(["bash", "-c",
      'hyprctl setcursor "$1" 24 >/dev/null; '
      // Hyprland itself leaves cursor-theme at "default" (not the schema's
      // Adwaita), so that is what "back to default" restores.
      + 'gsettings set org.gnome.desktop.interface cursor-theme default; '
      + 'gsettings set org.gnome.desktop.interface cursor-size 24; '
      + '"$2" set --no-cursor >/dev/null',
      "lacquer-cursor", live, root.app.pluginDir + "/desktop-block"], "Cursor back to the default")
  }

  // ---------------------------------------------------------------- runner

  property var queue: []

  function run(cmd, doneText) {
    var q = root.queue.slice()
    q.push({ cmd: cmd, text: doneText || "" })
    root.queue = q
    pump()
  }

  function pump() {
    if (runProc.running || root.queue.length === 0) return
    var q = root.queue.slice()
    var job = q.shift()
    root.queue = q
    runProc.doneText = job.text
    // Every command gets a deadline, so a stuck tool cannot wedge the queue.
    runProc.command = ["timeout", "-k", "2", "30"].concat(job.cmd)
    runProc.running = true
  }

  Process {
    id: runProc
    property string doneText: ""
    stderr: StdioCollector { id: runErr; waitForEnd: true }
    onExited: function(code) {
      if (code === 0) { if (doneText) root.app.statusText = doneText }
      else root.app.errorText = String(runErr.text || "").trim() || ("Command failed (" + code + ")")
      if (root.queue.length > 0) root.pump()
      else root.rescan()
    }
  }

  Timer {
    id: textTimer
    interval: 450
    onTriggered: root.run(["omarchy-display-text-size", String(root.textPx)], "Text size " + root.textPx + " px")
  }

  Process {
    id: scanProc
    command: ["timeout", "-k", "2", "30", "python3", root.app.pluginDir + "/scan-desktop"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text)
          root.info = parsed
          if (!textTimer.running && parsed.text && parsed.text.px) root.textPx = parsed.text.px
          if (parsed.ui && parsed.ui.size) root.uiSize = parsed.ui.size
          root.loaded = true
        } catch (e) {
          root.app.errorText = "Could not read the desktop settings"
        }
      }
    }
    onExited: if (root.rescanPending) { root.rescanPending = false; running = true }
  }

  Process {
    id: blockProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { try { root.block = JSON.parse(text) } catch (e) { } }
    }
  }

  // Written through FileView, read through the bounded reader.
  FileView {
    id: pinsFile
    path: root.stateDir + "/pins.json"
    preload: false
    printErrors: false
    atomicWrites: true
  }

  Process {
    id: pinsRead
    command: ["timeout", "-k", "1", "5", root.app.pluginDir + "/read-state", root.stateDir + "/pins.json", "16384"]
    running: true
    stdout: StdioCollector { id: pinsOut; waitForEnd: true }
    onExited: function(code) {
      var clean = {}
      if (code === 0) {
        try {
          var parsed = JSON.parse(pinsOut.text)
          var keys = root.pinnedKeys.split(" ")
          for (var i = 0; i < keys.length; i++)
            if (typeof parsed[keys[i]] === "string" && root.validValue(parsed[keys[i]])) clean[keys[i]] = parsed[keys[i]]
        } catch (e) { }
      }
      root.pins = clean
    }
  }

  // A theme or scheme name as gsettings would hold it.
  function validValue(v) { return /^[A-Za-z0-9._+ -]{1,80}$/.test(String(v)) }

  FileView {
    id: reopenFile
    path: root.stateDir + "/reopen"
    printErrors: false
  }
}
