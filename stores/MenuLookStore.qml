import QtQuick
import Quickshell
import Quickshell.Io

// omamenu's Menu Look, through the IPC its local-look-ipc branch adds. The menu
// keeps the file; this only reads the live values and sends new ones.
Item {
  id: root
  visible: false

  required property var app

  readonly property string pluginPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/io.github.omamenu"
  property var look: null
  property bool available: false
  property bool probed: false

  function rescan() { if (!readProc.running) readProc.running = true }

  function send() {
    if (!root.look) return
    sendTimer.restart()
  }

  function step(key, delta) {
    if (!root.look) return
    var next = JSON.parse(JSON.stringify(root.look))
    if (key === "scale") next.scale = Math.round(Math.max(0.8, Math.min(1.5, next.scale + delta * 0.05)) * 100) / 100
    else if (key === "cornerRadius") next.cornerRadius = Math.max(-1, Math.min(24, next.cornerRadius + delta))
    else if (key === "borderWidth") next.borderWidth = Math.max(-1, Math.min(6, next.borderWidth + delta))
    else if (key === "transparency") next.transparency = Math.max(0, Math.min(90, next.transparency + delta * 5))
    root.look = next
    send()
  }

  function reset() {
    sendTimer.stop()
    runProc.command = ["omarchy-shell", "omamenu", "resetLook"]
    runProc.running = true
  }

  Timer {
    id: sendTimer
    interval: 250
    onTriggered: {
      if (runProc.running) { restart(); return }
      runProc.command = ["omarchy-shell", "omamenu", "setLook", String(root.look.scale), String(root.look.cornerRadius),
                         String(root.look.borderWidth), String(root.look.transparency)]
      runProc.running = true
    }
  }

  Process {
    id: runProc
    stdout: StdioCollector { id: runOut; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0 || String(runOut.text).trim() !== "ok") root.app.errorText = "omamenu did not accept the change"
      else root.app.statusText = "Menu look saved"
      if (!sendTimer.running) root.rescan()
    }
  }

  Process {
    id: readProc
    command: ["omarchy-shell", "omamenu", "look"]
    stdout: StdioCollector { id: readOut; waitForEnd: true }
    onExited: function(code) {
      // look and available first: the section builds its rows the moment
      // probed turns true.
      try {
        var parsed = JSON.parse(readOut.text)
        if (!sendTimer.running && !runProc.running) root.look = parsed
        root.available = root.look !== null
      } catch (e) {
        root.available = false
      }
      root.probed = true
    }
  }
}
