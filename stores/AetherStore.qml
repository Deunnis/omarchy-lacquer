import QtQuick
import Quickshell
import Quickshell.Io

// aether, driven through its own CLI. aether is a separate compiled app, so
// nothing here reimplements it: palettes come from `--extract-palette` (read
// only), themes from `--generate`, saved themes from `--apply-blueprint`, and
// everything else is one click away in aether's own window.
//
// `--generate` is not a preview. It builds an Omarchy theme named `aether`,
// activates it with omarchy-theme-set, sets the wallpaper, and by default also
// writes into Zed, VS Code and Neovim. The section says so and asks twice.
Item {
  id: root
  visible: false

  required property var app

  readonly property string home: Quickshell.env("HOME")

  property string source: ""
  property bool light: false
  property var palette: []
  property string paletteError: ""
  property bool extracting: false
  property bool extractPending: false

  property bool includeZed: true
  property bool includeVscode: true
  property bool includeNeovim: true

  property var blueprints: []
  property bool generating: false
  property string applyingBlueprint: ""
  property bool available: true

  function refresh() {
    if (root.source === "" && root.app.theme.currentWallpaper !== "") root.source = root.app.theme.currentWallpaper
    if (!blueprintsProc.running) blueprintsProc.running = true
    extract()
  }

  function setSource(path) {
    if (!path || path === root.source) return
    root.source = path
    extract()
  }

  function setLight(on) {
    if (root.light === on) return
    root.light = on
    extract()
  }

  function extract() {
    if (root.source === "") return
    if (extractProc.running) { root.extractPending = true; return }
    root.extracting = true
    root.paletteError = ""
    var cmd = ["timeout", "45", "aether", "--extract-palette", root.source, "--json"]
    if (root.light) cmd.splice(4, 0, "--light-mode")
    extractProc.command = cmd
    extractProc.running = true
  }

  function generate() {
    if (root.generating || root.source === "") return
    var cmd = ["aether", "--generate", root.source]
    if (root.light) cmd.push("--light-mode")
    if (!root.includeZed) cmd.push("--no-zed")
    if (!root.includeVscode) cmd.push("--no-vscode")
    if (!root.includeNeovim) cmd.push("--no-neovim")
    root.generating = true
    root.app.errorText = ""
    root.app.statusText = "Generating a theme from the wallpaper…"
    runProc.command = cmd
    runProc.startDetached()
    doneTimeout.restart()
  }

  function applyBlueprint(name) {
    if (root.generating || !name) return
    root.generating = true
    root.applyingBlueprint = name
    root.app.statusText = "Applying blueprint " + name + "…"
    runProc.command = ["aether", "--apply-blueprint", name]
    runProc.startDetached()
    doneTimeout.restart()
  }

  // Omarchy's own image picker (the one its background switcher uses), fed the
  // wallpapers of every installed theme, or the desktop file chooser. Both are
  // other shell surfaces, so this panel closes first; a detached helper waits
  // for the pick and summons Lacquer back on Generate with it.
  readonly property string pickScript:
      'mode=$1; current=$2\n'
    + 'if [ "$mode" = file ]; then\n'
    + '  sel=$(omarchy-file-select --title "Pick an image for aether" --extensions "png jpg jpeg webp" | head -n 1)\n'
    + 'else\n'
    + '  dirs=(); seen=" "\n'
    + '  for d in "$HOME/.config/omarchy/themes"/*/backgrounds "$HOME/.config/omarchy/backgrounds"/* /usr/share/omarchy/themes/*/backgrounds; do\n'
    + '    [ -d "$d" ] || continue\n'
    + '    r=$(readlink -f "$d"); case "$seen" in *" $r "*) continue ;; esac\n'
    + '    seen="$seen$r "; dirs+=("$d")\n'
    + '  done\n'
    // current/theme holds copies, so the picker cannot match the current
    // wallpaper by inode; find the same file name in the listed folders.
    + '  selected=$current; base=${current##*/}\n'
    + '  for d in "${dirs[@]}"; do [ -f "$d/$base" ] && { selected="$d/$base"; break; }; done\n'
    + '  sel=$(omarchy-menu-images --selected "$selected" --filterable --lazy-thumbnails "${dirs[@]}" | head -n 1)\n'
    + 'fi\n'
    + 'if [ -n "$sel" ] && [ -f "$sel" ]; then payload=$(jq -nc --arg s "$sel" \'{section:"generate", aetherSource:$s}\')\n'
    + 'else payload=\'{"section":"generate"}\'; fi\n'
    + 'omarchy-shell shell summon io.github.deunnis.lacquer "$payload" >/dev/null\n'

  function pick(mode) {
    root.app.dismiss()
    Quickshell.execDetached(["bash", "-c", root.pickScript, "lacquer-pick", mode === "file" ? "file" : "wallpapers", root.source])
  }

  // A freshly created panel asks for a source before the wallpaper list has
  // been read; take the current wallpaper as soon as it is known.
  Connections {
    target: root.app.theme
    function onCurrentWallpaperChanged() {
      if (root.source === "" && root.app.theme.currentWallpaper !== "") {
        root.source = root.app.theme.currentWallpaper
        root.extract()
      }
    }
  }

  function openAether() {
    Quickshell.execDetached(["uwsm-app", "--", "aether"])
  }

  function finished(ok) {
    if (!root.generating) return
    root.generating = false
    root.applyingBlueprint = ""
    doneTimeout.stop()
    if (ok) {
      root.app.statusText = "Applied"
      root.app.theme.rescan()
    }
  }

  Process {
    id: extractProc
    stdout: StdioCollector { id: extractOut; waitForEnd: true }
    stderr: StdioCollector { id: extractErr; waitForEnd: true }
    onExited: function(code) {
      root.extracting = false
      try {
        var parsed = JSON.parse(extractOut.text)
        root.palette = Array.isArray(parsed.colors) ? parsed.colors : []
        root.paletteError = parsed.error ? String(parsed.error) : ""
      } catch (e) {
        root.palette = []
        root.paletteError = code === 127 ? "aether is not installed" : "Could not read a palette from this image"
        if (code === 127) root.available = false
      }
      if (root.extractPending) { root.extractPending = false; Qt.callLater(root.extract) }
    }
  }

  Process {
    id: blueprintsProc
    command: ["timeout", "20", "aether", "--list-blueprints", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text)
          root.blueprints = Array.isArray(parsed.blueprints) ? parsed.blueprints : []
        } catch (e) {
          root.blueprints = []
        }
      }
    }
  }

  // Detached, like every caller of omarchy-theme-set here: its background
  // child holds stdout. Completion is read from theme.name instead.
  Process { id: runProc }

  FileView {
    path: root.home + "/.local/state/omarchy/current/theme.name"
    printErrors: false
    watchChanges: true
    onFileChanged: { reload(); root.finished(true) }
  }

  Timer {
    id: doneTimeout
    interval: 45000
    onTriggered: {
      // theme.name is rewritten with the same text when the active theme was
      // already "aether", which may not register as a change. Rescan anyway.
      if (!root.generating) return
      root.finished(true)
    }
  }
}
