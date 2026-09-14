import QtQuick
import Quickshell
import Quickshell.Io

// Lock screen, boot screen, idle timings and screensaver art.
//
// Lock and boot go through lock-explorer's `omarchy-shell lock …` IPC only; its
// Plymouth rebuild stays behind lock-explorer's own Apply button, which is the
// one place that tracks what is baked. Idle timings live in shell.json and are
// written from a fresh read. Branding goes through `omarchy branding`.
Item {
  id: root
  visible: false

  required property var app

  readonly property string home: Quickshell.env("HOME")
  property var info: null

  // Optimistic copies, so steppers answer at once.
  property int unlockMs: 800
  property int blankMs: 5000

  readonly property var status: info ? info.status : ({})

  function rescan() {
    if (scanProc.running) { root.rescanPending = true; return }
    scanProc.running = true
  }
  property bool rescanPending: false

  function lock(args, doneText) {
    run(["omarchy-shell", "lock"].concat(args), doneText, true)
  }

  function setDesign(id) { lock(["setDesign", id], "Lock design set") }
  function previewDesign(id) {
    root.app.dismiss()
    lock(["previewDesign", id], "")
  }
  function setUnlockAnimation(name) { lock(["setUnlockAnimation", name], "Unlock animation: " + name) }
  function stepUnlockMs(delta) {
    root.unlockMs = Math.max(0, Math.min(2000, root.unlockMs + delta * 100))
    unlockTimer.restart()
  }
  function setClock(v) { lock(["setClockFormat", v], v === "12" ? "12-hour clock" : "24-hour clock") }
  function setKeepDisplayOn(on) { lock(["setKeepDisplayOn", on ? "true" : "false"], on ? "Display stays on while locked" : "Display blanks while locked") }
  function stepBlank(delta) {
    var steps = [1000, 2000, 5000, 10000, 15000, 30000, 60000, 120000, 300000, 600000]
    var i = 0
    while (i < steps.length - 1 && steps[i] < root.blankMs) i++
    i = Math.max(0, Math.min(steps.length - 1, i + delta))
    root.blankMs = steps[i]
    blankTimer.restart()
  }
  function setBoot(id) { lock(["setBoot", id], "Boot screen chosen — apply it in lock-explorer") }
  function openExplorer(tab) {
    root.app.dismiss()
    run(["omarchy-shell", "lock", "exploreTab", tab], "", false)
  }

  function setIdle(key, seconds) {
    var idle = { lock: root.info.idle.lock, screensaver: root.info.idle.screensaver }
    idle[key] = seconds
    run([root.app.pluginDir + "/shell-json-set", "idle", JSON.stringify(idle)],
        (key === "lock" ? "Lock after " : "Screensaver after ") + root.formatSeconds(seconds), true)
  }

  function setScreensaverEnabled(on) {
    var flag = root.home + "/.local/state/omarchy/toggles/screensaver-off"
    run(on ? ["rm", "-f", flag] : ["bash", "-c", 'mkdir -p "${1%/*}" && touch "$1"', "lacquer", flag],
        on ? "Screensaver on" : "Screensaver off", true)
  }

  // `omarchy branding … image` opens the desktop file picker and transcodes;
  // `text` opens an editor. Both are Omarchy's own flows, run detached.
  function branding(which, action) {
    if (action === "preview") {
      root.app.dismiss()
      Quickshell.execDetached(which === "about" ? ["omarchy-launch-about"] : ["omarchy-launch-screensaver", "force"])
      return
    }
    if (action === "reset") {
      run(["bash", "-c", 'cp "$OMARCHY_PATH/$1" "$HOME/.config/omarchy/branding/$2"', "lacquer",
           which === "about" ? "icon.txt" : "logo.txt", which + ".txt"], "Reset to the Omarchy art", true)
      return
    }
    root.app.dismiss()
    Quickshell.execDetached(["omarchy", "branding", which, action])
  }

  function formatSeconds(s) {
    if (s === 0) return "never"
    if (s < 60) return s + " s"
    if (s % 60 === 0) return (s / 60) + " min"
    return (s / 60).toFixed(1).replace(/\.0$/, "") + " min"
  }

  property var queue: []

  function run(cmd, doneText, rescanAfter) {
    var q = root.queue.slice()
    q.push({ cmd: cmd, text: doneText, rescan: rescanAfter })
    root.queue = q
    pump()
  }

  function pump() {
    if (runProc.running || root.queue.length === 0) return
    var q = root.queue.slice()
    var job = q.shift()
    root.queue = q
    runProc.job = job
    runProc.command = job.cmd
    runProc.running = true
  }

  Process {
    id: runProc
    property var job: null
    stdout: StdioCollector { id: runOut; waitForEnd: true }
    stderr: StdioCollector { id: runErr; waitForEnd: true }
    onExited: function(code) {
      var reply = String(runOut.text || "").trim()
      var failed = code !== 0 || (job.cmd[0] === "omarchy-shell" && reply !== "" && reply !== "ok")
      if (failed) root.app.errorText = String(runErr.text || "").trim() || ("lock-explorer said: " + (reply || code))
      else if (job.text) root.app.statusText = job.text
      var again = job.rescan
      if (root.queue.length > 0) root.pump()
      else if (again) root.rescan()
    }
  }

  Timer { id: unlockTimer; interval: 400; onTriggered: root.lock(["setUnlockDuration", String(root.unlockMs)], "Unlock takes " + root.unlockMs + " ms") }
  Timer { id: blankTimer; interval: 400; onTriggered: root.lock(["setBlankDelay", String(root.blankMs)], "Blank after " + root.formatSeconds(root.blankMs / 1000)) }

  Process {
    id: scanProc
    command: ["python3", root.app.pluginDir + "/scan-screens"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text)
          root.info = parsed
          if (parsed.status) {
            if (!unlockTimer.running && parsed.status.unlockMs !== undefined) root.unlockMs = parsed.status.unlockMs
            if (!blankTimer.running && parsed.status.blankMs !== undefined) root.blankMs = parsed.status.blankMs
          }
        } catch (e) {
          root.app.errorText = "Could not read the lock and screensaver settings"
        }
      }
    }
    onExited: if (root.rescanPending) { root.rescanPending = false; running = true }
  }
}
