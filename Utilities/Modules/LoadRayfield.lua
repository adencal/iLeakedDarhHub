--[[ Fetches Rayfield Gen2 and patches Plugin-only APIs for Potassium. ]]--

local function http(url)
	if type(httpget) == "function" then
		return httpget(url)
	end
	return game:HttpGet(url)
end

local env = getgenv()
local getObjects = rawget(env, "getobjects") or getobjects
assert(type(getObjects) == "function", "[LoadRayfield] Potassium getobjects() is required")

getobjects = getObjects
env.getobjects = getObjects

local source = http("https://sirius.menu/gen2")
assert(type(source) == "string" and #source > 0, "[LoadRayfield] empty Rayfield gen2")

source = string.gsub(source, "game:GetObjects", "getobjects")
source = string.gsub(source, "game%.GetObjects", "getobjects")

do
	local parentExpr = [[(function()
		if gethui then
			return gethui()
		end
		local ok, pg = pcall(function()
			return game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
		end)
		if ok then
			return pg
		end
		return game:GetService("CoreGui")
	end)()]]

	source = string.gsub(source, "Rayfield%.Parent = CoreGui", "Rayfield.Parent = " .. parentExpr)
	source = string.gsub(source, "KeyUI%.Parent = CoreGui", "KeyUI.Parent = " .. parentExpr)
end

local chunk = assert(loadstring(source, "@RayfieldGen2.patched"))
return chunk()
