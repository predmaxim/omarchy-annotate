// node test.js
const fs = require("fs")
const path = require("path")
const assert = require("assert")
const os = require("os")
const { spawnSync } = require("child_process")
const load = (file, names) => new Function(
  fs.readFileSync(path.join(__dirname, file), "utf8").replace(".pragma library", "") + "; return {" + names + "}")()
const M = load("Model.js", "PALETTE, TOOLS, DEFAULTS, WIDTH_STEP, colorOf, normalize, readEntry, parseEvent, newShape, extend, isEmpty, svgPath, arrowHead, fontSize, keyAction, screenAt, fileName, areaGeometry, captureCommand")

// Palette: keys resolve to colors; accent and unknown keys take the theme's accent.
assert.strictEqual(M.PALETTE.length, 8)
assert.strictEqual(M.colorOf("red", "#123456"), "#e5484d")
assert.strictEqual(M.colorOf("accent", "#123456"), "#123456")
assert.strictEqual(M.colorOf("nope", "#123456"), "#123456")

// Settings: defaults fill gaps, bad values fall back, widths are clamped, unknown fields go.
assert.deepStrictEqual(M.normalize({}), M.DEFAULTS)
assert.deepStrictEqual(M.normalize(undefined), M.DEFAULTS)
assert.deepStrictEqual(
  M.normalize({ id: "x", tempEnabled: false, tempColor: "blue", tempWidth: 99, editColor: "pink",
    editWidth: 1, editTool: "brush", saveDir: "  ~/Shots ", junk: 1 }),
  { tempEnabled: false, tempColor: "blue", tempWidth: 24, editEnabled: true, editColor: "red",
    editWidth: 2, editTool: "pen", saveDir: "~/Shots" })
assert.strictEqual(M.normalize({ tempWidth: "abc" }).tempWidth, 4)
assert.strictEqual(M.normalize({ editWidth: 7 }).editWidth, 7)
assert.strictEqual(M.normalize({ editEnabled: "no" }).editEnabled, true)
assert.strictEqual(M.normalize({ editTool: "arrow" }).editTool, "arrow")

// shell.json: the plugin's entry, {} when absent, null when the file is broken.
const cfg = JSON.stringify({ plugins: [{ id: "other" }, { id: "predmaxim.annotate", tempColor: "green" }] })
assert.deepStrictEqual(M.readEntry(cfg, "predmaxim.annotate"), { id: "predmaxim.annotate", tempColor: "green" })
assert.deepStrictEqual(M.readEntry("{}", "predmaxim.annotate"), {})
assert.deepStrictEqual(M.readEntry("", "predmaxim.annotate"), {})
assert.strictEqual(M.readEntry("{\"plugins\": [", "predmaxim.annotate"), null)

// Events from annotate.lua.
assert.deepStrictEqual(M.parseEvent("custom", "annotate temp start 10.5 20"), { type: "start", mode: "temp", x: 10.5, y: 20 })
assert.deepStrictEqual(M.parseEvent("custom", "annotate edit start -1920.00 0.00"), { type: "start", mode: "edit", x: -1920, y: 0 })
assert.deepStrictEqual(M.parseEvent("custom", "annotate move 1 2"), { type: "move", x: 1, y: 2 })
assert.deepStrictEqual(M.parseEvent("custom", "annotate end"), { type: "end" })
assert.strictEqual(M.parseEvent("custom", "annotate release"), null, "release is not an event any more")
for (const [name, data] of [["custom", "omannotate start 1 2"], ["workspace", "annotate end"],
  ["custom", "annotate move 1"], ["custom", "annotate move x 2"], ["custom", "annotate fly start 1 2"], ["custom", undefined]])
  assert.strictEqual(M.parseEvent(name, data), null, name + " " + data)

// Pen: points closer than 1 px are dropped; a single click is a dot.
const pen = M.newShape("pen", "red", 4, 0, 0)
assert.strictEqual(M.extend(pen, 0.5, 0), false)
assert.strictEqual(M.extend(pen, 3, 4), true)
assert.deepStrictEqual(pen.points, [[0, 0], [3, 4]])
assert.strictEqual(M.svgPath(pen), "M 0 0 L 3 4")
const dot = M.newShape("pen", "red", 4, 5, 5)
assert.strictEqual(M.isEmpty(dot), false)
assert.strictEqual(M.svgPath(dot), "M 5 5 L 5 5")

// Rect and ellipse: any drag direction; a flat one is empty.
const r = M.newShape("rect", "red", 4, 10, 10)
M.extend(r, 0, 30)
assert.strictEqual(M.svgPath(r), "M 0 10 L 10 10 L 10 30 L 0 30 Z")
assert.strictEqual(M.isEmpty(r), false)
const flat = M.newShape("rect", "red", 4, 0, 0)
M.extend(flat, 50, 1)
assert.strictEqual(M.isEmpty(flat), true)
assert.strictEqual(M.extend(flat, 50, 1), false, "the same point changes nothing")
const e = M.newShape("ellipse", "red", 4, 0, 0)
M.extend(e, 20, 10)
assert.strictEqual(M.svgPath(e), "M 0 5 A 10 5 0 1 0 20 5 A 10 5 0 1 0 0 5 Z")

// Arrow: a head of max(12, 4·width) at ±30°, never longer than the arrow.
const a = M.newShape("arrow", "red", 4, 0, 0)
M.extend(a, 100, 0)
assert.deepStrictEqual(M.arrowHead(a).map(p => p.map(v => Math.round(v * 100) / 100)), [[86.14, 8], [86.14, -8]])
assert.strictEqual(M.svgPath(a), "M 0 0 L 100 0 M 86.14 8 L 100 0 L 86.14 -8")
const short = M.newShape("arrow", "red", 4, 0, 0)
M.extend(short, 10, 0)
const tip = M.arrowHead(short)[0]
assert.ok(Math.abs(Math.hypot(tip[0] - 10, tip[1]) - 10) < 1e-9, "the head is cut to the arrow's length")
const stub = M.newShape("arrow", "red", 4, 0, 0)
M.extend(stub, 1, 1)
assert.strictEqual(M.isEmpty(stub), true)

// Text: blank text is empty; the size grows with the width.
const t = M.newShape("text", "red", 4, 0, 0)
assert.strictEqual(M.isEmpty(t), true)
t.text = "hi"; assert.strictEqual(M.isEmpty(t), false)
t.text = "   "; assert.strictEqual(M.isEmpty(t), true)
assert.strictEqual(M.fontSize(4), 20)

// Keys: a Latin Qt key first (wtype, English layout), else the scan code
// (evdev + 8), so the Russian layout works too.
const CYR = 0x42b  // Ы: what the S key gives in the Russian layout
assert.strictEqual(M.keyAction(9, 0x01000000, false, false), "close")
assert.strictEqual(M.keyAction(0, 0x01000000, false, false), "close")
assert.strictEqual(M.keyAction(39, 0x53, true, false), "save")
assert.strictEqual(M.keyAction(39, CYR, true, false), "save", "Russian layout: by scan code")
assert.strictEqual(M.keyAction(39, CYR, true, true), "saveRegion")
assert.strictEqual(M.keyAction(200, 0x53, true, false), "save", "wtype: unknown scan code, Latin key")
assert.strictEqual(M.keyAction(9, 0x53, true, false), "save", "the Latin key wins over a colliding scan code")
assert.strictEqual(M.keyAction(54, 0x43, true, false), "copy")
assert.strictEqual(M.keyAction(52, 0x5a, true, false), "undo")
assert.strictEqual(M.keyAction(54, 0x43, false, false), "tool:ellipse")
assert.deepStrictEqual([33, 27, 38, 28].map(c => M.keyAction(c, 0, false, false)),
  ["tool:pen", "tool:rect", "tool:arrow", "tool:text"])
assert.strictEqual(M.keyAction(10, 0x31, false, false), "color:accent")
assert.strictEqual(M.keyAction(17, 0x38, false, false), "color:black")
assert.strictEqual(M.keyAction(34, 0x445, false, false), "narrower", "[ is х in the Russian layout")
assert.strictEqual(M.keyAction(35, 0x5d, false, false), "wider")
assert.strictEqual(M.keyAction(39, 0x53, false, false), "", "a bare S does nothing")
assert.strictEqual(M.keyAction(33, 0x50, true, false), "", "Ctrl+P does nothing")
assert.strictEqual(M.keyAction(10, 0x31, true, false), "", "Ctrl+1 does nothing")

// Screens: the one under the point, else the first.
const screens = [{ name: "A", x: 0, y: 0, width: 1920, height: 1080 }, { name: "B", x: 1920, y: 0, width: 2560, height: 1440 }]
assert.strictEqual(M.screenAt(screens, 100, 100).name, "A")
assert.strictEqual(M.screenAt(screens, 1920, 1200).name, "B")
assert.strictEqual(M.screenAt(screens, -5, -5).name, "A")
assert.strictEqual(M.screenAt([], 0, 0), null)

// File name: local time.
assert.strictEqual(M.fileName(new Date(2026, 8, 29, 7, 5, 3)), "annotate-2026-09-29_07-05-03.png")

// Area drawn in the editor: any drag direction, rounded; too small is none.
assert.strictEqual(M.areaGeometry(100.4, 50, 10, 200.6), "10,50 90x151")
assert.strictEqual(M.areaGeometry(-1920, 0, -1900, 30), "-1920,0 20x30")
assert.strictEqual(M.areaGeometry(5, 5, 6, 90), "")

// Capture script, run with grim and wl-copy stubs in a scratch HOME.
function capture(kind, saveDir, prepare, area) {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "annotate-"))
  const bin = path.join(home, "bin")
  fs.mkdirSync(bin)
  const stub = (name, body) => fs.writeFileSync(path.join(bin, name), "#!/bin/bash\n" + body + "\n", { mode: 0o755 })
  stub("grim", 'echo "$*" >> "$HOME/grim.args"; [[ -n $GRIM_FAIL ]] && { echo "grim: no output" >&2; exit 1; }; out=${@: -1}; if [[ $out == - ]]; then echo PNG; else echo PNG > "$out"; fi')
  stub("slurp", 'touch "$HOME/slurp.called"')
  stub("wl-copy", 'cat > "$HOME/clip"; echo "$*" > "$HOME/wl-copy.args"')
  const env = Object.assign({ PATH: bin + ":" + process.env.PATH, HOME: home }, prepare ? prepare(home) : {})
  const cmd = M.captureCommand(kind, "DP-1", saveDir, "shot.png", area)
  const r = spawnSync(cmd[0], cmd.slice(1), { env, encoding: "utf8" })
  const read = f => fs.existsSync(path.join(home, f)) ? fs.readFileSync(path.join(home, f), "utf8") : null
  return { home, status: r.status, out: r.stdout.trim(), err: r.stderr, read }
}

let c = capture("screen", "")
assert.strictEqual(c.status, 0, c.err)
assert.strictEqual(c.out, c.home + "/Pictures/Screenshots/shot.png")
assert.strictEqual(c.read("Pictures/Screenshots/shot.png"), "PNG\n")
assert.strictEqual(c.read("grim.args"), "-o DP-1 " + c.home + "/Pictures/Screenshots/shot.png\n")
assert.strictEqual(c.read("clip"), null, "Ctrl+S does not touch the clipboard")

c = capture("screen", "~/My Shots")
assert.strictEqual(c.out, c.home + "/My Shots/shot.png", "~ and spaces in the folder")
assert.strictEqual(c.read("My Shots/shot.png"), "PNG\n")

c = capture("screen", "", home => ({ OMARCHY_SCREENSHOT_DIR: home + "/omarchy" }))
assert.strictEqual(c.out, c.home + "/Pictures/Screenshots/shot.png", "Omarchy's screenshot folder is not used")

c = capture("screen", "", home => {
  fs.mkdirSync(home + "/.config")
  fs.writeFileSync(home + "/.config/user-dirs.dirs", 'XDG_PICTURES_DIR="$HOME/Images"\n')
  return {}
})
assert.strictEqual(c.out, c.home + "/Images/Screenshots/shot.png")

c = capture("region", "", null, "1,2 30x40")
assert.strictEqual(c.status, 0, c.err)
assert.strictEqual(c.out, c.home + "/Pictures/Screenshots/shot.png")
assert.strictEqual(c.read("grim.args"), "-g 1,2 30x40 " + c.home + "/Pictures/Screenshots/shot.png\n")
assert.strictEqual(c.read("clip"), "PNG\n", "the area goes to the clipboard too")
assert.strictEqual(c.read("wl-copy.args"), "-t image/png\n")

c = capture("region", "", () => ({ GRIM_FAIL: "1" }), "1,2 30x40")
assert.notStrictEqual(c.status, 0)
assert.strictEqual(c.read("clip"), null, "nothing is copied when the shot failed")
assert.strictEqual(c.read("slurp.called"), null, "the area comes from the editor, not slurp")

c = capture("copy", "")
assert.strictEqual(c.status, 0, c.err)
assert.strictEqual(c.read("clip"), "PNG\n")
assert.strictEqual(c.read("wl-copy.args"), "-t image/png\n")
assert.strictEqual(c.read("Pictures/Screenshots/shot.png"), null, "copying saves no file")

c = capture("copy", "", () => ({ GRIM_FAIL: "1" }))
assert.notStrictEqual(c.status, 0, "a failed grim fails the copy")

c = capture("screen", "", () => ({ GRIM_FAIL: "1" }))
assert.notStrictEqual(c.status, 0)
assert.strictEqual(c.out, "", "no path for a failed shot")
assert.match(c.err, /grim: no output/)

// Interface language, and a Russian line for every tr("…") in the QML.
const I = load("I18n.js", "TABLES, textLanguage, translator")
const envOf = o => n => o[n]
assert.strictEqual(I.textLanguage(envOf({ LANG: "ru_RU.UTF-8" })), "ru")
assert.strictEqual(I.textLanguage(envOf({ LANG: "ru_RU.UTF-8", LC_ALL: "en_US.UTF-8" })), "en")
assert.strictEqual(I.translator("ru")("Saved: %1", "/a.png"), "Сохранено: /a.png")
const qml = fs.readdirSync(__dirname).filter(f => f.endsWith(".qml"))
const keys = qml.flatMap(f => [...fs.readFileSync(path.join(__dirname, f), "utf8").matchAll(/\btr\("((?:[^"\\]|\\.)*)"/g)].map(m => m[1]))
assert.deepStrictEqual(keys.filter(k => !(k in I.TABLES.ru)), [])
console.log("ok")
