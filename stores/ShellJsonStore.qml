import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "../LookSchema.js" as LookSchema
import "../AnimSchema.js" as AnimSchema
import "../StyleLua.js" as StyleLua
import "../ShellSchema.js" as ShellSchema
import "../TomlEdit.js" as TomlEdit

// ~/.config/omarchy/shell.json: the bar layout and every plugin's settings,
// written through the omarchy CLIs where one exists.
Item {
  id: root
  visible: false

  // The panel that owns this store; everything outside the store goes through it.
  required property var app

  readonly property alias scanProcRef: scanProc
  readonly property alias shellJsonFileRef: shellJsonFile

  // ~/.config/omarchy/shell.json: the bar layout and every plugin's settings.
  // Bar widgets are written through the `omarchy bar` CLI because the shell API
  // only lets a plugin write its OWN settings unless it declares kind "bar",
  // which would mean replacing the user's whole bar. Plugins that are not on
  // the bar have no CLI at all, so those go through a guarded direct write.
  property string shellJsonText: ""

  property var barConfig: ({})

  property bool jsonSelfWrite: false

  property var plugins: []

  property var cliQueue: []

  // ------------------------------------------------------------ shell.json

  readonly property var barSections: ["left", "center", "right"]

  function barLayout(section) {
    var bar = root.barConfig.bar
    var layout = bar && bar.layout ? bar.layout[section] : null
    return Array.isArray(layout) ? layout : []
  }

  function barSectionOf(id) {
    for (var i = 0; i < root.barSections.length; i++) {
      var list = barLayout(root.barSections[i])
      for (var j = 0; j < list.length; j++)
        if (String(list[j].id) === String(id)) return root.barSections[i]
    }
    return ""
  }

  function barIndexOf(id) {
    var list = barLayout(barSectionOf(id))
    for (var i = 0; i < list.length; i++)
      if (String(list[i].id) === String(id)) return i
    return -1
  }

  function pluginFor(id) {
    for (var i = 0; i < root.plugins.length; i++)
      if (root.plugins[i].id === id) return root.plugins[i]
    return null
  }

  // A bar widget stores settings inline on its layout entry; everything else on
  // its entry in the top-level plugins list. Both are just { id, ...settings }.
  function settingsEntry(plugin) {
    if (!plugin) return null
    var section = barSectionOf(plugin.id)
    if (section !== "") {
      var list = barLayout(section)
      for (var i = 0; i < list.length; i++)
        if (String(list[i].id) === plugin.id) return list[i]
    }
    var others = Array.isArray(root.barConfig.plugins) ? root.barConfig.plugins : []
    for (var j = 0; j < others.length; j++)
      if (String(others[j].id) === plugin.id) return others[j]
    return null
  }

  function settingValue(plugin, key) {
    var entry = settingsEntry(plugin)
    return entry && entry[key] !== undefined ? entry[key] : undefined
  }

  function settingModified(plugin, key) {
    return settingValue(plugin, key) !== undefined
  }

  function pluginTouched(plugin) {
    for (var i = 0; i < (plugin.schema || []).length; i++)
      if (settingModified(plugin, plugin.schema[i].key)) return true
    return false
  }

  function pluginEnabled(plugin) {
    if (barSectionOf(plugin.id) !== "") return true
    var others = Array.isArray(root.barConfig.plugins) ? root.barConfig.plugins : []
    for (var i = 0; i < others.length; i++)
      if (String(others[i].id) === plugin.id) return true
    return false
  }

  // Clicking two arrows quickly used to drop the second command with no
  // feedback, because only one Process can run at a time. They queue instead.
  function runCli(args, label) {
    var queued = root.cliQueue.slice()
    queued.push({ args: args, label: label || "" })
    root.cliQueue = queued
    pumpCli()
  }

  function pumpCli() {
    if (cliProc.running || root.cliQueue.length === 0) return
    var next = root.cliQueue[0]
    app.statusText = next.label !== "" ? next.label + "…" : "Working…"
    cliProc.command = next.args
    cliProc.running = true
  }

  function writeShellJson(doc) {
    var text = JSON.stringify(doc, null, 2) + "\n"
    if (text === root.shellJsonText) return
    root.jsonSelfWrite = true
    root.shellJsonText = text
    root.barConfig = doc
    shellJsonFile.setText(text)
  }

  // Re-parsed from the file on every write rather than held, so a change the
  // shell or the CLI made in between is never clobbered from a stale copy.
  function currentJson() {
    try {
      return JSON.parse(root.shellJsonText)
    } catch (e) {
      return null
    }
  }

  function setSetting(plugin, spec, value) {
    if (!plugin || !spec) return
    if (barSectionOf(plugin.id) !== "") {
      runCli(["omarchy", "bar", "set", plugin.id, spec.key, JSON.stringify(value), "--json"],
             plugin.name)
      return
    }
    var doc = currentJson()
    if (!doc) return
    if (!Array.isArray(doc.plugins)) doc.plugins = []
    var found = false
    for (var i = 0; i < doc.plugins.length; i++) {
      if (String(doc.plugins[i].id) !== plugin.id) continue
      doc.plugins[i][spec.key] = value
      found = true
    }
    if (!found) {
      var entry = { id: plugin.id }
      entry[spec.key] = value
      doc.plugins.push(entry)
    }
    writeShellJson(doc)
  }

  function resetSetting(plugin, spec) {
    if (!plugin || !spec) return
    if (barSectionOf(plugin.id) !== "") {
      // The CLI has no unset, so the entry is rewritten without the key.
      var doc = currentJson()
      if (!doc) return
      var section = barSectionOf(plugin.id)
      var list = doc.bar && doc.bar.layout ? doc.bar.layout[section] : null
      if (Array.isArray(list))
        for (var i = 0; i < list.length; i++)
          if (String(list[i].id) === plugin.id) delete list[i][spec.key]
      writeShellJson(doc)
      return
    }
    var other = currentJson()
    if (!other) return
    var entries = Array.isArray(other.plugins) ? other.plugins : []
    for (var j = 0; j < entries.length; j++)
      if (String(entries[j].id) === plugin.id) delete entries[j][spec.key]
    writeShellJson(other)
  }

  // ------------------------------------------------------------------ bar

  function setBarPosition(position) {
    runCli(["omarchy", "bar", "position", String(position)], "Bar position")
  }

  function setBarTransparent(on) {
    runCli(["omarchy", "bar", "transparent", on ? "true" : "false"], "Bar transparency")
  }

  function moveWidget(id, section, index) {
    runCli(["omarchy", "bar", "move", String(id),
            "--section", String(section), "--index", String(index)], "Move")
  }

  function nudgeWidget(id, delta) {
    var section = barSectionOf(id)
    if (section === "") return
    var at = barIndexOf(id)
    var list = barLayout(section)
    var next = at + delta
    if (next < 0 || next >= list.length) return
    moveWidget(id, section, next)
  }

  function shiftWidget(id, delta) {
    var section = barSectionOf(id)
    if (section === "") return
    var at = root.barSections.indexOf(section) + delta
    if (at < 0 || at >= root.barSections.length) return
    moveWidget(id, root.barSections[at], barLayout(root.barSections[at]).length)
  }

  function setWidgetOnBar(id, on) {
    runCli(["omarchy", "plugin", on ? "enable" : "disable", String(id)],
           on ? "Enable" : "Disable")
  }

  Process {
    id: scanProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text)
          root.plugins = Array.isArray(parsed) ? parsed : []
          if (app.selectedPlugin === "") {
            for (var i = 0; i < root.plugins.length; i++)
              if ((root.plugins[i].schema || []).length > 0) { app.selectedPlugin = root.plugins[i].id; break }
          }
        } catch (e) {
          app.errorText = "Could not read plugin manifests"
        }
      }
    }
  }

  Process {
    id: cliProc
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(code) {
      if (code !== 0) { app.errorText = "That command failed"; app.statusText = "" }
      else app.statusText = "Done"
      if (root.cliQueue.length > 0) root.cliQueue = root.cliQueue.slice(1)
      shellJsonFile.reload()
      // Reading the file back between commands is what keeps a queued write
      // from being computed against a layout the previous one already changed.
      Qt.callLater(root.pumpCli)
    }
  }

  FileView {
    id: shellJsonFile
    path: app.home + "/.config/omarchy/shell.json"
    atomicWrites: true
    printErrors: false
    watchChanges: true
    onLoaded: {
      root.shellJsonText = text()
      try {
        root.barConfig = JSON.parse(text())
      } catch (e) {
        root.barConfig = ({})
        app.errorText = "shell.json is not valid JSON"
      }
    }
    onLoadFailed: { root.shellJsonText = ""; root.barConfig = ({}) }
    onSaved: root.jsonSelfWrite = false
    onSaveFailed: {
      root.jsonSelfWrite = false
      app.errorText = "Could not write ~/.config/omarchy/shell.json"
    }
    onFileChanged: { if (root.jsonSelfWrite) return; reload() }
  }
}
