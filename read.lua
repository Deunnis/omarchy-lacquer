-- Reads a chunk of Hyprland Lua config by running it against recording stubs,
-- and reports everything it declared. Lua reading Lua, so there is no second
-- grammar to keep in sync with Hyprland's.
--
--   lua read.lua <path>        run a file  (Omarchy's shipped looknfeel.lua)
--   lua read.lua -e <source>   run a string (a managed block)
--
-- Output is one tab-separated record per line:
--
--   k  <key:path>  <type>  <value>                     an hl.config setting
--   a  <leaf>  <enabled>  <speed>  <bezier>  <style>   an hl.animation leaf
--   c  <name>  <x0>  <y0>  <x1>  <y1>                  an hl.curve bezier
--   w  <opacity>                                       a blanket window opacity
--
-- Nothing is applied: every stub only records. Exits non-zero with the Lua
-- error on stderr if the chunk does not load or run.

local out = {}

local function clean(s)
  return (tostring(s):gsub("\t", " "):gsub("\n", " "))
end

local function emit(...)
  local parts = {}
  for i, v in ipairs({ ... }) do parts[i] = clean(v) end
  out[#out + 1] = table.concat(parts, "\t")
end

-- hl.config nests arbitrarily; flatten to the colon paths the schema uses.
local function walk(t, prefix)
  for k, v in pairs(t) do
    local path = prefix == "" and tostring(k) or (prefix .. ":" .. tostring(k))
    if type(v) == "table" then
      walk(v, path)
    else
      emit("k", path, type(v), v)
    end
  end
end

-- hl.curve("name", { type = "bezier", points = { { x0, y0 }, { x1, y1 } } })
local function curve(name, spec)
  if type(spec) ~= "table" then return end
  local points = spec.points
  if type(points) ~= "table" or type(points[1]) ~= "table" or type(points[2]) ~= "table" then return end
  emit("c", name or "", points[1][1] or 0, points[1][2] or 0, points[2][1] or 0, points[2][2] or 0)
end

local function noop() end

hl = {
  config = function(t) if type(t) == "table" then walk(t, "") end end,
  animation = function(t)
    if type(t) ~= "table" then return end
    emit("a", t.leaf or "", t.enabled ~= false, t.speed or "", t.bezier or "", t.style or "")
  end,
  curve = curve,
  window_rule = function(t) if type(t) == "table" and t.opacity then emit("w", t.opacity) end end,
  layer_rule = noop,
  workspace = noop,
  bind = noop,
  unbind = noop,
  submap = noop,
  monitor = noop,
  env = noop,
  exec = noop,
  on = noop,
}

o = {
  window = function(_, rules)
    if type(rules) == "table" and rules.opacity then emit("w", rules.opacity) end
  end,
  bind = noop,
  unbind = noop,
  toggle = noop,
}

-- Omarchy's config surface is much wider than the handful of calls above
-- (o.launch_webapp, hl.gesture, hl.timer, o.cmd_present, ...) and it grows.
-- The managed block is documented as safe to hand-edit, so anything the user
-- adds has to run rather than blow up: an unknown call is a no-op, not a
-- "attempt to call a nil value" that would make the whole block unreadable.
local fallback = { __index = function() return noop end }
setmetatable(hl, fallback)
setmetatable(o, fallback)

local source, name
if arg[1] == "-e" then
  source, name = arg[2] or "", "lacquer-block"
else
  local file, err = io.open(arg[1], "r")
  if not file then
    io.stderr:write(tostring(err))
    os.exit(1)
  end
  source, name = file:read("a"), arg[1]
  file:close()
end

local chunk, loadErr = load(source, name, "t")
if not chunk then
  io.stderr:write(tostring(loadErr))
  os.exit(1)
end

local ok, runErr = pcall(chunk)
if not ok then
  io.stderr:write(tostring(runErr))
  os.exit(1)
end

print(table.concat(out, "\n"))
