.pragma library
// Interface text in other languages, keyed by the English text itself, so a
// string missing from a table shows in English. tr("Saved: %1", x) fills in
// %1, %2… after the lookup. The same scheme as predmaxim.jira.
var TABLES = {
  ru: {
    "Annotate": "Рисование",
    // Service
    "Saved: %1": "Сохранено: %1",
    "Saved and copied: %1": "Сохранено и скопировано: %1",
    "Copied to the clipboard": "Скопировано в буфер обмена",
    "Not saved: %1": "Не сохранено: %1",
    "Not copied: %1": "Не скопировано: %1",
    // Settings
    "Draw while held (Ctrl+Super+drag)": "Рисовать, пока зажаты клавиши (Ctrl+Super+мышь)",
    "Lines vanish when Super or Ctrl is let go.": "Линии исчезают, когда отпускаешь Super или Ctrl.",
    "Editor (Shift+Super+click)": "Редактор (Shift+Super+щелчок)",
    "Shapes and text. Ctrl+S saves the screen, Ctrl+Shift+S an area, Ctrl+C copies, Esc drops.":
      "Фигуры и текст. Ctrl+S — сохранить экран, Ctrl+Shift+S — область, Ctrl+C — копировать, Esc — сбросить.",
    "Width: %1 px": "Толщина: %1 px",
    "Save to": "Сохранять в",
    "Empty — ~/Pictures/Screenshots": "Пусто — ~/Pictures/Screenshots",
    "Done": "Готово"
  }
}

// Text follows LC_MESSAGES, overridden by LC_ALL and defaulting to LANG, as
// the system splits it. env is name -> value (Quickshell.env in QML).
function textLanguage(env) {
  var names = ["LC_ALL", "LC_MESSAGES", "LANG"]
  for (var i = 0; i < names.length; i++) {
    var v = String(env(names[i]) || "").split(".")[0].split("@")[0]
    if (v && v !== "C" && v !== "POSIX") {
      var l = v.slice(0, 2).toLowerCase()
      return TABLES[l] ? l : "en"
    }
  }
  return "en"
}

function translator(lang) {
  var table = TABLES[lang] || {}
  return function(text) {
    var out = Object.prototype.hasOwnProperty.call(table, text) ? table[text] : text
    for (var i = 1; i < arguments.length; i++) out = out.split("%" + i).join(String(arguments[i]))
    return out
  }
}
