local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local Aimbot = {
	Settings = {
		Enabled = false,
		KeyBind = "",
		HitPart = "Head",
		TeamCheck = true,
		WallCheck = true,
		AliveCheck = true,
		ShowFOV = true,
		FOV = 120,
		FOVType = "Pixels",
		Prediction = 0,
		Smoothness = 0,
		Deadzone = 2,
		MaxDistance = 2000,
		Mode = "Auto",
		FOVColor = Color3.fromRGB(255, 255, 255),
		FOVTransparency = 0.85,
		FOVThickness = 1,
	},
	Locked = nil,
}

local fovCircle
local renderConnection
local inputBegan
local inputEnded
local keyHeld = false
local lockedPlayer = nil
local lockedPartName = nil
local randomParts = { "Head", "Torso", "HumanoidRootPart" }

local function refreshCamera()
	camera = Workspace.CurrentCamera
	return camera
end

local function bindName(bind)
	if typeof(bind) == "EnumItem" then
		return bind.Name
	end
	if type(bind) == "string" then
		return bind
	end
	return ""
end

local function enumFromName(enumType, name)
	if type(name) ~= "string" or name == "" then
		return nil
	end
	local ok, value = pcall(function()
		return enumType[name]
	end)
	if ok then
		return value
	end
	return nil
end

local function isBindDown()
	local name = bindName(Aimbot.Settings.KeyBind)
	if name == "" then
		return true
	end

	local mouse = enumFromName(Enum.UserInputType, name)
	if mouse and UserInputService:IsMouseButtonPressed(mouse) then
		return true
	end

	local key = enumFromName(Enum.KeyCode, name)
	if key and UserInputService:IsKeyDown(key) then
		return true
	end

	return keyHeld
end

local function inputMatchesBind(input)
	local name = bindName(Aimbot.Settings.KeyBind)
	if name == "" then
		return false
	end
	if input.KeyCode ~= Enum.KeyCode.Unknown and input.KeyCode.Name == name then
		return true
	end
	if input.UserInputType ~= Enum.UserInputType.None and input.UserInputType.Name == name then
		return true
	end
	return false
end

local function destroyCircle()
	if not fovCircle then
		return
	end
	pcall(function()
		fovCircle:Destroy()
	end)
	pcall(function()
		fovCircle:Remove()
	end)
	fovCircle = nil
end

local function ensureCircle()
	if fovCircle then
		return fovCircle
	end
	if type(Drawing) ~= "table" or type(Drawing.new) ~= "function" then
		return nil
	end
	local circle = Drawing.new("Circle")
	circle.Filled = false
	circle.NumSides = 64
	circle.Visible = false
	fovCircle = circle
	return circle
end

local function screenCenter()
	if not camera then
		return Vector2.zero
	end
	local viewport = camera.ViewportSize
	return Vector2.new(viewport.X * 0.5, viewport.Y * 0.5)
end

function Aimbot.GetScreenFovRadius()
	if not refreshCamera() then
		return 0
	end
	local fov = Aimbot.Settings.FOV
	if type(fov) ~= "number" or fov <= 0 then
		local viewport = camera.ViewportSize
		return math.max(viewport.X, viewport.Y)
	end
	if Aimbot.Settings.FOVType ~= "Degrees" then
		return fov
	end
	local camFov = math.rad(camera.FieldOfView)
	if camFov <= 0 then
		return 0
	end
	return math.tan(math.rad(fov) * 0.5) / math.tan(camFov * 0.5) * (camera.ViewportSize.Y * 0.5)
end

function Aimbot.IsValidTarget(other)
	if other == player then
		return false
	end
	if Aimbot.Settings.TeamCheck and player.Team and other.Team and player.Team == other.Team then
		return false
	end
	return true
end

function Aimbot.GetHitPart(character, choice)
	choice = choice or Aimbot.Settings.HitPart
	if choice == "Random" then
		choice = lockedPartName or "Head"
	end
	if choice == "Torso" then
		return character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	end
	return character:FindFirstChild(choice)
end

function Aimbot.GetAimPosition(part)
	local pos = part.Position
	local pred = Aimbot.Settings.Prediction
	if type(pred) ~= "number" or pred <= 0 then
		return pos
	end
	local vel = part.AssemblyLinearVelocity
	if typeof(vel) ~= "Vector3" or vel.Magnitude < 0.05 then
		local root = part.Parent and part.Parent:FindFirstChild("HumanoidRootPart")
		if root then
			vel = root.AssemblyLinearVelocity
		end
	end
	if typeof(vel) == "Vector3" then
		return pos + vel * pred
	end
	return pos
end

local function hasWall(origin, part)
	local localCharacter = player.Character
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { localCharacter, part.Parent }
	local delta = part.Position - origin
	if delta.Magnitude <= 0 then
		return false
	end
	local result = Workspace:Raycast(origin, delta, params)
	if not result then
		return false
	end
	return not result.Instance:IsDescendantOf(part.Parent)
end

local function isAlive(character)
	if not Aimbot.Settings.AliveCheck then
		return true
	end
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function pickRandomPart(character)
	local available = {}
	for i = 1, #randomParts do
		local part = Aimbot.GetHitPart(character, randomParts[i])
		if part then
			available[#available + 1] = randomParts[i]
		end
	end
	if #available == 0 then
		return "Head"
	end
	return available[math.random(1, #available)]
end

local function evaluateTarget(other, origin, center, radius)
	if not Aimbot.IsValidTarget(other) then
		return nil
	end
	local character = other.Character
	if not character or not isAlive(character) then
		return nil
	end

	local partChoice = Aimbot.Settings.HitPart
	if partChoice == "Random" then
		if lockedPlayer == other and lockedPartName then
			partChoice = lockedPartName
		else
			partChoice = pickRandomPart(character)
		end
	end

	local part = Aimbot.GetHitPart(character, partChoice)
	if not part then
		return nil
	end

	local aimPos = Aimbot.GetAimPosition(part)
	local worldDist = (aimPos - origin).Magnitude
	local maxDist = Aimbot.Settings.MaxDistance
	if type(maxDist) == "number" and maxDist > 0 and worldDist > maxDist then
		return nil
	end

	local screen, onScreen = camera:WorldToViewportPoint(aimPos)
	if not onScreen or screen.Z <= 0 then
		return nil
	end

	local dx = screen.X - center.X
	local dy = screen.Y - center.Y
	local pixelDist = math.sqrt(dx * dx + dy * dy)
	if pixelDist > radius then
		return nil
	end

	if Aimbot.Settings.WallCheck and hasWall(origin, part) then
		return nil
	end

	return {
		player = other,
		character = character,
		part = part,
		partName = partChoice,
		position = aimPos,
		screen = Vector2.new(screen.X, screen.Y),
		pixelDistance = pixelDist,
		worldDistance = worldDist,
	}
end

function Aimbot.GetTarget()
	if not refreshCamera() then
		return nil
	end

	local origin = camera.CFrame.Position
	local center = screenCenter()
	local radius = Aimbot.GetScreenFovRadius()
	local best = nil
	local bestScore = 1e9
	local list = Players:GetPlayers()

	if lockedPlayer and lockedPlayer.Parent then
		local sticky = evaluateTarget(lockedPlayer, origin, center, radius)
		if sticky then
			return sticky
		end
		lockedPlayer = nil
		lockedPartName = nil
	end

	for i = 1, #list do
		local other = list[i]
		local candidate = evaluateTarget(other, origin, center, radius)
		if candidate and candidate.pixelDistance < bestScore then
			bestScore = candidate.pixelDistance
			best = candidate
		end
	end

	return best
end

local function useMouse()
	local mode = Aimbot.Settings.Mode
	if mode == "Camera" then
		return false
	end
	if mode == "Mouse" then
		return type(mousemoverel) == "function"
	end
	return type(mousemoverel) == "function"
end

local function smoothAlpha()
	local smoothness = Aimbot.Settings.Smoothness
	if type(smoothness) ~= "number" or smoothness <= 0 then
		return 1
	end
	return math.clamp(1 / smoothness, 0.04, 1)
end

local function aimAt(target)
	local deadzone = Aimbot.Settings.Deadzone
	if type(deadzone) ~= "number" then
		deadzone = 0
	end
	if target.pixelDistance <= deadzone then
		return
	end

	local alpha = smoothAlpha()
	if useMouse() then
		local center = screenCenter()
		local dx = (target.screen.X - center.X) * alpha
		local dy = (target.screen.Y - center.Y) * alpha
		if math.abs(dx) < 0.15 and math.abs(dy) < 0.15 then
			return
		end
		mousemoverel(dx, dy)
		return
	end

	if not camera then
		return
	end
	local goal = CFrame.new(camera.CFrame.Position, target.position)
	if alpha >= 1 then
		camera.CFrame = goal
		return
	end
	camera.CFrame = camera.CFrame:Lerp(goal, alpha)
end

local function updateFovCircle()
	local settings = Aimbot.Settings
	local show = settings.ShowFOV and settings.Enabled and refreshCamera() ~= nil
	if not show then
		if fovCircle then
			fovCircle.Visible = false
		end
		return
	end

	local circle = ensureCircle()
	if not circle then
		return
	end

	circle.Position = screenCenter()
	circle.Radius = Aimbot.GetScreenFovRadius()
	circle.Color = settings.FOVColor
	circle.Transparency = settings.FOVTransparency
	circle.Thickness = settings.FOVThickness
	circle.Visible = true
end

local function onRender()
	updateFovCircle()

	if not Aimbot.Settings.Enabled then
		Aimbot.Locked = nil
		lockedPlayer = nil
		lockedPartName = nil
		return
	end
	if UserInputService:GetFocusedTextBox() then
		return
	end
	if not isBindDown() then
		Aimbot.Locked = nil
		lockedPlayer = nil
		lockedPartName = nil
		return
	end

	local target = Aimbot.GetTarget()
	Aimbot.Locked = target
	if not target then
		lockedPlayer = nil
		lockedPartName = nil
		return
	end

	lockedPlayer = target.player
	if Aimbot.Settings.HitPart == "Random" then
		lockedPartName = target.partName
	else
		lockedPartName = nil
	end

	aimAt(target)
end

function Aimbot.Destroy()
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	if inputBegan then
		inputBegan:Disconnect()
		inputBegan = nil
	end
	if inputEnded then
		inputEnded:Disconnect()
		inputEnded = nil
	end
	destroyCircle()
	Aimbot.Locked = nil
	lockedPlayer = nil
	lockedPartName = nil
	keyHeld = false
end

inputBegan = UserInputService.InputBegan:Connect(function(input, processed)
	if processed and input.UserInputType == Enum.UserInputType.Keyboard then
		return
	end
	if inputMatchesBind(input) then
		keyHeld = true
	end
end)

inputEnded = UserInputService.InputEnded:Connect(function(input)
	if inputMatchesBind(input) then
		keyHeld = false
	end
end)

Players.PlayerRemoving:Connect(function(other)
	if other == lockedPlayer then
		lockedPlayer = nil
		lockedPartName = nil
		Aimbot.Locked = nil
	end
	if other == player then
		Aimbot.Destroy()
	end
end)

renderConnection = RunService.RenderStepped:Connect(onRender)

return Aimbot
