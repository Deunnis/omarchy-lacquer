import QtQuick
import Quickshell
import "stores"

// Installs the launcher entry, so the panel is reachable from SUPER+SPACE
// without the user wiring up a keybind first. Omarchy has no install hook and
// no manifest field for registering one, so it happens here instead.
//
// Only a file carrying the X-Lacquer-Managed marker is ever written or
// deleted: if something else already owns that path, it is left alone.
QtObject {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null

  // The theme shuffle runs here rather than in the panel: the panel only exists
  // once it has been opened, and a shuffle has to act on boot and at sunset
  // whether or not anyone opens Lacquer.
  readonly property ShuffleEngine shuffle: ShuffleEngine { }

  // 4.0.3 strips __sourceDir from every third-party manifest
  // (shell.qml publicPluginManifest), so the plugin's own directory has to come
  // from the QML file's own URL rather than from the host.
  readonly property string pluginDir: {
    var url = String(Qt.resolvedUrl("."))
    if (url.indexOf("file://") === 0) url = url.substring(7)
    return decodeURIComponent(url).replace(/\/+$/, "")
  }

  readonly property string dest: Quickshell.env("HOME") + "/.local/share/applications/lacquer.desktop"
  readonly property string marker: "^X-Lacquer-Managed=true$"

  readonly property string installScript:
      '[ -f "$1" ] || exit 0\n'
    + 'if [ -e "$2" ] && ! grep -q "$3" "$2"; then exit 0; fi\n'
    + 'mkdir -p "${2%/*}" || exit 0\n'
    + 'tmp=$2.lacquer.new\n'
    + 'sed "s|@ICON@|$4|" "$1" > "$tmp" || exit 0\n'
    + 'if cmp -s "$tmp" "$2"; then rm -f "$tmp"; else mv -f "$tmp" "$2"; fi\n'

  // Same ownership rule as the launcher entry, copied verbatim.
  readonly property string hookScript:
      'mkdir -p "$4"\n'
    + '[ -f "$1" ] || exit 0\n'
    + 'if [ -e "$2" ] && ! grep -q "$3" "$2"; then exit 0; fi\n'
    + 'mkdir -p "${2%/*}" || exit 0\n'
    + 'if cmp -s "$1" "$2"; then exit 0; fi\n'
    + 'cp -f "$1" "$2.lacquer.new" && mv -f "$2.lacquer.new" "$2"\n'

  readonly property string removeScript:
    'grep -q "$2" "$1" 2>/dev/null && rm -f "$1"\n'

  property bool installed: false

  // Pinned GTK, colour-scheme and icon choices are put back after every theme
  // switch by a hook, so they hold even while Lacquer is closed. The hook
  // removes itself if Lacquer is ever uninstalled.
  readonly property string hookDest: Quickshell.env("HOME") + "/.config/omarchy/hooks/theme-set.d/lacquer-reapply"
  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy/io.github.deunnis.lacquer"

  // Setting a monospace font restarts the shell. The panel leaves a marker
  // naming its section; a fresh one reopens Lacquer right where it was.
  readonly property string reopenScript:
      'f=$1; [ -f "$f" ] || exit 0\n'
    + 'age=$(( $(date +%s) - $(stat -c %Y "$f") ))\n'
    + 'sec=$(head -c 40 "$f" | tr -cd "a-z-")\n'
    + 'rm -f "$f"\n'
    + '[ "$age" -lt 120 ] && [ -n "$sec" ] || exit 0\n'
    + 'for i in 1 2 3 4 5 6 7 8 9 10; do\n'
    + '  sleep 1\n'
    + '  [ "$(omarchy-shell shell summon io.github.deunnis.lacquer "{\\"section\\":\\"$sec\\"}" 2>/dev/null)" = ok ] && exit 0\n'
    + 'done\n'

  // Installing on completion rather than on a manifest signal: the directory
  // no longer comes from the host, so there is nothing to wait for.
  Component.onCompleted: {
    installed = true
    Quickshell.execDetached(["sh", "-c", installScript, "sh",
                             pluginDir + "/lacquer.desktop", dest, marker, pluginDir + "/icon.png"])
    Quickshell.execDetached(["sh", "-c", hookScript, "sh",
                             pluginDir + "/lacquer-reapply.hook", hookDest, marker, stateDir])
    Quickshell.execDetached(["sh", "-c", reopenScript, "sh", stateDir + "/reopen"])
  }

  // Reached on disable and on remove alike: omarchy-plugin-remove disables
  // first, so the service is torn down while the entry is still ours.
  Component.onDestruction: {
    if (!installed) return
    Quickshell.execDetached(["sh", "-c", removeScript, "sh", dest, marker])
  }
}
