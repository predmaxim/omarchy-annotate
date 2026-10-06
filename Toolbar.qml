import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The editor's toolbar: tools, the palette and the width. Everything is
// clickable; the keys do the same (Model.keyAction). Dragged by its grip or
// any empty spot, within the screen; the place is kept for the next editor.
// Hidden during a capture.
Rectangle {
  id: bar

  required property var service
  readonly property color fg: Color.menu.text

  color: Color.menu.background
  radius: Style.cornerRadius
  border.width: 1
  border.color: Util.alpha(fg, 0.25)
  implicitWidth: row.implicitWidth + Style.space(16)
  implicitHeight: row.implicitHeight + Style.space(12)

  // Clicks between the buttons must not draw on the screen below; a drag
  // there moves the toolbar.
  MouseArea {
    id: mover
    anchors.fill: parent
    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
    drag.target: bar
    drag.minimumX: 0
    drag.minimumY: 0
    drag.maximumX: bar.parent ? bar.parent.width - bar.width : 0
    drag.maximumY: bar.parent ? bar.parent.height - bar.height : 0
    onReleased: bar.service.toolbarPos = Qt.point(bar.x, bar.y)
  }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(6)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "⠿"
      color: Qt.darker(bar.fg, 1.4)
      font.pixelSize: Style.font.title
    }

    Repeater {
      model: Model.TOOLS

      delegate: Rectangle {
        required property var modelData
        readonly property bool chosen: bar.service.penTool === modelData.key
        width: Style.space(32)
        height: width
        radius: Style.space(6)
        color: chosen ? Util.alpha(bar.fg, 0.2) : "transparent"

        Text {
          anchors.centerIn: parent
          text: modelData.icon
          color: bar.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.title
        }
        Text {
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.margins: Style.space(2)
          text: modelData.letter
          color: Qt.darker(bar.fg, 1.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: bar.service.act("tool:" + modelData.key)
        }
      }
    }

    Rectangle { width: 1; height: Style.space(24); anchors.verticalCenter: parent.verticalCenter; color: Util.alpha(bar.fg, 0.3) }

    Repeater {
      model: Model.PALETTE

      delegate: Rectangle {
        required property var modelData
        readonly property bool chosen: bar.service.penColor === modelData.key
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(22)
        height: width
        radius: width / 2
        color: Model.colorOf(modelData.key, bar.service.accent)
        border.width: chosen ? Math.max(2, Style.space(3)) : 1
        border.color: chosen ? bar.fg : Util.alpha(bar.fg, 0.35)

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: bar.service.act("color:" + modelData.key)
        }
      }
    }

    Rectangle { width: 1; height: Style.space(24); anchors.verticalCenter: parent.verticalCenter; color: Util.alpha(bar.fg, 0.3) }

    PanelSlider {
      id: slider
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(120)
      height: Style.space(24)
      minimum: Model.WIDTH_MIN
      maximum: Model.WIDTH_MAX
      step: Model.WIDTH_STEP
      integer: true
      trackColor: Style.selectedFillFor(bar.fg, Color.accent)
      fillColor: bar.fg
      knobColor: bar.fg
      tickColor: bar.color
      value: bar.service.penWidth
      onReleased: function(value) { bar.service.store({ editWidth: Math.round(value) }) }
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(36)
      text: Math.round(slider.liveValue) + " px"
      color: bar.fg
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }
}
