import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "Model.js" as Model

// The editor: takes one monitor's mouse and keyboard until the drawing is
// saved, copied or dropped. Shapes are kept in global coordinates.
PanelWindow {
  id: editor

  required property var service
  readonly property var monitor: service.editScreen

  screen: monitor
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "predmaxim-annotate"
  WlrLayershell.layer: WlrLayer.Overlay
  // Let go during a capture, so slurp gets the keyboard (Esc cancels it).
  WlrLayershell.keyboardFocus: service.capturing ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive

  function toGlobal(x, y) {
    return Qt.point(x + editor.monitor.x, y + editor.monitor.y)
  }

  function beginText(gx, gy) {
    typing.gx = gx
    typing.gy = gy
    typing.text = ""
    typing.visible = true
    typing.forceActiveFocus()
  }

  function commitText() {
    if (!typing.visible) return
    editor.service.addText(typing.gx, typing.gy, typing.text)
    typing.visible = false
    keys.forceActiveFocus()
  }

  function cancelText() {
    typing.visible = false
    keys.forceActiveFocus()
  }

  function run(event, ctrlOnly) {
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    if (ctrlOnly && !ctrl) return
    var action = Model.keyAction(event.nativeScanCode, event.key, ctrl, (event.modifiers & Qt.ShiftModifier) !== 0)
    if (!action) return
    event.accepted = true
    editor.commitText()  // Saving or copying keeps the text being typed.
    editor.service.act(action)
  }

  Item {
    id: keys
    anchors.fill: parent
    focus: true

    Component.onCompleted: forceActiveFocus()

    Keys.onPressed: function(event) { editor.run(event, false) }

    Drawing {
      anchors.fill: parent
      shapes: editor.service.editShapes
      revision: editor.service.editRevision
      accent: editor.service.accent
      originX: editor.monitor.x
      originY: editor.monitor.y
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.CrossCursor
      property var shape: null

      onPressed: function(mouse) {
        editor.commitText()
        var p = editor.toGlobal(mouse.x, mouse.y)
        if (editor.service.penTool === "text") editor.beginText(p.x, p.y)
        else shape = editor.service.startEditShape(p.x, p.y)
      }
      onPositionChanged: function(mouse) {
        if (!shape) return
        var p = editor.toGlobal(mouse.x, mouse.y)
        if (Model.extend(shape, p.x, p.y)) editor.service.editRevision++
      }
      onReleased: {
        if (shape) editor.service.endEditShape()
        shape = null
      }
      onWheel: function(wheel) { editor.service.act(wheel.angleDelta.y > 0 ? "wider" : "narrower") }
    }

    TextInput {
      id: typing
      property real gx: 0
      property real gy: 0
      visible: false
      x: gx - editor.monitor.x
      y: gy - editor.monitor.y
      color: Model.colorOf(editor.service.penColor, editor.service.accent)
      font.pixelSize: Model.fontSize(editor.service.penWidth)
      font.bold: true
      cursorVisible: visible
      // Ctrl+S / Ctrl+C / Ctrl+Z while typing act on the drawing.
      Keys.onPressed: function(event) { editor.run(event, true) }
      Keys.onReturnPressed: editor.commitText()
      Keys.onEnterPressed: editor.commitText()
      Keys.onEscapePressed: editor.cancelText()
    }

    Toolbar {
      service: editor.service
      visible: !editor.service.capturing
      anchors.top: parent.top
      anchors.topMargin: Style.space(16)
      anchors.horizontalCenter: parent.horizontalCenter
    }
  }
}
