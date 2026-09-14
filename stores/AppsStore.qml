import QtQuick
import Quickshell.Io

// Terminals, btop and the starship prompt, through the `app-config` helper,
// which owns every file edit and reload signal.
Item {
  id: root
  visible: false

  required property var app

  property var info: null
  property var pending: ({})

  readonly property var term: {
    if (!info || !info.terminals || info.terminals.length === 0) return null
    var preferred = String(info["default"] || "").replace(/\.desktop$/, "").toLowerCase()
    for (var i = 0; i < info.terminals.length; i++)
      if (info.terminals[i].name === preferred && info.terminals[i].values) return info.terminals[i].values
    return info.terminals[0].values
  }

  // Optimistic stepper values, keyed "target.key".
  function shown(target, key, fallback) {
    var k = target + "." + key
    if (root.pending[k] !== undefined) return root.pending[k]
    return fallback
  }

  function rescan() { exec(["print"], "") }

  function set(target, key, value, label) {
    exec(["set", target, key, String(value)], label || "Saved")
  }

  function stepTo(target, key, value, label) {
    var next = JSON.parse(JSON.stringify(root.pending))
    next[target + "." + key] = value
    root.pending = next
    stepTimer.job = { target: target, key: key, value: value, label: label }
    stepTimer.restart()
  }

  Timer {
    id: stepTimer
    property var job: null
    interval: 450
    onTriggered: if (job) root.set(job.target, job.key, job.value, job.label)
  }

  property var queued: []

  function exec(args, doneText) {
    if (proc.running) { var q = root.queued.slice(); q.push({ args: args, text: doneText }); root.queued = q; return }
    proc.doneText = doneText
    proc.command = ["timeout", "-k", "2", "20", root.app.pluginDir + "/app-config"].concat(args)
    proc.running = true
  }

  Process {
    id: proc
    property string doneText: ""
    stdout: StdioCollector { id: out; waitForEnd: true }
    stderr: StdioCollector { id: err; waitForEnd: true }
    onExited: function(code) {
      if (code === 0) {
        try { root.info = JSON.parse(out.text) } catch (e) { }
        if (doneText) root.app.statusText = doneText
      } else {
        root.app.errorText = String(err.text || "").trim() || "Could not save that"
      }
      if (root.queued.length > 0) {
        var q = root.queued.slice()
        var next = q.shift()
        root.queued = q
        root.exec(next.args, next.text)
      } else if (!stepTimer.running) {
        root.pending = ({})
      }
    }
  }
}
