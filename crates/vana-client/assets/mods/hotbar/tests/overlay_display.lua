-- Hotbars overlay display: HUD slots and knobs, bar order, library drops, suggestion glow, and display / mode switches.

local HUD = { elems = {}, handlers = {}, removed = {} }
local function hud_put(kind, id, spec)
  HUD.elems[id] = { kind = kind, spec = spec }
  HUD.removed[id] = nil
end
hud = {
  screen = function() return { width = 800, height = 600, ui_scale = 1 } end,
  rect = function(id, spec) hud_put("rect", id, spec) end,
  tri = function(id, spec) hud_put("tri", id, spec) end,
  icon = function(id, spec) hud_put("icon", id, spec) end,
  text = function(id, spec) hud_put("text", id, spec) end,
  on = function(id, f) HUD.handlers[id] = f end,
  off = function(id) HUD.handlers[id] = nil end,
  remove = function(id) HUD.elems[id] = nil; HUD.removed[id] = true end,
}
input.mouse = function() return { x = 400, y = 550 } end

local FRAME = {}
events = {
  on = function(n, f)
    FRAME[n] = FRAME[n] or {}
    FRAME[n][#FRAME[n] + 1] = f
  end,
  off = function(h) for _, list in pairs(FRAME) do for i, f in ipairs(list) do if f == h then table.remove(list, i); break end end end end,
  emit = function(n, ...)
    for _, f in ipairs(FRAME[n] or {}) do f(...) end
  end,
}
timer.after = function(_, f) f() end
timer.every = function() end
chat = { add = function() end }
storage = { character = { hb_shown = 2 }, account = {}, save = function() end }

local OVER = { on = true, visible = true, display = "Overlay", bars = 2, slots = 12, size = 40, gap = 4,
  show_keys = false, pad_size = 36, pad_autohide = false }
local real_get = settings.get
settings.get = function(k) if OVER[k] ~= nil then return OVER[k] end return real_get(k) end

res = setmetatable({
  spell = function(id) if id == 1 then return { name = "Cure", kind = 1 } end end,
  job = function(id) return ({ [5] = "RDM" })[id] end,
}, { __index = function() return function() end end })
game = setmetatable({
  player = function() return { main_job = 5, sub_job = 0 } end,
  recasts = function() return { spells = {}, abilities = {}, totals = { spells = {}, abilities = {} } } end,
}, { __index = function() return function() return {} end end })

local OPEN = {}
ui.window = function() end
ui.on = function() end
ui.update = function() end
ui.close = function(id) OPEN[id] = nil end
ui.open = function(id) OPEN[id] = true end
ui.is_open = function(id) return OPEN[id] end

local data = require("src.data")
data.init({ read = function() return nil end, write = function() end, decode = json.decode, encode = json.encode })
local lib_id = data.save_entry("RDM", nil, { name = "Cure", action = { kind = "ma", name = "Cure", target = "t" },
  lines = { '/ma "Cure" <t>' } })
local grp_id = data.save_entry("RDM", nil, { name = "Sets", group = {
  { name = "A", lines = { '/echo a' } },
  { name = "B", lines = { '/echo b' } },
} })
data.assign("RDM", nil, 1, 1, lib_id)
data.assign("RDM", nil, 1, 3, grp_id)

local bar = require("src.bar")
bar.hooks = { changed = function() end, open_manager = function() end, palette = function() end }
bar.rebuild()

assert(HUD.elems["ovb_1_1"], "overlay draws slot 1:1")
assert(HUD.elems["ovb_1_3_g"] and HUD.elems["ovb_1_3_g"].kind == "tri", "group slots draw a gold hud.tri marker")
assert(HUD.elems["ovb_plus"] and HUD.elems["ovb_minus"], "overlay draws grow knobs")
local y1, y2 = HUD.elems["ovb_1_1"].spec.y, HUD.elems["ovb_2_1"].spec.y
assert(y1 > y2, ("bar 1 (y=%s) sits below bar 2 (y=%s)"):format(y1, y2))

events.emit("suggestions", { { kind = "spell", id = 1 } })
assert(HUD.elems["ovb_1_1_sg0"], "suggestion glow draws without error")

local overlay = require("src.overlay")
local slot = HUD.elems["ovb_1_3"].spec
assert(overlay.drop_at(slot.x + 2, slot.y + 2, lib_id))
local dropped, from = data.resolve("RDM", nil, 1, 3)
assert(dropped and dropped.name == "Cure" and from == "main", "a library drop lands on the slot under the pointer")

OVER.display = "Window"
bar.rebuild()
assert(OPEN.bars and HUD.removed["ovb_1_1"], "window mode opens the bars canvas and clears overlay slots")

OVER.display = "Overlay"
HUD.elems, HUD.removed = {}, {}
bar.rebuild()
assert(HUD.elems["ovb_1_1"], "overlay slots come back when display switches to Overlay")

local mode = require("src.mode")
input.pad = function() return { connected = true, buttons = {} } end
mode.set("gamepad")
local pad = require("src.pad")
pad.hooks = { changed = function() end, open_manager = function() end, palette = function() end,
  editing = function() return false end }
bar.rebuild()
pad.rebuild()
assert(not HUD.elems["ovb_1_1"] and HUD.elems["ovp_lt_up"], "gamepad overlay replaces keyboard bars")

mode.set("hotbars")
pad.rebuild()
bar.rebuild()
assert(HUD.elems["ovb_1_1"] and HUD.removed["ovp_lt_up"], "keyboard overlay returns after leaving gamepad mode")

OVER.pad_autohide = true
mode.set("gamepad")
pad.rebuild()
assert(HUD.elems["ovp_idle"], "folded crossbars show an Open Manager HUD button in overlay mode")