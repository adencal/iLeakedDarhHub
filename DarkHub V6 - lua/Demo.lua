local DarkHub
do
	local ok, lib = pcall(function()
		return require(script.Parent:WaitForChild("Library"))
	end)
	if ok then
		DarkHub = lib
	elseif typeof(readfile) == "function" then
		DarkHub = assert(loadstring(readfile("Library.lua")), "Failed to compile Library.lua")()
	else
		error("Could not load DarkHub Library, or expose readfile()")
	end
end

local window = DarkHub.new({
	title = "DarkHub",
	content = "Demo",
	version = "V6",
	togglebind = "RightControl",
	profiles = { "Primary" },
	key = "DEMO-KEY-1234",
	discord = "",
	supportedgames = {
		{ name = "Demo Place", placeId = game.PlaceId },
		{ name = "Universal", id = nil },
	},
	changelogs = {
		ui = {
			{
				title = "Dashboard refresh",
				date = "Jul 2026",
				body = "Softer cards, clearer hierarchy, and a cleaner overview layout.",
			},
			{
				title = "Columns & first-person",
				date = "Jul 2026",
				body = "Side-by-side sections and mouse unlock while the UI is open.",
			},
		},
		games = {
			{
				title = "Demo hooks",
				date = "Jul 2026",
				body = "Sample game entries for the dashboard games list.",
			},
		},
	},
})

local main = window:addtab({
	content = "Main",
	settings = { open = true },
})

local info = main:addsection({ content = "Info" })
info:addlabel({
	content = "Toggle UI with RightControl",
})

local cols = main:addcolumns(2)
local basics = cols[1]:addsection({ content = "Basics" })
local inputs = cols[2]:addsection({ content = "Inputs" })

basics:addtoggle({
	content = "Enable Feature",
	flag = "demo_enable",
	default = true,
	callback = function(state)
		print("[DarkHub Demo] Enable Feature:", state)
	end,
})

basics:addslider({
	content = "Power",
	flag = "demo_power",
	min = 0,
	max = 100,
	float = 1,
	default = 50,
	callback = function(value)
		print("[DarkHub Demo] Power:", value)
	end,
})

basics:addbutton({
	content = "Run Test",
	buttontext = "Fire",
	callback = function()
		print("[DarkHub Demo] Run Test clicked — flags:", window.flags.demo_enable, window.flags.demo_power)
	end,
})

inputs:addbox({
	content = "Username",
	flag = "demo_username",
	placeholder = "Enter name...",
	default = "Player",
	callback = function(text)
		print("[DarkHub Demo] Username:", text)
	end,
})

inputs:adddropdown({
	content = "Mode",
	flag = "demo_mode",
	items = { "Safe", "Normal", "Aggressive" },
	default = "Normal",
	callback = function(value)
		print("[DarkHub Demo] Mode:", value)
	end,
})

inputs:addchecklist({
	content = "Options",
	flag = "demo_options",
	items = { "Option A", "Option B", "Option C" },
	default = { "Option A" },
	callback = function(values)
		print("[DarkHub Demo] Options:", table.concat(values, ", "))
	end,
})

inputs:addcolorpicker({
	content = "Theme Color",
	flag = "demo_color",
	default = Color3.fromRGB(255, 0, 0),
	callback = function(color)
		print("[DarkHub Demo] Theme Color:", color)
	end,
})

inputs:addbind({
	content = "Hotkey",
	flag = "demo_hotkey",
	default = "E",
	callback = function(key)
		print("[DarkHub Demo] Hotkey bound:", key)
	end,
})

local extras = main:addsection({ content = "Extras" })

extras:addtoggle({
	content = "Full Width Toggle",
	flag = "demo_fullwidth",
	default = false,
	callback = function(state)
		print("[DarkHub Demo] Full Width Toggle:", state)
	end,
})
