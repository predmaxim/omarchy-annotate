-- predmaxim.annotate: the Hyprland side of drawing on screen.
--
-- Service.qml loads this file with `hyprctl eval` when it starts and after
-- every config reload (a reload starts a fresh Lua state). Hyprland only
-- reports the pointer on its event socket; the service draws:
--   custom>>annotate temp start X Y   Ctrl+Super+button went down
--   custom>>annotate edit start X Y   Shift+Super+button went down
--   custom>>annotate move X Y         the cursor moved (at most once a frame)
--   custom>>annotate end              the button came up
-- Letting go of Ctrl/Super is seen by the temp overlay, which takes the
-- keyboard: release binds on a modifier never fire once a mouse bind fired
-- while it was held (Hyprland 0.56, checked by hand).
--
-- Hyprland 0.56 (as learned in omannotate): binds are made once and then only
-- enabled or disabled. Unbinding removes every bind on the same key, and
-- touching a removed bind from Lua crashes Hyprland; tostring() is the one
-- safe way to see whether a bind was removed elsewhere.

local VERSION = 1
if type(annotate) == "table" and annotate.version == VERSION then return end

local FRAME_MS = 16

-- A newer copy loaded into the same Lua state keeps the older copy's binds,
-- timer and state; every callback goes through the global table.
local previous = type(annotate) == "table" and type(annotate.state) == "table" and annotate or nil
local state = previous and previous.state or { drawing = false, temp = false, edit = false }
local M = { version = VERSION, state = state, binds = previous and previous.binds or {} }
M.sampler = previous and previous.sampler
annotate = M

local function emit(text)
  hl.dispatch(hl.dsp.event("annotate " .. text))
end

local function alive(keybind)
  return keybind ~= nil and tostring(keybind) ~= "HL.Keybind(expired)"
end

local function enable(name, on)
  if alive(M.binds[name]) then M.binds[name]:set_enabled(on) end
end

-- Cursor movement has no Lua event, so it is sampled only while a line is drawn.
function M.sample()
  if not state.drawing then return end
  local p = hl.get_cursor_pos()
  if p and (p.x ~= state.x or p.y ~= state.y) then
    state.x, state.y = p.x, p.y
    emit(string.format("move %.2f %.2f", p.x, p.y))
  end
end

function M.press(mode)
  local p = hl.get_cursor_pos()
  if not p then return end
  state.drawing, state.x, state.y = true, p.x, p.y
  emit(string.format("%s start %.2f %.2f", mode, p.x, p.y))
  M.sampler:set_enabled(true)
end

function M.finish()
  if not state.drawing then return end
  -- The button can come up after the cursor moved since the last sample.
  M.sample()
  state.drawing = false
  M.sampler:set_enabled(false)
  emit("end")
end

local SPECS = {
  temp = { "SUPER + CTRL + mouse:272", function() annotate.press("temp") end,
    { description = "Annotate: draw while Ctrl+Super are held" } },
  edit = { "SUPER + SHIFT + mouse:272", function() annotate.press("edit") end,
    { description = "Annotate: open the editor" } },
  -- Ends the line even if the keys are let go before the button. A release
  -- bind swallows every press unless it is non-consuming.
  button = { "mouse:272", function() annotate.finish() end,
    { release = true, ignore_mods = true, non_consuming = true } },
}

-- Makes what is missing; a live bind is never replaced.
local function ensure()
  if not M.sampler then
    M.sampler = hl.timer(function() annotate.sample() end, { timeout = FRAME_MS, type = "repeat" })
    M.sampler:set_enabled(false)
  end
  for name, spec in pairs(SPECS) do
    if not alive(M.binds[name]) then M.binds[name] = hl.bind(spec[1], spec[2], spec[3]) end
  end
end

local function apply()
  local owned = state.owner ~= nil
  local any = owned and (state.temp or state.edit)
  enable("temp", owned and state.temp)
  enable("edit", owned and state.edit)
  enable("button", any)
  if not any then M.finish() end
end

-- The newest service owns the binds: one that a plugin reload replaced must
-- not switch the new one's off when it shuts down.
function M.activate(token, temp, edit)
  state.owner, state.temp, state.edit = token, temp == true, edit == true
  ensure()
  apply()
  return "ok"
end

function M.set_modes(token, temp, edit)
  if token ~= state.owner then return "not owner" end
  state.temp, state.edit = temp == true, edit == true
  apply()
  return "ok"
end

function M.deactivate(token)
  if token ~= state.owner then return "not owner" end
  state.owner = nil
  apply()
  return "ok"
end

if not previous then
  hl.layer_rule({ match = { namespace = "predmaxim-annotate" }, no_anim = true, animation = "none" })
end
ensure()
apply()  -- Everything stays off until a service activates it.
