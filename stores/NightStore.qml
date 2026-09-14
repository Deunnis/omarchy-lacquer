import QtQuick
import Quickshell.Io

// Nightlight through the `nightlight` helper: the hyprsunset schedule, and the
// screen temperature right now. The helper owns every file and process; this
// only keeps the view's state and a draft of the schedule while it is off.
Item {
  id: root
  visible: false

  required property var app

  property var status: null
  property string morning: "07:00"
  property string evening: "20:00"
  property int warmth: 4000
  property bool confirmReplace: false
  property bool busy: false

  readonly property bool scheduled: !!(status && status.schedule)
  readonly property bool custom: !!(status && status.custom)

  function rescan() { exec(["print"], "") }

  function setNow(value) {
    exec(["now", value === "off" ? "off" : String(value)],
         value === "off" ? "Nightlight off" : "Screen at " + value + " K")
  }

  function setScheduled(on) {
    if (!on) { root.confirmReplace = false; exec(["schedule", "off"], "Schedule off"); return }
    if (root.custom && !root.confirmReplace) { root.confirmReplace = true; return }
    var args = ["schedule", "on", root.morning, root.evening, String(root.warmth)]
    if (root.custom) args.push("--replace")
    root.confirmReplace = false
    exec(args, "Warmer screen from " + root.evening)
  }

  function shiftTime(which, minutes) {
    var parts = root[which].split(":")
    var total = ((Number(parts[0]) * 60 + Number(parts[1]) + minutes) % 1440 + 1440) % 1440
    var next = String(Math.floor(total / 60)).padStart(2, "0") + ":" + String(total % 60).padStart(2, "0")
    var other = which === "morning" ? root.evening : root.morning
    if (next === other) return
    root[which] = next
    if (root.scheduled) applyTimer.restart()
  }

  function stepWarmth(delta) {
    var next = Math.max(2500, Math.min(6000, root.warmth + delta * 250))
    if (next === root.warmth) return
    root.warmth = next
    if (root.scheduled) applyTimer.restart()
  }

  // Each schedule change restarts hyprsunset, so a run of steps is one write.
  Timer {
    id: applyTimer
    interval: 700
    onTriggered: if (root.scheduled && !root.custom) root.exec(["schedule", "on", root.morning, root.evening, String(root.warmth)], "Schedule saved")
  }

  property var queued: null

  function exec(args, doneText) {
    if (proc.running) { root.queued = { args: args, text: doneText }; return }
    root.busy = args[0] !== "print"
    proc.doneText = doneText
    proc.command = ["timeout", "-k", "2", "40", root.app.pluginDir + "/nightlight"].concat(args)
    proc.running = true
  }

  Process {
    id: proc
    property string doneText: ""
    stdout: StdioCollector { id: out; waitForEnd: true }
    stderr: StdioCollector { id: err; waitForEnd: true }
    onExited: function(code) {
      root.busy = false
      if (code === 0) {
        try {
          var parsed = JSON.parse(out.text)
          root.status = parsed
          if (parsed.schedule && !applyTimer.running) {
            root.morning = parsed.schedule.morning
            root.evening = parsed.schedule.evening
            root.warmth = parsed.schedule.temperature
          }
        } catch (e) { }
        if (doneText) root.app.statusText = doneText
      } else {
        root.app.errorText = String(err.text || "").trim() || "Nightlight change failed"
      }
      if (root.queued) {
        var next = root.queued
        root.queued = null
        root.exec(next.args, next.text)
      }
    }
  }
}
