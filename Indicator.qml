import QtQuick
import Quickshell
import qs.Ui
import "@PLUGIN_DIR@/I18n.js" as I18n

// predmaxim.annotate among the bar's indicators: a trigger, never "on", so it
// shows with the other inactive ones when the group is hovered. Click opens
// the editor on the focused monitor, right click the settings.
// keep-custom-widgets.sh copies this file into the predmaxim.indicators clone
// as indicators/Annotate.qml and fills in @PLUGIN_DIR@.
BarIndicator {
  id: root

  readonly property var tr: I18n.translator(I18n.textLanguage(function(name) { return Quickshell.env(name) }))

  active: false
  activeText: "󰏫"
  inactiveText: "󰏫"
  activeTooltipText: root.tr("Draw on screen · right click: settings")

  onPressed: function(button) {
    Quickshell.execDetached(["omarchy-shell", "predmaxim.annotate", button === Qt.RightButton ? "settings" : "edit"])
  }
}
