--[[ RemoteSpy
     Hooks all remote/bindable traffic and script execution, then writes
     every event to RemoteSpy.log in the executor's workspace folder.

     Detected events
     ─────────────────────────────────────────────────────────────────
     Outbound  RemoteEvent:FireServer
               RemoteFunction:InvokeServer
               BindableEvent:Fire
               BindableFunction:Invoke

     Inbound   RemoteEvent.OnClientEvent  (server → client)
               RemoteFunction.OnClientInvoke

     Scripts   require()  calls
               loadstring() calls
               LocalScript / Script added to the DataModel
]]--

local LOG_FILE  = "RemoteSpy.log"
local MAX_DEPTH = 4        -- max table recursion depth in arg serializer
local ENABLED   = true     -- set false to pause without unloading

-- ── file helpers ──────────────────────────────────────────────────────────────

local function readSafe(path)
    if type(isfile) == "function" and not isfile(path) then
        return ""
    end
    local ok, result = pcall(readfile, path)
    return ok and result or ""
end

local function appendLog(line)
    local existing = readSafe(LOG_FILE)
    writefile(LOG_FILE, existing .. line .. "\n")
end

-- seed the log with a header
do
    local stamp = os.date("%Y-%m-%d %H:%M:%S")
    writefile(LOG_FILE, ("=== RemoteSpy session started %s ===\n"):format(stamp))
end

-- ── argument serialiser ───────────────────────────────────────────────────────

local function serialise(value, depth)
    depth = depth or 0
    local t = typeof(value)

    if t == "nil"     then return "nil"
    elseif t == "boolean" then return tostring(value)
    elseif t == "number"  then
        -- keep floats readable
        if value == math.floor(value) then
            return tostring(math.floor(value))
        end
        return string.format("%.4g", value)
    elseif t == "string"  then
        return string.format("%q", value)
    elseif t == "Instance" then
        local ok, path = pcall(function() return value:GetFullName() end)
        return ok and ("<Instance> " .. path) or ("<Instance> " .. tostring(value))
    elseif t == "Vector2"  then
        return string.format("Vector2(%g, %g)", value.X, value.Y)
    elseif t == "Vector3"  then
        return string.format("Vector3(%g, %g, %g)", value.X, value.Y, value.Z)
    elseif t == "CFrame"   then
        local p = value.Position
        return string.format("CFrame(%g, %g, %g)", p.X, p.Y, p.Z)
    elseif t == "Color3"   then
        return string.format("Color3(%g, %g, %g)", value.R, value.G, value.B)
    elseif t == "UDim2"    then
        return string.format("UDim2(%g, %g, %g, %g)",
            value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset)
    elseif t == "Enum" or t == "EnumItem" then
        return tostring(value)
    elseif t == "table" then
        if depth >= MAX_DEPTH then
            return "{...}"
        end
        local parts = {}
        for k, v in pairs(value) do
            local key = (type(k) == "string")
                and k
                or ("[" .. serialise(k, depth + 1) .. "]")
            parts[#parts + 1] = key .. " = " .. serialise(v, depth + 1)
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    else
        return "(" .. t .. ")"
    end
end

local function serialiseArgs(...)
    local n    = select("#", ...)
    local out  = {}
    for i = 1, n do
        out[i] = serialise(select(i, ...))
    end
    return table.concat(out, ", ")
end

-- ── caller identification ─────────────────────────────────────────────────────

local function callerName()
    if type(getcallingscript) == "function" then
        local s = getcallingscript()
        if s then
            local ok, name = pcall(function() return s:GetFullName() end)
            if ok then return name end
        end
    end
    return "unknown"
end

-- ── log writer ────────────────────────────────────────────────────────────────

local function log(category, remote, args)
    if not ENABLED then return end
    local stamp    = os.date("%H:%M:%S")
    local caller   = callerName()
    local remoteName
    if typeof(remote) == "Instance" then
        local ok, n = pcall(function() return remote:GetFullName() end)
        remoteName = ok and n or tostring(remote)
    else
        remoteName = tostring(remote)
    end

    local line = string.format("[%s] [%s] %s | caller: %s | args: %s",
        stamp, category, remoteName, caller, args)
    appendLog(line)
end

-- ── __namecall hook ──────────────────────────────────────────────────────────
-- Catches: FireServer, InvokeServer, Fire (Bindable), Invoke (Bindable)

local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
    if not checkcaller() then
        local method = getnamecallmethod()

        local isRemoteEvent   = typeof(self) == "Instance" and self:IsA("RemoteEvent")
        local isRemoteFunc    = typeof(self) == "Instance" and self:IsA("RemoteFunction")
        local isBindableEvent = typeof(self) == "Instance" and self:IsA("BindableEvent")
        local isBindableFunc  = typeof(self) == "Instance" and self:IsA("BindableFunction")

        if method == "FireServer" and isRemoteEvent then
            log("RE:FireServer", self, serialiseArgs(...))

        elseif method == "InvokeServer" and isRemoteFunc then
            log("RF:InvokeServer", self, serialiseArgs(...))

        elseif method == "Fire" and isBindableEvent then
            log("BE:Fire", self, serialiseArgs(...))

        elseif method == "Invoke" and isBindableFunc then
            log("BF:Invoke", self, serialiseArgs(...))
        end
    end

    return oldNamecall(self, ...)
end))

-- ── __index hook for inbound remote wrappers ──────────────────────────────────
-- Wraps OnClientEvent / OnClientInvoke connections so inbound traffic is also logged.

local oldIndex
oldIndex = hookmetamethod(game, "__index", newcclosure(function(self, key)
    local result = oldIndex(self, key)

    if checkcaller() then
        return result
    end

    if typeof(self) == "Instance" then
        if self:IsA("RemoteEvent") and key == "OnClientEvent" then
            -- Return a proxy signal so Connect callbacks are wrapped
            return setmetatable({}, {
                __index = function(_, k)
                    if k == "Connect" or k == "connect" then
                        return function(_, callback)
                            return result:Connect(function(...)
                                log("RE:OnClientEvent", self, serialiseArgs(...))
                                callback(...)
                            end)
                        end
                    end
                    return result[k]
                end,
            })

        elseif self:IsA("RemoteFunction") and key == "OnClientInvoke" then
            return result
        end
    end

    return result
end))

-- ── require hook ─────────────────────────────────────────────────────────────

local oldRequire = hookfunction(require, newcclosure(function(module, ...)
    if not checkcaller() then
        local caller  = callerName()
        local modName = (typeof(module) == "Instance")
            and (pcall(function() return module:GetFullName() end) and module:GetFullName() or tostring(module))
            or tostring(module)
        local stamp = os.date("%H:%M:%S")
        appendLog(string.format("[%s] [REQUIRE] %s | caller: %s", stamp, modName, caller))
    end
    return oldRequire(module, ...)
end))

-- ── loadstring hook ──────────────────────────────────────────────────────────

local oldLoadstring = hookfunction(loadstring, newcclosure(function(source, chunkname, ...)
    if not checkcaller() then
        local caller  = callerName()
        local stamp   = os.date("%H:%M:%S")
        local preview = type(source) == "string"
            and source:sub(1, 120):gsub("\n", "\\n")
            or tostring(source)
        appendLog(string.format("[%s] [LOADSTRING] chunk: %s | caller: %s | source: %s",
            stamp, tostring(chunkname), caller, preview))
    end
    return oldLoadstring(source, chunkname, ...)
end))

-- ── DataModel script-added listener ─────────────────────────────────────────

local function onDescendantAdded(obj)
    if not ENABLED then return end
    if typeof(obj) ~= "Instance" then return end
    if obj:IsA("LocalScript") or obj:IsA("Script") or obj:IsA("ModuleScript") then
        local stamp = os.date("%H:%M:%S")
        local ok, fullName = pcall(function() return obj:GetFullName() end)
        appendLog(string.format("[%s] [SCRIPT_ADDED] %s (%s)",
            stamp, ok and fullName or "?", obj.ClassName))
    end
end

game.DescendantAdded:Connect(onDescendantAdded)

-- ── public handle ─────────────────────────────────────────────────────────────

local RemoteSpy = {}

function RemoteSpy.Pause()  ENABLED = false end
function RemoteSpy.Resume() ENABLED = true  end
function RemoteSpy.Toggle() ENABLED = not ENABLED end

function RemoteSpy.ClearLog()
    writefile(LOG_FILE, "")
end

function RemoteSpy.GetLogPath()
    return LOG_FILE
end

return RemoteSpy
