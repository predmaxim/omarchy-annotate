.pragma library
// predmaxim.annotate: everything that needs no QML — the palette, settings,
// events from annotate.lua, shapes, keys and the capture script (node test.js).

var PALETTE = [
  { key: "accent", color: "" },  // The theme's accent, given by the caller.
  { key: "red", color: "#e5484d" },
  { key: "orange", color: "#f76b15" },
  { key: "yellow", color: "#ffc53d" },
  { key: "green", color: "#46a758" },
  { key: "blue", color: "#3e63dd" },
  { key: "white", color: "#ffffff" },
  { key: "black", color: "#111111" }
]

var TOOLS = [
  { key: "pen", icon: "✎", letter: "P" },
  { key: "rect", icon: "▭", letter: "R" },
  { key: "ellipse", icon: "◯", letter: "C" },
  { key: "arrow", icon: "↗", letter: "A" },
  { key: "text", icon: "T", letter: "T" }
]

var WIDTH_MIN = 2
var WIDTH_MAX = 24
var WIDTH_STEP = 2

var DEFAULTS = {
  tempEnabled: true, tempColor: "red", tempWidth: 4,
  editEnabled: true, editColor: "red", editWidth: 4, editTool: "pen",
  saveDir: ""
}

function has(list, key) {
  for (var i = 0; i < list.length; i++) if (list[i].key === key) return true
  return false
}

function colorOf(key, accent) {
  for (var i = 0; i < PALETTE.length; i++)
    if (PALETTE[i].key === key) return PALETTE[i].color || accent
  return accent
}

function clampWidth(value, fallback) {
  var n = Math.round(Number(value))
  if (value === undefined || value === null || !isFinite(n)) return fallback
  return Math.max(WIDTH_MIN, Math.min(WIDTH_MAX, n))
}

// Every field present and valid; anything else is dropped. shell.json keeps
// exactly this, since updateEntryInline replaces the whole entry.
function normalize(entry) {
  var e = entry || {}
  function flag(v, d) { return typeof v === "boolean" ? v : d }
  return {
    tempEnabled: flag(e.tempEnabled, DEFAULTS.tempEnabled),
    tempColor: has(PALETTE, e.tempColor) ? e.tempColor : DEFAULTS.tempColor,
    tempWidth: clampWidth(e.tempWidth, DEFAULTS.tempWidth),
    editEnabled: flag(e.editEnabled, DEFAULTS.editEnabled),
    editColor: has(PALETTE, e.editColor) ? e.editColor : DEFAULTS.editColor,
    editWidth: clampWidth(e.editWidth, DEFAULTS.editWidth),
    editTool: has(TOOLS, e.editTool) ? e.editTool : DEFAULTS.editTool,
    saveDir: typeof e.saveDir === "string" ? e.saveDir.trim() : DEFAULTS.saveDir
  }
}

// This plugin's entry in shell.json; {} when there is none, null when the
// file does not parse (a half-written file keeps the previous settings).
function readEntry(text, id) {
  var config
  try { config = JSON.parse(text || "{}") } catch (e) { return null }
  var plugins = config && Array.isArray(config.plugins) ? config.plugins : []
  for (var i = 0; i < plugins.length; i++)
    if (plugins[i] && plugins[i].id === id) return plugins[i]
  return {}
}

// Hyprland's `custom>>annotate …` events (annotate.lua).
function parseEvent(name, data) {
  if (name !== "custom" || typeof data !== "string") return null
  var w = data.split(" ").filter(function(s) { return s !== "" })
  if (w[0] !== "annotate") return null
  if (w.length === 2 && w[1] === "end") return { type: "end" }
  var start = w.length === 5 && w[2] === "start" && (w[1] === "temp" || w[1] === "edit")
  var move = w.length === 4 && w[1] === "move"
  if (!start && !move) return null
  var x = Number(w[w.length - 2]), y = Number(w[w.length - 1])
  if (!isFinite(x) || !isFinite(y)) return null
  return start ? { type: "start", mode: w[1], x: x, y: y } : { type: "move", x: x, y: y }
}

function newShape(tool, color, width, x, y) {
  if (tool === "pen") return { type: "pen", color: color, width: width, points: [[x, y]] }
  return { type: tool, color: color, width: width, x1: x, y1: y, x2: x, y2: y, text: "" }
}

// Moves the free end; false when nothing changed, so nothing repaints.
function extend(shape, x, y) {
  if (shape.type === "pen") {
    var p = shape.points[shape.points.length - 1]
    if (Math.hypot(x - p[0], y - p[1]) < 1) return false
    shape.points.push([x, y])
    return true
  }
  if (shape.x2 === x && shape.y2 === y) return false
  shape.x2 = x
  shape.y2 = y
  return true
}

function isEmpty(shape) {
  if (shape.type === "pen") return false  // A click leaves a dot.
  if (shape.type === "text") return String(shape.text || "").trim() === ""
  if (shape.type === "arrow") return Math.hypot(shape.x2 - shape.x1, shape.y2 - shape.y1) < 2
  return Math.abs(shape.x2 - shape.x1) < 2 || Math.abs(shape.y2 - shape.y1) < 2
}

function arrowHead(shape) {
  var dx = shape.x2 - shape.x1, dy = shape.y2 - shape.y1
  var size = Math.min(Math.max(12, 4 * shape.width), Math.hypot(dx, dy))
  var angle = Math.atan2(dy, dx)
  return [-1, 1].map(function(side) {
    var a = angle + side * Math.PI / 6
    return [shape.x2 - size * Math.cos(a), shape.y2 - size * Math.sin(a)]
  })
}

function svg(parts) {
  return parts.map(function(p) {
    return typeof p === "number" ? String(Math.round(p * 100) / 100) : p
  }).join(" ")
}

// An SVG path for PathSvg, in the same (global) coordinates as the shape.
function svgPath(shape) {
  if (shape.type === "pen") {
    var pts = shape.points
    var parts = ["M", pts[0][0], pts[0][1]]
    if (pts.length === 1) parts.push("L", pts[0][0], pts[0][1])  // A round-capped dot.
    for (var i = 1; i < pts.length; i++) parts.push("L", pts[i][0], pts[i][1])
    return svg(parts)
  }
  if (shape.type === "arrow") {
    var h = arrowHead(shape)
    return svg(["M", shape.x1, shape.y1, "L", shape.x2, shape.y2,
      "M", h[0][0], h[0][1], "L", shape.x2, shape.y2, "L", h[1][0], h[1][1]])
  }
  var x = Math.min(shape.x1, shape.x2), y = Math.min(shape.y1, shape.y2)
  var w = Math.abs(shape.x2 - shape.x1), hgt = Math.abs(shape.y2 - shape.y1)
  if (shape.type === "rect")
    return svg(["M", x, y, "L", x + w, y, "L", x + w, y + hgt, "L", x, y + hgt, "Z"])
  var rx = w / 2, ry = hgt / 2, cy = y + ry
  return svg(["M", x, cy, "A", rx, ry, 0, 1, 0, x + w, cy, "A", rx, ry, 0, 1, 0, x, cy, "Z"])
}

function fontSize(width) {
  return 12 + 2 * width
}

// Named keys by Qt key (Latin layouts, wtype) and by scan code (evdev + 8,
// the same key whatever layout is on — the Russian one gives Cyrillic Qt keys).
var BY_KEY = {
  0x01000000: "esc", 0x53: "s", 0x43: "c", 0x5a: "z", 0x50: "p", 0x52: "r", 0x41: "a", 0x54: "t",
  0x5b: "[", 0x5d: "]", 0x31: "1", 0x32: "2", 0x33: "3", 0x34: "4", 0x35: "5", 0x36: "6", 0x37: "7", 0x38: "8"
}
var BY_SCAN = {
  9: "esc", 39: "s", 54: "c", 52: "z", 33: "p", 27: "r", 38: "a", 28: "t", 34: "[", 35: "]",
  10: "1", 11: "2", 12: "3", 13: "4", 14: "5", 15: "6", 16: "7", 17: "8"
}
var TOOL_BY_NAME = { p: "pen", r: "rect", c: "ellipse", a: "arrow", t: "text" }

function keyAction(scan, key, ctrl, shift) {
  var name = BY_KEY[key] || BY_SCAN[scan] || ""
  if (name === "esc") return "close"
  if (ctrl) {
    if (name === "s") return shift ? "saveRegion" : "save"
    if (name === "c") return "copy"
    if (name === "z") return "undo"
    return ""
  }
  if (name >= "1" && name <= "8" && name.length === 1) return "color:" + PALETTE[Number(name) - 1].key
  if (name === "[") return "narrower"
  if (name === "]") return "wider"
  return TOOL_BY_NAME[name] ? "tool:" + TOOL_BY_NAME[name] : ""
}

// The screen holding the point (global, logical pixels); else the first.
function screenAt(screens, x, y) {
  for (var i = 0; i < screens.length; i++) {
    var s = screens[i]
    if (x >= s.x && x < s.x + s.width && y >= s.y && y < s.y + s.height) return s
  }
  return screens.length > 0 ? screens[0] : null
}

function pad(n) {
  return (n < 10 ? "0" : "") + n
}

function fileName(d) {
  return "annotate-" + d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate())
    + "_" + pad(d.getHours()) + "-" + pad(d.getMinutes()) + "-" + pad(d.getSeconds()) + ".png"
}

// Saves or copies the monitor with the drawing on it (the overlay is on
// screen, so grim takes it too). Prints the saved path; exits 2 when the
// area selection was cancelled. The folder is found as omarchy-capture-screenshot does.
var CAPTURE = [
  'set -o pipefail',
  'kind=$1 monitor=$2 dir=$3 name=$4',
  'if [[ $kind == copy ]]; then grim -o "$monitor" - | wl-copy -t image/png; exit; fi',
  '[[ -f ~/.config/user-dirs.dirs ]] && source ~/.config/user-dirs.dirs',
  'dir=${dir/#\\~/$HOME}',
  'dir=${dir:-${OMARCHY_SCREENSHOT_DIR:-${XDG_PICTURES_DIR:-$HOME/Pictures}}}',
  'mkdir -p "$dir" || exit',
  'if [[ $kind == region ]]; then',
  '  area=$(slurp) || exit 2',
  '  grim -g "$area" "$dir/$name"',
  'else',
  '  grim -o "$monitor" "$dir/$name"',
  'fi || exit',
  'echo "$dir/$name"'
].join("\n")

function captureCommand(kind, monitor, saveDir, name) {
  return ["bash", "-c", CAPTURE, "annotate", kind, monitor, saveDir || "", name]
}
