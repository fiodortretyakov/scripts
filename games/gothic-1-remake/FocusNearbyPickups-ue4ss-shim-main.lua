-- UE4SS host shim for "Highlight All Nearby Items" 4.2.0 (Nexus gothic1remake mod 53), which ships as a
-- PLuaModLoader child mod. It needs only Sched.every(ms, fn, name), Mod.path(name), Mod.log(fmt, ...) and
-- Sched.VERSION. PLuaModLoader runs its scheduler pump on the game thread, so every callback does too.
local dir = (debug.getinfo(1, "S").source:gsub("^@", "")):match("^(.*[\\/])") or ""
local TAG = "[FocusNearbyPickups]"

local function log(fmt, ...)
    local ok, msg = pcall(string.format, tostring(fmt), ...)
    print(string.format("%s %s\n", TAG, ok and msg or tostring(fmt)))
end

local Sched = { VERSION = "ue4ss-shim-1" }

function Sched.every(ms, fn, name)
    local interval = math.max(16, math.floor(tonumber(ms) or 500))
    LoopAsync(interval, function()
        ExecuteInGameThread(function()
            local ok, err = pcall(fn)
            if not ok then
                log("%s failed: %s", tostring(name), tostring(err))
            end
        end)
        return false -- keep repeating
    end)
end

local Mod = {
    Sched = Sched,
    path = function(rel) return dir .. rel end,
    log = log,
}

local chunk, err = loadfile(dir .. "FocusNearbyPickups.lua")
if not chunk then
    log("cannot load FocusNearbyPickups.lua: %s", tostring(err))
    return
end
local entry = chunk()
local ok, runErr = pcall(entry, Mod)
if not ok then
    log("start failed: %s", tostring(runErr))
end
