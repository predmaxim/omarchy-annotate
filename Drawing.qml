import QtQuick
import QtQuick.Shapes
import "Model.js" as Model

// Draws shapes kept in global coordinates onto one monitor, whose top-left is
// (originX, originY). Only the last shape follows `revision`: it is the one
// still being drawn, so a new point repaints one path, not all of them.
Item {
  id: drawing

  property var shapes: []
  property int revision: 0
  property color accent: "white"
  property real originX: 0
  property real originY: 0

  Repeater {
    model: drawing.shapes.length

    delegate: Item {
      id: item
      required property int index
      readonly property var shape: drawing.shapes[index]
      readonly property int live: index === drawing.shapes.length - 1 ? drawing.revision : 0
      readonly property color ink: shape ? Model.colorOf(shape.color, drawing.accent) : "transparent"

      x: -drawing.originX
      y: -drawing.originY

      Shape {
        visible: item.shape !== undefined && item.shape.type !== "text"
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
          fillColor: "transparent"
          strokeColor: item.ink
          strokeWidth: item.shape ? item.shape.width : 0
          capStyle: ShapePath.RoundCap
          joinStyle: ShapePath.RoundJoin
          PathSvg { path: item.live >= 0 && item.shape && item.shape.type !== "text" ? Model.svgPath(item.shape) : "" }
        }
      }

      Text {
        visible: item.shape !== undefined && item.shape.type === "text"
        x: item.shape ? item.shape.x1 : 0
        y: item.shape ? item.shape.y1 : 0
        text: item.shape && item.shape.text ? item.shape.text : ""
        color: item.ink
        font.pixelSize: item.shape ? Model.fontSize(item.shape.width) : 12
        font.bold: true
      }
    }
  }
}
