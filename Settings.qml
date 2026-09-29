import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "I18n.js" as I18n

// predmaxim.annotate settings: each mode on or off, the color and width of
// temp lines and of the editor's pen, and the folder shots are saved to. A
// normal floating window (Super+W closes it). Changes go through the service
// into this plugin's entry in shell.json and apply at once.
// Open: `omarchy-shell predmaxim.annotate settings`, or Annotate in the app launcher.
Item {
  id: root

  // Injected by omarchy-shell.
  property var shell: null
  property var manifest: null
  property var service: null

  // True while the shell itself hides the window, so that is not reported back.
  property bool closingFromHost: false
  readonly property var tr: I18n.translator(I18n.textLanguage(function(name) { return Quickshell.env(name) }))
  readonly property var s: service ? service.settings : Model.normalize({})
  readonly property color accent: Color.accent
  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property int contentMargin: Style.spacing.panelPadding

  function open(payloadJson) {
    root.closingFromHost = false
    window.visible = true
    Qt.callLater(function() { if (window.visible) keys.forceActiveFocus() })
    raise.restart()
  }

  function close() {
    root.closingFromHost = true
    window.visible = false
    root.closingFromHost = false
  }

  function dismiss() {
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide((root.manifest && root.manifest.id) || "predmaxim.annotate")
    else close()
  }

  function set(key, value) {
    var change = {}
    change[key] = value
    if (root.service) root.service.store(change)
  }

  // The window may open behind others; ask Hyprland to focus it.
  Timer {
    id: raise
    interval: 120
    onTriggered: if (window.visible) Quickshell.execDetached(["hyprctl", "eval",
      "hl.dispatch(hl.dsp.focus({ window = " + JSON.stringify("title:^" + window.title + "$") + " }))"])
  }

  component Label: Text {
    Layout.fillWidth: true
    wrapMode: Text.WordWrap
    color: root.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  // Color, width and a sample line for one mode.
  component Pen: ColumnLayout {
    id: pen
    property string colorKey: ""
    property int lineWidth: 4
    signal colorPicked(string key)
    signal widthPicked(int value)
    Layout.fillWidth: true
    spacing: Style.space(6)

    RowLayout {
      spacing: Style.space(8)
      Repeater {
        model: Model.PALETTE
        delegate: Rectangle {
          required property var modelData
          readonly property bool chosen: pen.colorKey === modelData.key
          Layout.preferredWidth: Style.space(22)
          Layout.preferredHeight: Style.space(22)
          radius: width / 2
          color: Model.colorOf(modelData.key, root.accent)
          border.width: chosen ? Math.max(2, Style.space(3)) : 1
          border.color: chosen ? root.foreground : Util.alpha(root.foreground, 0.35)
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: pen.colorPicked(modelData.key)
          }
        }
      }
    }

    Label { text: root.tr("Width: %1 px", slider.liveValue) }

    PanelSlider {
      id: slider
      Layout.fillWidth: true
      Layout.preferredHeight: Style.space(24)
      minimum: Model.WIDTH_MIN
      maximum: Model.WIDTH_MAX
      step: Model.WIDTH_STEP
      integer: true
      trackColor: Style.selectedFillFor(root.foreground, Color.accent)
      fillColor: root.foreground
      knobColor: root.foreground
      tickColor: root.background
      value: pen.lineWidth
      onReleased: function(value) { pen.widthPicked(Math.round(value)) }
    }

    Item {
      Layout.fillWidth: true
      Layout.preferredHeight: Style.space(40)
      Shape {
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
          fillColor: "transparent"
          strokeColor: Model.colorOf(pen.colorKey, root.accent)
          strokeWidth: slider.liveValue
          capStyle: ShapePath.RoundCap
          joinStyle: ShapePath.RoundJoin
          PathSvg { path: "M 12 28 C 80 0 140 40 220 12" }
        }
      }
    }
  }

  FloatingWindow {
    id: window
    title: root.tr("Annotate")
    visible: false
    color: root.background
    implicitWidth: Style.space(440)
    implicitHeight: content.implicitHeight + root.contentMargin * 2
    // A fixed size, so Hyprland floats it like a dialog.
    minimumSize: Qt.size(implicitWidth, implicitHeight)
    maximumSize: Qt.size(implicitWidth, implicitHeight)

    // Closed by the compositor (Super+W): tell the shell, so it opens again next time.
    onVisibleChanged: {
      if (!visible && !root.closingFromHost && root.shell && typeof root.shell.hide === "function")
        root.shell.hide((root.manifest && root.manifest.id) || "predmaxim.annotate")
    }

    Item {
      id: keys
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.dismiss()

      ColumnLayout {
        id: content
        x: root.contentMargin
        y: root.contentMargin
        width: window.width - root.contentMargin * 2
        spacing: Style.space(12)

        Text {
          text: root.tr("Annotate")
          color: root.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Toggle {
          Layout.fillWidth: true
          label: root.tr("Draw while held (Ctrl+Super+drag)")
          description: root.tr("Lines vanish when Super or Ctrl is let go.")
          checked: root.s.tempEnabled
          foreground: root.foreground
          onClicked: root.set("tempEnabled", !root.s.tempEnabled)
        }

        Pen {
          enabled: root.s.tempEnabled
          opacity: enabled ? 1 : 0.5
          colorKey: root.s.tempColor
          lineWidth: root.s.tempWidth
          onColorPicked: function(key) { root.set("tempColor", key) }
          onWidthPicked: function(value) { root.set("tempWidth", value) }
        }

        PanelSeparator { Layout.fillWidth: true }

        Toggle {
          Layout.fillWidth: true
          label: root.tr("Editor (Shift+Super+click)")
          description: root.tr("Shapes and text. Ctrl+S saves the screen, Ctrl+Shift+S an area, Ctrl+C copies, Esc drops.")
          checked: root.s.editEnabled
          foreground: root.foreground
          onClicked: root.set("editEnabled", !root.s.editEnabled)
        }

        Pen {
          enabled: root.s.editEnabled
          opacity: enabled ? 1 : 0.5
          colorKey: root.s.editColor
          lineWidth: root.s.editWidth
          onColorPicked: function(key) { root.set("editColor", key) }
          onWidthPicked: function(value) { root.set("editWidth", value) }
        }

        Label { text: root.tr("Save to") }

        TextField {
          Layout.fillWidth: true
          text: root.s.saveDir
          placeholderText: root.tr("Empty — ~/Pictures/Screenshots")
          foreground: root.foreground
          font.family: Style.font.family
          onEditingFinished: root.set("saveDir", text)
        }

        RowLayout {
          Layout.fillWidth: true
          Layout.topMargin: Style.space(6)
          Item { Layout.fillWidth: true }
          Button {
            text: root.tr("Done")
            foreground: root.foreground
            bordered: true
            onClicked: root.dismiss()
          }
        }
      }
    }
  }
}
