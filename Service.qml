import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import "Model.js" as Model
import "I18n.js" as I18n

// predmaxim.annotate: drawing on screen. annotate.lua turns Ctrl+Super+drag
// and Shift+Super+drag into Hyprland events. Temp lines are drawn here in
// click-through overlays and vanish when Super or Ctrl is let go; the editor
// (Editor.qml) keeps shapes until they are saved, copied or dropped.
// Settings live in this plugin's entry in shell.json (Settings.qml edits them).
Item {
  id: root

  // Injected by omarchy-shell.
  property var shell: null
  property var manifest: null

  readonly property string pluginId: (manifest && manifest.id) || "predmaxim.annotate"
  readonly property string configPath: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
  readonly property string luaPath: decodeURIComponent(String(Qt.resolvedUrl("annotate.lua")).replace(/^file:\/\//, ""))
  // Each instance owns the binds under its own token, so the instance a
  // plugin reload replaces cannot switch the new one's off (annotate.lua).
  readonly property string token: Date.now().toString(36) + Math.random().toString(36).slice(2, 8)
  readonly property var tr: I18n.translator(I18n.textLanguage(function(name) { return Quickshell.env(name) }))
  readonly property color accent: Color.accent

  property var settings: Model.normalize({})
  property bool settingsLoaded: false
  property string appliedModes: ""

  // The temp line annotate.lua is drawing.
  property var drawing: null

  property var tempShapes: []
  property int tempRevision: 0
  // The monitor the temp lines started on: its overlay takes the keyboard, so
  // letting go of Ctrl/Super reaches it (Hyprland drops release binds on a
  // modifier once a mouse bind fired while it was held).
  property string tempScreen: ""

  // The editor is open while editScreen is set.
  property var editScreen: null
  property var editShapes: []
  property int editRevision: 0
  property bool capturing: false
  // Where the editor's toolbar was moved to (null: top centre), until a restart.
  property var toolbarPos: null
  // Ctrl+Shift+S: the next drag in the editor marks the area to save.
  property bool selectingArea: false
  readonly property string penTool: settings.editTool
  readonly property string penColor: settings.editColor
  readonly property int penWidth: settings.editWidth

  // ------------------------------------------------------------ settings

  function readSettings(text) {
    var entry = Model.readEntry(text, root.pluginId)
    if (entry === null) {
      console.warn("predmaxim.annotate: could not read " + root.configPath)
      return
    }
    root.settings = Model.normalize(entry)
    if (!root.settingsLoaded) {
      root.settingsLoaded = true
      root.claimBinds()
    } else {
      root.applyModes()
    }
  }

  // From the editor and Settings.qml: merged, checked, stored, applied.
  function store(changes) {
    var entry = {}
    for (var k in root.settings) entry[k] = root.settings[k]
    for (var c in changes) entry[c] = changes[c]
    root.settings = Model.normalize(entry)
    if (root.shell && typeof root.shell.updateEntryInline === "function")
      root.shell.updateEntryInline(root.pluginId, root.settings)
    root.applyModes()
  }

  FileView {
    path: root.configPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.readSettings(text())
  }

  // ------------------------------------------------------------ binds

  function modes() {
    return root.settings.tempEnabled + ", " + root.settings.editEnabled
  }

  function claimBinds() {
    root.appliedModes = root.modes()
    claim.command = ["hyprctl", "eval", "dofile(" + JSON.stringify(root.luaPath) + "); annotate.activate("
      + JSON.stringify(root.token) + ", " + root.appliedModes + ")"]
    claim.running = true
  }

  function applyModes() {
    if (root.modes() === root.appliedModes) return
    root.appliedModes = root.modes()
    Quickshell.execDetached(["hyprctl", "eval",
      "if annotate then annotate.set_modes(" + JSON.stringify(root.token) + ", " + root.appliedModes + ") end"])
  }

  Process {
    id: claim
    stdout: StdioCollector {
      onStreamFinished: {
        var reply = String(text || "").trim()
        if (reply !== "ok") console.warn("predmaxim.annotate: binds did not load: " + reply)
      }
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "configreloaded") {
        // A reload drops runtime binds and the line being drawn with them.
        root.drawing = null
        root.clearTemp()
        root.claimBinds()
        return
      }
      var parsed = Model.parseEvent(event.name, event.data)
      if (parsed) root.handle(parsed)
    }
  }

  Component.onDestruction: Quickshell.execDetached(["hyprctl", "eval",
    "if annotate then annotate.deactivate(" + JSON.stringify(root.token) + ") end"])

  // ------------------------------------------------------------ events

  function handle(e) {
    if (e.type === "start" && e.mode === "temp") {
      if (root.tempShapes.length === 0) {
        var screen = Model.screenAt(Quickshell.screens, e.x, e.y)
        root.tempScreen = screen ? screen.name : ""
      }
      root.drawing = Model.newShape("pen", root.settings.tempColor, root.settings.tempWidth, e.x, e.y)
      root.tempShapes = root.tempShapes.concat([root.drawing])
    } else if (e.type === "start") {
      if (root.editScreen) return  // Already open: its own mouse area draws.
      root.openEditor(Model.screenAt(Quickshell.screens, e.x, e.y))
    } else if (e.type === "move") {
      if (root.drawing && Model.extend(root.drawing, e.x, e.y)) root.tempRevision++
    } else if (e.type === "end") {
      root.drawing = null
    }
  }

  function clearTemp() {
    root.drawing = null
    root.tempShapes = []
    root.tempScreen = ""
  }

  // ------------------------------------------------------------ editor

  // From Shift+Super+press or IPC `edit`. Drawing starts with the next press,
  // in Editor.qml's own mouse area.
  function openEditor(screen) {
    if (!screen) return
    root.editShapes = []
    root.editScreen = screen
  }

  function startEditShape(x, y) {
    var shape = Model.newShape(root.penTool, root.penColor, root.penWidth, x, y)
    root.editShapes = root.editShapes.concat([shape])
    return shape
  }

  // Drops the last shape if it came out empty (a click with the rect tool).
  function endEditShape() {
    var last = root.editShapes[root.editShapes.length - 1]
    if (last && Model.isEmpty(last)) root.editShapes = root.editShapes.slice(0, -1)
  }

  function addText(x, y, text) {
    var shape = Model.newShape("text", root.penColor, root.penWidth, x, y)
    shape.text = text
    if (!Model.isEmpty(shape)) root.editShapes = root.editShapes.concat([shape])
  }

  function undo() {
    if (root.editShapes.length > 0) root.editShapes = root.editShapes.slice(0, -1)
  }

  function closeEditor() {
    root.capturing = false
    root.selectingArea = false
    root.editScreen = null
    root.editShapes = []
  }

  // area: grim's -g geometry, for kind "region" (Model.areaGeometry).
  function capture(kind, area) {
    if (root.capturing || !root.editScreen) return
    root.capturing = true  // Editor.qml hides the toolbar.
    captureDelay.kind = kind
    captureDelay.area = area || ""
    captureDelay.restart()
  }

  function notify(text) {
    Quickshell.execDetached(["omarchy-notification-send", "--app-name", root.tr("Annotate"), text])
  }

  Timer {
    id: captureDelay
    property string kind: ""
    property string area: ""
    // ponytail: a fixed wait for the toolbar to leave the screen; switch to
    // the window's frameSwapped if it ever shows up in a shot.
    interval: 100
    onTriggered: {
      capturer.kind = kind
      capturer.command = Model.captureCommand(kind, root.editScreen.name, root.settings.saveDir, Model.fileName(new Date()), area)
      capturer.running = true
    }
  }

  Process {
    id: capturer
    property string kind: ""
    stdout: StdioCollector { id: captureOut }
    stderr: StdioCollector { id: captureErr }
    onExited: function(exitCode) {
      root.capturing = false
      if (exitCode === 0) {
        var file = String(captureOut.text || "").trim()
        if (kind === "copy") root.notify(root.tr("Copied to the clipboard"))
        else if (kind === "region") root.notify(root.tr("Saved and copied: %1", file))
        else root.notify(root.tr("Saved: %1", file))
        root.closeEditor()
        return
      }
      // A failed capture keeps the editor open: the drawing is not lost.
      var why = String(captureErr.text || "").trim() || ("exit " + exitCode)
      if (kind === "copy") root.notify(root.tr("Not copied: %1", why))
      else root.notify(root.tr("Not saved: %1", why))
    }
  }

  // Keys (Model.keyAction), toolbar clicks and the wheel.
  function act(action) {
    if (action === "close" && root.selectingArea) root.selectingArea = false
    else if (action === "close") root.closeEditor()
    else if (action === "save") root.capture("screen")
    else if (action === "saveRegion") root.selectingArea = !root.capturing
    else if (action === "copy") root.capture("copy")
    else if (action === "undo") root.undo()
    else if (action === "wider") root.store({ editWidth: root.penWidth + Model.WIDTH_STEP })
    else if (action === "narrower") root.store({ editWidth: root.penWidth - Model.WIDTH_STEP })
    else if (action.indexOf("tool:") === 0) root.store({ editTool: action.slice(5) })
    else if (action.indexOf("color:") === 0) root.store({ editColor: action.slice(6) })
  }

  LazyLoader {
    active: root.editScreen !== null
    Editor { service: root }
  }

  // ------------------------------------------------------------ temp lines

  Variants {
    model: root.tempShapes.length > 0 ? Quickshell.screens : []

    delegate: Component {
      PanelWindow {
        id: overlay
        required property var modelData

        screen: modelData
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "predmaxim-annotate"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: overlay.modelData.name === root.tempScreen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        // An empty input region: clicks go to the windows below.
        mask: Region {}

        Item {
          anchors.fill: parent
          focus: true
          // Any key coming up (Ctrl or Super, as a rule) clears the lines and
          // gives the keyboard back, so the overlay can never lock typing out.
          Keys.onReleased: function(event) {
            event.accepted = true
            root.clearTemp()
          }

          Drawing {
            anchors.fill: parent
            shapes: root.tempShapes
            revision: root.tempRevision
            accent: root.accent
            originX: overlay.modelData.x
            originY: overlay.modelData.y
          }
        }
      }
    }
  }

  // ------------------------------------------------------------ IPC

  IpcHandler {
    target: "predmaxim.annotate"

    function status(): string {
      return JSON.stringify({
        temp: root.tempShapes.length,
        editing: root.editScreen !== null,
        shapes: root.editShapes.length,
        settings: root.settings
      })
    }
    // Opens the editor on the focused monitor, without a first line.
    function edit(): string {
      if (root.editScreen) return "already open"
      var name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
      var screens = Quickshell.screens
      for (var i = 0; i < screens.length; i++)
        if (screens[i].name === name) { root.openEditor(screens[i]); return "ok" }
      root.openEditor(screens.length > 0 ? screens[0] : null)
      return "ok"
    }
    // Opens the settings window, or brings it forward if it is already open.
    function settings(): string {
      if (root.shell) root.shell.summon(root.pluginId, "{}")
      return "ok"
    }
    function clear(): string {
      root.clearTemp()
      root.editShapes = []
      return "ok"
    }
  }
}
