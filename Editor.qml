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
  // The service drops editScreen before this window unloads.
  readonly property real originX: monitor ? monitor.x : 0
  readonly property real originY: monitor ? monitor.y : 0

  screen: monitor
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "predmaxim-annotate"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

  function toGlobal(x, y) {
    return Qt.point(x + editor.originX, y + editor.originY)
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
      originX: editor.originX
      originY: editor.originY
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.CrossCursor
      property var shape: null
      // Ctrl+Shift+S: the area being dragged, in this window's coordinates.
      property point areaStart
      property bool dragging: false

      onPressed: function(mouse) {
        editor.commitText()
        if (editor.service.selectingArea) {
          areaStart = Qt.point(mouse.x, mouse.y)
          area.width = 0
          area.height = 0
          dragging = true
          return
        }
        var p = editor.toGlobal(mouse.x, mouse.y)
        if (editor.service.penTool === "text") editor.beginText(p.x, p.y)
        else shape = editor.service.startEditShape(p.x, p.y)
      }
      onPositionChanged: function(mouse) {
        if (dragging) {
          area.x = Math.min(areaStart.x, mouse.x)
          area.y = Math.min(areaStart.y, mouse.y)
          area.width = Math.abs(mouse.x - areaStart.x)
          area.height = Math.abs(mouse.y - areaStart.y)
          return
        }
        if (!shape) return
        var p = editor.toGlobal(mouse.x, mouse.y)
        if (Model.extend(shape, p.x, p.y)) editor.service.editRevision++
      }
      onReleased: function(mouse) {
        if (dragging) {
          dragging = false
          var a = editor.toGlobal(areaStart.x, areaStart.y), b = editor.toGlobal(mouse.x, mouse.y)
          var geometry = Model.releasedArea(editor.service.selectingArea, a.x, a.y, b.x, b.y)
          // A frame too small to mean anything leaves the selection on.
          if (!geometry) return
          editor.service.selectingArea = false
          editor.service.capture("region", geometry)
          return
        }
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
      x: gx - editor.originX
      y: gy - editor.originY
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

    // The area being marked; hidden before the shot is taken.
    Rectangle {
      id: area
      visible: editor.service.selectingArea && width > 0
      color: Util.alpha("white", 0.08)
      border.width: 1
      border.color: "white"
    }

    Toolbar {
      service: editor.service
      visible: !editor.service.capturing
      // Bottom centre, off the edge, until moved; then where it was left (Toolbar.qml).
      x: editor.service.toolbarPos ? editor.service.toolbarPos.x : (parent.width - width) / 2
      y: editor.service.toolbarPos ? editor.service.toolbarPos.y : parent.height - height - Style.space(48)
    }
  }
}
