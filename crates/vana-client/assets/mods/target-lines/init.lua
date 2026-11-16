-- FFXII-style target lines: MogSafe's TargetLines for Windower (https://github.com/MogSafe/TargetLines),
-- drawn as glowing arcs.

local E = require("engine")
local Arc = require("arc")

local GROW_SECS = 0.25
local MAX_STAMPS = 90
local MAX_LINES = 24
local MAX_RINGS = 8
local TEST_SECS = 8

local shown = false
local test_until = 0

local function faded(c, fade)
  return { c[1], c[2], c[3], math.max(180, math.floor(c[4] * fade)) }
end

local function whiter(c, k)
  local f = math.floor
  return { f(c[1] + (255 - c[1]) * k), f(c[2] + (255 - c[2]) * k), f(c[3] + (255 - c[3]) * k), c[4] }
end

local function path_points(from, to)
  if settings.get("curved") then return Arc.samples(from, to, 20) end
  return { from, to }
end

-- The first `grow` (0..1) of a polyline.
local function cut(pts, grow)
  if grow >= 1 then return pts end
  local f = grow * (#pts - 1)
  local k = math.floor(f)
  local out = {}
  for i = 1, k + 1 do out[i] = pts[i] end
  local a, b, r = pts[k + 1], pts[k + 2], f - k
  if b and r > 0 then
    out[#out + 1] = { x = a.x + (b.x - a.x) * r, y = a.y + (b.y - a.y) * r, z = a.z + (b.z - a.z) * r }
  end
  return out
end

local function world_arc(uid, pts, colour)
  local w = settings.get("world_width") * 0.3
  local dim = { colour[1], colour[2], colour[3], math.floor(colour[4] / 2) }
  for s, dy in ipairs({ 0, -w, w }) do
    for i = 1, #pts - 1 do
      local a, b = pts[i], pts[i + 1]
      draw.line(("l%d_%d_%d"):format(uid, s, i), { from = { x = a.x, y = a.y + dy, z = a.z },
        to = { x = b.x, y = b.y + dy, z = b.z }, colour = s == 1 and colour or dim })
    end
  end
end

local function sprite(id, path, x, y, size, colour, layer)
  hud.image(id, { path = path, x = x - size / 2, y = y - size / 2, w = size, h = size, colour = colour, layer = layer })
end

local function screen_arc(uid, pts, colour, done)
  local thick = settings.get("thickness")
  local sp = {}
  for i, p in ipairs(pts) do
    sp[i] = draw.to_screen(p)
    if not sp[i] then return end
  end
  local function len(i) return math.sqrt((sp[i + 1].x - sp[i].x) ^ 2 + (sp[i + 1].y - sp[i].y) ^ 2) end
  local total = 0
  for i = 1, #sp - 1 do total = total + len(i) end
  if total < 2 then return end
  local step = math.max(thick * 0.35, total / MAX_STAMPS)
  local glow = { colour[1], colour[2], colour[3], math.floor(colour[4] * 0.22) }
  local core = whiter(colour, 0.45)
  local pulse = (os.clock() * 1.2) % 1
  local n, seg, along = 0, 1, 0
  for d = 0, total, step do
    while seg < #sp - 1 and d - along > len(seg) do
      along, seg = along + len(seg), seg + 1
    end
    local a, b = sp[seg], sp[seg + 1]
    local r = math.min(1, (d - along) / math.max(0.001, len(seg)))
    local x, y = a.x + (b.x - a.x) * r, a.y + (b.y - a.y) * r
    local near = math.abs(d / total - pulse)
    local boost = near < 0.06 and (1 - near / 0.06) or 0
    n = n + 1
    sprite(("g%d_%d"):format(uid, n), "img/glow.png", x, y, thick * (3 + boost * 1.5), glow, 2)
    sprite(("c%d_%d"):format(uid, n), "img/core.png", x, y, thick * (0.55 + boost * 0.5), core, 3)
  end
  if done then
    local e = sp[#sp]
    sprite("og" .. uid, "img/glow.png", e.x, e.y, thick * 5,
      { colour[1], colour[2], colour[3], math.floor(colour[4] * 0.5) }, 2)
    sprite("oc" .. uid, "img/core.png", e.x, e.y, thick * 1.4, whiter(colour, 0.7), 4)
  end
end

local function beam(uid, from, to, colour, age)
  local grow = math.max(0.1, math.min(1, age / GROW_SECS))
  local pts = cut(path_points(from, to), grow)
  if #pts < 2 then return end
  if settings.get("screen_lines") then
    screen_arc(uid, pts, colour, grow >= 1)
  else
    world_arc(uid, pts, colour)
  end
end

local function draw_all(lines, rings, now)
  draw.clear()
  hud.clear()
  for i = 1, math.min(#lines, MAX_LINES) do
    local line = lines[i]
    local s = game.entity(line.source.id) or line.source
    local t = game.entity(line.target.id) or line.target
    local age = now - line.created
    beam(line.uid, E.anchor(s, "source"), E.anchor(t, "target"), faded(line.colour, 1 - age / line.timeout), age)
  end
  local contract = settings.get("aoe_mode") == "ring2"
  for i = 1, math.min(#rings, MAX_RINGS) do
    local ring = rings[i]
    local cent = game.entity(ring.center.id) or ring.center
    local age = now - ring.created
    local progress = math.max(0.08, math.min(1, age / ring.timeout))
    local fade = 1 - math.min(1, age / (ring.timeout + 0.5))
    local colour = faded(ring.colour, fade)
    local feet = { x = cent.pos.x, y = cent.pos.y - 0.05, z = cent.pos.z }
    local radius = math.max(0.5, ring.radius * progress)
    draw.ring("r" .. ring.uid, { at = feet, radius = radius, colour = colour, segments = 64 })
    draw.ring("r" .. ring.uid .. "f", { at = feet, radius = radius, filled = true, segments = 64,
      colour = { colour[1], colour[2], colour[3], math.floor(colour[4] * 0.25) } })
    if contract then
      for j, tgt in ipairs(ring.targets) do
        local te = game.entity(tgt.id) or tgt
        beam(ring.uid * 1000 + j, E.anchor(cent, "source"), E.anchor(te, "target"),
          faded(ring.colour, fade * (1 - progress)), age)
      end
    end
  end
  if now < test_until then
    local me, tgt = game.player(), game.target()
    if me and tgt and tgt.pos and not tgt.me then
      beam(0, E.anchor(me, "source"), E.anchor(tgt, "target"), { 255, 40, 255, 255 }, TEST_SECS - (test_until - now))
    end
  end
  shown = true
end

local function hide()
  if shown then
    draw.clear()
    hud.clear()
  end
  shown = false
end

events.on("action", function(a) E.on_action(a) end)

events.on("frame", function()
  if not settings.get("on") then return hide() end
  local lines, rings = E.collect()
  local now = os.clock()
  if #lines == 0 and #rings == 0 and now >= test_until then return hide() end
  draw_all(lines, rings, now)
end)

events.on("zone_change", function() E.clear() end)

events.on("load", function()
  if not settings.get("on") then
    chat.add("Target Lines is off: turn it on under Battle settings or with //tl on.")
  end
end)

local function set(key, value)
  commands.run(("/lua set target-lines %s %s"):format(key, value))
end

local TOGGLES = {
  colorblind = "color_blind", playerlines = "player_lines", partylines = "party_lines", petlines = "pet_lines",
  enemylines = "enemy_lines", otherpartylines = "other_party_lines", speciallines = "special_lines",
}
local AOE_MODES = { off = true, fan = true, ring1 = true, ring2 = true }
local REGULAR_MODES = { first = true, ["repeat"] = true, off = true }

local function tl(sub, arg)
  sub, arg = (sub or "status"):lower(), (arg or ""):lower()
  if sub == "status" then
    local lines, rings = E.collect()
    chat.add(("Target Lines %s: %d line(s), %d ring(s), thickness %d.")
      :format(settings.get("on") and "on" or "off", #lines, #rings, settings.get("thickness")))
  elseif sub == "test" then
    if not settings.get("on") then return chat.add("Target Lines is off: //tl on first.") end
    test_until = os.clock() + TEST_SECS
    chat.add("Target Lines: a test line to your target for " .. TEST_SECS .. " s.")
  elseif sub == "width" then
    local n = arg == "+" and settings.get("thickness") + 1 or arg == "-" and settings.get("thickness") - 1
      or tonumber(arg)
    if not n then return chat.add("//tl width +, - or a number of pixels.") end
    set("thickness", math.max(4, math.min(18, math.floor(n))))
  elseif sub == "on" or sub == "off" then
    set("on", tostring(sub == "on"))
    chat.add("Target Lines " .. sub .. ".")
  elseif sub == "clear" then
    E.clear()
    test_until = 0
    hide()
    chat.add("Target Lines cleared.")
  elseif sub == "settings" or sub == "config" then
    commands.run("/lua settings target-lines")
  elseif sub == "aoemode" and AOE_MODES[arg] then
    set("aoe_mode", arg)
    chat.add("Target Lines AoE style: " .. arg .. ".")
  elseif sub == "regular" and REGULAR_MODES[arg] then
    set("regular_attacks", arg)
    chat.add("Target Lines regular attacks: " .. arg .. ".")
  elseif TOGGLES[sub] and (arg == "on" or arg == "off") then
    set(TOGGLES[sub], tostring(arg == "on"))
    chat.add(("Target Lines: %s %s."):format(sub, arg))
  else
    chat.add("Unknown //tl command: //mods tl lists them.")
  end
end

commands.register("tl", tl)
commands.register("targetlines", tl)
