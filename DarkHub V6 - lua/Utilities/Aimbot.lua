--[[ Services ]]--

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

--[[ Variables ]]--

local localPlayer = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- [[ Helpers ]]--

local config = {
    keyBind = Enum.KeyCode.E or Enum.UserInputType.MouseButton1,
    smoothing =  15, -- Higher = faster, lower = smoother/more weight
    maxDistance = 500,
}

local isEnabled = false

-- [[ Functions ]]--

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == config.keyBind then
        isEnabled = not isEnabled
    end
end) 

local function closetTarget()
    local closestPlayer = nil
    local closestDistance = config.maxDistance

    for _, player in pairs(Players:GetPlayers()) do
        if player ~= localPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            local distance = (player.Character.HumanoidRootPart.Position - camera.CFrame.Position).Magnitude
            if distance < closestDistance then
                closestDistance = distance
                closestPlayer = player
            end
        end
    end

    return closestPlayer
end

RunService.RenderStepped:Connect(function()
    if isEnabled then
        local targetPlayer = closetTarget()
        if targetPlayer and targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart") then
            local targetPosition = targetPlayer.Character.HumanoidRootPart.Position
            local direction = (targetPosition - camera.CFrame.Position).Unit
            local newCFrame = CFrame.new(camera.CFrame.Position, camera.CFrame.Position + direction)
            camera.CFrame = camera.CFrame:Lerp(newCFrame, 1 / config.smoothing)
        end
    end
end)