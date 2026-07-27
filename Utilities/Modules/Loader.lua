--[[ DarkHub Loader
	Cached module importer

	Bootstrap once:
		local DarkHub = loadstring(readfile("Loader.lua"))()
		-- or from GitHub:
		local DarkHub = loadstring(httpget(
			"https://raw.githubusercontent.com/adencal/iLeakedDarhHub/main/DarkHub%20V6%20-%20lua/Loader.lua"
		))()

	Then in any script:
		local Maid = DarkHub:utility("Maid")
		local Signal = DarkHub:utility("Signal")
		local SpatialHash = DarkHub:utility("SpatialHash")
		local Esp = DarkHub:import("Utilities/Esp")
]]

local BASE = "https://raw.githubusercontent.com/adencal/iLeakedDarhHub/main/DarkHub%20V6%20-%20lua/"

local LOCAL_ROOTS = {
	"",
	"DarkHub V6 - lua/",
}

local env = (getgenv and getgenv()) or _G
local DarkHub = env.DarkHub

if type(DarkHub) == "table" and DarkHub._loaderVersion == 1 then
	return DarkHub
end

DarkHub = {
	_loaderVersion = 1,
	_cache = {},
	base = BASE,
	localRoots = LOCAL_ROOTS,
}

env.DarkHub = DarkHub

local function httpFetch(url)
	if type(httpget) == "function" then
		return httpget(url)
	end
	if type(HttpGet) == "function" then
		return HttpGet(url)
	end
	if game and game.HttpGetAsync then
		return game:HttpGetAsync(url)
	end
	if game and game.HttpGet then
		return game:HttpGet(url)
	end
	error("[DarkHub] No httpget available", 2)
end

local function readLocal(relPath)
	if type(readfile) ~= "function" then
		return nil
	end
	for i = 1, #DarkHub.localRoots do
		local full = DarkHub.localRoots[i] .. relPath
		local ok, result = pcall(readfile, full)
		if ok and type(result) == "string" and #result > 0 then
			return result, full
		end
	end
	return nil
end

local function normalize(path)
	path = string.gsub(path, "\\", "/")
	path = string.gsub(path, "^/+", "")
	if not string.find(path, "%.lua$") then
		path = path .. ".lua"
	end
	return path
end

function DarkHub:fetchSource(path)
	path = normalize(path)

	local source, from = readLocal(path)
	if source then
		return source, from
	end

	local url = self.base .. string.gsub(path, " ", "%%20")
	source = httpFetch(url)
	assert(type(source) == "string" and #source > 0, "[DarkHub] Empty response for " .. path)
	return source, url
end

function DarkHub:import(path)
	path = normalize(path)
	local cached = self._cache[path]
	if cached ~= nil then
		return cached
	end

	local source, origin = self:fetchSource(path)
	local chunk, err = loadstring(source, "@" .. path)
	assert(chunk, ("[DarkHub] Compile failed %s (%s): %s"):format(path, tostring(origin), tostring(err)))

	local ok, result = pcall(chunk)
	assert(ok, ("[DarkHub] Runtime error in %s: %s"):format(path, tostring(result)))
	assert(result ~= nil, "[DarkHub] Module returned nil: " .. path)

	self._cache[path] = result
	return result
end

function DarkHub:utility(name)
	return self:import("Utilities/" .. name)
end

function DarkHub:utilities(...)
	local names = { ... }
	local out = {}
	for i = 1, #names do
		local name = names[i]
		out[name] = self:utility(name)
	end
	return out
end

function DarkHub:unload(path)
	self._cache[normalize(path)] = nil
end

function DarkHub:clearCache()
	table.clear(self._cache)
end

DarkHub.imports = {
	fetch = function(_, path)
		return DarkHub:import(path)
	end,
	fetchutility = function(_, name)
		return DarkHub:utility(name)
	end,
	fetchmodule = function(_, path)
		return DarkHub:import(path)
	end,
}

return DarkHub
