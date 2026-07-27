--[[ Services ]]--

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

--[[ Variables ]]--

local localPlayer = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local abs, cos, sin, rad = math.abs, math.cos, math.sin, math.rad
local huge, round, clamp = math.huge, math.round, math.clamp

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

local BOX_3D_EDGES = {
	{ 1, 2 }, { 2, 3 }, { 3, 4 }, { 4, 1 },
	{ 5, 6 }, { 6, 7 }, { 7, 8 }, { 8, 5 },
	{ 1, 5 }, { 2, 6 }, { 3, 7 }, { 4, 8 },
}

local esp = {
	Fonts = (Drawing and Drawing.Fonts) or { UI = 0, System = 1, Plex = 2, Monospace = 3 },
	container = {},
	settings = {
		enabled = false,

		boxes = true,
		boxType = "2d", -- "2d" | "3d"
		boxThickness = 1,

		tracers = false,
		tracerOrigin = "bottom", -- "bottom" | "center" | "top" | "mouse"
		tracerThickness = 1,

		skeletons = false,
		skeletonThickness = 1,

		health = true,

		names = true,
		distances = true,
		useDisplayNames = false,
		textSize = 14,
		font = 0,
		textOpacity = 1,

		offscreenArrows = false,
		arrowOffset = 120,
		arrowHeight = 18,
		arrowWidth = 12,

		teammates = true,
		useTeamColours = true,
		enemyColour = Color3.fromRGB(220, 70, 70),
		friendlyColour = Color3.fromRGB(80, 200, 120),
		colour = WHITE,
		opacity = 1,

		-- optional: only draw the N closest players
		closestOnly = false,
		maxClosest = 1, -- how many closest to show when closestOnly is true
		maxDistance = nil, -- optional studs cap (nil = no limit)

		scanDescendants = false,
	},
}

esp.settings.font = esp.Fonts.UI or 0

--[[ Helpers ]]--

local function destroyObj(obj)
	if not obj then
		return
	end
	pcall(function()
		if obj.Destroy then
			obj:Destroy()
		elseif obj.Remove then
			obj:Remove()
		end
	end)
end

local function drawNew(className, props)
	local obj = Drawing.new(className)
	if props then
		for key, value in pairs(props) do
			obj[key] = value
		end
	end
	return obj
end

local function hideAll(drawings)
	for i = 1, #drawings do
		drawings[i].Visible = false
	end
end

local function destroyAll(drawings)
	for i = 1, #drawings do
		destroyObj(drawings[i])
	end
end

local function makeText(size, font)
	return drawNew("Text", {
		Center = true,
		Outline = true,
		OutlineColor = BLACK,
		Color = WHITE,
		Size = size,
		Font = font,
		Text = "",
		Visible = false,
	})
end

local function makeLine(thickness)
	return drawNew("Line", {
		Color = WHITE,
		Thickness = thickness,
		Visible = false,
	})
end

local function makeSquare(thickness, filled)
	return drawNew("Square", {
		Color = WHITE,
		Thickness = thickness,
		Filled = filled and true or false,
		Visible = false,
	})
end

local function makeTriangle()
	return drawNew("Triangle", {
		Color = WHITE,
		Filled = true,
		Visible = false,
	})
end

local function buildDrawings(bones, settings)
	local drawings = {}
	local parts = {
		box2d = makeSquare(settings.boxThickness, false),
		health = makeSquare(1, true),
		name = makeText(settings.textSize, settings.font),
		dist = makeText(settings.textSize, settings.font),
		tracer = makeLine(settings.tracerThickness),
		arrow = makeTriangle(),
		box3d = {},
		skeleton = {},
	}

	drawings[#drawings + 1] = parts.box2d
	drawings[#drawings + 1] = parts.health
	drawings[#drawings + 1] = parts.name
	drawings[#drawings + 1] = parts.dist
	drawings[#drawings + 1] = parts.tracer
	drawings[#drawings + 1] = parts.arrow

	for i = 1, 12 do
		local edge = makeLine(settings.boxThickness)
		parts.box3d[i] = edge
		drawings[#drawings + 1] = edge
	end

	for i = 1, #bones do
		local bone = makeLine(settings.skeletonThickness)
		parts.skeleton[i] = bone
		drawings[#drawings + 1] = bone
	end

	parts._all = drawings
	return parts
end

--[[ Math porn ]]--

local function accumulatePartBounds(obj, bounds)
	local size = obj.Size
	local sx, sy, sz = size.X, size.Y, size.Z
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = obj.CFrame:GetComponents()
	local wsx = 0.5 * (abs(r00) * sx + abs(r01) * sy + abs(r02) * sz)
	local wsy = 0.5 * (abs(r10) * sx + abs(r11) * sy + abs(r12) * sz)
	local wsz = 0.5 * (abs(r20) * sx + abs(r21) * sy + abs(r22) * sz)
	if x - wsx < bounds.minX then bounds.minX = x - wsx end
	if y - wsy < bounds.minY then bounds.minY = y - wsy end
	if z - wsz < bounds.minZ then bounds.minZ = z - wsz end
	if x + wsx > bounds.maxX then bounds.maxX = x + wsx end
	if y + wsy > bounds.maxY then bounds.maxY = y + wsy end
	if z + wsz > bounds.maxZ then bounds.maxZ = z + wsz end
	bounds.found = true
end

local function getBounds(model, useDescendants)
	if not model then
		return nil, nil
	end

	-- BasePart refs (wild pets, pet slots, traps) have no children — use the part itself
	if model:IsA("BasePart") then
		return model.Position, model.Size
	end

	local bounds = {
		minX = huge,
		minY = huge,
		minZ = huge,
		maxX = -huge,
		maxY = -huge,
		maxZ = -huge,
		found = false,
	}

	-- Always walk descendants — plant/fruit visuals are nested under folders
	local parts = model:GetDescendants()
	for i = 1, #parts do
		local obj = parts[i]
		if obj:IsA("BasePart") then
			accumulatePartBounds(obj, bounds)
		end
	end

	if not bounds.found and model:IsA("Model") then
		local ok, pivot = pcall(model.GetPivot, model)
		if ok and pivot then
			local _, size = pcall(function()
				return model:GetExtentsSize()
			end)
			return pivot.Position, size or Vector3.new(2, 2, 2)
		end
	end

	if not bounds.found then
		return nil, nil
	end

	local omin = Vector3.new(bounds.minX, bounds.minY, bounds.minZ)
	local omax = Vector3.new(bounds.maxX, bounds.maxY, bounds.maxZ)
	return (omax + omin) * 0.5, omax - omin
end

local function rotate2(vec, angle)
	local a = rad(angle)
	return Vector2.new(vec.X * cos(a) - vec.Y * sin(a), vec.X * sin(a) + vec.Y * cos(a))
end

local function toScreen(pos)
	local p, onScreen = camera:WorldToViewportPoint(pos)
	return Vector2.new(p.X, p.Y), onScreen, p.Z
end

local function healthColor(h)
	return Color3.new(
		h < 0.5 and 1 or 1 - ((h - 0.5) * 2),
		h > 0.5 and 1 or h * 2,
		0
	)
end

local function isEnemy(player)
	if not player then
		return true
	end
	return player.Team ~= localPlayer.Team
end

local function resolveColour(settings, player, override)
	if override then
		return override
	end
	if settings.useTeamColours and player then
		return settings[isEnemy(player) and "enemyColour" or "friendlyColour"]
	end
	return settings.colour
end

local function resolveTracerOrigin(origin, viewport)
	if typeof(origin) == "Vector2" then
		return origin
	end
	local kind = type(origin) == "string" and string.lower(origin) or "bottom"
	if kind == "center" then
		return viewport * 0.5
	elseif kind == "top" then
		return Vector2.new(viewport.X * 0.5, 10)
	elseif kind == "mouse" then
		return UserInputService:GetMouseLocation()
	end
	return Vector2.new(viewport.X * 0.5, viewport.Y - 10)
end

local function createBoneMap(model)
	local map = {}
	for _, v in ipairs(model:GetDescendants()) do
		if v:IsA("Motor6D") and v.Part0 and v.Part1 then
			map[#map + 1] = { v.Part0, v.Part1 }
		end
	end
	return map
end

local function getHealthFraction(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.MaxHealth <= 0 then
		return 0
	end
	return clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
end

local function displayName(settings, player, fallback)
	if player then
		return player[settings.useDisplayNames and "DisplayName" or "Name"]
	end
	return fallback
end

local function box2d(center, size, camPos)
	local cf = CFrame.new(center, camPos)
	local r = size * 0.5
	local corners = {
		(cf * CFrame.new(r.X, r.Y, 0)).Position,
		(cf * CFrame.new(r.X, -r.Y, 0)).Position,
		(cf * CFrame.new(-r.X, r.Y, 0)).Position,
		(cf * CFrame.new(-r.X, -r.Y, 0)).Position,
	}
	local minX, minY, maxX, maxY = huge, huge, 0, 0
	for i = 1, 4 do
		local s = toScreen(corners[i])
		if s.X < minX then minX = s.X end
		if s.X > maxX then maxX = s.X end
		if s.Y < minY then minY = s.Y end
		if s.Y > maxY then maxY = s.Y end
	end
	return Vector2.new(minX, minY), Vector2.new(maxX - minX, maxY - minY), minX, minY, maxX, maxY
end

local function box3dCorners(center, size)
	local hx, hy, hz = size.X * 0.5, size.Y * 0.5, size.Z * 0.5
	return {
		center + Vector3.new(-hx, hy, -hz),
		center + Vector3.new(hx, hy, -hz),
		center + Vector3.new(hx, hy, hz),
		center + Vector3.new(-hx, hy, hz),
		center + Vector3.new(-hx, -hy, -hz),
		center + Vector3.new(hx, -hy, -hz),
		center + Vector3.new(hx, -hy, hz),
		center + Vector3.new(-hx, -hy, hz),
	}
end

local function buildClosestSet(camPos, settings)
	if not settings.closestOnly then
		return nil
	end

	local ranked = {}
	local maxDist = settings.maxDistance
	local count = settings.maxClosest or 1
	if count < 1 then
		count = 1
	end

	for i = 1, #esp.container do
		local inst = esp.container[i]
		local model = inst.model
		if model and model.Parent then
			local player = inst.player
			local skip = (not settings.teammates) and player and (not isEnemy(player))
			if not skip then
				local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
				local pos = root and root.Position
				if not pos then
					local center = getBounds(model, settings.scanDescendants)
					pos = center
				end
				if pos then
					local dist = (pos - camPos).Magnitude
					if not maxDist or dist <= maxDist then
						ranked[#ranked + 1] = { inst = inst, dist = dist }
					end
				end
			end
		end
	end

	table.sort(ranked, function(a, b)
		return a.dist < b.dist
	end)

	local allowed = {}
	for i = 1, math.min(count, #ranked) do
		allowed[ranked[i].inst] = true
	end
	return allowed
end

local function update()
	local settings = esp.settings
	camera = Workspace.CurrentCamera

	if not settings.enabled then
		for i = 1, #esp.container do
			hideAll(esp.container[i].draw._all)
		end
		return
	end

	local camCF = camera.CFrame
	local camPos = camCF.Position
	local viewport = camera.ViewportSize
	local centerScreen = viewport * 0.5
	local tracerOrigin = resolveTracerOrigin(settings.tracerOrigin, viewport)
	local opacity = settings.opacity
	local textOpacity = settings.textOpacity
	local font = settings.font or esp.Fonts.UI
	local closestSet = buildClosestSet(camPos, settings)
	local maxDist = settings.maxDistance

	for i = 1, #esp.container do
		local inst = esp.container[i]
		local draw = inst.draw
		local model = inst.model

		if not model or not model.Parent then
			hideAll(draw._all)
		elseif closestSet and not closestSet[inst] then
			hideAll(draw._all)
		else
			local player = inst.player
			local skip = (not settings.teammates) and player and (not isEnemy(player))
			local center, size = nil, nil
			if not skip then
				center, size = getBounds(model, settings.scanDescendants)
			end

			if skip or not center then
				hideAll(draw._all)
			elseif maxDist and (center - camPos).Magnitude > maxDist then
				hideAll(draw._all)
			else
				local screenPos, onScreen = toScreen(center)
				local colour = resolveColour(settings, player, inst.colour)

				hideAll(draw._all)

				if onScreen then
					local topLeft, boxSize, minX, minY, maxX, maxY = box2d(center, size, camPos)

					-- 2d / 3d boxes
					if settings.boxes then
						if settings.boxType == "3d" then
							local corners = box3dCorners(center, size)
							local points = {}
							for c = 1, 8 do
								points[c] = toScreen(corners[c])
							end
							for e = 1, 12 do
								local edge = BOX_3D_EDGES[e]
								local lineObj = draw.box3d[e]
								lineObj.From = points[edge[1]]
								lineObj.To = points[edge[2]]
								lineObj.Color = colour
								lineObj.Thickness = settings.boxThickness
								lineObj.Transparency = opacity
								lineObj.Visible = true
							end
						else
							local box = draw.box2d
							box.Position = topLeft
							box.Size = boxSize
							box.Color = colour
							box.Thickness = settings.boxThickness
							box.Transparency = opacity
							box.Visible = true
						end
					end

					-- skeleton
					if settings.skeletons then
						local boneCache = {}
						for b = 1, #inst.bones do
							local pair = inst.bones[b]
							local lineObj = draw.skeleton[b]
							if lineObj and pair[1] and pair[2] and pair[1].Parent and pair[2].Parent then
								if not boneCache[pair[1]] then
									boneCache[pair[1]] = toScreen(pair[1].Position)
								end
								if not boneCache[pair[2]] then
									boneCache[pair[2]] = toScreen(pair[2].Position)
								end
								lineObj.From = boneCache[pair[1]]
								lineObj.To = boneCache[pair[2]]
								lineObj.Color = colour
								lineObj.Thickness = settings.skeletonThickness
								lineObj.Transparency = opacity
								lineObj.Visible = true
							end
						end
					end

					-- health
					if settings.health then
						local hp = getHealthFraction(model)
						local h = boxSize.Y * hp
						local bar = draw.health
						bar.Position = Vector2.new(minX - 5, maxY - h)
						bar.Size = Vector2.new(2, h)
						bar.Color = healthColor(hp)
						bar.Transparency = opacity
						bar.Visible = true
					end

					-- name
					if settings.names then
						local label = draw.name
						label.Text = displayName(settings, player, inst.name)
						label.Size = settings.textSize
						label.Font = font
						label.Color = colour
						label.Transparency = textOpacity
						label.Position = Vector2.new(screenPos.X, minY - settings.textSize - 2)
						label.Visible = true
					end

					-- distance
					if settings.distances then
						local label = draw.dist
						label.Text = tostring(round((center - camPos).Magnitude)) .. "m"
						label.Size = settings.textSize
						label.Font = font
						label.Color = colour
						label.Transparency = textOpacity
						label.Position = Vector2.new(screenPos.X, maxY + 2)
						label.Visible = true
					end

					-- tracer
					if settings.tracers then
						local tracer = draw.tracer
						tracer.From = tracerOrigin
						tracer.To = Vector2.new(screenPos.X, maxY)
						tracer.Color = colour
						tracer.Thickness = settings.tracerThickness
						tracer.Transparency = opacity
						tracer.Visible = true
					end
				elseif settings.offscreenArrows then
					local ray = camCF:PointToObjectSpace(center)
					local dir = -Vector2.new(ray.X, ray.Z)
					if dir.Magnitude > 0 then
						dir = dir.Unit
						local tip = dir * settings.arrowOffset
						local half = settings.arrowWidth * 0.5
						local arrow = draw.arrow
						arrow.PointA = centerScreen - (tip + rotate2(dir, 90) * half)
						arrow.PointB = centerScreen - (tip + rotate2(dir, -90) * half)
						arrow.PointC = centerScreen - (dir * (settings.arrowOffset + settings.arrowHeight))
						arrow.Color = colour
						arrow.Transparency = opacity
						arrow.Visible = true
					end
				end
			end
		end
	end
end

function esp:add(model, options)
	options = options or {}
	if not model then
		return nil
	end

	for i = 1, #self.container do
		if self.container[i].model == model then
			return self.container[i]
		end
	end

	local bones = options.bones or createBoneMap(model)
	local inst = {
		model = model,
		player = Players:GetPlayerFromCharacter(model),
		name = options.name or model.Name,
		colour = options.colour,
		bones = bones,
		draw = buildDrawings(bones, self.settings),
	}

	local alwaysRemove = options.alwaysRemove
	if alwaysRemove == nil then
		alwaysRemove = true
	end

	inst.conn = model.AncestryChanged:Connect(function(_, parent)
		if alwaysRemove and not parent then
			self:remove(inst)
		elseif options.removed and parent == options.removed then
			self:remove(inst)
		end
	end)

	self.container[#self.container + 1] = inst
	return inst
end

function esp:remove(instOrModel)
	local model = typeof(instOrModel) == "Instance" and instOrModel or (instOrModel and instOrModel.model)
	for i = 1, #self.container do
		local inst = self.container[i]
		if inst == instOrModel or inst.model == model then
			if inst.conn then
				inst.conn:Disconnect()
			end
			destroyAll(inst.draw._all)
			table.remove(self.container, i)
			return true
		end
	end
	return false
end

function esp:clear()
	for i = #self.container, 1, -1 do
		self:remove(self.container[i])
	end
end

function esp:has(model)
	for i = 1, #self.container do
		if self.container[i].model == model then
			return true
		end
	end
	return false
end

function esp:bindPlayers()
	if self._playerBound then
		return
	end
	self._playerBound = true

	local function track(character)
		if character then
			self:add(character)
		end
	end

	local function hook(plr)
		if plr == localPlayer then
			return
		end
		if plr.Character then
			track(plr.Character)
		end
		plr.CharacterAdded:Connect(track)
	end

	for _, plr in ipairs(Players:GetPlayers()) do
		hook(plr)
	end
	self._playerAdded = Players.PlayerAdded:Connect(hook)
end

function esp:unbindPlayers()
	if self._playerAdded then
		self._playerAdded:Disconnect()
		self._playerAdded = nil
	end
	self._playerBound = false
end

function esp:dispose()
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end
	self:unbindPlayers()
	self:clear()
	if cleardrawcache then
		pcall(cleardrawcache)
	end
end

esp._conn = RunService.RenderStepped:Connect(update)

if getgenv then
	getgenv().esp = esp
end

return esp
