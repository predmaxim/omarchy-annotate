-- lua annotate_test.lua (from any folder)
local events, made = {}, {}
local cursor = { x = 10, y = 20 }

local function handle(spec)
  local h = { spec = spec, enabled = true, expired = false }
  function h:set_enabled(on) self.enabled = on end
  return setmetatable(h, { __tostring = function(self)
    return self.expired and "HL.Keybind(expired)" or "HL.Keybind"
  end })
end

hl = {
  bind = function(keys, fn, opts) local b = handle({ keys = keys, fn = fn, opts = opts }); made[#made + 1] = b; return b end,
  timer = function(fn, opts) local t = handle({ fn = fn, opts = opts }); made[#made + 1] = t; return t end,
  dispatch = function(e) events[#events + 1] = e end,
  dsp = { event = function(text) return text end },
  get_cursor_pos = function() return { x = cursor.x, y = cursor.y } end,
  layer_rule = function() end,
}

local path = (arg[0]:match("^(.*)/") or ".") .. "/annotate.lua"
dofile(path)
local A = annotate
local function b(name) return A.binds[name] end
local function last() return events[#events] end
local function fire(name) b(name).spec.fn() end
local function tick() A.sampler.spec.fn() end

-- Loaded without an owner: nothing is bound.
for _, name in ipairs({ "temp", "edit", "button" }) do
  assert(b(name).enabled == false, name .. " must start disabled")
end
-- Letting go of Ctrl/Super is caught by the temp overlay (Service.qml), not by
-- release binds: Hyprland drops those once a mouse bind fired while held.
local count = 0
for _ in pairs(A.binds) do count = count + 1 end
assert(count == 3, "only temp, edit and button are bound, got " .. count)
assert(b("temp").spec.keys == "SUPER + CTRL + mouse:272")
assert(b("edit").spec.keys == "SUPER + SHIFT + mouse:272")
assert(b("button").spec.opts.release and b("button").spec.opts.non_consuming and b("button").spec.opts.ignore_mods)

assert(A.activate("a", true, true) == "ok")
assert(b("temp").enabled and b("edit").enabled and b("button").enabled)

-- A temp line: start, a move only when the cursor moves, end.
fire("temp")
assert(last() == "annotate temp start 10.00 20.00", last())
assert(A.sampler.enabled)
local n = #events
tick(); assert(#events == n, "a still cursor sends nothing")
cursor.x = 15; tick(); assert(last() == "annotate move 15.00 20.00", last())
cursor.y = 25; fire("button")
assert(events[#events - 1] == "annotate move 15.00 25.00" and last() == "annotate end")
assert(not A.sampler.enabled)
n = #events; fire("button"); assert(#events == n, "a stray button release sends nothing")

-- Shift+Super+click only opens the editor: no line, no sampling, no end.
fire("edit"); assert(last() == "annotate edit start 15.00 25.00", last())
assert(not A.sampler.enabled, "opening the editor draws nothing")
n = #events; fire("button"); assert(#events == n)

-- Modes: only the owner switches them; switching everything off ends a line.
assert(A.set_modes("b", false, false) == "not owner")
assert(b("temp").enabled)
assert(A.set_modes("a", false, true) == "ok")
assert(not b("temp").enabled and b("edit").enabled and b("button").enabled)
assert(A.activate("a", true, true) == "ok")
fire("temp")
assert(A.set_modes("a", false, false) == "ok")
assert(not b("button").enabled and last() == "annotate end" and not A.sampler.enabled)

-- Loading the same version again changes nothing.
local count = #made
dofile(path)
assert(#made == count and annotate == A)

-- A new owner takes over; a bind removed elsewhere is made again.
b("temp").expired = true
local old = b("temp")
assert(A.activate("c", true, false) == "ok")
assert(b("temp") ~= old and b("temp").enabled)
assert(A.deactivate("a") == "not owner" and b("temp").enabled)
assert(A.deactivate("c") == "ok" and not b("temp").enabled and not b("edit").enabled)

print("annotate_test.lua: ok")
