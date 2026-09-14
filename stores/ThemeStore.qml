import QtQuick
import Quickshell
import Quickshell.Io

// Omarchy themes and the active theme's wallpapers.
//
// Applying goes through `omarchy theme set`, the same command the menu and
// OmaShuffle use: it retints every themed app, runs the theme-set hook and
// swaps the wallpaper. It is started detached because it leaves a short-lived
// background child holding its stdout, which would otherwise hold the Process
// open. Completion is read from theme.name, which the command rewrites once the
// new theme is in place.
//
// Its browser-policy step needs root, but on this machine sudo grants that one
// command without a password, so no prompt appears.
Item {
  id: root
  visible: false

  required property var app

  readonly property string home: Quickshell.env("HOME")

  property var allThemes: []
  // A theme folder with no colors.toml (an empty `aether`, say) would apply as
  // a broken theme, so it is never offered.
  readonly property var themes: {
    var out = []
    for (var i = 0; i < allThemes.length; i++)
      if (allThemes[i].hasColors) out.push(allThemes[i])
    return out
  }
  property string current: ""
  property var wallpapers: []
  property string currentWallpaper: ""
  property string applyingTheme: ""
  property string applyingWallpaper: ""
  property bool wallsPending: false

  function themeFor(slug) {
    for (var i = 0; i < allThemes.length; i++)
      if (allThemes[i].slug === slug) return allThemes[i]
    return null
  }

  function displayOf(slug) {
    var t = themeFor(slug)
    return t ? t.display : slug
  }

  function rescan() {
    if (!themesProc.running) themesProc.running = true
    themeNameFile.reload()
    scanWallpapers()
  }

  function scanWallpapers() {
    if (wallsProc.running) { root.wallsPending = true; return }
    wallsProc.running = true
  }

  function apply(slug) {
    if (!slug || slug === root.current || root.applyingTheme !== "") return
    var t = themeFor(slug)
    if (!t || !t.hasColors) return
    root.applyingTheme = slug
    root.app.errorText = ""
    root.app.statusText = "Applying " + t.display + "…"
    // With the shuffle live, a pick goes through it: that records the pick in
    // the history and pauses Day & Night until its next boundary, exactly as a
    // pick in OmaShuffle's own grid did.
    var engine = root.app.shuffle
    if (engine && engine.active) {
      if (!engine.applyTheme(slug, false)) { root.applyingTheme = ""; return }
    } else {
      applyProc.command = ["omarchy", "theme", "set", slug]
      applyProc.startDetached()
    }
    applyTimeout.restart()
  }

  function setWallpaper(path) {
    if (!path || path === root.currentWallpaper || bgProc.running) return
    root.applyingWallpaper = path
    bgProc.command = ["omarchy", "theme", "bg", "set", path]
    bgProc.running = true
  }

  function noteCurrent(text) {
    var name = String(text || "").trim()
    if (name === "") return
    root.current = name
    if (root.applyingTheme !== "" && name === root.applyingTheme) {
      root.applyingTheme = ""
      applyTimeout.stop()
      root.app.statusText = "Applied " + displayOf(name)
    }
    // The wallpaper symlink is swapped a moment after theme.name is written.
    wallsDelay.restart()
  }

  Process {
    id: themesProc
    command: ["python3", root.app.pluginDir + "/scan-themes"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text)
          root.allThemes = Array.isArray(parsed) ? parsed : []
        } catch (e) {
          root.app.errorText = "Could not read installed themes"
        }
      }
    }
  }

  Process {
    id: wallsProc
    command: ["python3", root.app.pluginDir + "/scan-wallpapers"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text)
          root.wallpapers = Array.isArray(parsed.wallpapers) ? parsed.wallpapers : []
          root.currentWallpaper = String(parsed.current || "")
        } catch (e) {
          root.wallpapers = []
        }
      }
    }
    onExited: {
      if (!root.wallsPending) return
      root.wallsPending = false
      Qt.callLater(root.scanWallpapers)
    }
  }

  Process { id: applyProc }

  Process {
    id: bgProc
    onExited: function(code) {
      root.applyingWallpaper = ""
      if (code !== 0) root.app.errorText = "Could not set the wallpaper"
      root.scanWallpapers()
    }
  }

  Timer {
    id: wallsDelay
    interval: 1500
    onTriggered: root.scanWallpapers()
  }

  // A theme that never reports back (the command failed, or was queued behind
  // another switch for too long) must not leave the grid stuck in "Applying".
  Timer {
    id: applyTimeout
    interval: 25000
    onTriggered: {
      if (root.applyingTheme === "") return
      root.app.errorText = displayOf(root.applyingTheme) + " did not finish applying"
      root.applyingTheme = ""
    }
  }

  FileView {
    id: themeNameFile
    path: root.home + "/.local/state/omarchy/current/theme.name"
    printErrors: false
    watchChanges: true
    onLoaded: root.noteCurrent(text())
    onFileChanged: reload()
  }
}
