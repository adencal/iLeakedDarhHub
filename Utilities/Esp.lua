--[[ Esp
	Player / item ESP using Drawing + Highlights.

	Optimized:
	- One RenderStepped for everyone (not one per player/item)
	- Cheap screen boxes (no GetExtentsSize every frame)
	- Local root / camera cached once per frame
	- Items via DescendantAdded (no GetDescendants spam)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local Visuals = {
	Settings = {
		TeamCheck = false,
		AliveCheck = false,
		DefaultColor = Color3.new(1, 1, 1),
		TeamColors = {
			Ally = Color3.new(0, 0, 1),
			Enemy = Color3.new(1, 0, 0),
		},
		MaxDistance = 2000,
	},
	Tracers = {
		Enabled = false,
		Origin = "Bottom",
		Thickness = 1,
	},
	Boxes = {
		Enabled = false,
		Filled = false,
	},
	Names = {
		Enabled = false,
		Size = 13,
	},
	Distance = {
		Enabled = false,
		Size = 13,
		ShowStuds = true,
	},
	HealthBar = {
		Enabled = false,
		Origin = "Right",
	},
	Chams = {
		Enabled = false,
		FillTransparency = 0.5,
		OutlineTransparency = 0,
	},
	Items = {
		Enabled = false,
		ShowDistance = false,
		MaxDistance = 100,
		Chams = {
			Enabled = false,
			Color = Color3.new(1, 1, 0),
			OutlineColor = Color3.new(1, 1, 1),
			FillTransparency = 0.5,
			OutlineTransparency = 0,
		},
		ValidItemNames = {},
		ValidItemTypes = {},
	},
	Container = {},
	ItemContainer = {},
	ChamsContainer = {},
}

-- Per-frame cache
local localRoot = nil
local localPos = nil
local tracerOrigin = Vector2.zero
local anyPlayerEsp = false
local anyItemEsp = false
local lastItemScan = 0
local scanExistingItems

local function createDrawing(drawingType, properties)
	local object = Drawing.new(drawingType)
	for property, value in pairs(properties) do
		object[property] = value
	end
	return object
end

local function createHighlight(parent, settings)
	local highlight = Instance.new("Highlight")
	highlight.FillColor = settings.Color
	highlight.OutlineColor = settings.OutlineColor or settings.Color
	highlight.FillTransparency = settings.FillTransparency
	highlight.OutlineTransparency = settings.OutlineTransparency
	highlight.Adornee = parent
	highlight.Parent = parent
	return highlight
end

local function hideDrawings(drawings)
	for _, drawing in pairs(drawings) do
		drawing.Visible = false
	end
end

function Visuals.GetTeamColor(target)
	if not Visuals.Settings.TeamCheck then
		return Visuals.Settings.DefaultColor
	end
	if target.Team == player.Team then
		return Visuals.Settings.TeamColors.Ally
	end
	return Visuals.Settings.TeamColors.Enemy
end

function Visuals.GetTracerOrigin()
	local size = camera.ViewportSize
	local origin = Visuals.Tracers.Origin
	if origin == "Top" then
		return Vector2.new(size.X * 0.5, 0)
	elseif origin == "Center" or origin == "Middle" then
		return Vector2.new(size.X * 0.5, size.Y * 0.5)
	elseif origin == "Mouse" then
		return UserInputService:GetMouseLocation()
	end
	return Vector2.new(size.X * 0.5, size.Y)
end

function Visuals.IsAlive(character)
	if not Visuals.Settings.AliveCheck then
		return true
	end
	if not character then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

function Visuals.GetHealth(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		return {
			Health = humanoid.Health,
			MaxHealth = humanoid.MaxHealth,
		}
	end
	return { Health = 0, MaxHealth = 100 }
end

function Visuals.IsValidItem(item)
	if not item then
		return false
	end
	if not Visuals.Items.ValidItemTypes[item.ClassName] then
		return false
	end
	return Visuals.Items.ValidItemNames[item.Name] == true
end

function Visuals.GetItemPosition(item)
	if item:IsA("BasePart") then
		return item.Position
	end
	if item:IsA("Model") then
		local part = item.PrimaryPart or item:FindFirstChild("Handle") or item:FindFirstChildWhichIsA("BasePart")
		return part and part.Position
	end
	if item:IsA("Tool") then
		local handle = item:FindFirstChild("Handle")
		return handle and handle.Position
	end
	return nil
end

-- Screen box from model bounding box (8 corners). Size is cached; pose updates every frame.
local extentsCache = setmetatable({}, { __mode = "k" })

local function getScreenBox(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end

	local cached = extentsCache[character]
	local now = os.clock()
	local cf, size

	if cached and (now - cached.time) < 1 then
		size = cached.size
		cf = root.CFrame * cached.offset
	else
		local ok, boxCf, boxSize = pcall(character.GetBoundingBox, character)
		if not ok or typeof(boxCf) ~= "CFrame" or typeof(boxSize) ~= "Vector3" then
			return nil
		end
		cf = boxCf
		size = boxSize
		extentsCache[character] = {
			time = now,
			size = boxSize,
			offset = root.CFrame:ToObjectSpace(boxCf),
		}
	end

	local half = size * 0.5
	local corners = {
		cf * Vector3.new(-half.X, -half.Y, -half.Z),
		cf * Vector3.new(-half.X, -half.Y, half.Z),
		cf * Vector3.new(-half.X, half.Y, -half.Z),
		cf * Vector3.new(-half.X, half.Y, half.Z),
		cf * Vector3.new(half.X, -half.Y, -half.Z),
		cf * Vector3.new(half.X, -half.Y, half.Z),
		cf * Vector3.new(half.X, half.Y, -half.Z),
		cf * Vector3.new(half.X, half.Y, half.Z),
	}

	local minX, minY = math.huge, math.huge
	local maxX, maxY = -math.huge, -math.huge
	local visible = false

	for i = 1, 8 do
		local screen = camera:WorldToViewportPoint(corners[i])
		if screen.Z > 0 then
			visible = true
			if screen.X < minX then
				minX = screen.X
			end
			if screen.Y < minY then
				minY = screen.Y
			end
			if screen.X > maxX then
				maxX = screen.X
			end
			if screen.Y > maxY then
				maxY = screen.Y
			end
		end
	end

	if not visible then
		return nil
	end

	return Vector2.new(minX, minY), Vector2.new(maxX - minX, maxY - minY), root
end

local function refreshFeatureFlags()
	anyPlayerEsp = Visuals.Boxes.Enabled
		or Visuals.Names.Enabled
		or Visuals.Distance.Enabled
		or Visuals.HealthBar.Enabled
		or Visuals.Tracers.Enabled
		or Visuals.Chams.Enabled
	anyItemEsp = Visuals.Items.Enabled
end

local function ensureChams(key, parent, color, settings)
	local highlight = Visuals.ChamsContainer[key]
	if highlight and highlight.Parent then
		if highlight.Adornee ~= parent then
			highlight.Adornee = parent
			highlight.Parent = parent
		end
		highlight.FillColor = color
		highlight.OutlineColor = color
		highlight.FillTransparency = settings.FillTransparency
		highlight.OutlineTransparency = settings.OutlineTransparency
		highlight.Enabled = true
		return highlight
	end

	highlight = createHighlight(parent, {
		Color = color,
		OutlineColor = color,
		FillTransparency = settings.FillTransparency,
		OutlineTransparency = settings.OutlineTransparency,
	})
	Visuals.ChamsContainer[key] = highlight
	return highlight
end

local function disableChams(key)
	local highlight = Visuals.ChamsContainer[key]
	if highlight then
		highlight.Enabled = false
	end
end

function Visuals.Create(target)
	if target == player or Visuals.Container[target] then
		return
	end

	local teamColor = Visuals.GetTeamColor(target)
	local drawings = {
		Tracer = createDrawing("Line", {
			Thickness = Visuals.Tracers.Thickness,
			Visible = false,
			Color = teamColor,
			Transparency = 1,
		}),
		Box = createDrawing("Square", {
			Thickness = 1,
			Filled = Visuals.Boxes.Filled,
			Visible = false,
			Color = teamColor,
			Transparency = 1,
		}),
		Name = createDrawing("Text", {
			Text = target.Name,
			Size = Visuals.Names.Size,
			Center = true,
			Outline = true,
			OutlineColor = Color3.new(0, 0, 0),
			Font = 2,
			Visible = false,
			Color = teamColor,
			Transparency = 1,
		}),
		Distance = createDrawing("Text", {
			Text = "",
			Size = Visuals.Distance.Size,
			Center = true,
			Outline = true,
			OutlineColor = Color3.new(0, 0, 0),
			Font = 2,
			Visible = false,
			Color = teamColor,
			Transparency = 1,
		}),
		HealthBarOutline = createDrawing("Square", {
			Thickness = 1,
			Filled = true,
			Visible = false,
			Color = Color3.new(0, 0, 0),
			Transparency = 1,
		}),
		HealthBar = createDrawing("Square", {
			Thickness = 1,
			Filled = true,
			Visible = false,
			Color = Color3.new(0, 1, 0),
			Transparency = 1,
		}),
	}

	Visuals.Container[target] = {
		drawings = drawings,
		teamColor = teamColor,
		lastTeam = target.Team,
	}
end

function Visuals.CreateItem(item)
	if not Visuals.Items.Enabled or not Visuals.IsValidItem(item) then
		return
	end
	if Visuals.ItemContainer[item] then
		return
	end

	local color = Visuals.Items.Chams.Color
	local drawings = {
		Name = createDrawing("Text", {
			Text = item.Name,
			Size = Visuals.Names.Size,
			Center = true,
			Outline = true,
			OutlineColor = Color3.new(0, 0, 0),
			Font = 2,
			Visible = false,
			Color = color,
			Transparency = 1,
		}),
		Distance = createDrawing("Text", {
			Text = "",
			Size = Visuals.Distance.Size,
			Center = true,
			Outline = true,
			OutlineColor = Color3.new(0, 0, 0),
			Font = 2,
			Visible = false,
			Color = color,
			Transparency = 1,
		}),
	}

	Visuals.ItemContainer[item] = {
		drawings = drawings,
	}
end

function Visuals.Remove(target)
	local entry = Visuals.Container[target]
	if entry then
		for _, drawing in pairs(entry.drawings) do
			drawing:Remove()
		end
		Visuals.Container[target] = nil
	end

	local highlight = Visuals.ChamsContainer[target]
	if highlight then
		highlight:Destroy()
		Visuals.ChamsContainer[target] = nil
	end
end

function Visuals.RemoveItem(item)
	local entry = Visuals.ItemContainer[item]
	if entry then
		for _, drawing in pairs(entry.drawings) do
			drawing:Remove()
		end
		Visuals.ItemContainer[item] = nil
	end

	local highlight = Visuals.ChamsContainer[item]
	if highlight then
		highlight:Destroy()
		Visuals.ChamsContainer[item] = nil
	end
end

local function updatePlayer(target, entry)
	local drawings = entry.drawings
	local character = target.Character
	if not character or not Visuals.IsAlive(character) then
		hideDrawings(drawings)
		disableChams(target)
		return
	end

	if entry.lastTeam ~= target.Team then
		entry.lastTeam = target.Team
		entry.teamColor = Visuals.GetTeamColor(target)
	end
	local teamColor = entry.teamColor

	local topLeft, boxSize, root = getScreenBox(character)
	if not topLeft then
		hideDrawings(drawings)
		return
	end

	if localPos and Visuals.Settings.MaxDistance then
		local dist = (root.Position - localPos).Magnitude
		if dist > Visuals.Settings.MaxDistance then
			hideDrawings(drawings)
			disableChams(target)
			return
		end
	end

	local centerX = topLeft.X + boxSize.X * 0.5

	if Visuals.Boxes.Enabled then
		drawings.Box.Size = boxSize
		drawings.Box.Position = topLeft
		drawings.Box.Filled = Visuals.Boxes.Filled
		drawings.Box.Color = teamColor
		drawings.Box.Visible = true
	else
		drawings.Box.Visible = false
	end

	if Visuals.Names.Enabled then
		drawings.Name.Position = Vector2.new(centerX, topLeft.Y - 20)
		drawings.Name.Size = Visuals.Names.Size
		drawings.Name.Color = teamColor
		drawings.Name.Visible = true
	else
		drawings.Name.Visible = false
	end

	if Visuals.Distance.Enabled and localPos then
		local dist = math.floor((root.Position - localPos).Magnitude)
		drawings.Distance.Text = tostring(dist) .. (Visuals.Distance.ShowStuds and " studs" or "")
		drawings.Distance.Position = Vector2.new(centerX, topLeft.Y - 35)
		drawings.Distance.Size = Visuals.Distance.Size
		drawings.Distance.Color = teamColor
		drawings.Distance.Visible = true
	else
		drawings.Distance.Visible = false
	end

	if Visuals.HealthBar.Enabled then
		local health = Visuals.GetHealth(character)
		local maxHealth = health.MaxHealth
		if maxHealth <= 0 then
			maxHealth = 1
		end
		local percent = math.clamp(health.Health / maxHealth, 0, 1)
		local barWidth = 3
		local barHeight = boxSize.Y
		local barX = Visuals.HealthBar.Origin == "Left" and (topLeft.X - barWidth - 4) or (topLeft.X + boxSize.X + 4)
		local barPos = Vector2.new(barX, topLeft.Y)

		drawings.HealthBarOutline.Size = Vector2.new(barWidth, barHeight)
		drawings.HealthBarOutline.Position = barPos
		drawings.HealthBarOutline.Visible = true

		drawings.HealthBar.Size = Vector2.new(barWidth, barHeight * percent)
		drawings.HealthBar.Position = Vector2.new(barPos.X, barPos.Y + barHeight * (1 - percent))
		drawings.HealthBar.Color = Color3.new(1 - percent, percent, 0)
		drawings.HealthBar.Visible = true
	else
		drawings.HealthBar.Visible = false
		drawings.HealthBarOutline.Visible = false
	end

	if Visuals.Tracers.Enabled then
		local screen, onScreen = camera:WorldToViewportPoint(root.Position)
		if onScreen and screen.Z > 0 then
			drawings.Tracer.From = tracerOrigin
			drawings.Tracer.To = Vector2.new(screen.X, screen.Y)
			drawings.Tracer.Thickness = Visuals.Tracers.Thickness
			drawings.Tracer.Color = teamColor
			drawings.Tracer.Visible = true
		else
			drawings.Tracer.Visible = false
		end
	else
		drawings.Tracer.Visible = false
	end

	if Visuals.Chams.Enabled then
		ensureChams(target, character, teamColor, Visuals.Chams)
	else
		disableChams(target)
	end
end

local function updateItem(item, entry)
	local drawings = entry.drawings
	if not item.Parent then
		hideDrawings(drawings)
		disableChams(item)
		Visuals.RemoveItem(item)
		return
	end

	local worldPos = Visuals.GetItemPosition(item)
	if not worldPos then
		hideDrawings(drawings)
		return
	end

	if localPos then
		local dist = (worldPos - localPos).Magnitude
		if dist > Visuals.Items.MaxDistance then
			hideDrawings(drawings)
			disableChams(item)
			return
		end
	end

	local screen, onScreen = camera:WorldToViewportPoint(worldPos)
	if not onScreen or screen.Z <= 0 then
		hideDrawings(drawings)
		return
	end

	local screenPos = Vector2.new(screen.X, screen.Y)
	drawings.Name.Position = screenPos
	drawings.Name.Visible = true

	if Visuals.Items.ShowDistance and localPos then
		local dist = math.floor((worldPos - localPos).Magnitude)
		drawings.Distance.Text = tostring(dist) .. " studs"
		drawings.Distance.Position = screenPos + Vector2.new(0, 15)
		drawings.Distance.Visible = true
	else
		drawings.Distance.Visible = false
	end

	if Visuals.Items.Chams.Enabled then
		ensureChams(item, item, Visuals.Items.Chams.Color, Visuals.Items.Chams)
	else
		disableChams(item)
	end
end

local function onRender()
	refreshFeatureFlags()
	camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local character = player.Character
	localRoot = character and character:FindFirstChild("HumanoidRootPart")
	localPos = localRoot and localRoot.Position or nil
	if Visuals.Tracers.Enabled then
		tracerOrigin = Visuals.GetTracerOrigin()
	end

	if anyPlayerEsp then
		for target, entry in pairs(Visuals.Container) do
			updatePlayer(target, entry)
		end
	else
		for target, entry in pairs(Visuals.Container) do
			hideDrawings(entry.drawings)
			disableChams(target)
		end
	end

	if anyItemEsp then
		local now = os.clock()
		if now - lastItemScan > 5 then
			lastItemScan = now
			scanExistingItems()
		end
		for item, entry in pairs(Visuals.ItemContainer) do
			updateItem(item, entry)
		end
	else
		for item, entry in pairs(Visuals.ItemContainer) do
			hideDrawings(entry.drawings)
			disableChams(item)
		end
	end
end

local renderConnection = RunService.RenderStepped:Connect(onRender)

-- Item discovery without GetDescendants spam
scanExistingItems = function()
	if not Visuals.Items.Enabled then
		return
	end
	for _, item in ipairs(workspace:GetDescendants()) do
		if Visuals.IsValidItem(item) then
			Visuals.CreateItem(item)
		end
	end
end

workspace.DescendantAdded:Connect(function(item)
	if Visuals.Items.Enabled and Visuals.IsValidItem(item) then
		Visuals.CreateItem(item)
	end
end)

-- Call after enabling item ESP / filling ValidItemNames
function Visuals.RefreshItems()
	scanExistingItems()
end

Players.PlayerAdded:Connect(function(target)
	Visuals.Create(target)
end)

Players.PlayerRemoving:Connect(function(target)
	Visuals.Remove(target)
	if target == player then
		Visuals.Destroy()
	end
end)

for _, target in ipairs(Players:GetPlayers()) do
	Visuals.Create(target)
end

function Visuals.Destroy()
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end

	for target in pairs(Visuals.Container) do
		Visuals.Remove(target)
	end
	for item in pairs(Visuals.ItemContainer) do
		Visuals.RemoveItem(item)
	end
	table.clear(Visuals.Container)
	table.clear(Visuals.ItemContainer)
	table.clear(Visuals.ChamsContainer)
end

return Visuals
