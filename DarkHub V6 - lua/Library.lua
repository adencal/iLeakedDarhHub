local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local hugevec2 = Vector2.new(math.huge, math.huge)

local blacklistedkeys = {
	[Enum.KeyCode.Unknown] = true,
}

local whitelistedtypes = {
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.MouseButton2] = true,
	[Enum.UserInputType.MouseButton3] = true,
}

--[[ Helpers ]]--

local function randomstring(size)
	return HttpService:GenerateGUID(false):gsub("-", ""):sub(1, size or 16)
end

local function mergetables(base, edit)
	if typeof(edit) == "table" then
		for i, v in next, edit do
			if typeof(base[i]) == typeof(v) or base[i] == nil then
				base[i] = v
			end
		end
	end
	return base
end

local function deepCopy(value)
	if typeof(value) ~= "table" then
		return value
	end
	local clone = {}
	for k, v in next, value do
		clone[k] = deepCopy(v)
	end
	return clone
end

local function firecallback(item, fn, ...)
	if item.library and item.library.settings.silent then
		return
	end
	task.spawn(fn, ...)
end

local function round(val, nearest)
	local mul = 1 / nearest
	return math.round(val * mul) / mul
end

local function tween(instance, duration, properties, style)
	local t = TweenService:Create(instance, TweenInfo.new(duration, style or Enum.EasingStyle.Sine), properties)
	t:Play()
	return t
end

local function formatduration(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	local days = math.floor(seconds / 86400)
	local hours = math.floor((seconds % 86400) / 3600)
	local mins = math.floor((seconds % 3600) / 60)
	local secs = seconds % 60
	if days > 0 then
		return string.format("%dd %dh %dm", days, hours, mins)
	elseif hours > 0 then
		return string.format("%dh %dm %ds", hours, mins, secs)
	elseif mins > 0 then
		return string.format("%dm %ds", mins, secs)
	end
	return string.format("%ds", secs)
end

local function maskkey(key)
	key = tostring(key or "")
	if key == "" or key == "—" then
		return "—"
	end
	if #key <= 8 then
		return key
	end
	return key:sub(1, 4) .. string.rep("•", math.min(12, #key - 8)) .. key:sub(-4)
end

local function copytext(text)
	text = tostring(text or "")
	if text == "" then
		return false
	end
	return pcall(function()
		if typeof(setclipboard) == "function" then
			setclipboard(text)
		elseif typeof(toclipboard) == "function" then
			toclipboard(text)
		elseif typeof(Clipboard) == "table" and typeof(Clipboard.set) == "function" then
			Clipboard.set(text)
		else
			error("clipboard unavailable")
		end
	end)
end

local function openurl(url)
	url = tostring(url or "")
	if url == "" then
		return false
	end
	local openers = {
		rawget(_G, "open_url"),
		rawget(_G, "openurl"),
	}
	for i = 1, #openers do
		local fn = openers[i]
		if typeof(fn) == "function" then
			local ok = pcall(fn, url)
			if ok then
				return "opened"
			end
		end
	end
	if copytext(url) then
		return "copied"
	end
	return false
end

local memoryfs = {}

local function ensurefolder(path)
	if typeof(isfolder) == "function" and typeof(makefolder) == "function" then
		if not isfolder(path) then
			pcall(makefolder, path)
		end
	end
end

local function readtextfile(path)
	if typeof(isfile) == "function" and typeof(readfile) == "function" then
		local ok, exists = pcall(isfile, path)
		if ok and exists then
			local ok2, data = pcall(readfile, path)
			if ok2 and typeof(data) == "string" then
				return data
			end
		end
	end
	return memoryfs[path]
end

local function writetextfile(path, data)
	local folder = path:match("^(.*)/[^/]+$") or path:match("^(.*)\\[^\\]+$")
	if folder then
		ensurefolder(folder)
	end
	if typeof(writefile) == "function" then
		local ok = pcall(writefile, path, tostring(data))
		if ok then
			memoryfs[path] = nil
			return true
		end
	end
	memoryfs[path] = tostring(data)
	return true
end

local function deletetextfile(path)
	if typeof(delfile) == "function" and typeof(isfile) == "function" then
		local ok, exists = pcall(isfile, path)
		if ok and exists then
			pcall(delfile, path)
		end
	end
	memoryfs[path] = nil
	return true
end

local function listtextfiles(folder)
	local names = {}
	local seen = {}
	if typeof(listfiles) == "function" then
		local ok, files = pcall(listfiles, folder)
		if ok and typeof(files) == "table" then
			for _, path in ipairs(files) do
				local name = tostring(path):match("([^/\\]+)%.json$")
				if name and not seen[name] then
					seen[name] = true
					table.insert(names, name)
				end
			end
		end
	end
	local prefix = folder .. "/"
	for path in next, memoryfs do
		if typeof(path) == "string" and path:sub(1, #prefix) == prefix then
			local name = path:sub(#prefix + 1):match("^(.-)%.json$")
			if name and not seen[name] then
				seen[name] = true
				table.insert(names, name)
			end
		end
	end
	table.sort(names)
	return names
end

local function sanitizeconfigname(name)
	name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
	name = name:gsub("[^%w%-%._ ]", "")
	if name == "" then
		return nil
	end
	return name
end

local function serializeflagvalue(value)
	local t = typeof(value)
	if t == "Color3" then
		return { __color = true, r = value.R, g = value.G, b = value.B }
	end
	if t ~= "table" then
		return value
	end
	local out = {}
	for k, v in next, value do
		if k ~= "color" then
			out[k] = serializeflagvalue(v)
		end
	end
	return out
end

local function deserializeflagvalue(value)
	if typeof(value) ~= "table" then
		return value
	end
	if value.__color == true then
		return Color3.new(tonumber(value.r) or 0, tonumber(value.g) or 0, tonumber(value.b) or 0)
	end
	local out = {}
	for k, v in next, value do
		out[k] = deserializeflagvalue(v)
	end
	return out
end

local function autoresize(layout, frame)
	local busy = false
	local function update()
		if busy then
			return
		end
		local y = layout.AbsoluteContentSize.Y
		local size = frame.Size
		if size.Y.Scale == 0 and size.Y.Offset == y then
			return
		end
		busy = true
		frame.Size = UDim2.new(size.X.Scale, size.X.Offset, 0, y)
		busy = false
	end
	update()
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		task.defer(update)
	end)
end

local function autocanvasresize(layout, frame)
	local busy = false
	local function update()
		if busy then
			return
		end
		local y = layout.AbsoluteContentSize.Y
		if frame.CanvasSize.Y.Offset == y then
			return
		end
		busy = true
		frame.CanvasSize = UDim2.new(0, 0, 0, y)
		busy = false
	end
	update()
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		task.defer(update)
	end)
end

local function autofitcolumnwidths(row, getcolumns, gap)
	local busy = false
	local function update()
		if busy then
			return
		end
		local cols = getcolumns()
		local n = #cols
		local width = row.AbsoluteSize.X
		if n == 0 or width <= 0 then
			return
		end
		busy = true
		local totalweight = 0
		for i = 1, n do
			totalweight = totalweight + (cols[i].weight or 1)
		end
		if totalweight <= 0 then
			totalweight = n
		end
		local available = math.max(0, width - gap * (n - 1))
		for i = 1, n do
			local col = cols[i]
			local colwidth = available * ((col.weight or 1) / totalweight)
			local h = col.frame.Size.Y.Offset
			col.frame.Size = UDim2.new(0, math.floor(colwidth + 0.5), 0, h)
		end
		busy = false
	end
	local function deferupdate()
		task.defer(update)
	end
	row:GetPropertyChangedSignal("AbsoluteSize"):Connect(deferupdate)
	deferupdate()
	return deferupdate
end

local maid = {}
maid.__index = maid

function maid.new()
	return setmetatable({ _tasks = {} }, maid)
end

function maid:givetask(connection)
	table.insert(self._tasks, connection)
	return connection
end

function maid:dispose()
	for i = 1, #self._tasks do
		local task = self._tasks[i]
		if typeof(task) == "RBXScriptConnection" then
			task:Disconnect()
		elseif typeof(task) == "Instance" then
			task:Destroy()
		elseif typeof(task) == "function" then
			task()
		end
	end
	table.clear(self._tasks)
end

local COL_HEADER = Color3.fromRGB(90, 96, 112)
local COL_TRACKOFF = Color3.fromRGB(32, 34, 44)
local COL_KNOBOFF = Color3.fromRGB(120, 126, 142)
local COL_STROKE = Color3.fromRGB(48, 52, 68)
local COL_ROWEDGE = Color3.fromRGB(42, 46, 60)

local theme = setmetatable({
	items = {
		mainbackground = {},
		titlebackground = {},
		sectionbackground = {},
		inputbackground = {},
		foreground = {},
		muted = {},
		highlight = {},
		dynamic = {},
	},
	values = {
		mainbackground = Color3.fromRGB(10, 10, 14),
		titlebackground = Color3.fromRGB(14, 14, 20),
		sectionbackground = Color3.fromRGB(20, 20, 28),
		inputbackground = Color3.fromRGB(28, 28, 38),
		foreground = Color3.fromRGB(240, 242, 248),
		muted = Color3.fromRGB(130, 134, 148),
		highlight = Color3.fromRGB(56, 140, 255),
	},
}, {
	__index = function(t, k)
		return t.values[k]
	end,
	__newindex = function(t, k, v)
		t.values[k] = v
		for inst, prop in next, t.items[k] do
			inst[prop] = v
		end
		for inst, data in next, t.items.dynamic do
			if data.func() == k then
				inst[data.prop] = v
			end
		end
	end,
})

local uicache = {}

local function create(classname, properties, children)
	local inst = Instance.new(classname)
	for i, v in next, properties do
		if i == "Theme" then
			for prop, item in next, v do
				if type(item) == "function" then
					theme.items.dynamic[inst] = {
						prop = prop,
						func = item,
					}
					inst[prop] = theme[item()]
				else
					theme.items[item][inst] = prop
					inst[prop] = theme[item]
				end
			end
		elseif i ~= "Parent" then
			inst[i] = v
		end
	end
	if children then
		for i = 1, #children do
			children[i].Parent = inst
		end
	end
	if inst:IsA("GuiObject") then
		table.insert(uicache, inst)
	end
	inst.Parent = properties.Parent
	return inst
end

local function cardgradient(parent)
	return create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(210, 214, 228)),
		}),
		Rotation = 90,
		Parent = parent,
		Name = "depth",
	})
end

local function makerow(name)
	local frame = create("Frame", {
		Theme = { BackgroundColor3 = "sectionbackground" },
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 54),
		Name = name,
	}, {
		create("UICorner", {
			CornerRadius = UDim.new(0, 10),
			Name = "corner",
		}),
		create("UIStroke", {
			Color = COL_ROWEDGE,
			Thickness = 1,
			Transparency = 0.7,
			Name = "edge",
		}),
		create("TextLabel", {
			Theme = { TextColor3 = "foreground" },
			Font = Enum.Font.GothamMedium,
			Text = name,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 18, 0.5, 0),
			Size = UDim2.new(0.35, 0, 0, 22),
			Name = "title",
		}),
	})
	cardgradient(frame)
	return frame
end

--[[ Label ]]--

local label = {}
label.__index = label

function label.new(options)
	local newlabel = setmetatable(mergetables({
		itemtype = "label",
		content = "No Content Provided",
		flag = randomstring(32),
		ignore = false,
	}, options), label)

	newlabel.frame = create("TextLabel", {
		Theme = { TextColor3 = "muted" },
		Font = Enum.Font.Gotham,
		Text = "",
		TextSize = 12,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 18),
		Name = "label",
	})

	return newlabel
end

function label:update(content)
	self.content = content
	self.frame.Text = content
end

--[[ Button ]]--

local button = {}
button.__index = button

function button.new(options)
	local newbutton = setmetatable(mergetables({
		itemtype = "button",
		content = "No Content Provided",
		buttontext = "Run",
		flag = randomstring(32),
		ignore = false,
		callback = function() end,
	}, options), button)

	newbutton.frame = makerow(newbutton.content)
	newbutton.frame.title.Text = newbutton.content

	local run = create("TextButton", {
		Theme = {
			BackgroundColor3 = "highlight",
			TextColor3 = "foreground",
		},
		Font = Enum.Font.GothamBold,
		Text = newbutton.buttontext,
		TextSize = 13,
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.new(0, 112, 0, 38),
		Parent = newbutton.frame,
		Name = "run",
	}, {
		create("UICorner", {
			CornerRadius = UDim.new(0, 6),
			Name = "corner",
		}),
		create("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(70, 155, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 110, 230)),
			}),
			Rotation = 90,
			Name = "gradient",
		}),
	})

	create("ImageLabel", {
		Image = "rbxassetid://6015897845",
		ImageColor3 = Color3.fromRGB(56, 152, 255),
		ImageTransparency = 0.72,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -6, 0.5, 0),
		Size = UDim2.new(0, 150, 0, 76),
		ZIndex = 0,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(49, 49, 450, 450),
		Parent = newbutton.frame,
		Name = "glow",
	})

	run.MouseButton1Click:Connect(function()
		local original = run.Size
		tween(run, 0.08, {
			Size = UDim2.new(original.X.Scale, original.X.Offset - 8, original.Y.Scale, original.Y.Offset - 4),
		})
		task.delay(0.08, function()
			tween(run, 0.12, { Size = original })
		end)
		local glow = newbutton.frame:FindFirstChild("glow")
		if glow then
			tween(glow, 0.08, { ImageTransparency = 0.45 })
			task.delay(0.08, function()
				tween(glow, 0.18, { ImageTransparency = 0.72 })
			end)
		end
		task.spawn(newbutton.callback)
	end)

	return newbutton
end

function button:fire(...)
	self.callback(...)
end

--[[ Toggle ]]--

local toggle = {}
toggle.__index = toggle

function toggle.new(options)
	local newtoggle = setmetatable(mergetables({
		itemtype = "toggle",
		content = "No Content Provided",
		flag = randomstring(32),
		ignore = false,
		callback = function() end,
	}, options), toggle)

	newtoggle.frame = makerow(newtoggle.content)
	newtoggle.frame.title.Text = newtoggle.content

	local track = create("Frame", {
		BackgroundColor3 = COL_TRACKOFF,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.new(0, 44, 0, 24),
		Parent = newtoggle.frame,
		Name = "track",
	}, {
		create("UICorner", {
			CornerRadius = UDim.new(1, 0),
			Name = "corner",
		}),
		create("UIStroke", {
			Color = COL_STROKE,
			Thickness = 1,
			Transparency = 0.5,
			Name = "stroke",
		}),
		create("Frame", {
			BackgroundColor3 = COL_KNOBOFF,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 2, 0.5, 0),
			Size = UDim2.new(0, 20, 0, 20),
			Name = "knob",
		}, {
			create("UICorner", {
				CornerRadius = UDim.new(1, 0),
				Name = "corner",
			}),
		}),
	})

	newtoggle.frame.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			newtoggle:switch()
		end
	end)

	return newtoggle
end

function toggle:set(bool)
	self.library.flags[self.flag] = bool
	local track = self.frame.track
	tween(track, 0.2, { BackgroundColor3 = bool and theme.highlight or COL_TRACKOFF })
	tween(track.knob, 0.2, {
		Position = bool and UDim2.new(1, -22, 0.5, 0) or UDim2.new(0, 2, 0.5, 0),
		BackgroundColor3 = bool and Color3.fromRGB(255, 255, 255) or COL_KNOBOFF,
	})
	local stroke = track:FindFirstChild("stroke")
	if stroke then
		tween(stroke, 0.2, { Transparency = bool and 0.15 or 0.5, Color = bool and theme.highlight or COL_STROKE })
	end
	firecallback(self, self.callback, bool)
end

function toggle:switch()
	self:set(not self.library.flags[self.flag])
end

--[[ Bind ]]--

local bind = {}
bind.__index = bind

function bind.new(options)
	local newbind = setmetatable(mergetables({
		itemtype = "bind",
		content = "No Content Provided",
		flag = randomstring(32),
		ignore = false,
		onkeydown = function() end,
		onkeyup = function() end,
		onkeychanged = function() end,
	}, options), bind)

	newbind.frame = makerow(newbind.content)
	newbind.frame.title.Text = newbind.content

	create("TextButton", {
		Theme = {
			BackgroundColor3 = "inputbackground",
			TextColor3 = "foreground",
		},
		Font = Enum.Font.GothamBold,
		Text = "None",
		TextSize = 13,
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.new(0, 40, 0, 34),
		Parent = newbind.frame,
		Name = "key",
	}, {
		create("UICorner", {
			CornerRadius = UDim.new(0, 6),
			Name = "corner",
		}),
		create("UIStroke", {
			Color = COL_STROKE,
			Thickness = 1,
			Transparency = 0.5,
			Name = "stroke",
		}),
	})

	newbind.frame.key.MouseButton1Click:Connect(function()
		if newbind.library.settings.binding then
			return
		end
		newbind.library.settings.binding = true
		newbind.frame.key.Text = "..."

		local conn
		conn = UserInputService.InputBegan:Connect(function(input)
			local isKey = input.UserInputType == Enum.UserInputType.Keyboard and not blacklistedkeys[input.KeyCode]
			local isMouse = whitelistedtypes[input.UserInputType] and input.UserInputType ~= Enum.UserInputType.MouseButton1
			if not isKey and not isMouse then
				return
			end
			conn:Disconnect()
			local name = isKey and input.KeyCode.Name or input.UserInputType.Name
			newbind:set(name)
			task.defer(function()
				newbind.library.settings.binding = false
			end)
		end)
	end)

	return newbind
end

function bind:set(inputname)
	local value = (inputname == "Escape" or inputname == "") and "None" or inputname
	local old = self.library.flags[self.flag]
	self.library.flags[self.flag] = value
	local width = math.max(40, TextService:GetTextSize(value, 13, Enum.Font.GothamBold, hugevec2).X + 18)
	self.frame.key.Size = UDim2.new(0, width, 0, 34)
	self.frame.key.Text = value
	if not self.library.settings.silent then
		self.onkeychanged(old, value)
	end
end

--[[ Box ]]--

local box = {}
box.__index = box

function box.new(options)
	local newbox = setmetatable(mergetables({
		itemtype = "box",
		content = "No Content Provided",
		flag = randomstring(32),
		ignore = false,
		placeholder = "Enter text...",
		numonly = false,
		callback = function() end,
	}, options), box)

	newbox.frame = makerow(newbox.content)
	newbox.frame.title.Text = newbox.content

	create("TextBox", {
		Theme = {
			BackgroundColor3 = "inputbackground",
			TextColor3 = "foreground",
		},
		Font = Enum.Font.Gotham,
		PlaceholderColor3 = Color3.fromRGB(100, 104, 120),
		PlaceholderText = newbox.placeholder,
		Text = "",
		TextSize = 13,
		ClearTextOnFocus = false,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.new(0.32, 0, 0, 36),
		Parent = newbox.frame,
		Name = "input",
	}, {
		create("UICorner", {
			CornerRadius = UDim.new(0, 6),
			Name = "corner",
		}),
		create("UIStroke", {
			Color = COL_STROKE,
			Thickness = 1,
			Transparency = 0.5,
			Name = "stroke",
		}),
		create("UIPadding", {
			PaddingLeft = UDim.new(0, 12),
			PaddingRight = UDim.new(0, 12),
			Name = "padding",
		}),
	})

	newbox.frame.input.FocusLost:Connect(function()
		newbox:set(newbox.frame.input.Text)
	end)

	return newbox
end

function box:set(value)
	local text = tostring(value or "")
	if self.numonly and text ~= "" and not tonumber(text) then
		self.frame.input.Text = tostring(self.library.flags[self.flag] or "")
		return
	end
	self.library.flags[self.flag] = text
	self.frame.input.Text = text
	firecallback(self, self.callback, text)
end

--[[ Slider ]]--

local slider = {}
slider.__index = slider

function slider.new(options)
	local newslider = setmetatable(mergetables({
		itemtype = "slider",
		content = "No Content Provided",
		flag = randomstring(32),
		ignore = false,
		min = 0,
		max = 100,
		float = 1,
		callback = function() end,
	}, options), slider)

	newslider.frame = makerow(newslider.content)
	newslider.frame.title.Text = newslider.content

	local holder = create("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.new(0.55, 0, 0, 20),
		Parent = newslider.frame,
		Name = "holder",
	}, {
		create("TextLabel", {
			Theme = { TextColor3 = "muted" },
			Font = Enum.Font.GothamMedium,
			Text = tostring(newslider.min) .. "%",
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextYAlignment = Enum.TextYAlignment.Center,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, 0, 1, -8),
			Size = UDim2.new(0, 48, 0, 12),
			Name = "percent",
		}),
		create("Frame", {
			BackgroundColor3 = COL_TRACKOFF,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, 0),
			Size = UDim2.new(1, 0, 0, 6),
			Name = "track",
		}, {
			create("UICorner", {
				CornerRadius = UDim.new(0, 6),
				Name = "corner",
			}),
			create("Frame", {
				Theme = { BackgroundColor3 = "highlight" },
				BorderSizePixel = 0,
				Size = UDim2.new(0, 0, 1, 0),
				Name = "fill",
			}, {
				create("UICorner", {
					CornerRadius = UDim.new(0, 6),
					Name = "corner",
				}),
				create("UIGradient", {
					Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, Color3.fromRGB(70, 155, 255)),
						ColorSequenceKeypoint.new(1, Color3.fromRGB(110, 180, 255)),
					}),
					Name = "gradient",
				}),
			}),
			create("Frame", {
				BackgroundColor3 = Color3.fromRGB(255, 255, 255),
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0, 0, 0.5, 0),
				Size = UDim2.new(0, 14, 0, 14),
				Name = "thumb",
			}, {
				create("UICorner", {
					CornerRadius = UDim.new(1, 0),
					Name = "corner",
				}),
			}),
		}),
	})

	local slidemaid = maid.new()
	holder.track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			newslider.library.settings.dragging = true
			local mouse = Players.LocalPlayer:GetMouse()
			local function update()
				local alpha = math.clamp((mouse.X - holder.track.AbsolutePosition.X) / math.max(holder.track.AbsoluteSize.X, 1), 0, 1)
				newslider:set(newslider.min + (newslider.max - newslider.min) * alpha, false, true)
			end
			update()
			slidemaid:givetask(mouse.Move:Connect(update))
			slidemaid:givetask(input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					slidemaid:dispose()
					newslider.library.settings.dragging = false
				end
			end))
		end
	end)

	return newslider
end

function slider:set(value, force, instant)
	local numvalue = math.clamp(round(value, self.float), self.min, self.max)
	if not force and numvalue == self.library.flags[self.flag] then
		return
	end
	self.library.flags[self.flag] = numvalue
	local alpha = (numvalue - self.min) / math.max(self.max - self.min, 1e-6)
	if instant then
		self.frame.holder.track.fill.Size = UDim2.new(alpha, 0, 1, 0)
		self.frame.holder.track.thumb.Position = UDim2.new(alpha, 0, 0.5, 0)
	else
		tween(self.frame.holder.track.fill, 0.15, { Size = UDim2.new(alpha, 0, 1, 0) })
		tween(self.frame.holder.track.thumb, 0.15, { Position = UDim2.new(alpha, 0, 0.5, 0) })
	end
	self.frame.holder.percent.Text = tostring(numvalue) .. "%"
	firecallback(self, self.callback, numvalue)
end

--[[ Dropdown ]]--

local dropdown = {}
dropdown.__index = dropdown

local function closeotheroverlays(library, except)
	for _, item in next, library.items do
		if item ~= except and (item.itemtype == "dropdown" or item.itemtype == "checklist") and item.settings.open then
			item:close()
		end
	end
end

local function placeoverlay(drop, anchor, main)
	local mainPos = main.AbsolutePosition
	local anchorPos = anchor.AbsolutePosition
	local anchorSize = anchor.AbsoluteSize
	drop.Parent = main
	drop.AnchorPoint = Vector2.new(0, 0)
	drop.Position = UDim2.new(0, anchorPos.X - mainPos.X, 0, anchorPos.Y - mainPos.Y + anchorSize.Y + 4)
	return anchorSize.X
end

local function stopfollow(item)
	if item._follow then
		item._follow:Disconnect()
		item._follow = nil
	end
end

-- Keep the open menu glued to its bar while the tab ScrollingFrame moves.
local function startfollow(item)
	stopfollow(item)
	local anchor = item.frame.bar
	local main = item.library.gui.main
	item._follow = anchor:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
		if item.settings.open and item.drop.Parent then
			placeoverlay(item.drop, anchor, main)
		end
	end)
end

function dropdown.new(options)
	local newdropdown = setmetatable(mergetables({
		itemtype = "dropdown",
		content = "No Content Provided",
		flag = randomstring(32),
		ignore = false,
		callback = function() end,
		settings = { open = false },
	}, options), dropdown)

	newdropdown.frame = makerow(newdropdown.content)
	newdropdown.frame.title.Text = newdropdown.content
	newdropdown._items = {}

	local bar = create("TextButton", {
		Theme = { BackgroundColor3 = "inputbackground" },
		Text = "",
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.new(0.32, 0, 0, 36),
		ZIndex = 2,
		Parent = newdropdown.frame,
		Name = "bar",
	}, {
		create("UICorner", {
			CornerRadius = UDim.new(0, 8),
			Name = "corner",
		}),
		create("UIStroke", {
			Color = COL_STROKE,
			Thickness = 1,
			Transparency = 0.45,
			Name = "stroke",
		}),
		create("TextLabel", {
			Theme = { TextColor3 = "foreground" },
			Font = Enum.Font.GothamMedium,
			Text = "",
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 12, 0, 0),
			Size = UDim2.new(1, -36, 1, 0),
			ZIndex = 3,
			Name = "selected",
		}),
		create("ImageLabel", {
			Theme = { ImageColor3 = "muted" },
			Image = "rbxassetid://9243354333",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -16, 0.5, 0),
			Size = UDim2.new(0, 14, 0, 14),
			Rotation = 90,
			ZIndex = 3,
			Name = "chevron",
		}),
	})

	-- Kept unparented until open so ScrollingFrame clipping cannot hide it.
	local drop = create("Frame", {
		Theme = { BackgroundColor3 = "sectionbackground" },
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Size = UDim2.new(0, 0, 0, 0),
		Visible = false,
		ZIndex = 40,
		Active = true,
		Name = "drop",
	}, {
		create("UICorner", {
			CornerRadius = UDim.new(0, 10),
			Name = "corner",
		}),
		create("UIStroke", {
			Color = COL_STROKE,
			Thickness = 1,
			Transparency = 0.25,
			Name = "stroke",
		}),
		create("ImageLabel", {
			Image = "rbxassetid://6015897845",
			ImageColor3 = Color3.fromRGB(0, 0, 0),
			ImageTransparency = 0.55,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 4),
			Size = UDim2.new(1, 28, 1, 28),
			ZIndex = 39,
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Rect.new(49, 49, 450, 450),
			Name = "shadow",
		}),
		create("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(210, 214, 228)),
			}),
			Rotation = 90,
			Name = "depth",
		}),
		create("ScrollingFrame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = Color3.fromRGB(70, 74, 90),
			CanvasSize = UDim2.new(),
			Size = UDim2.new(1, 0, 1, 0),
			ZIndex = 41,
			Name = "list",
		}, {
			create("UIListLayout", {
				Padding = UDim.new(0, 4),
				SortOrder = Enum.SortOrder.LayoutOrder,
				Name = "layout",
			}),
			create("UIPadding", {
				PaddingTop = UDim.new(0, 8),
				PaddingBottom = UDim.new(0, 8),
				PaddingLeft = UDim.new(0, 8),
				PaddingRight = UDim.new(0, 8),
				Name = "padding",
			}),
		}),
	})

	newdropdown.drop = drop
	autocanvasresize(drop.list.layout, drop.list)

	bar.MouseEnter:Connect(function()
		tween(bar.stroke, 0.15, { Transparency = 0.15 })
	end)
	bar.MouseLeave:Connect(function()
		if not newdropdown.settings.open then
			tween(bar.stroke, 0.15, { Transparency = 0.45 })
		end
	end)

	bar.MouseButton1Click:Connect(function()
		if newdropdown.settings.open then
			newdropdown:close()
		else
			newdropdown:open()
		end
	end)

	return newdropdown
end

function dropdown:open(force)
	if force or not self.settings.open then
		closeotheroverlays(self.library, self)
		self.settings.open = true
		local width = placeoverlay(self.drop, self.frame.bar, self.library.gui.main)
		self.drop.Size = UDim2.new(0, width, 0, 0)
		self.drop.Visible = true
		startfollow(self)
		local height = math.min(168, 16 + 34 * #self._items)
		tween(self.drop, 0.2, { Size = UDim2.new(0, width, 0, height) })
		tween(self.frame.bar.chevron, 0.2, { Rotation = 270 })
		tween(self.frame.bar.stroke, 0.15, { Transparency = 0.1, Color = theme.highlight })
	end
end

function dropdown:close()
	if self.settings.open then
		self.settings.open = false
		stopfollow(self)
		local width = math.max(self.drop.AbsoluteSize.X, 1)
		tween(self.drop, 0.2, { Size = UDim2.new(0, width, 0, 0) }).Completed:Connect(function()
			if not self.settings.open then
				self.drop.Visible = false
				self.drop.Parent = nil
			end
		end)
		tween(self.frame.bar.chevron, 0.2, { Rotation = 90 })
		tween(self.frame.bar.stroke, 0.15, { Transparency = 0.45, Color = COL_STROKE })
	end
end

function dropdown:additem(value)
	local strvalue = tostring(value)
	table.insert(self._items, strvalue)

	local item = create("TextButton", {
		BackgroundColor3 = theme.inputbackground,
		Font = Enum.Font.GothamMedium,
		Text = "  " .. strvalue,
		TextColor3 = theme.foreground,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		AutoButtonColor = false,
		Size = UDim2.new(1, 0, 0, 30),
		ZIndex = 42,
		Parent = self.drop.list,
		Name = strvalue,
	}, {
		create("UICorner", {
			CornerRadius = UDim.new(0, 7),
			Name = "corner",
		}),
		create("Frame", {
			Theme = { BackgroundColor3 = "highlight" },
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.new(0, 3, 0.62, 0),
			Visible = false,
			ZIndex = 43,
			Name = "accent",
		}, {
			create("UICorner", {
				CornerRadius = UDim.new(1, 0),
				Name = "corner",
			}),
		}),
		create("TextLabel", {
			Theme = { TextColor3 = "highlight" },
			Font = Enum.Font.GothamBold,
			Text = "✓",
			TextSize = 12,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.new(0, 14, 0, 14),
			Visible = false,
			ZIndex = 43,
			Name = "check",
		}),
	})

	item.MouseEnter:Connect(function()
		if self.library.flags[self.flag] ~= strvalue then
			tween(item, 0.12, { BackgroundColor3 = Color3.fromRGB(34, 36, 48) })
		end
	end)
	item.MouseLeave:Connect(function()
		local selected = self.library.flags[self.flag] == strvalue
		tween(item, 0.12, { BackgroundColor3 = selected and Color3.fromRGB(28, 40, 64) or theme.inputbackground })
	end)

	item.MouseButton1Click:Connect(function()
		self:set(strvalue)
		self:close()
	end)
end

function dropdown:removeitem(value)
	local strvalue = tostring(value)
	for i = #self._items, 1, -1 do
		if self._items[i] == strvalue then
			table.remove(self._items, i)
		end
	end
	local item = self.drop.list:FindFirstChild(strvalue)
	if item then
		item:Destroy()
	end
end

function dropdown:clear()
	table.clear(self._items)
	for _, child in self.drop.list:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
end

function dropdown:set(value)
	local strvalue = tostring(value)
	if self.library.flags[self.flag] == strvalue then
		return
	end
	local old = self.library.flags[self.flag]
	self.library.flags[self.flag] = strvalue
	self.frame.bar.selected.Text = strvalue
	for _, child in self.drop.list:GetChildren() do
		if child:IsA("TextButton") then
			local selected = child.Name == strvalue
			child.BackgroundColor3 = selected and Color3.fromRGB(28, 40, 64) or theme.inputbackground
			if child:FindFirstChild("accent") then
				child.accent.Visible = selected
			end
			if child:FindFirstChild("check") then
				child.check.Visible = selected
			end
		end
	end
	firecallback(self, self.callback, strvalue, old)
end

--[[ Checklist ]]--

local checklist = {}
checklist.__index = checklist

function checklist.new(options)
	local newchecklist = setmetatable(mergetables({
		itemtype = "checklist",
		content = "No Content Provided",
		flag = randomstring(32),
		ignore = false,
		callback = function() end,
		settings = { open = false },
	}, options), checklist)

	newchecklist.frame = makerow(newchecklist.content)
	newchecklist.frame.title.Text = newchecklist.content
	newchecklist._items = {}

	local bar = create("TextButton", {
		Theme = { BackgroundColor3 = "inputbackground" },
		Text = "",
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.new(0.32, 0, 0, 36),
		ZIndex = 2,
		Parent = newchecklist.frame,
		Name = "bar",
	}, {
		create("UICorner", {
			CornerRadius = UDim.new(0, 8),
			Name = "corner",
		}),
		create("UIStroke", {
			Color = COL_STROKE,
			Thickness = 1,
			Transparency = 0.45,
			Name = "stroke",
		}),
		create("TextLabel", {
			Theme = { TextColor3 = "foreground" },
			Font = Enum.Font.GothamMedium,
			Text = "0 Selected",
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 12, 0, 0),
			Size = UDim2.new(1, -36, 1, 0),
			ZIndex = 3,
			Name = "selected",
		}),
		create("ImageLabel", {
			Theme = { ImageColor3 = "muted" },
			Image = "rbxassetid://9243354333",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -16, 0.5, 0),
			Size = UDim2.new(0, 14, 0, 14),
			Rotation = 90,
			ZIndex = 3,
			Name = "chevron",
		}),
	})

	local drop = create("Frame", {
		Theme = { BackgroundColor3 = "sectionbackground" },
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Size = UDim2.new(0, 0, 0, 0),
		Visible = false,
		ZIndex = 40,
		Active = true,
		Name = "drop",
	}, {
		create("UICorner", {
			CornerRadius = UDim.new(0, 10),
			Name = "corner",
		}),
		create("UIStroke", {
			Color = COL_STROKE,
			Thickness = 1,
			Transparency = 0.25,
			Name = "stroke",
		}),
		create("ImageLabel", {
			Image = "rbxassetid://6015897845",
			ImageColor3 = Color3.fromRGB(0, 0, 0),
			ImageTransparency = 0.55,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 4),
			Size = UDim2.new(1, 28, 1, 28),
			ZIndex = 39,
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Rect.new(49, 49, 450, 450),
			Name = "shadow",
		}),
		create("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(210, 214, 228)),
			}),
			Rotation = 90,
			Name = "depth",
		}),
		create("ScrollingFrame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = Color3.fromRGB(70, 74, 90),
			CanvasSize = UDim2.new(),
			Size = UDim2.new(1, 0, 1, 0),
			ZIndex = 41,
			Name = "list",
		}, {
			create("UIListLayout", {
				Padding = UDim.new(0, 4),
				SortOrder = Enum.SortOrder.LayoutOrder,
				Name = "layout",
			}),
			create("UIPadding", {
				PaddingTop = UDim.new(0, 8),
				PaddingBottom = UDim.new(0, 8),
				PaddingLeft = UDim.new(0, 8),
				PaddingRight = UDim.new(0, 8),
				Name = "padding",
			}),
		}),
	})

	newchecklist.drop = drop
	autocanvasresize(drop.list.layout, drop.list)

	bar.MouseEnter:Connect(function()
		tween(bar.stroke, 0.15, { Transparency = 0.15 })
	end)
	bar.MouseLeave:Connect(function()
		if not newchecklist.settings.open then
			tween(bar.stroke, 0.15, { Transparency = 0.45 })
		end
	end)

	bar.MouseButton1Click:Connect(function()
		if newchecklist.settings.open then
			newchecklist:close()
		else
			newchecklist:open()
		end
	end)

	return newchecklist
end

function checklist:open(force)
	if force or not self.settings.open then
		closeotheroverlays(self.library, self)
		self.settings.open = true
		local width = placeoverlay(self.drop, self.frame.bar, self.library.gui.main)
		self.drop.Size = UDim2.new(0, width, 0, 0)
		self.drop.Visible = true
		startfollow(self)
		local count = 0
		for _ in next, self._items do
			count += 1
		end
		local height = math.min(168, 16 + 34 * count)
		tween(self.drop, 0.2, { Size = UDim2.new(0, width, 0, height) })
		tween(self.frame.bar.chevron, 0.2, { Rotation = 270 })
		tween(self.frame.bar.stroke, 0.15, { Transparency = 0.1, Color = theme.highlight })
	end
end

function checklist:close()
	if self.settings.open then
		self.settings.open = false
		stopfollow(self)
		local width = math.max(self.drop.AbsoluteSize.X, 1)
		tween(self.drop, 0.2, { Size = UDim2.new(0, width, 0, 0) }).Completed:Connect(function()
			if not self.settings.open then
				self.drop.Visible = false
				self.drop.Parent = nil
			end
		end)
		tween(self.frame.bar.chevron, 0.2, { Rotation = 90 })
		tween(self.frame.bar.stroke, 0.15, { Transparency = 0.45, Color = COL_STROKE })
	end
end

function checklist:updateselected()
	local count = 0
	for _, enabled in next, self.library.flags[self.flag] do
		if enabled then
			count += 1
		end
	end
	self.frame.bar.selected.Text = tostring(count) .. " Selected"
end

function checklist:additem(key, value)
	local strkey = tostring(key)
	self._items[strkey] = true
	self.library.flags[self.flag][strkey] = false

	local item = create("TextButton", {
		BackgroundColor3 = theme.inputbackground,
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.new(1, 0, 0, 30),
		ZIndex = 42,
		Parent = self.drop.list,
		Name = strkey,
	}, {
		create("UICorner", {
			CornerRadius = UDim.new(0, 7),
			Name = "corner",
		}),
		create("Frame", {
			BackgroundColor3 = COL_TRACKOFF,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 10, 0.5, 0),
			Size = UDim2.new(0, 16, 0, 16),
			ZIndex = 43,
			Name = "box",
		}, {
			create("UICorner", {
				CornerRadius = UDim.new(0, 5),
				Name = "corner",
			}),
			create("UIStroke", {
				Color = COL_STROKE,
				Thickness = 1,
				Name = "stroke",
			}),
			create("TextLabel", {
				Theme = { TextColor3 = "foreground" },
				Font = Enum.Font.GothamBold,
				Text = "✓",
				TextSize = 11,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 1, 0),
				Visible = false,
				ZIndex = 44,
				Name = "check",
			}),
		}),
		create("TextLabel", {
			Theme = { TextColor3 = "foreground" },
			Font = Enum.Font.GothamMedium,
			Text = strkey,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 34, 0, 0),
			Size = UDim2.new(1, -42, 1, 0),
			ZIndex = 43,
			Name = "label",
		}),
	})

	item.MouseEnter:Connect(function()
		if not self.library.flags[self.flag][strkey] then
			tween(item, 0.12, { BackgroundColor3 = Color3.fromRGB(34, 36, 48) })
		end
	end)
	item.MouseLeave:Connect(function()
		local enabled = self.library.flags[self.flag][strkey]
		tween(item, 0.12, { BackgroundColor3 = enabled and Color3.fromRGB(28, 40, 64) or theme.inputbackground })
	end)

	item.MouseButton1Click:Connect(function()
		self:switch(strkey)
	end)

	if value then
		self:toggle(strkey, true)
	end
end

function checklist:removeitem(key)
	local strkey = tostring(key)
	self._items[strkey] = nil
	self.library.flags[self.flag][strkey] = nil
	local item = self.drop.list:FindFirstChild(strkey)
	if item then
		item:Destroy()
	end
	self:updateselected()
end

function checklist:clear()
	for key in next, self._items do
		self:removeitem(key)
	end
end

function checklist:toggle(key, value)
	local strkey = tostring(key)
	local enabled = value
	if enabled == nil then
		enabled = not self.library.flags[self.flag][strkey]
	end
	self.library.flags[self.flag][strkey] = enabled
	local item = self.drop.list:FindFirstChild(strkey)
	if item then
		item.box.check.Visible = enabled
		item.box.BackgroundColor3 = enabled and theme.highlight or COL_TRACKOFF
		item.box.stroke.Enabled = not enabled
		item.BackgroundColor3 = enabled and Color3.fromRGB(28, 40, 64) or theme.inputbackground
	end
	self:updateselected()
	firecallback(self, self.callback, self.library.flags[self.flag])
end

function checklist:switch(key)
	self:toggle(key)
end

--[[ Color Picker ]]--

local picker = {}
picker.__index = picker

local function colorToHex(color)
	return string.format("%02X%02X%02X", math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
end

local function hexToColor(hex)
	hex = hex:gsub("#", "")
	if #hex ~= 6 then
		return nil
	end
	local r = tonumber(hex:sub(1, 2), 16)
	local g = tonumber(hex:sub(3, 4), 16)
	local b = tonumber(hex:sub(5, 6), 16)
	if not (r and g and b) then
		return nil
	end
	return Color3.fromRGB(r, g, b)
end

function picker.new(options)
	local newpicker = setmetatable(mergetables({
		itemtype = "picker",
		content = "No Content Provided",
		flag = randomstring(32),
		ignore = false,
		maxswatches = 5,
		callback = function() end,
		settings = { open = false },
	}, options), picker)

	newpicker.frame = makerow(newpicker.content)
	newpicker.frame.title.Text = newpicker.content
	newpicker._swatches = {}
	newpicker._activeIndex = 1
	newpicker._h, newpicker._s, newpicker._v = 0, 1, 1

	local swatchrow = create("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.new(0, 200, 0, 30),
		Parent = newpicker.frame,
		Name = "swatches",
	}, {
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Name = "layout",
		}),
		create("TextButton", {
			BackgroundColor3 = Color3.fromRGB(34, 36, 48),
			Font = Enum.Font.GothamBold,
			Text = "+",
			TextColor3 = Color3.fromRGB(150, 154, 168),
			TextSize = 16,
			AutoButtonColor = false,
			Size = UDim2.new(0, 24, 0, 24),
			LayoutOrder = 0,
			Name = "add",
		}, {
			create("UICorner", {
				CornerRadius = UDim.new(1, 0),
				Name = "corner",
			}),
		}),
	})

	swatchrow.add.MouseButton1Click:Connect(function()
		newpicker:open()
	end)

	return newpicker
end

function picker:_ensurepopup()
	if self._popup then
		return
	end

	local main = self.library.gui.main
	local backdrop = create("TextButton", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Visible = false,
		ZIndex = 50,
		Text = "",
		AutoButtonColor = false,
		Parent = main,
		Name = "ColorPickerBackdrop_" .. self.flag,
	})

	local popup = create("Frame", {
		BackgroundColor3 = Color3.fromRGB(18, 18, 26),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 240, 0, 320),
		Visible = false,
		ZIndex = 51,
		Active = true,
		Parent = main,
		Name = "ColorPickerPopup_" .. self.flag,
	}, {
		create("UICorner", {
			CornerRadius = UDim.new(0, 12),
			Name = "corner",
		}),
		create("UIPadding", {
			PaddingTop = UDim.new(0, 16),
			PaddingBottom = UDim.new(0, 16),
			PaddingLeft = UDim.new(0, 16),
			PaddingRight = UDim.new(0, 16),
			Name = "padding",
		}),
		create("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(210, 214, 228)),
			}),
			Rotation = 80,
			Name = "DepthGradient",
		}),
		create("ImageLabel", {
			Image = "rbxassetid://6015897845",
			ImageColor3 = Color3.fromRGB(0, 0, 0),
			ImageTransparency = 0.45,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 6),
			Size = UDim2.new(1, 36, 1, 36),
			ZIndex = 50,
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Rect.new(49, 49, 450, 450),
			Name = "shadow",
		}),
		create("Frame", {
			Theme = { BackgroundColor3 = "highlight" },
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 0, 0, 8),
			Size = UDim2.new(0, 6, 0, 6),
			ZIndex = 52,
			Name = "titledot",
		}, {
			create("UICorner", {
				CornerRadius = UDim.new(1, 0),
				Name = "corner",
			}),
		}),
		create("TextLabel", {
			Theme = { TextColor3 = "muted" },
			Font = Enum.Font.GothamMedium,
			Text = "CUSTOM COLOR",
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 12, 0, 0),
			Size = UDim2.new(1, -12, 0, 16),
			ZIndex = 52,
			Name = "title",
		}),
		create("Frame", {
			BackgroundColor3 = Color3.fromRGB(255, 0, 0),
			BorderSizePixel = 0,
			ClipsDescendants = true,
			Position = UDim2.new(0, 0, 0, 26),
			Size = UDim2.new(1, 0, 0, 130),
			ZIndex = 52,
			Active = true,
			Name = "sv",
		}, {
			create("UICorner", {
				CornerRadius = UDim.new(0, 10),
				Name = "corner",
			}),
			create("Frame", {
				BackgroundColor3 = Color3.fromRGB(255, 255, 255),
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 1, 0),
				ZIndex = 53,
				Name = "white",
			}, {
				create("UIGradient", {
					Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 0),
						NumberSequenceKeypoint.new(1, 1),
					}),
					Name = "gradient",
				}),
			}),
			create("Frame", {
				BackgroundColor3 = Color3.fromRGB(0, 0, 0),
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 1, 0),
				ZIndex = 54,
				Name = "black",
			}, {
				create("UIGradient", {
					Rotation = 90,
					Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 1),
						NumberSequenceKeypoint.new(1, 0),
					}),
					Name = "gradient",
				}),
			}),
			create("Frame", {
				BackgroundColor3 = Color3.fromRGB(255, 0, 0),
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(1, 0, 0, 0),
				Size = UDim2.new(0, 16, 0, 16),
				ZIndex = 56,
				Name = "cursor",
			}, {
				create("UICorner", {
					CornerRadius = UDim.new(1, 0),
					Name = "corner",
				}),
			}),
			create("TextButton", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 1, 0),
				ZIndex = 57,
				Text = "",
				AutoButtonColor = false,
				Name = "hit",
			}),
		}),
		create("Frame", {
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BorderSizePixel = 0,
			Position = UDim2.new(0, 0, 0, 170),
			Size = UDim2.new(1, 0, 0, 18),
			ZIndex = 52,
			Active = true,
			Name = "hue",
		}, {
			create("UICorner", {
				CornerRadius = UDim.new(0, 9),
				Name = "corner",
			}),
			create("UIGradient", {
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
					ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
					ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 255, 0)),
					ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 255, 255)),
					ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 0, 255)),
					ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0, 255)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)),
				}),
				Name = "gradient",
			}),
			create("Frame", {
				BackgroundColor3 = Color3.fromRGB(255, 0, 0),
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0, 0, 0.5, 0),
				Size = UDim2.new(0, 20, 0, 20),
				ZIndex = 53,
				Name = "thumb",
			}, {
				create("UICorner", {
					CornerRadius = UDim.new(1, 0),
					Name = "corner",
				}),
			}),
			create("TextButton", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 1, 0),
				ZIndex = 54,
				Text = "",
				AutoButtonColor = false,
				Name = "hit",
			}),
		}),
		create("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 0, 0, 202),
			Size = UDim2.new(1, 0, 0, 36),
			ZIndex = 52,
			Name = "previewrow",
		}, {
			create("Frame", {
				BackgroundColor3 = Color3.fromRGB(255, 0, 0),
				BorderSizePixel = 0,
				Size = UDim2.new(0, 36, 0, 36),
				ZIndex = 52,
				Name = "preview",
			}, {
				create("UICorner", {
					CornerRadius = UDim.new(0, 10),
					Name = "corner",
				}),
			}),
			create("Frame", {
				BackgroundColor3 = Color3.fromRGB(28, 28, 38),
				BorderSizePixel = 0,
				Position = UDim2.new(0, 46, 0, 0),
				Size = UDim2.new(1, -46, 0, 36),
				ZIndex = 52,
				Name = "hexfield",
			}, {
				create("UICorner", {
					CornerRadius = UDim.new(0, 10),
					Name = "corner",
				}),
				create("TextLabel", {
					Theme = { TextColor3 = "muted" },
					Font = Enum.Font.GothamMedium,
					Text = "#",
					TextSize = 13,
					BackgroundTransparency = 1,
					Position = UDim2.new(0, 12, 0, 0),
					Size = UDim2.new(0, 12, 1, 0),
					ZIndex = 53,
					Name = "hash",
				}),
				create("TextBox", {
					Theme = { TextColor3 = "foreground" },
					Font = Enum.Font.GothamMedium,
					PlaceholderColor3 = Color3.fromRGB(140, 140, 155),
					PlaceholderText = "FF0000",
					Text = "FF0000",
					TextSize = 13,
					TextXAlignment = Enum.TextXAlignment.Left,
					ClearTextOnFocus = false,
					BackgroundTransparency = 1,
					Position = UDim2.new(0, 24, 0, 0),
					Size = UDim2.new(1, -32, 1, 0),
					ZIndex = 53,
					Name = "input",
				}),
			}),
		}),
		create("TextButton", {
			Theme = {
				BackgroundColor3 = "highlight",
				TextColor3 = "foreground",
			},
			Font = Enum.Font.GothamBold,
			Text = "Apply Color",
			TextSize = 13,
			AutoButtonColor = false,
			Position = UDim2.new(0, 0, 0, 252),
			Size = UDim2.new(1, 0, 0, 36),
			ZIndex = 52,
			Name = "addswatch",
		}, {
			create("UICorner", {
				CornerRadius = UDim.new(0, 10),
				Name = "corner",
			}),
			create("UIGradient", {
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(70, 155, 255)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 110, 230)),
				}),
				Rotation = 90,
				Name = "gradient",
			}),
		}),
	})

	self._backdrop = backdrop
	self._popup = popup
	self._interacting = false

	local function applyFromHSV(h, s, v, skiphex)
		self:set(h, s, v, skiphex)
	end

	local function beginDrag(maidObj, input, update)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		self._interacting = true
		local mouse = Players.LocalPlayer:GetMouse()
		update(mouse)
		maidObj:givetask(mouse.Move:Connect(function()
			update(mouse)
		end))
		maidObj:givetask(input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				maidObj:dispose()
				-- Delay so backdrop click from the same press cannot close the popup.
				task.defer(function()
					self._interacting = false
				end)
			end
		end))
	end

	local svmaid = maid.new()
	popup.sv.hit.InputBegan:Connect(function(input)
		beginDrag(svmaid, input, function(mouse)
			local x = math.clamp((mouse.X - popup.sv.AbsolutePosition.X) / math.max(popup.sv.AbsoluteSize.X, 1), 0, 1)
			local y = math.clamp((mouse.Y - popup.sv.AbsolutePosition.Y) / math.max(popup.sv.AbsoluteSize.Y, 1), 0, 1)
			applyFromHSV(self._h, x, 1 - y)
		end)
	end)

	local huemaid = maid.new()
	popup.hue.hit.InputBegan:Connect(function(input)
		beginDrag(huemaid, input, function(mouse)
			local x = math.clamp((mouse.X - popup.hue.AbsolutePosition.X) / math.max(popup.hue.AbsoluteSize.X, 1), 0, 1)
			applyFromHSV(x, self._s, self._v)
		end)
	end)

	popup.previewrow.hexfield.input.FocusLost:Connect(function()
		local color = hexToColor(popup.previewrow.hexfield.input.Text)
		if color then
			local h, s, v = color:ToHSV()
			applyFromHSV(h, s, v, true)
		else
			popup.previewrow.hexfield.input.Text = colorToHex(Color3.fromHSV(self._h, self._s, self._v))
		end
	end)

	popup.addswatch.MouseButton1Click:Connect(function()
		self:replaceswatch(Color3.fromHSV(self._h, self._s, self._v))
		self:close()
	end)

	backdrop.MouseButton1Click:Connect(function()
		if not self._interacting then
			self:close()
		end
	end)
end

function picker:_refreshswatchselection()
	for i, swatch in ipairs(self._swatches) do
		local stroke = swatch:FindFirstChild("stroke")
		if not stroke then
			stroke = create("UIStroke", {
				Color = Color3.fromRGB(255, 255, 255),
				Thickness = 2,
				Transparency = 1,
				Parent = swatch,
				Name = "stroke",
			})
		end
		tween(stroke, 0.15, {
			Transparency = i == self._activeIndex and 0 or 1,
			Color = i == self._activeIndex and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(140, 140, 155),
		})
	end
end

function picker:addswatch(color)
	-- Initial setup only: fill up to maxswatches, never grow past that.
	if #self._swatches >= self.maxswatches then
		return
	end
	local index = #self._swatches + 1
	local swatch = create("TextButton", {
		BackgroundColor3 = color,
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.new(0, 24, 0, 24),
		LayoutOrder = index,
		Parent = self.frame.swatches,
		Name = "Swatch" .. index,
	}, {
		create("UICorner", {
			CornerRadius = UDim.new(1, 0),
			Name = "corner",
		}),
		create("UIStroke", {
			Color = Color3.fromRGB(255, 255, 255),
			Thickness = 2,
			Transparency = 1,
			Name = "stroke",
		}),
	})
	table.insert(self._swatches, swatch)

	swatch.MouseButton1Click:Connect(function()
		local found = table.find(self._swatches, swatch) or index
		self._activeIndex = found
		local h, s, v = swatch.BackgroundColor3:ToHSV()
		self:set(h, s, v)
		self:_refreshswatchselection()
	end)

	if index == 1 then
		self._activeIndex = 1
		self:_refreshswatchselection()
	end
end

function picker:replaceswatch(color)
	if #self._swatches == 0 then
		self:addswatch(color)
		self:set(color:ToHSV())
		return
	end
	local index = math.clamp(self._activeIndex or 1, 1, #self._swatches)
	local swatch = self._swatches[index]
	swatch.BackgroundColor3 = color
	self._activeIndex = index
	local h, s, v = color:ToHSV()
	self:set(h, s, v)
	self:_refreshswatchselection()
end

function picker:open(force)
	self:_ensurepopup()
	if force or not self.settings.open then
		self.settings.open = true
		self._backdrop.Visible = true
		self._popup.Visible = true
		self:set(self._h, self._s, self._v)
	end
end

function picker:close()
	if self.settings.open then
		self.settings.open = false
		if self._backdrop then
			self._backdrop.Visible = false
		end
		if self._popup then
			self._popup.Visible = false
		end
	end
end

function picker:set(h, s, v, skiphex)
	self._h, self._s, self._v = h, s, v
	local colour = Color3.fromHSV(h, s, v)
	self.library.flags[self.flag] = { h = h, s = s, v = v, color = colour }

	if self._popup then
		self._popup.sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
		self._popup.sv.cursor.BackgroundColor3 = colour
		self._popup.sv.cursor.Position = UDim2.new(s, 0, 1 - v, 0)
		self._popup.hue.thumb.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
		self._popup.hue.thumb.Position = UDim2.new(h, 0, 0.5, 0)
		self._popup.previewrow.preview.BackgroundColor3 = colour
		if not skiphex then
			self._popup.previewrow.hexfield.input.Text = colorToHex(colour)
		end
	end

	firecallback(self, self.callback, colour)
end

--[[ Section ]]--

local section = {}
section.__index = section

function section.new(options)
	local newsection = setmetatable(mergetables({
		content = "No Content Provided",
	}, options), section)

	newsection.frame = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		Name = newsection.content,
	}, {
		create("UIListLayout", {
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			Name = "list",
		}),
		create("TextLabel", {
			Theme = { TextColor3 = "muted" },
			Font = Enum.Font.GothamBold,
			Text = string.upper(newsection.content),
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 18),
			LayoutOrder = 0,
			Name = "header",
		}),
	})

	autoresize(newsection.frame.list, newsection.frame)
	return newsection
end

--[[ Column ]]--

local column = {}
column.__index = column

function column.new(options)
	local newcolumn = setmetatable(mergetables({
		weight = 1,
	}, options), column)

	newcolumn.frame = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		Name = "column",
	}, {
		create("UIListLayout", {
			Padding = UDim.new(0, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			Name = "list",
		}),
	})

	autoresize(newcolumn.frame.list, newcolumn.frame)
	return newcolumn
end

function column:addsection(options)
	local newsection = section.new(options)
	newsection.library = self.library
	newsection.frame.Parent = self.frame
	newsection.frame.LayoutOrder = #self.frame:GetChildren()
	if self._onresize then
		newsection.frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(self._onresize)
		self._onresize()
	end
	return newsection
end

--[[ Columns ]]--

local columns = {}

function columns.__index(self, key)
	if typeof(key) == "number" then
		return self._columns[key]
	end
	return columns[key]
end

function columns.new(options)
	local newcolumns = setmetatable(mergetables({
		gap = 12,
	}, options), columns)

	newcolumns._columns = {}
	newcolumns.frame = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		Name = "columns",
	}, {
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			Padding = UDim.new(0, newcolumns.gap),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Name = "list",
		}),
	})

	autoresize(newcolumns.frame.list, newcolumns.frame)
	newcolumns._relayout = autofitcolumnwidths(newcolumns.frame, function()
		return newcolumns._columns
	end, newcolumns.gap)

	return newcolumns
end

function columns:addcolumn(options)
	local newcolumn = column.new(options)
	newcolumn.library = self.library
	newcolumn._onresize = self._relayout
	newcolumn.frame.Parent = self.frame
	newcolumn.frame.LayoutOrder = #self._columns + 1
	newcolumn.frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(self._relayout)
	table.insert(self._columns, newcolumn)
	self._relayout()
	return newcolumn
end

local function mount(sectionself, item, options)
	item.library = sectionself.library
	item.frame.Parent = sectionself.frame
	item.frame.LayoutOrder = #sectionself.frame:GetChildren()
	sectionself.library.items[item.flag] = item
	return item
end

function section:addlabel(options)
	local newlabel = label.new(options)
	mount(self, newlabel, options)
	newlabel:update(newlabel.content)
	return newlabel
end

function section:addbutton(options)
	local newbutton = button.new(options)
	return mount(self, newbutton, options)
end

function section:addtoggle(options)
	local newtoggle = toggle.new(options)
	self.library.flags[newtoggle.flag] = false
	mount(self, newtoggle, options)
	if options and options.default then
		newtoggle:set(true)
	end
	return newtoggle
end

function section:addbind(options)
	local newbind = bind.new(options)
	self.library.flags[newbind.flag] = "None"
	mount(self, newbind, options)
	if options and options.default then
		newbind:set(options.default)
	end
	return newbind
end

function section:addbox(options)
	local newbox = box.new(options)
	self.library.flags[newbox.flag] = ""
	mount(self, newbox, options)
	if options and options.default then
		newbox:set(options.default)
	end
	return newbox
end

function section:addslider(options)
	local newslider = slider.new(options)
	self.library.flags[newslider.flag] = newslider.min
	mount(self, newslider, options)
	if options and options.default then
		newslider:set(options.default, true)
	else
		newslider:set(newslider.min, true)
	end
	return newslider
end

function section:adddropdown(options)
	local newdropdown = dropdown.new(options)
	self.library.flags[newdropdown.flag] = ""
	mount(self, newdropdown, options)
	if options and options.items then
		for i = 1, #options.items do
			newdropdown:additem(options.items[i])
		end
	end
	if options and options.default then
		newdropdown:set(options.default)
	end
	return newdropdown
end

function section:addchecklist(options)
	local newchecklist = checklist.new(options)
	self.library.flags[newchecklist.flag] = {}
	mount(self, newchecklist, options)
	if options and options.items then
		for i = 1, #options.items do
			local entry = options.items[i]
			if typeof(entry) == "table" then
				newchecklist:additem(entry[1] or entry.key, entry[2] or entry.value)
			else
				newchecklist:additem(entry, false)
			end
		end
	end
	return newchecklist
end

function section:addpicker(options)
	local newpicker = picker.new(options)
	self.library.flags[newpicker.flag] = { h = 0, s = 1, v = 1, color = Color3.fromRGB(255, 0, 0) }
	mount(self, newpicker, options)
	if options and options.default then
		local h, s, v = options.default:ToHSV()
		newpicker:set(h, s, v)
	end
	if options and options.swatches then
		for i = 1, #options.swatches do
			newpicker:addswatch(options.swatches[i])
		end
	end
	return newpicker
end

--[[ Tab ]]--

local tab = {}
tab.__index = tab

function tab.new(options)
	local newtab = setmetatable(mergetables({
		content = "No Content Provided",
		settings = { open = false },
	}, options), tab)

	newtab.button = create("TextButton", {
		Theme = { TextColor3 = "muted" },
		Font = Enum.Font.Gotham,
		Text = newtab.content,
		TextSize = 13,
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		ZIndex = 2,
		Name = newtab.content,
	})

	newtab.frame = create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 24, 0, 18),
		Size = UDim2.new(1, -48, 1, -36),
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 3,
		Visible = false,
		Name = newtab.content,
	}, {
		create("UIPadding", {
			PaddingRight = UDim.new(0, 4),
			Name = "padding",
		}),
		create("UIListLayout", {
			Padding = UDim.new(0, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Name = "list",
		}),
	})

	autocanvasresize(newtab.frame.list, newtab.frame)

	newtab.button.MouseButton1Click:Connect(function()
		if not newtab.settings.open then
			newtab:open()
		end
	end)

	return newtab
end

function tab:open()
	local profile = self.profile or self.library._currentProfile
	if self.library.closedashboard then
		self.library:closedashboard()
	end
	local selected = profile and profile.selected
	if selected == self and self.settings.open then
		return
	end
	if selected and selected ~= self then
		selected:close()
	end
	if profile then
		profile.selected = self
		profile.page.Visible = true
	end
	self.library.settings.selected = self
	self.settings.open = true
	self.frame.Visible = true
	tween(self.button, 0.15, { TextColor3 = theme.foreground })
end

function tab:close()
	local profile = self.profile or self.library._currentProfile
	if self.library.settings.selected == self then
		self.library.settings.selected = nil
	end
	if profile and profile.selected == self then
		profile.selected = nil
	end
	self.settings.open = false
	self.frame.Visible = false
	tween(self.button, 0.15, { TextColor3 = theme.muted })
end

function tab:addsection(options)
	local newsection = section.new(options)
	newsection.library = self.library
	newsection.frame.Parent = self.frame
	return newsection
end

function tab:addcolumns(options)
	local count = 2
	local gap = 12
	local widths = nil
	if typeof(options) == "number" then
		count = math.max(1, math.floor(options))
	elseif typeof(options) == "table" then
		gap = options.gap or 12
		widths = options.widths
		count = options.count or (widths and #widths) or 2
		count = math.max(1, math.floor(count))
	end

	local row = columns.new({
		gap = gap,
		library = self.library,
	})
	row.library = self.library
	row.frame.Parent = self.frame

	for i = 1, count do
		local weight = 1
		if widths and typeof(widths[i]) == "number" then
			weight = widths[i]
		end
		row:addcolumn({ weight = weight })
	end

	return row
end

--[[ Library ]]--

local library = {}
library.__index = library

function library.new(options)
	local player = Players.LocalPlayer
	if not player then
		error("AvalonLibrary must run on the client (use a LocalScript)", 2)
	end
	local mouse = player:GetMouse()

	local newlibrary = setmetatable(mergetables({
		title = "Avalon",
		content = "Avalon",
		version = "1.0.0",
		togglebind = "RightControl",
		profiles = { "Primary", "Secondary" },
		onprofilechanged = function() end,
		key = "—",
		keyexpires = nil,
		discord = "",
		supportedgames = {},
		changelogs = {
			ui = {},
			games = {},
		},
		configfolder = "Avalon/configs",
		autoloadconfig = nil,
		flags = {},
		items = {},
		tabs = {},
		settings = {
			theme = theme,
			dragging = false,
			binding = false,
			silent = false,
			selected = nil,
			profile = "Primary",
			profileIndex = 1,
			dashboardopen = false,
			changelogtab = "ui",
			configname = "",
			activeconfig = nil,
			configpickeropen = false,
			istextboxfocused = UserInputService:GetFocusedTextBox() ~= nil,
			dragleniency = 0.15,
		},
	}, options), library)

	newlibrary.settings.togglebind = newlibrary.togglebind
	newlibrary._profiles = {}

	if typeof(newlibrary.changelogs) ~= "table" then
		newlibrary.changelogs = { ui = {}, games = {} }
	else
		newlibrary.changelogs.ui = newlibrary.changelogs.ui or newlibrary.changelogs.UI or {}
		newlibrary.changelogs.games = newlibrary.changelogs.games
			or newlibrary.changelogs.game
			or newlibrary.changelogs.Games
			or {}
	end
	if typeof(newlibrary.supportedgames) ~= "table" then
		newlibrary.supportedgames = {}
	end
	newlibrary.discord = tostring(newlibrary.discord or "")
	newlibrary.configfolder = tostring(newlibrary.configfolder or "Avalon/configs")
	newlibrary._configStatusText = ""

	newlibrary.dir = create("Folder", {
		Name = "AvalonLib",
	}, {
		create("ScreenGui", {
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			DisplayOrder = 50,
			ResetOnSpawn = false,
			Name = "gui",
		}, {
			create("Frame", {
				Theme = { BackgroundColor3 = "mainbackground" },
				BorderSizePixel = 0,
				ClipsDescendants = false,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0.5, 0),
				Size = UDim2.new(0, 740, 0, 560),
				Active = true,
				Name = "main",
			}, {
				create("UICorner", {
					CornerRadius = UDim.new(0, 12),
					Name = "corner",
				}),
				create("UIGradient", {
					Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, Color3.fromRGB(16, 16, 22)),
						ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 8, 12)),
					}),
					Rotation = 80,
					Name = "DepthGradient",
				}),
				create("Frame", {
					Theme = { BackgroundColor3 = "titlebackground" },
					BackgroundTransparency = 0.15,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 54),
					ZIndex = 5,
					Name = "top",
				}, {
					create("UICorner", {
						CornerRadius = UDim.new(0, 12),
						Name = "corner",
					}),
					create("Frame", {
						BackgroundColor3 = COL_STROKE,
						BackgroundTransparency = 0.4,
						BorderSizePixel = 0,
						AnchorPoint = Vector2.new(0, 1),
						Position = UDim2.new(0, 0, 1, 0),
						Size = UDim2.new(1, 0, 0, 1),
						Name = "divider",
					}),
					create("Frame", {
						BackgroundColor3 = Color3.fromRGB(255, 255, 255),
						BorderSizePixel = 0,
						AnchorPoint = Vector2.new(0, 1),
						Position = UDim2.new(0, 0, 1, 0),
						Size = UDim2.new(1, 0, 0, 1),
						ZIndex = 5,
						Name = "accent",
					}, {
						create("UIGradient", {
							Transparency = NumberSequence.new({
								NumberSequenceKeypoint.new(0, 1),
								NumberSequenceKeypoint.new(0.2, 0.85),
								NumberSequenceKeypoint.new(0.5, 0.94),
								NumberSequenceKeypoint.new(0.8, 0.85),
								NumberSequenceKeypoint.new(1, 1),
							}),
							Name = "gradient",
						}),
					}),
					create("TextButton", {
						Theme = { TextColor3 = "foreground" },
						Font = Enum.Font.GothamBold,
						Text = newlibrary.title,
						TextSize = 16,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextYAlignment = Enum.TextYAlignment.Center,
						AutoButtonColor = false,
						BackgroundTransparency = 1,
						AutomaticSize = Enum.AutomaticSize.X,
						AnchorPoint = Vector2.new(0, 0.5),
						Position = UDim2.new(0, 20, 0.5, 0),
						Size = UDim2.new(0, 0, 0, 22),
						ZIndex = 6,
						Name = "brand",
					}),
					create("Frame", {
						BackgroundColor3 = COL_STROKE,
						BackgroundTransparency = 0.2,
						BorderSizePixel = 0,
						AnchorPoint = Vector2.new(0, 0.5),
						Position = UDim2.new(0, 92, 0.5, 0),
						Size = UDim2.new(0, 1, 0, 18),
						ZIndex = 3,
						Name = "namedivider",
					}),
					create("Frame", {
						BackgroundTransparency = 1,
						AnchorPoint = Vector2.new(0, 0.5),
						Position = UDim2.new(0, 108, 0.5, 0),
						Size = UDim2.new(0, 320, 0, 30),
						ClipsDescendants = true,
						ZIndex = 4,
						Name = "nav",
					}),
					create("Frame", {
						BackgroundColor3 = Color3.fromRGB(18, 18, 26),
						BorderSizePixel = 0,
						AnchorPoint = Vector2.new(1, 0.5),
						Position = UDim2.new(1, -92, 0.5, 0),
						Size = UDim2.new(0, 172, 0, 30),
						ClipsDescendants = true,
						Active = true,
						ZIndex = 6,
						Name = "profile",
					}, {
						create("UICorner", {
							CornerRadius = UDim.new(0, 8),
							Name = "corner",
						}),
						create("UIStroke", {
							Color = COL_STROKE,
							Thickness = 1,
							Transparency = 0.55,
							Name = "stroke",
						}),
						create("Frame", {
							BackgroundColor3 = Color3.fromRGB(40, 90, 180),
							BorderSizePixel = 0,
							AnchorPoint = Vector2.new(0, 0.5),
							Position = UDim2.new(0, 2, 0.5, 0),
							Size = UDim2.new(0, 80, 0, 24),
							ZIndex = 1,
							Name = "active",
						}, {
							create("UICorner", {
								CornerRadius = UDim.new(0, 6),
								Name = "corner",
							}),
							create("UIGradient", {
								Color = ColorSequence.new({
									ColorSequenceKeypoint.new(0, Color3.fromRGB(56, 140, 255)),
									ColorSequenceKeypoint.new(1, Color3.fromRGB(36, 100, 210)),
								}),
								Rotation = 90,
								Name = "gradient",
							}),
						}),
						create("Frame", {
							BackgroundTransparency = 1,
							Size = UDim2.new(1, -4, 1, 0),
							Position = UDim2.new(0, 2, 0, 0),
							ZIndex = 2,
							Name = "tabs",
						}, {
							create("UIListLayout", {
								FillDirection = Enum.FillDirection.Horizontal,
								HorizontalAlignment = Enum.HorizontalAlignment.Left,
								VerticalAlignment = Enum.VerticalAlignment.Center,
								SortOrder = Enum.SortOrder.LayoutOrder,
								Name = "list",
							}),
						}),
					}),
					create("TextButton", {
						Theme = { TextColor3 = "muted" },
						Font = Enum.Font.Gotham,
						Text = "-",
						TextSize = 16,
						AutoButtonColor = false,
						BackgroundTransparency = 1,
						AnchorPoint = Vector2.new(1, 0.5),
						Position = UDim2.new(1, -46, 0.5, 0),
						Size = UDim2.new(0, 26, 0, 26),
						Name = "minimize",
					}),
					create("TextButton", {
						Theme = { TextColor3 = "muted" },
						Font = Enum.Font.Gotham,
						Text = "×",
						TextSize = 16,
						AutoButtonColor = false,
						BackgroundTransparency = 1,
						AnchorPoint = Vector2.new(1, 0.5),
						Position = UDim2.new(1, -14, 0.5, 0),
						Size = UDim2.new(0, 26, 0, 26),
						Name = "close",
					}),
				}),
				create("Frame", {
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					ClipsDescendants = true,
					Position = UDim2.new(0, 0, 0, 54),
					Size = UDim2.new(1, 0, 1, -54),
					Name = "content",
				}),
			}),
		}),
	})

	newlibrary.gui = newlibrary.dir.gui
	local main = newlibrary.gui.main
	local top = main.top
	local content = main.content

	-- Invisible modal sink unlocks the mouse in LockFirstPerson / mouse-locked states.
	create("TextButton", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Text = "",
		AutoButtonColor = false,
		Modal = true,
		Active = true,
		Selectable = false,
		ZIndex = 0,
		Parent = newlibrary.gui,
		Name = "cursorunlock",
	})

	local function applycursoroverride(enabled)
		if enabled then
			if not newlibrary._cursorConn then
				newlibrary._savedMouseBehavior = UserInputService.MouseBehavior
				newlibrary._savedMouseIconEnabled = UserInputService.MouseIconEnabled
				newlibrary._cursorConn = RunService.RenderStepped:Connect(function()
					if not newlibrary.gui.Enabled then
						return
					end
					UserInputService.MouseBehavior = Enum.MouseBehavior.Default
					UserInputService.MouseIconEnabled = true
				end)
			end
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		else
			if newlibrary._cursorConn then
				newlibrary._cursorConn:Disconnect()
				newlibrary._cursorConn = nil
			end
			if newlibrary._savedMouseBehavior ~= nil then
				UserInputService.MouseBehavior = newlibrary._savedMouseBehavior
				newlibrary._savedMouseBehavior = nil
			end
			if newlibrary._savedMouseIconEnabled ~= nil then
				UserInputService.MouseIconEnabled = newlibrary._savedMouseIconEnabled
				newlibrary._savedMouseIconEnabled = nil
			end
		end
	end

	newlibrary._applycursoroverride = applycursoroverride
	if newlibrary.gui.Enabled then
		applycursoroverride(true)
	end

	local function dashsectionlabel(text, order)
		return create("TextLabel", {
			Font = Enum.Font.GothamBold,
			Text = string.upper(text),
			TextColor3 = COL_HEADER,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 16),
			LayoutOrder = order,
			Name = "section_" .. text,
		})
	end

	local dashboard = create("Frame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		Visible = false,
		ZIndex = 3,
		Parent = content,
		Name = "dashboard",
	}, {
		create("UIPadding", {
			PaddingTop = UDim.new(0, 22),
			PaddingBottom = UDim.new(0, 22),
			PaddingLeft = UDim.new(0, 20),
			PaddingRight = UDim.new(0, 20),
			Name = "padding",
		}),
		-- LEFT: transparent scroll with stacked soft cards
		create("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 0, 0, 0),
			Size = UDim2.new(0.5, -8, 1, 0),
			Name = "left",
		}, {
			create("ScrollingFrame", {
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 1, 0),
				CanvasSize = UDim2.new(),
				ScrollBarThickness = 3,
				ScrollBarImageColor3 = Color3.fromRGB(70, 74, 90),
				ScrollingDirection = Enum.ScrollingDirection.Y,
				ClipsDescendants = true,
				Name = "panel",
			}, {
				create("UIPadding", {
					PaddingTop = UDim.new(0, 4),
					PaddingBottom = UDim.new(0, 12),
					PaddingLeft = UDim.new(0, 2),
					PaddingRight = UDim.new(0, 6),
					Name = "padding",
				}),
				create("UIListLayout", {
					Padding = UDim.new(0, 16),
					SortOrder = Enum.SortOrder.LayoutOrder,
					VerticalAlignment = Enum.VerticalAlignment.Top,
					Name = "list",
				}),
				-- Hero (no card)
				create("TextLabel", {
					Theme = { TextColor3 = "foreground" },
					Font = Enum.Font.GothamBold,
					Text = newlibrary.title,
					TextSize = 28,
					TextXAlignment = Enum.TextXAlignment.Left,
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 32),
					LayoutOrder = 1,
					Name = "brand",
				}),
				create("TextLabel", {
					Theme = { TextColor3 = "muted" },
					Font = Enum.Font.Gotham,
					Text = tostring(newlibrary.version) .. "  ·  Dashboard",
					TextSize = 12,
					TextXAlignment = Enum.TextXAlignment.Left,
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 18),
					LayoutOrder = 2,
					Name = "subtitle",
				}),
				create("Frame", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 6),
					LayoutOrder = 3,
					Name = "herospacer",
				}),
				-- Account card
				create("Frame", {
					Theme = { BackgroundColor3 = "sectionbackground" },
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 88),
					LayoutOrder = 4,
					Name = "account",
				}, {
					create("UICorner", { CornerRadius = UDim.new(0, 14), Name = "corner" }),
					create("UIStroke", { Color = COL_ROWEDGE, Thickness = 1, Transparency = 0.75, Name = "edge" }),
					create("ImageLabel", {
						BackgroundColor3 = Color3.fromRGB(24, 24, 32),
						BorderSizePixel = 0,
						Size = UDim2.new(0, 48, 0, 48),
						Position = UDim2.new(0, 18, 0.5, 0),
						AnchorPoint = Vector2.new(0, 0.5),
						Name = "avatar",
					}, {
						create("UICorner", { CornerRadius = UDim.new(1, 0), Name = "corner" }),
					}),
					create("TextLabel", {
						Theme = { TextColor3 = "foreground" },
						Font = Enum.Font.GothamMedium,
						Text = player.DisplayName,
						TextSize = 15,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextTruncate = Enum.TextTruncate.AtEnd,
						BackgroundTransparency = 1,
						AnchorPoint = Vector2.new(0, 0.5),
						Position = UDim2.new(0, 78, 0.5, -9),
						Size = UDim2.new(1, -170, 0, 18),
						Name = "displayname",
					}),
					create("TextLabel", {
						Theme = { TextColor3 = "muted" },
						Font = Enum.Font.Gotham,
						Text = "@" .. player.Name,
						TextSize = 12,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextTruncate = Enum.TextTruncate.AtEnd,
						BackgroundTransparency = 1,
						AnchorPoint = Vector2.new(0, 0.5),
						Position = UDim2.new(0, 78, 0.5, 11),
						Size = UDim2.new(1, -170, 0, 14),
						Name = "username",
					}),
					create("TextButton", {
						BackgroundColor3 = Color3.fromRGB(72, 82, 196),
						Font = Enum.Font.GothamMedium,
						Text = "Discord",
						TextColor3 = Color3.fromRGB(255, 255, 255),
						TextSize = 11,
						AutoButtonColor = false,
						AnchorPoint = Vector2.new(1, 0.5),
						Position = UDim2.new(1, -16, 0.5, 0),
						Size = UDim2.new(0, 68, 0, 28),
						Visible = false,
						Name = "discord",
					}, {
						create("UICorner", { CornerRadius = UDim.new(0, 8), Name = "corner" }),
					}),
				}),
				-- License card
				create("Frame", {
					Theme = { BackgroundColor3 = "sectionbackground" },
					BorderSizePixel = 0,
					AutomaticSize = Enum.AutomaticSize.Y,
					Size = UDim2.new(1, 0, 0, 0),
					LayoutOrder = 5,
					Name = "license",
				}, {
					create("UICorner", { CornerRadius = UDim.new(0, 14), Name = "corner" }),
					create("UIStroke", { Color = COL_ROWEDGE, Thickness = 1, Transparency = 0.75, Name = "edge" }),
					create("UIPadding", {
						PaddingTop = UDim.new(0, 16),
						PaddingBottom = UDim.new(0, 16),
						PaddingLeft = UDim.new(0, 16),
						PaddingRight = UDim.new(0, 16),
						Name = "padding",
					}),
					create("UIListLayout", {
						Padding = UDim.new(0, 12),
						SortOrder = Enum.SortOrder.LayoutOrder,
						Name = "list",
					}),
					dashsectionlabel("License", 1),
					create("TextButton", {
						Theme = { TextColor3 = "foreground", BackgroundColor3 = "inputbackground" },
						Font = Enum.Font.GothamMedium,
						Text = "—",
						TextSize = 13,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextTruncate = Enum.TextTruncate.AtEnd,
						AutoButtonColor = false,
						Size = UDim2.new(1, 0, 0, 40),
						LayoutOrder = 2,
						Name = "keyvalue",
					}, {
						create("UICorner", { CornerRadius = UDim.new(0, 10), Name = "corner" }),
						create("UIPadding", {
							PaddingLeft = UDim.new(0, 12),
							PaddingRight = UDim.new(0, 12),
							Name = "padding",
						}),
					}),
					create("TextLabel", {
						Theme = { TextColor3 = "muted" },
						Font = Enum.Font.Gotham,
						Text = "Click key to copy",
						TextSize = 10,
						TextXAlignment = Enum.TextXAlignment.Left,
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 12),
						LayoutOrder = 3,
						Name = "keylabel",
					}),
					create("Frame", {
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 28),
						LayoutOrder = 4,
						Name = "expiresrow",
					}, {
						create("TextLabel", {
							Theme = { TextColor3 = "muted" },
							Font = Enum.Font.Gotham,
							Text = "Time remaining",
							TextSize = 12,
							TextXAlignment = Enum.TextXAlignment.Left,
							BackgroundTransparency = 1,
							AnchorPoint = Vector2.new(0, 0.5),
							Position = UDim2.new(0, 0, 0.5, 0),
							Size = UDim2.new(0.5, 0, 0, 16),
							Name = "expireslabel",
						}),
						create("TextLabel", {
							Theme = { TextColor3 = "highlight" },
							Font = Enum.Font.GothamBold,
							Text = "Lifetime",
							TextSize = 14,
							TextXAlignment = Enum.TextXAlignment.Right,
							BackgroundTransparency = 1,
							AnchorPoint = Vector2.new(1, 0.5),
							Position = UDim2.new(1, 0, 0.5, 0),
							Size = UDim2.new(0.5, 0, 0, 18),
							Name = "expiresvalue",
						}),
					}),
				}),
				-- Configs card
				create("Frame", {
					Theme = { BackgroundColor3 = "sectionbackground" },
					BorderSizePixel = 0,
					AutomaticSize = Enum.AutomaticSize.Y,
					Size = UDim2.new(1, 0, 0, 0),
					LayoutOrder = 6,
					Name = "configs",
				}, {
					create("UICorner", { CornerRadius = UDim.new(0, 14), Name = "corner" }),
					create("UIStroke", { Color = COL_ROWEDGE, Thickness = 1, Transparency = 0.75, Name = "edge" }),
					create("UIPadding", {
						PaddingTop = UDim.new(0, 16),
						PaddingBottom = UDim.new(0, 16),
						PaddingLeft = UDim.new(0, 16),
						PaddingRight = UDim.new(0, 16),
						Name = "padding",
					}),
					create("UIListLayout", {
						Padding = UDim.new(0, 12),
						SortOrder = Enum.SortOrder.LayoutOrder,
						Name = "list",
					}),
					dashsectionlabel("Configs", 1),
					create("TextLabel", {
						Theme = { TextColor3 = "muted" },
						Font = Enum.Font.Gotham,
						Text = "Active · none",
						TextSize = 12,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextTruncate = Enum.TextTruncate.AtEnd,
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 14),
						LayoutOrder = 2,
						Name = "configactive",
					}),
					create("TextButton", {
						Theme = { TextColor3 = "foreground", BackgroundColor3 = "inputbackground" },
						Font = Enum.Font.GothamMedium,
						Text = "Pick a config",
						TextSize = 13,
						TextXAlignment = Enum.TextXAlignment.Left,
						AutoButtonColor = false,
						Size = UDim2.new(1, 0, 0, 40),
						LayoutOrder = 3,
						Name = "configpick",
					}, {
						create("UICorner", { CornerRadius = UDim.new(0, 10), Name = "corner" }),
						create("UIPadding", {
							PaddingLeft = UDim.new(0, 12),
							PaddingRight = UDim.new(0, 36),
							Name = "padding",
						}),
						create("ImageLabel", {
							Theme = { ImageColor3 = "muted" },
							Image = "rbxassetid://9243354333",
							BackgroundTransparency = 1,
							AnchorPoint = Vector2.new(0.5, 0.5),
							Position = UDim2.new(1, -16, 0.5, 0),
							Size = UDim2.new(0, 14, 0, 14),
							Rotation = 90,
							ZIndex = 3,
							Name = "caret",
						}),
					}),
					create("ScrollingFrame", {
						Theme = { BackgroundColor3 = "inputbackground" },
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, 0),
						CanvasSize = UDim2.new(),
						ScrollBarThickness = 3,
						ScrollBarImageColor3 = Color3.fromRGB(70, 74, 90),
						Visible = false,
						ZIndex = 6,
						LayoutOrder = 4,
						Name = "configlist",
					}, {
						create("UICorner", { CornerRadius = UDim.new(0, 10), Name = "corner" }),
						create("UIPadding", {
							PaddingTop = UDim.new(0, 10),
							PaddingBottom = UDim.new(0, 10),
							PaddingLeft = UDim.new(0, 10),
							PaddingRight = UDim.new(0, 10),
							Name = "padding",
						}),
						create("UIListLayout", {
							Padding = UDim.new(0, 6),
							SortOrder = Enum.SortOrder.LayoutOrder,
							Name = "layout",
						}),
					}),
					create("TextLabel", {
						Theme = { TextColor3 = "muted" },
						Font = Enum.Font.Gotham,
						Text = "Name",
						TextSize = 10,
						TextXAlignment = Enum.TextXAlignment.Left,
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 12),
						LayoutOrder = 5,
						Name = "confignamelabel",
					}),
					create("TextBox", {
						Theme = { TextColor3 = "foreground", BackgroundColor3 = "inputbackground" },
						Font = Enum.Font.GothamMedium,
						PlaceholderColor3 = Color3.fromRGB(100, 104, 120),
						PlaceholderText = "e.g. Rage, Legit, Farm",
						Text = "",
						TextSize = 13,
						TextXAlignment = Enum.TextXAlignment.Left,
						ClearTextOnFocus = false,
						Size = UDim2.new(1, 0, 0, 40),
						LayoutOrder = 6,
						Name = "configname",
					}, {
						create("UICorner", { CornerRadius = UDim.new(0, 10), Name = "corner" }),
						create("UIPadding", {
							PaddingLeft = UDim.new(0, 12),
							PaddingRight = UDim.new(0, 12),
							Name = "padding",
						}),
					}),
					create("Frame", {
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 34),
						LayoutOrder = 7,
						Name = "configactions",
					}, {
						create("UIListLayout", {
							FillDirection = Enum.FillDirection.Horizontal,
							Padding = UDim.new(0, 8),
							SortOrder = Enum.SortOrder.LayoutOrder,
							Name = "layout",
						}),
						create("TextButton", {
							Theme = { BackgroundColor3 = "highlight", TextColor3 = "foreground" },
							Font = Enum.Font.GothamMedium,
							Text = "Make",
							TextSize = 12,
							AutoButtonColor = false,
							Size = UDim2.new(1 / 3, -6, 1, 0),
							LayoutOrder = 1,
							Name = "make",
						}, {
							create("UICorner", { CornerRadius = UDim.new(0, 8), Name = "corner" }),
						}),
						create("TextButton", {
							Theme = { BackgroundColor3 = "inputbackground", TextColor3 = "foreground" },
							Font = Enum.Font.GothamMedium,
							Text = "Set",
							TextSize = 12,
							AutoButtonColor = false,
							Size = UDim2.new(1 / 3, -6, 1, 0),
							LayoutOrder = 2,
							Name = "set",
						}, {
							create("UICorner", { CornerRadius = UDim.new(0, 8), Name = "corner" }),
						}),
						create("TextButton", {
							BackgroundColor3 = Color3.fromRGB(48, 28, 32),
							Font = Enum.Font.GothamMedium,
							Text = "Delete",
							TextColor3 = Color3.fromRGB(255, 140, 140),
							TextSize = 12,
							AutoButtonColor = false,
							Size = UDim2.new(1 / 3, -6, 1, 0),
							LayoutOrder = 3,
							Name = "delete",
						}, {
							create("UICorner", { CornerRadius = UDim.new(0, 8), Name = "corner" }),
						}),
					}),
					create("TextLabel", {
						Theme = { TextColor3 = "muted" },
						Font = Enum.Font.Gotham,
						Text = "Make creates · Set overwrites · Pick loads",
						TextSize = 11,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextWrapped = true,
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 28),
						LayoutOrder = 8,
						Name = "configstatus",
					}),
				}),
			}),
		}),
		-- RIGHT: soft Games + Changelog cards
		create("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0.5, 8, 0, 0),
			Size = UDim2.new(0.5, -8, 1, 0),
			Name = "right",
		}, {
			create("Frame", {
				Theme = { BackgroundColor3 = "sectionbackground" },
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, 156),
				Name = "gamesblock",
			}, {
				create("UICorner", { CornerRadius = UDim.new(0, 14), Name = "corner" }),
				create("UIStroke", { Color = COL_ROWEDGE, Thickness = 1, Transparency = 0.75, Name = "edge" }),
				create("UIPadding", {
					PaddingTop = UDim.new(0, 14),
					PaddingBottom = UDim.new(0, 14),
					PaddingLeft = UDim.new(0, 14),
					PaddingRight = UDim.new(0, 14),
					Name = "padding",
				}),
				create("TextLabel", {
					Font = Enum.Font.GothamBold,
					Text = "GAMES",
					TextColor3 = COL_HEADER,
					TextSize = 10,
					TextXAlignment = Enum.TextXAlignment.Left,
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 16),
					Name = "gamesheader",
				}),
				create("ScrollingFrame", {
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Position = UDim2.new(0, 0, 0, 24),
					Size = UDim2.new(1, 0, 1, -24),
					CanvasSize = UDim2.new(),
					ScrollBarThickness = 3,
					ScrollBarImageColor3 = Color3.fromRGB(70, 74, 90),
					Name = "games",
				}, {
					create("UIListLayout", {
						Padding = UDim.new(0, 8),
						SortOrder = Enum.SortOrder.LayoutOrder,
						Name = "layout",
					}),
				}),
			}),
			create("Frame", {
				Theme = { BackgroundColor3 = "sectionbackground" },
				BorderSizePixel = 0,
				Position = UDim2.new(0, 0, 0, 170),
				Size = UDim2.new(1, 0, 1, -170),
				Name = "logsblock",
			}, {
				create("UICorner", { CornerRadius = UDim.new(0, 14), Name = "corner" }),
				create("UIStroke", { Color = COL_ROWEDGE, Thickness = 1, Transparency = 0.75, Name = "edge" }),
				create("UIPadding", {
					PaddingTop = UDim.new(0, 14),
					PaddingBottom = UDim.new(0, 14),
					PaddingLeft = UDim.new(0, 14),
					PaddingRight = UDim.new(0, 14),
					Name = "padding",
				}),
				create("Frame", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 26),
					Name = "loghead",
				}, {
					create("TextLabel", {
						Font = Enum.Font.GothamBold,
						Text = "CHANGELOG",
						TextColor3 = COL_HEADER,
						TextSize = 10,
						TextXAlignment = Enum.TextXAlignment.Left,
						BackgroundTransparency = 1,
						Size = UDim2.new(1, -140, 1, 0),
						Name = "logsheader",
					}),
					create("Frame", {
						BackgroundTransparency = 1,
						AnchorPoint = Vector2.new(1, 0.5),
						Position = UDim2.new(1, 0, 0.5, 0),
						Size = UDim2.new(0, 130, 0, 24),
						Name = "logtabs",
					}, {
						create("UIListLayout", {
							FillDirection = Enum.FillDirection.Horizontal,
							HorizontalAlignment = Enum.HorizontalAlignment.Right,
							VerticalAlignment = Enum.VerticalAlignment.Center,
							Padding = UDim.new(0, 6),
							Name = "layout",
						}),
						create("TextButton", {
							Theme = { BackgroundColor3 = "highlight", TextColor3 = "foreground" },
							Font = Enum.Font.GothamMedium,
							Text = "UI",
							TextSize = 11,
							AutoButtonColor = false,
							Size = UDim2.new(0, 44, 0, 24),
							LayoutOrder = 1,
							Name = "ui",
						}, {
							create("UICorner", { CornerRadius = UDim.new(0, 8), Name = "corner" }),
						}),
						create("TextButton", {
							BackgroundColor3 = Color3.fromRGB(22, 22, 30),
							Font = Enum.Font.GothamMedium,
							Text = "Games",
							TextColor3 = theme.foreground,
							TextSize = 11,
							AutoButtonColor = false,
							Size = UDim2.new(0, 62, 0, 24),
							LayoutOrder = 2,
							Name = "games",
						}, {
							create("UICorner", { CornerRadius = UDim.new(0, 8), Name = "corner" }),
						}),
					}),
				}),
				create("ScrollingFrame", {
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Position = UDim2.new(0, 0, 0, 34),
					Size = UDim2.new(1, 0, 1, -34),
					CanvasSize = UDim2.new(),
					ScrollBarThickness = 3,
					ScrollBarImageColor3 = Color3.fromRGB(70, 74, 90),
					Name = "logs",
				}, {
					create("UIListLayout", {
						Padding = UDim.new(0, 10),
						SortOrder = Enum.SortOrder.LayoutOrder,
						Name = "layout",
					}),
				}),
			}),
		}),
	})
	autocanvasresize(dashboard.left.panel.list, dashboard.left.panel)

	newlibrary._dashboard = dashboard
	newlibrary._dashboardReturnTab = nil
	newlibrary._dashboardExpiryConn = nil
	newlibrary._avatarLoaded = false

	local function cleardashchildren(holder)
		for _, child in ipairs(holder:GetChildren()) do
			if not child:IsA("UIListLayout") and not child:IsA("UIPadding") and not child:IsA("UICorner") then
				child:Destroy()
			end
		end
	end

	local function emptyhint(parent, text)
		create("Frame", {
			Theme = { BackgroundColor3 = "inputbackground" },
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 44),
			Parent = parent,
			Name = "empty",
		}, {
			create("UICorner", { CornerRadius = UDim.new(0, 10), Name = "corner" }),
			create("UIPadding", {
				PaddingTop = UDim.new(0, 12),
				PaddingBottom = UDim.new(0, 12),
				PaddingLeft = UDim.new(0, 14),
				PaddingRight = UDim.new(0, 14),
				Name = "padding",
			}),
			create("TextLabel", {
				Theme = { TextColor3 = "muted" },
				Font = Enum.Font.Gotham,
				Text = text,
				TextSize = 12,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 1, 0),
				Name = "label",
			}),
		})
	end

	local function updatekeyexpiry(self)
		local label = self._dashboard.left.panel.license.expiresrow.expiresvalue
		local expires = self.keyexpires
		if expires == nil or expires == false then
			label.Text = "Lifetime"
			label.TextColor3 = theme.highlight
			return
		end
		local remaining = tonumber(expires) - os.time()
		if remaining <= 0 then
			label.Text = "Expired"
			label.TextColor3 = Color3.fromRGB(255, 110, 110)
		else
			label.Text = formatduration(remaining)
			label.TextColor3 = theme.highlight
		end
	end

	local function setchangelogtabvisual(which)
		local tabs = dashboard.right.logsblock.loghead.logtabs
		if which == "games" then
			tabs.ui.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
			tabs.ui.TextColor3 = theme.muted
			tabs.games.BackgroundColor3 = theme.highlight
			tabs.games.TextColor3 = theme.foreground
		else
			tabs.ui.BackgroundColor3 = theme.highlight
			tabs.ui.TextColor3 = theme.foreground
			tabs.games.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
			tabs.games.TextColor3 = theme.muted
		end
	end

	local function fillchangelogs(self)
		local panel = self._dashboard.right.logsblock.logs
		cleardashchildren(panel)
		local which = self.settings.changelogtab or "ui"
		local entries = (self.changelogs and self.changelogs[which]) or {}
		if #entries == 0 then
			emptyhint(panel, which == "games" and "No game change logs yet." or "No UI change logs yet.")
		else
			for i, entry in ipairs(entries) do
				local title = tostring(entry.title or entry.name or ("Update " .. i))
				local date = tostring(entry.date or entry.when or "")
				local body = tostring(entry.body or entry.description or entry.content or "")
				create("Frame", {
					Theme = { BackgroundColor3 = "inputbackground" },
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					LayoutOrder = i,
					Parent = panel,
					Name = "log" .. i,
				}, {
					create("UICorner", {
						CornerRadius = UDim.new(0, 10),
						Name = "corner",
					}),
					create("UIPadding", {
						PaddingTop = UDim.new(0, 14),
						PaddingBottom = UDim.new(0, 14),
						PaddingLeft = UDim.new(0, 14),
						PaddingRight = UDim.new(0, 14),
						Name = "padding",
					}),
					create("UIListLayout", {
						Padding = UDim.new(0, 4),
						SortOrder = Enum.SortOrder.LayoutOrder,
						Name = "layout",
					}),
					create("TextLabel", {
						Theme = { TextColor3 = "muted" },
						Font = Enum.Font.Gotham,
						Text = date,
						TextSize = 10,
						TextXAlignment = Enum.TextXAlignment.Left,
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 12),
						Visible = date ~= "",
						LayoutOrder = 1,
						Name = "date",
					}),
					create("TextLabel", {
						Theme = { TextColor3 = "foreground" },
						Font = Enum.Font.GothamMedium,
						Text = title,
						TextSize = 13,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextWrapped = true,
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						LayoutOrder = 2,
						Name = "title",
					}),
					create("TextLabel", {
						Theme = { TextColor3 = "muted" },
						Font = Enum.Font.Gotham,
						Text = body,
						TextSize = 11,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextWrapped = true,
						BackgroundTransparency = 1,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
						Visible = body ~= "",
						LayoutOrder = 3,
						Name = "body",
					}),
				})
			end
		end
		local layout = panel:FindFirstChild("layout")
		if layout then
			task.defer(function()
				panel.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 20)
			end)
		end
	end

	local keyBtn = dashboard.left.panel.license.keyvalue
	local discordBtn = dashboard.left.panel.account.discord
	local copyingKey = false

	keyBtn.MouseButton1Click:Connect(function()
		if copyingKey then
			return
		end
		local raw = tostring(newlibrary.key or "")
		if raw == "" or raw == "—" then
			return
		end
		copyingKey = true
		local ok = copytext(raw)
		keyBtn.Text = ok and "Copied!" or "Copy failed"
		keyBtn.TextColor3 = ok and theme.highlight or Color3.fromRGB(255, 110, 110)
		task.delay(1.1, function()
			if keyBtn.Parent then
				keyBtn.Text = maskkey(newlibrary.key)
				keyBtn.TextColor3 = theme.foreground
			end
			copyingKey = false
		end)
	end)

	discordBtn.MouseButton1Click:Connect(function()
		local url = tostring(newlibrary.discord or "")
		if url == "" then
			return
		end
		local result = openurl(url)
		local prev = discordBtn.Text
		discordBtn.Text = (result == "opened" and "Opened") or (result == "copied" and "Copied") or "Failed"
		task.delay(1.1, function()
			if discordBtn.Parent then
				discordBtn.Text = prev
			end
		end)
	end)

	local configs = dashboard.left.panel.configs
	local configNameBox = configs.configname
	local configList = configs.configlist
	local configStatus = configs.configstatus
	local configActions = configs.configactions
	local configPick = configs.configpick
	local configActive = configs.configactive
	local configNameLabel = configs.confignamelabel
	local CONFIG_LIST_OPEN_H = 120

	local function setconfigstatus(text, kind)
		newlibrary._configStatusText = tostring(text or "")
		configStatus.Text = newlibrary._configStatusText
		if kind == "ok" then
			configStatus.TextColor3 = theme.highlight
		elseif kind == "err" then
			configStatus.TextColor3 = Color3.fromRGB(255, 110, 110)
		else
			configStatus.TextColor3 = theme.muted
		end
	end

	local function updateconfigactive()
		local active = sanitizeconfigname(newlibrary.settings.activeconfig)
		if active then
			configActive.Text = "Active · " .. active
			configActive.TextColor3 = theme.highlight
			configPick.Text = active
		else
			configActive.Text = "Active · none"
			configActive.TextColor3 = theme.muted
			configPick.Text = "Pick a config"
		end
	end

	local function layoutconfigpicker(open)
		newlibrary.settings.configpickeropen = open == true
		configList.Visible = open == true
		configList.Size = UDim2.new(1, 0, 0, open and CONFIG_LIST_OPEN_H or 0)
		tween(configPick.caret, 0.15, { Rotation = open and 270 or 90 })
	end

	local function refreshconfiglist()
		cleardashchildren(configList)
		local names = newlibrary:listconfigs()
		local active = sanitizeconfigname(newlibrary.settings.activeconfig) or ""
		if #names == 0 then
			emptyhint(configList, "No configs yet — Make one below.")
		else
			for i, name in ipairs(names) do
				local selected = name == active
				local row = create("TextButton", {
					Theme = { TextColor3 = "foreground" },
					Font = Enum.Font.GothamMedium,
					Text = "  " .. name .. (selected and "  ✓" or ""),
					TextSize = 12,
					TextXAlignment = Enum.TextXAlignment.Left,
					AutoButtonColor = false,
					BackgroundColor3 = selected and theme.highlight or Color3.fromRGB(18, 18, 24),
					Size = UDim2.new(1, 0, 0, 30),
					LayoutOrder = i,
					Parent = configList,
					Name = name,
				}, {
					create("UICorner", {
						CornerRadius = UDim.new(0, 8),
						Name = "corner",
					}),
				})
				row.MouseButton1Click:Connect(function()
					local ok, err = newlibrary:loadconfig(name)
					if ok then
						newlibrary.settings.activeconfig = name
						configNameBox.Text = name
						newlibrary.settings.configname = name
						updateconfigactive()
						layoutconfigpicker(false)
						setconfigstatus("Picked · " .. name, "ok")
						refreshconfiglist()
					else
						setconfigstatus(err or "Pick failed", "err")
					end
				end)
			end
		end
		local layout = configList:FindFirstChild("layout")
		if layout then
			task.defer(function()
				configList.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 12)
			end)
		end
		updateconfigactive()
	end

	newlibrary._refreshconfiglist = refreshconfiglist
	newlibrary._setconfigstatus = setconfigstatus
	newlibrary._updateconfigactive = updateconfigactive

	configNameBox:GetPropertyChangedSignal("Text"):Connect(function()
		newlibrary.settings.configname = configNameBox.Text
	end)

	configPick.MouseButton1Click:Connect(function()
		layoutconfigpicker(not newlibrary.settings.configpickeropen)
		if newlibrary.settings.configpickeropen then
			refreshconfiglist()
		end
	end)

	-- Make: create a new named config from current flags (refuse overwrite)
	configActions.make.MouseButton1Click:Connect(function()
		local name = sanitizeconfigname(configNameBox.Text)
		if not name then
			setconfigstatus("Enter a name to Make a config", "err")
			return
		end
		local existing = readtextfile(newlibrary:getconfigpath(name))
		if existing then
			setconfigstatus("Already exists — Pick it, or Set to overwrite", "err")
			return
		end
		local ok, err = newlibrary:saveconfig(name)
		if ok then
			newlibrary.settings.activeconfig = name
			updateconfigactive()
			layoutconfigpicker(false)
			setconfigstatus("Made · " .. name, "ok")
			refreshconfiglist()
		else
			setconfigstatus(err or "Make failed", "err")
		end
	end)

	-- Set: overwrite the active (picked) config with current flags
	configActions.set.MouseButton1Click:Connect(function()
		local active = sanitizeconfigname(newlibrary.settings.activeconfig)
		local typed = sanitizeconfigname(configNameBox.Text)
		local name = active or typed
		if not name then
			setconfigstatus("Pick a config first, or type a name", "err")
			return
		end
		local ok, err = newlibrary:saveconfig(name)
		if ok then
			newlibrary.settings.activeconfig = name
			configNameBox.Text = name
			updateconfigactive()
			setconfigstatus("Set · " .. name, "ok")
			refreshconfiglist()
		else
			setconfigstatus(err or "Set failed", "err")
		end
	end)

	configActions.delete.MouseButton1Click:Connect(function()
		local name = sanitizeconfigname(newlibrary.settings.activeconfig)
			or sanitizeconfigname(configNameBox.Text)
		if not name then
			setconfigstatus("Pick a config to delete", "err")
			return
		end
		local ok, err = newlibrary:deleteconfig(name)
		if ok then
			if newlibrary.settings.activeconfig == name then
				newlibrary.settings.activeconfig = nil
			end
			if sanitizeconfigname(configNameBox.Text) == name then
				configNameBox.Text = ""
				newlibrary.settings.configname = ""
			end
			updateconfigactive()
			layoutconfigpicker(false)
			setconfigstatus("Deleted · " .. name, "ok")
			refreshconfiglist()
		else
			setconfigstatus(err or "Delete failed", "err")
		end
	end)

	layoutconfigpicker(false)
	updateconfigactive()
	if not newlibrary._configStatusText or newlibrary._configStatusText == "" then
		setconfigstatus("Make creates · Set overwrites · Pick loads", nil)
	end

	dashboard.right.logsblock.loghead.logtabs.ui.MouseButton1Click:Connect(function()
		newlibrary.settings.changelogtab = "ui"
		setchangelogtabvisual("ui")
		fillchangelogs(newlibrary)
	end)
	dashboard.right.logsblock.loghead.logtabs.games.MouseButton1Click:Connect(function()
		newlibrary.settings.changelogtab = "games"
		setchangelogtabvisual("games")
		fillchangelogs(newlibrary)
	end)

	function newlibrary:refreshdashboard()
		local dash = self._dashboard
		if not dash then
			return
		end
		local panel = dash.left.panel
		panel.brand.Text = self.title
		panel.subtitle.Text = tostring(self.version) .. "  ·  Dashboard"
		panel.account.displayname.Text = player.DisplayName
		panel.account.username.Text = "@" .. player.Name
		local hasDiscord = self.discord ~= ""
		panel.account.discord.Visible = hasDiscord
		local nameWidth = hasDiscord and -170 or -78
		panel.account.displayname.Size = UDim2.new(1, nameWidth, 0, 18)
		panel.account.username.Size = UDim2.new(1, nameWidth, 0, 14)
		if not self._avatarLoaded then
			self._avatarLoaded = true
			task.spawn(function()
				local ok, thumb = pcall(function()
					return Players:GetUserThumbnailAsync(
						player.UserId,
						Enum.ThumbnailType.HeadShot,
						Enum.ThumbnailSize.Size100x100
					)
				end)
				if ok and thumb and dash.Parent then
					panel.account.avatar.Image = thumb
				end
			end)
		end
		if not copyingKey then
			panel.license.keyvalue.Text = maskkey(self.key)
			panel.license.keyvalue.TextColor3 = theme.foreground
		end
		updatekeyexpiry(self)

		local configsPanel = panel.configs
		if configsPanel.configname and self.settings.configname and self.settings.configname ~= "" then
			configsPanel.configname.Text = self.settings.configname
		end
		layoutconfigpicker(self.settings.configpickeropen == true)
		if self._updateconfigactive then
			self._updateconfigactive()
		end
		if self._refreshconfiglist then
			self._refreshconfiglist()
		end
		if configsPanel.configstatus then
			configsPanel.configstatus.Text = self._configStatusText or ""
		end

		local games = dash.right.gamesblock.games
		cleardashchildren(games)
		local list = self.supportedgames or {}
		local placeId = game.PlaceId
		if #list == 0 then
			emptyhint(games, "No supported games configured.")
		else
			for i, entry in ipairs(list) do
				local name = tostring(entry.name or entry.title or entry[1] or ("Game " .. i))
				local id = entry.placeId or entry.PlaceId or entry.id or entry[2]
				local here = id and tonumber(id) == placeId
				local row = create("Frame", {
					Theme = { BackgroundColor3 = "inputbackground" },
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 0, 40),
					LayoutOrder = i,
					Parent = games,
					Name = name,
				}, {
					create("UICorner", {
						CornerRadius = UDim.new(0, 10),
						Name = "corner",
					}),
					create("UIPadding", {
						PaddingLeft = UDim.new(0, 14),
						PaddingRight = UDim.new(0, 14),
						Name = "padding",
					}),
					create("TextLabel", {
						Theme = { TextColor3 = "foreground" },
						Font = Enum.Font.GothamMedium,
						Text = name,
						TextSize = 13,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextTruncate = Enum.TextTruncate.AtEnd,
						BackgroundTransparency = 1,
						AnchorPoint = Vector2.new(0, 0.5),
						Position = UDim2.new(0, 0, 0.5, here and -7 or 0),
						Size = UDim2.new(1, here and -56 or 0, 0, 16),
						Name = "name",
					}),
					create("TextLabel", {
						Theme = { TextColor3 = "muted" },
						Font = Enum.Font.Gotham,
						Text = id and ("Place " .. tostring(id)) or "Universal",
						TextSize = 11,
						TextXAlignment = Enum.TextXAlignment.Left,
						BackgroundTransparency = 1,
						AnchorPoint = Vector2.new(0, 0.5),
						Position = UDim2.new(0, 0, 0.5, 9),
						Size = UDim2.new(1, here and -56 or 0, 0, 14),
						Visible = true,
						Name = "place",
					}),
				})
				if here then
					row.name.Position = UDim2.new(0, 0, 0.5, 0)
					row.place.Visible = false
					create("TextLabel", {
						Theme = { BackgroundColor3 = "highlight", TextColor3 = "foreground" },
						Font = Enum.Font.GothamMedium,
						Text = "Here",
						TextSize = 10,
						TextXAlignment = Enum.TextXAlignment.Center,
						AnchorPoint = Vector2.new(1, 0.5),
						Position = UDim2.new(1, 0, 0.5, 0),
						Size = UDim2.new(0, 46, 0, 20),
						Parent = row,
						Name = "badge",
					}, {
						create("UICorner", {
							CornerRadius = UDim.new(0, 6),
							Name = "corner",
						}),
					})
				end
			end
		end
		local gamesLayout = games:FindFirstChild("layout")
		if gamesLayout then
			task.defer(function()
				games.CanvasSize = UDim2.new(0, 0, 0, gamesLayout.AbsoluteContentSize.Y + 20)
			end)
		end

		setchangelogtabvisual(self.settings.changelogtab or "ui")
		fillchangelogs(self)
	end

	function newlibrary:setkeyinfo(info)
		info = info or {}
		if info.key ~= nil then
			self.key = tostring(info.key)
		end
		if info.expires ~= nil or info.keyexpires ~= nil then
			self.keyexpires = info.expires ~= nil and info.expires or info.keyexpires
		end
		if self.settings.dashboardopen then
			self:refreshdashboard()
		end
	end

	function newlibrary:setdiscord(url)
		self.discord = tostring(url or "")
		if self.settings.dashboardopen then
			self:refreshdashboard()
		end
	end

	function newlibrary:setsupportedgames(list)
		self.supportedgames = typeof(list) == "table" and list or {}
		if self.settings.dashboardopen then
			self:refreshdashboard()
		end
	end

	function newlibrary:setchangelogs(logs)
		logs = typeof(logs) == "table" and logs or {}
		self.changelogs = {
			ui = logs.ui or logs.UI or {},
			games = logs.games or logs.game or logs.Games or {},
		}
		if self.settings.dashboardopen then
			self:refreshdashboard()
		end
	end

	function newlibrary:opendashboard()
		if self.settings.dashboardopen then
			return
		end
		local profile = self._currentProfile
		if profile and profile.selected then
			self._dashboardReturnTab = profile.selected
			profile.selected.frame.Visible = false
			profile.selected.button.TextColor3 = theme.muted
			profile.selected.settings.open = false
			profile.selected = nil
		else
			self._dashboardReturnTab = nil
		end
		self.settings.selected = nil
		for _, entry in ipairs(self._profiles) do
			entry.page.Visible = false
		end
		self:refreshdashboard()
		self._dashboard.Visible = true
		self.settings.dashboardopen = true
		tween(top.brand, 0.12, { TextColor3 = theme.highlight })

		if self._dashboardExpiryConn then
			self._dashboardExpiryConn:Disconnect()
			self._dashboardExpiryConn = nil
		end
		if self.keyexpires then
			local elapsed = 0
			self._dashboardExpiryConn = RunService.Heartbeat:Connect(function(dt)
				if not self.settings.dashboardopen then
					return
				end
				elapsed += dt
				if elapsed >= 1 then
					elapsed = 0
					updatekeyexpiry(self)
				end
			end)
		end
	end

	function newlibrary:closedashboard()
		if not self.settings.dashboardopen then
			return
		end
		self._dashboard.Visible = false
		self.settings.dashboardopen = false
		top.brand.TextColor3 = theme.foreground
		if self._dashboardExpiryConn then
			self._dashboardExpiryConn:Disconnect()
			self._dashboardExpiryConn = nil
		end
		local profile = self._currentProfile
		if profile then
			profile.page.Visible = true
		end
	end

	function newlibrary:isdashboardopen()
		return self.settings.dashboardopen == true
	end

	local function layoutbrand()
		local brandLeft = top.brand.Position.X.Offset
		local brandWidth = top.brand.AbsoluteSize.X
		if brandWidth < 1 then
			brandWidth = TextService:GetTextSize(
				top.brand.Text,
				top.brand.TextSize,
				top.brand.Font,
				hugevec2
			).X
		end
		local gap = 8
		local dividerX = brandLeft + brandWidth + gap
		top.namedivider.Position = UDim2.new(0, dividerX, 0.5, 0)
		top.nav.Position = UDim2.new(0, dividerX + 1 + 12, 0.5, 0)
		return top.nav.Position.X.Offset
	end

	local function layoutnav()
		local left = layoutbrand()
		local rightChrome = 92
		local gap = 12
		local profileWidth = top.profile.AbsoluteSize.X
		if profileWidth < 1 then
			profileWidth = top.profile.Size.X.Offset
		end
		local windowWidth = main.AbsoluteSize.X
		if windowWidth < 1 then
			windowWidth = main.Size.X.Offset
		end
		local available = math.max(120, windowWidth - left - rightChrome - profileWidth - gap)
		top.nav.Size = UDim2.new(0, available, 0, 30)

		local profile = newlibrary._currentProfile
		if not profile or not profile.nav then
			return
		end

		local list = profile.nav:FindFirstChild("list")
		if list then
			list.Padding = UDim.new(0, 16)
		end

		-- Always keep full tab labels at normal size; scroll horizontally if needed.
		for _, t in ipairs(profile.tabs) do
			t.button.TextSize = 13
			t.button.AutomaticSize = Enum.AutomaticSize.X
			t.button.Size = UDim2.new(0, 0, 1, 0)
			t.button.TextTruncate = Enum.TextTruncate.None
		end

		if list then
			local width = list.AbsoluteContentSize.X
			profile.nav.CanvasSize = UDim2.new(0, width, 0, 0)
		end
	end

	local function layoutprofiles()
		local count = math.max(#newlibrary._profiles, 1)
		local width = math.clamp(44 + count * 58, 120, 260)
		top.profile.Size = UDim2.new(0, width, 0, 30)
		local tabWidth = (width - 4) / count
		for i, entry in ipairs(newlibrary._profiles) do
			entry.button.Size = UDim2.new(0, tabWidth, 1, 0)
			entry.button.LayoutOrder = i
			entry.button.TextSize = 11
			entry.button.TextTruncate = Enum.TextTruncate.AtEnd
		end
		local index = math.clamp(newlibrary.settings.profileIndex or 1, 1, count)
		local pill = top.profile.active
		tween(pill, 0.18, {
			Size = UDim2.new(0, math.max(tabWidth - 2, 8), 0, 24),
			Position = UDim2.new(0, 2 + (index - 1) * tabWidth, 0.5, 0),
		})
		layoutnav()
	end

	newlibrary._layoutnav = layoutnav

	top.brand:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		task.defer(layoutnav)
	end)
	task.defer(layoutnav)

	local function bindCurrentProfile(profile)
		newlibrary.flags = profile.flags
		newlibrary.items = profile.items
		newlibrary.tabs = profile.tabs
		newlibrary.settings.selected = profile.selected
		newlibrary._currentProfile = profile
	end

	function newlibrary:_setprofile(nameOrIndex, silent)
		local index = nameOrIndex
		if typeof(nameOrIndex) == "string" then
			index = nil
			for i, entry in ipairs(self._profiles) do
				if entry.name == nameOrIndex then
					index = i
					break
				end
			end
		end
		if not index or not self._profiles[index] then
			return
		end

		local profile = self._profiles[index]
		local changed = self.settings.profileIndex ~= index

		-- Hide every profile workspace.
		for _, entry in ipairs(self._profiles) do
			entry.page.Visible = false
			entry.nav.Visible = false
			local selected = entry == profile
			entry.button.TextColor3 = selected and theme.foreground or theme.muted
			entry.button.Font = selected and Enum.Font.GothamBold or Enum.Font.GothamMedium
		end

		profile.nav.Visible = true
		self.settings.profileIndex = index
		self.settings.profile = profile.name
		bindCurrentProfile(profile)
		layoutprofiles()

		if self.settings.dashboardopen then
			for _, entry in ipairs(self._profiles) do
				entry.page.Visible = false
			end
			self._dashboard.Visible = true
			self:refreshdashboard()
		elseif profile.selected then
			profile.page.Visible = true
			profile.selected:open()
		elseif #profile.tabs > 0 then
			profile.page.Visible = true
			profile.tabs[1]:open()
		else
			profile.page.Visible = true
			self.settings.selected = nil
		end

		if changed and not silent then
			task.spawn(self.onprofilechanged, self.settings.profile, index)
		end
	end

	function newlibrary:addprofile(name)
		local profileName = tostring(name or ("Profile " .. (#self._profiles + 1)))
		for _, entry in ipairs(self._profiles) do
			if entry.name == profileName then
				return entry
			end
		end

		local button = Instance.new("TextButton")
		button.Name = profileName
		button.Font = Enum.Font.GothamMedium
		button.Text = profileName
		button.TextSize = 11
		button.TextColor3 = theme.muted
		button.AutoButtonColor = false
		button.BackgroundTransparency = 1
		button.Size = UDim2.new(0, 80, 1, 0)
		button.ZIndex = 5
		button.Parent = top.profile.tabs

		local nav = create("ScrollingFrame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 1, 0),
			CanvasSize = UDim2.new(),
			ScrollBarThickness = 0,
			ScrollingDirection = Enum.ScrollingDirection.X,
			ElasticBehavior = Enum.ElasticBehavior.Never,
			Visible = false,
			Parent = top.nav,
			Name = profileName .. "_nav",
		}, {
			create("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 16),
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Name = "list",
			}),
		})

		nav.list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
			nav.CanvasSize = UDim2.new(0, nav.list.AbsoluteContentSize.X, 0, 0)
		end)

		local page = create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, 0),
			Visible = false,
			ClipsDescendants = true,
			Parent = main.content,
			Name = profileName .. "_page",
		})

		local profile = {
			name = profileName,
			button = button,
			nav = nav,
			page = page,
			tabs = {},
			flags = {},
			items = {},
			selected = nil,
		}
		table.insert(self._profiles, profile)

		button.Activated:Connect(function()
			self:_setprofile(profileName)
		end)

		layoutprofiles()
		if #self._profiles == 1 then
			self:_setprofile(1, true)
		end
		return profile
	end

	function newlibrary:removeprofile(name)
		for i, entry in ipairs(self._profiles) do
			if entry.name == name then
				entry.button:Destroy()
				entry.nav:Destroy()
				entry.page:Destroy()
				table.remove(self._profiles, i)
				if self.settings.profileIndex >= i then
					self.settings.profileIndex = math.max(1, self.settings.profileIndex - 1)
				end
				layoutprofiles()
				if self._profiles[self.settings.profileIndex] then
					self:_setprofile(self.settings.profileIndex, true)
				end
				return true
			end
		end
		return false
	end

	function newlibrary:setprofile(nameOrIndex)
		self:_setprofile(nameOrIndex)
	end

	function newlibrary:getprofile()
		return self.settings.profile, self.settings.profileIndex
	end

	function newlibrary:getprofiledata(name)
		name = name or self.settings.profile
		for _, entry in ipairs(self._profiles) do
			if entry.name == name then
				return entry
			end
		end
		return nil
	end

	for i = 1, #newlibrary.profiles do
		newlibrary:addprofile(newlibrary.profiles[i])
	end
	if #newlibrary._profiles > 0 then
		newlibrary:_setprofile(1, true)
	end

	top.close.MouseButton1Click:Connect(function()
		newlibrary:setopen(false)
	end)

	top.minimize.MouseButton1Click:Connect(function()
		newlibrary:setopen(false)
	end)

	UserInputService.TextBoxFocused:Connect(function()
		newlibrary.settings.istextboxfocused = true
	end)
	UserInputService.TextBoxFocusReleased:Connect(function()
		newlibrary.settings.istextboxfocused = false
	end)

	UserInputService.InputBegan:Connect(function(input)
		if newlibrary.settings.binding or newlibrary.settings.istextboxfocused then
			return
		end
		local name = input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode.Name or input.UserInputType.Name
		if name == newlibrary.settings.togglebind then
			newlibrary:toggle()
			return
		end
		for _, item in next, newlibrary.items do
			if item.itemtype == "bind" and newlibrary.flags[item.flag] == name then
				item.onkeydown()
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if newlibrary.settings.binding or newlibrary.settings.istextboxfocused then
			return
		end
		local name = input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode.Name or input.UserInputType.Name
		for _, item in next, newlibrary.items do
			if item.itemtype == "bind" and newlibrary.flags[item.flag] == name then
				item.onkeyup()
			end
		end
	end)

	top.Active = true
	newlibrary:makedraggable(top)

	local titleClickOrigin = nil
	top.brand.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			titleClickOrigin = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
	top.brand.InputEnded:Connect(function(input)
		if not titleClickOrigin then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local delta = Vector2.new(input.Position.X, input.Position.Y) - titleClickOrigin
		titleClickOrigin = nil
		if delta.Magnitude > 6 or newlibrary.settings.dragging then
			return
		end
		if newlibrary.settings.dashboardopen then
			newlibrary:closedashboard()
			local ret = newlibrary._dashboardReturnTab
			if ret and ret.profile == newlibrary._currentProfile then
				ret:open()
			elseif newlibrary._currentProfile and #newlibrary._currentProfile.tabs > 0 then
				newlibrary._currentProfile.tabs[1]:open()
			end
		else
			newlibrary:opendashboard()
		end
	end)

	local parent = player:FindFirstChild("PlayerGui") or player:WaitForChild("PlayerGui")
	if RunService:IsStudio() and not RunService:IsRunning() then
		parent = game:GetService("StarterGui")
	end
	newlibrary.gui.Parent = parent

	task.defer(layoutprofiles)

	return newlibrary
end

function library:getconfigpath(name)
	local safe = sanitizeconfigname(name)
	if not safe then
		return nil
	end
	local folder = tostring(self.configfolder or "Avalon/configs")
	return folder .. "/" .. safe .. ".json"
end

function library:listconfigs()
	local folder = tostring(self.configfolder or "Avalon/configs")
	return listtextfiles(folder)
end

function library:collectflags(profile)
	profile = profile or self._currentProfile
	if not profile then
		return {}
	end
	local out = {}
	for flag, value in next, profile.flags do
		local item = profile.items[flag]
		if item and item.ignore then
			-- skip ignored UI-only controls
		elseif item and (item.itemtype == "label" or item.itemtype == "button") then
			-- skip non-value controls
		else
			out[flag] = serializeflagvalue(value)
		end
	end
	return out
end

function library:applyflags(flags, profile)
	profile = profile or self._currentProfile
	if not profile or typeof(flags) ~= "table" then
		return
	end

	local prevFlags = self.flags
	local prevItems = self.items
	self.flags = profile.flags
	self.items = profile.items
	self.settings.silent = true

	for flag, value in next, flags do
		local item = profile.items[flag]
		local decoded = deserializeflagvalue(value)
		if item and item.ignore then
			-- skip
		elseif item and item.itemtype == "toggle" then
			item:set(decoded == true)
		elseif item and item.itemtype == "slider" then
			item:set(tonumber(decoded) or item.min, true)
		elseif item and item.itemtype == "picker" then
			if typeof(decoded) == "table" then
				item:set(tonumber(decoded.h) or 0, tonumber(decoded.s) or 1, tonumber(decoded.v) or 1)
			end
		elseif item and item.itemtype == "checklist" then
			if typeof(decoded) == "table" then
				for key in next, item._items or {} do
					item:toggle(key, decoded[tostring(key)] == true or decoded[key] == true)
				end
			end
		elseif item and typeof(item.set) == "function" then
			item:set(decoded)
		else
			profile.flags[flag] = decoded
		end
	end

	self.settings.silent = false
	self.flags = prevFlags
	self.items = prevItems
end

function library:saveconfig(name)
	local safe = sanitizeconfigname(name) or "default"
	local path = self:getconfigpath(safe)
	if not path then
		return false, "Invalid config name"
	end

	local profiles = {}
	for _, profile in ipairs(self._profiles or {}) do
		profiles[profile.name] = self:collectflags(profile)
	end

	local payload = {
		version = 1,
		name = safe,
		savedAt = os.time(),
		activeProfile = self.settings.profile,
		profiles = profiles,
	}

	local ok, encoded = pcall(HttpService.JSONEncode, HttpService, payload)
	if not ok or typeof(encoded) ~= "string" then
		return false, "Failed to encode config"
	end
	if not writetextfile(path, encoded) then
		return false, "Failed to write config"
	end
	self.settings.configname = safe
	self.settings.activeconfig = safe
	return true
end

function library:loadconfig(name)
	local safe = sanitizeconfigname(name)
	if not safe then
		return false, "Invalid config name"
	end
	local path = self:getconfigpath(safe)
	local raw = readtextfile(path)
	if not raw then
		return false, "Config not found"
	end

	local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok or typeof(data) ~= "table" then
		return false, "Invalid config file"
	end

	local profilesData = data.profiles
	if typeof(profilesData) ~= "table" then
		profilesData = { [self.settings.profile or "Primary"] = data.flags or data }
	end

	for _, profile in ipairs(self._profiles or {}) do
		local flags = profilesData[profile.name]
		if typeof(flags) == "table" then
			self:applyflags(flags, profile)
		end
	end

	if data.activeProfile then
		self:_setprofile(data.activeProfile, true)
	end

	self.settings.configname = safe
	self.settings.activeconfig = safe
	return true
end

function library:deleteconfig(name)
	local safe = sanitizeconfigname(name)
	if not safe then
		return false, "Invalid config name"
	end
	local path = self:getconfigpath(safe)
	local existing = readtextfile(path)
	if not existing then
		return false, "Config not found"
	end
	deletetextfile(path)
	return true
end

-- Call after all tabs/controls are built so defaults don't overwrite the file.
function library:tryautoload()
	local name = sanitizeconfigname(self.autoloadconfig)
	if not name then
		return false, "No autoloadconfig set"
	end
	self.settings.configname = name
	local configsPanel = self._dashboard and self._dashboard.left.panel:FindFirstChild("configs")
	if configsPanel and configsPanel:FindFirstChild("configname") then
		configsPanel.configname.Text = name
	end
	local ok, err = self:loadconfig(name)
	if ok then
		self.settings.activeconfig = name
	end
	if self._setconfigstatus then
		if ok then
			self._setconfigstatus("Autoloaded · " .. name, "ok")
		else
			self._setconfigstatus(err or "Autoload failed", "err")
		end
	end
	if self._refreshconfiglist then
		self._refreshconfiglist()
	end
	return ok, err
end

function library:setopen(open)
	open = open and true or false
	if self.gui.Enabled == open then
		if open and self._applycursoroverride then
			self._applycursoroverride(true)
		end
		return
	end
	self.gui.Enabled = open
	if self._applycursoroverride then
		self._applycursoroverride(open)
	end
end

function library:isopen()
	return self.gui.Enabled
end

function library:toggle()
	self:setopen(not self.gui.Enabled)
end

function library:makedraggable(handle)
	local DRAG_THRESHOLD = 5
	local dragMaid = maid.new()

	local function isOverHandle(x, y)
		local playerGui = Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
		if not playerGui then
			return false
		end
		local objs = playerGui:GetGuiObjectsAtPosition(x, y)
		for i = 1, #objs do
			local obj = objs[i]
			if obj == handle or obj:IsDescendantOf(handle) then
				if obj:IsA("TextBox") then
					return false
				end
				return true
			end
		end
		return false
	end

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if self.settings.dragging or self.settings.binding then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if UserInputService:GetFocusedTextBox() then
			return
		end
		if not handle.Parent then
			return
		end

		local start = Vector2.new(input.Position.X, input.Position.Y)
		if not isOverHandle(start.X, start.Y) then
			return
		end

		local main = self.gui.main
		local mouse = Players.LocalPlayer:GetMouse()
		local anchorOffset = Vector2.new(
			main.AbsoluteSize.X * main.AnchorPoint.X,
			main.AbsoluteSize.Y * main.AnchorPoint.Y
		)
		local grab = Vector2.new(
			start.X - (main.AbsolutePosition.X + anchorOffset.X),
			start.Y - (main.AbsolutePosition.Y + anchorOffset.Y)
		)
		local engaged = false

		dragMaid:dispose()
		dragMaid:givetask(UserInputService.InputChanged:Connect(function(changed)
			if changed.UserInputType ~= Enum.UserInputType.MouseMovement
				and changed.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			local cur = Vector2.new(changed.Position.X, changed.Position.Y)
			if not engaged then
				if (cur - start).Magnitude < DRAG_THRESHOLD then
					return
				end
				engaged = true
				self.settings.dragging = true
			end
			main.Position = UDim2.fromOffset(cur.X - grab.X, cur.Y - grab.Y)
		end))

		dragMaid:givetask(mouse.Move:Connect(function()
			local cur = Vector2.new(mouse.X, mouse.Y)
			if not engaged then
				if (cur - start).Magnitude < DRAG_THRESHOLD then
					return
				end
				engaged = true
				self.settings.dragging = true
			end
			main.Position = UDim2.fromOffset(mouse.X - grab.X, mouse.Y - grab.Y)
		end))

		dragMaid:givetask(UserInputService.InputEnded:Connect(function(ended)
			if ended.UserInputType == Enum.UserInputType.MouseButton1
				or ended.UserInputType == Enum.UserInputType.Touch then
				dragMaid:dispose()
				self.settings.dragging = false
			end
		end))
	end)
end

function library:settogglebind(bindname)
	self.settings.togglebind = tostring(bindname)
	self.togglebind = self.settings.togglebind
end

function library:addtab(options)
	local profile = self._currentProfile or self._profiles[self.settings.profileIndex]
	if not profile then
		error("Add a profile before adding tabs", 2)
	end

	local newtab = tab.new(options)
	newtab.library = self
	newtab.profile = profile
	newtab.button.Parent = profile.nav
	newtab.frame.Parent = profile.page
	table.insert(profile.tabs, newtab)
	table.insert(self.tabs, newtab)

	if self._layoutnav then
		self._layoutnav()
	end

	if options and options.settings and options.settings.open then
		newtab:open()
	elseif #profile.tabs == 1 and not self.settings.dashboardopen then
		newtab:open()
	end

	if self.refreshdashboard and self.settings.dashboardopen then
		self:refreshdashboard()
	end

	return newtab
end

return library
