import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "../LookSchema.js" as LookSchema
import "../AnimSchema.js" as AnimSchema
import "../StyleLua.js" as StyleLua
import "../ShellSchema.js" as ShellSchema
import "../TomlEdit.js" as TomlEdit

// ~/.config/omarchy/shell.toml: the user file Lacquer edits, the active theme's
// copy that unset keys fall back to, and the in-flight drag values.
Item {
  id: root
  visible: false

  // The panel that owns this store; everything outside the store goes through it.
  required property var app

  readonly property alias shellThemeFileRef: shellThemeFile
  readonly property alias shellUserFileRef: shellUserFile
  readonly property alias themeNameFileRef: themeNameFile

  // ~/.config/omarchy/shell.toml: user keys beat the theme's own copy and the
  // shell watches the file, so these apply with no restart and survive a theme
  // switch. `shellDraft` holds a value mid-drag, because unlike Hyprland there
  // is no eval to preview through — the only way to apply is to write.
  property string shellUserText: ""

  property var shellUser: ({})

  property var shellTheme: ({})

  property var shellDraft: ({})

  property bool shellSelfWrite: false

  function clearDraft() {
    if (Object.keys(root.shellDraft).length > 0) root.shellDraft = ({})
  }

  // --------------------------------------------------------------- shell.toml

  function shellValue(item) {
    if (root.shellDraft[item.id] !== undefined) return root.shellDraft[item.id]
    return root.shellUser[item.id]
  }

  function shellModified(item) {
    return root.shellUser[item.id] !== undefined
  }

  // What the row falls back to when nothing is pinned: the active theme's
  // value if it ships one, otherwise Omarchy's documented default. Many keys
  // ship commented out, so without the second step a row would display its
  // slider minimum instead of the number actually in effect.
  function shellDefault(item) {
    if (root.shellTheme[item.id] !== undefined) return root.shellTheme[item.id]
    if (item.fallback !== undefined) return String(item.fallback)
    return undefined
  }

  function writeShell(text) {
    if (text === root.shellUserText) return
    root.shellSelfWrite = true
    root.shellUserText = text
    root.shellUser = TomlEdit.values(text)
    shellUserFile.setText(text)
  }

  function setShell(item, value, commit) {
    app.beginEdit()
    var next = {}
    var k
    for (k in root.shellDraft) next[k] = root.shellDraft[k]
    if (!commit) {
      next[item.id] = ShellSchema.quantize(item, value)
      root.shellDraft = next
      return
    }
    delete next[item.id]
    root.shellDraft = next
    writeShell(TomlEdit.set(root.shellUserText, item.section, item.key,
                            ShellSchema.quantize(item, value)))
    app.commitEdit(item.label)
  }

  function resetShellItem(item) {
    app.beginEdit()
    writeShell(TomlEdit.unset(root.shellUserText, item.section, item.key))
    app.commitEdit(item.label)
  }

  FileView {
    id: shellUserFile
    path: app.home + "/.config/omarchy/shell.toml"
    atomicWrites: true
    printErrors: false
    watchChanges: true
    onLoaded: { root.shellUserText = text(); root.shellUser = TomlEdit.values(text()) }
    onLoadFailed: { root.shellUserText = ""; root.shellUser = ({}) }
    onSaved: root.shellSelfWrite = false
    onSaveFailed: {
      root.shellSelfWrite = false
      app.errorText = "Could not write ~/.config/omarchy/shell.toml"
    }
    onFileChanged: { if (root.shellSelfWrite) return; reload() }
  }

  // `omarchy theme set` builds current/next-theme and then mv's it over
  // current/theme wholesale, so a watch on a file *inside* that directory does
  // not survive the swap — after an OmaShuffle switch the fallbacks below
  // would still be the previous theme's. theme.name is a sibling of the
  // swapped directory and is rewritten on every switch, so it is the reliable
  // signal to re-read.
  FileView {
    id: themeNameFile
    path: app.home + "/.local/state/omarchy/current/theme.name"
    printErrors: false
    watchChanges: true
    onFileChanged: { reload(); shellThemeFile.reload() }
    onLoaded: shellThemeFile.reload()
  }

  // The active theme's own shell.toml is what an unset key falls back to, so
  // it is the "default" every pip and clear is measured against.
  FileView {
    id: shellThemeFile
    path: app.home + "/.local/state/omarchy/current/theme/shell.toml"
    printErrors: false
    watchChanges: true
    onLoaded: root.shellTheme = TomlEdit.values(text())
    onLoadFailed: root.shellTheme = ({})
    onFileChanged: reload()
  }
}
