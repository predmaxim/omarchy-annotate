import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import "@PLUGIN_DIR@/I18n.js" as I18n

// predmaxim.annotate among the bar's indicators: "on" while drawing on screen
// or the editor is open (Service.qml keeps a flag file), otherwise shown only
// when the group is hovered. Click opens
// the editor on the focused monitor, right click the settings.
// keep-custom-widgets.sh copies this file into the predmaxim.indicators clone
// as indicators/Annotate.qml and fills in @PLUGIN_DIR@.
BarIndicator {
  id: root

  readonly property var tr: I18n.translator(I18n.textLanguage(function(name) { return Quickshell.env(name) }))

  active: false

  FileView {
    path: Quickshell.env("XDG_RUNTIME_DIR") + "/predmaxim-annotate"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.active = text().trim() === "1"
    onLoadFailed: root.active = false
  }
  activeText: "󰏫"
  inactiveText: "󰏫"
  activeTooltipText: root.tr("Draw on screen · right click: settings")

  onPressed: function(button) {
    Quickshell.execDetached(["omarchy-shell", "predmaxim.annotate", button === Qt.RightButton ? "settings" : "edit"])
  }
}
