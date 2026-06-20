--------------------------------------------------------------------------
-- AntiFling Loader / GUI
-- Loads Trajectory API + AcidRedirect API separately
--------------------------------------------------------------------------

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local global = getgenv and getgenv() or _G

if global.__AntiFlingGuiController and typeof(global.__AntiFlingGuiController.Destroy) == "function" then
	pcall(global.__AntiFlingGuiController.Destroy)
end

local TRAJECTORY_API_URL = "https://raw.githubusercontent.com/XxInsaneX1/ClapperFEPublic/refs/heads/main/TJFPublicRelease"
local ACID_REDIRECT_API_URL = "https://raw.githubusercontent.com/XxInsaneX1/ClapperFEPublic/refs/heads/main/AcidRedirectAsync"

local DEFAULTS = {
	HorizontalMultiplier = 1,
	JumpVelocityBuffer = 2,
	RagdollMaxUpward = 0.1,
	RagdollMaxDownward = -400,
	MaxAngularSpeed = 1,
	AngularDamping = 0.2,
}

local Settings = {
	Enabled = false,
	HorizontalMultiplier = DEFAULTS.HorizontalMultiplier,
	JumpVelocityBuffer = DEFAULTS.JumpVelocityBuffer,
	RagdollMaxUpward = DEFAULTS.RagdollMaxUpward,
	RagdollMaxDownward = DEFAULTS.RagdollMaxDownward,
	MaxAngularSpeed = DEFAULTS.MaxAngularSpeed,
	AngularDamping = DEFAULTS.AngularDamping,
}

local AcidRedirect = {
	Enabled = false,
	Loading = false,
	Loaded = false,
	LoadToken = 0,
	Controller = nil,
	Predictor = nil,
	LastError = nil,
}

local MainConnections = {}
local Character, Humanoid, RootPart
local ragdolled = false
local characterConnections = {}

local COLOR_BG = Color3.fromRGB(14, 14, 16)
local COLOR_PANEL = Color3.fromRGB(18, 18, 21)
local COLOR_FIELD = Color3.fromRGB(26, 26, 30)
local COLOR_BORDER = Color3.fromRGB(38, 38, 43)
local COLOR_TEXT = Color3.fromRGB(235, 235, 238)
local COLOR_SUBTEXT = Color3.fromRGB(150, 150, 158)
local COLOR_ACCENT = Color3.fromRGB(255, 255, 255)

local function create(className, props)
	local inst = Instance.new(className)
	for prop, value in pairs(props) do
		inst[prop] = value
	end
	return inst
end

local function isRagdollState(state)
	return state == Enum.HumanoidStateType.Physics
		or state == Enum.HumanoidStateType.Ragdoll
		or state == Enum.HumanoidStateType.FallingDown
end

local function getAcidController()
	return AcidRedirect.Controller or global.__AcidRedirectController
end

local function isAcidRedirecting()
	if not AcidRedirect.Enabled then
		return false
	end

	local controller = getAcidController()
	if typeof(controller) ~= "table" then
		return false
	end

	if typeof(controller.IsRedirecting) == "function" then
		local ok, result = pcall(controller.IsRedirecting)
		if ok then
			return result == true
		end
	end

	return controller.LastDanger ~= nil
end

local function getMaxUpwardVelocity()
	if not Humanoid then
		return 0
	end

	if Humanoid.UseJumpPower then
		return Humanoid.JumpPower * Settings.JumpVelocityBuffer
	end

	return math.sqrt(2 * Workspace.Gravity * Humanoid.JumpHeight) * Settings.JumpVelocityBuffer
end

local function clampVelocity()
	if not Settings.Enabled then
		return
	end

	if not RootPart or not RootPart.Parent or not Humanoid then
		return
	end

	local velocity = RootPart.AssemblyLinearVelocity
	local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
	local maxHorizontal = Humanoid.WalkSpeed * Settings.HorizontalMultiplier

	if isAcidRedirecting() then
		maxHorizontal = math.max(maxHorizontal, 100)
	end

	local newHorizontal = horizontal
	if horizontal.Magnitude > maxHorizontal then
		newHorizontal = horizontal.Magnitude > 0 and horizontal.Unit * maxHorizontal or Vector3.zero
	end

	local maxUpward = getMaxUpwardVelocity()
	local minDownward = -math.huge

	if ragdolled then
		if isAcidRedirecting() then
			maxUpward = math.max(maxUpward, 36)
		else
			maxUpward = math.min(maxUpward, Settings.RagdollMaxUpward)
		end

		minDownward = Settings.RagdollMaxDownward
	end

	local newVelocity = Vector3.new(
		newHorizontal.X,
		math.clamp(velocity.Y, minDownward, maxUpward),
		newHorizontal.Z
	)

	if (newVelocity - velocity).Magnitude > 0.01 then
		RootPart.AssemblyLinearVelocity = newVelocity
	end

	local angular = RootPart.AssemblyAngularVelocity
	if angular.Magnitude > Settings.MaxAngularSpeed then
		RootPart.AssemblyAngularVelocity = angular * Settings.AngularDamping
	end
end

local function teardownCharacter()
	for _, conn in ipairs(characterConnections) do
		pcall(function()
			conn:Disconnect()
		end)
	end

	characterConnections = {}
	Character, Humanoid, RootPart = nil, nil, nil
	ragdolled = false
end

local function setupCharacter(character)
	teardownCharacter()

	local humanoid = character:WaitForChild("Humanoid", 10)
	local rootPart = character:WaitForChild("HumanoidRootPart", 10)

	if not humanoid or not rootPart then
		return
	end

	Character = character
	Humanoid = humanoid
	RootPart = rootPart
	ragdolled = isRagdollState(humanoid:GetState())

	table.insert(characterConnections, rootPart:GetPropertyChangedSignal("AssemblyLinearVelocity"):Connect(clampVelocity))
	table.insert(characterConnections, rootPart:GetPropertyChangedSignal("AssemblyAngularVelocity"):Connect(clampVelocity))

	table.insert(characterConnections, humanoid.StateChanged:Connect(function(_, newState)
		ragdolled = isRagdollState(newState)
		clampVelocity()
	end))

	table.insert(characterConnections, character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			teardownCharacter()
		end
	end))
end

if LocalPlayer.Character then
	setupCharacter(LocalPlayer.Character)
end

table.insert(MainConnections, LocalPlayer.CharacterAdded:Connect(setupCharacter))
table.insert(MainConnections, RunService.Heartbeat:Connect(clampVelocity))

local gui = create("ScreenGui", {
	Name = "AntiFlingGui",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = PlayerGui,
})

local notifications = create("Frame", {
	Name = "Notifications",
	Parent = gui,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -18, 0, 18),
	Size = UDim2.fromOffset(260, 330),
	BackgroundTransparency = 1,
})

create("UIListLayout", {
	Parent = notifications,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 8),
	HorizontalAlignment = Enum.HorizontalAlignment.Right,
})

local notifyIndex = 0

local function notify(titleText, bodyText, duration)
	notifyIndex += 1

	local toast = create("CanvasGroup", {
		Name = "Toast",
		Parent = notifications,
		LayoutOrder = -notifyIndex,
		Size = UDim2.fromOffset(260, 72),
		BackgroundColor3 = COLOR_PANEL,
		BorderSizePixel = 0,
		GroupTransparency = 1,
	})

	create("UICorner", { Parent = toast, CornerRadius = UDim.new(0, 12) })
	create("UIStroke", { Parent = toast, Color = COLOR_BORDER, Thickness = 1 })

	create("TextLabel", {
		Parent = toast,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 10),
		Size = UDim2.new(1, -28, 0, 16),
		Font = Enum.Font.GothamBold,
		Text = tostring(titleText),
		TextColor3 = COLOR_TEXT,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	create("TextLabel", {
		Parent = toast,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 30),
		Size = UDim2.new(1, -28, 0, 32),
		Font = Enum.Font.Gotham,
		Text = tostring(bodyText),
		TextColor3 = COLOR_SUBTEXT,
		TextSize = 11,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	})

	TweenService:Create(toast, TweenInfo.new(0.18), { GroupTransparency = 0 }):Play()

	task.delay(duration or 3, function()
		if not toast.Parent then
			return
		end

		local tween = TweenService:Create(toast, TweenInfo.new(0.16), { GroupTransparency = 1 })
		tween:Play()
		tween.Completed:Connect(function()
			if toast.Parent then
				toast:Destroy()
			end
		end)
	end)
end

local function loadRemoteChunk(url)
	local httpOk, source = pcall(function()
		return game:HttpGet(url)
	end)

	if not httpOk then
		return nil, tostring(source)
	end

	if typeof(source) ~= "string" or source == "" then
		return nil, "empty source returned from " .. tostring(url)
	end

	local chunk, compileError = loadstring(source)
	if not chunk then
		return nil, compileError or "loadstring failed"
	end

	return chunk, nil
end

local function checkTrajectoryApi()
	local chunk, loadError = loadRemoteChunk(TRAJECTORY_API_URL)
	if not chunk then
		return false, loadError, nil
	end

	local ok, predictorOrError = pcall(chunk)
	if not ok then
		return false, predictorOrError, nil
	end

	if typeof(predictorOrError) ~= "function" then
		return false, "Trajectory API did not return a function", nil
	end

	local predictOk, _, _, _, predictionData = pcall(
		predictorOrError,
		LocalPlayer,
		{
			MaxTime = 0.25,
			TimeStep = 1 / 60,
			CastMode = "Sphere",
			CastRadius = 1.65,
			DrawArc = false,
		}
	)

	if not predictOk then
		return false, predictionData, nil
	end

	if typeof(predictionData) ~= "table" then
		return false, "Trajectory API returned no prediction table", nil
	end

	return true, nil, predictorOrError
end

local acidStatusLabel
local acidToggleSetState

local function setAcidStatus(text, active)
	if acidStatusLabel then
		acidStatusLabel.Text = text
		acidStatusLabel.TextColor3 = active and COLOR_TEXT or COLOR_SUBTEXT
	end
end

local function stopAcidRedirect()
	AcidRedirect.LoadToken += 1

	local controller = AcidRedirect.Controller or global.__AcidRedirectController

	if controller then
		if typeof(controller.HideArc) == "function" then
			pcall(controller.HideArc)
		end

		if typeof(controller.Destroy) == "function" then
			pcall(controller.Destroy)
		elseif typeof(controller.Stop) == "function" then
			pcall(controller.Stop)
		end
	end

	if global.__AcidRedirectController == controller then
		global.__AcidRedirectController = nil
	end

	AcidRedirect.Enabled = false
	AcidRedirect.Loading = false
	AcidRedirect.Loaded = false
	AcidRedirect.Controller = nil
	AcidRedirect.Predictor = nil
	AcidRedirect.LastError = nil

	setAcidStatus("Disabled", false)
	notify("Acid-Redirect", "Stopped.")
end

local function startAcidRedirect()
	if AcidRedirect.Loaded then
		local controller = AcidRedirect.Controller or global.__AcidRedirectController

		if controller and typeof(controller.Start) == "function" then
			pcall(controller.Start)
		end

		if controller and typeof(controller.ShowArc) == "function" then
			pcall(controller.ShowArc)
		end

		AcidRedirect.Enabled = true
		setAcidStatus("Active", true)
		notify("Acid-Redirect", "Already active.")
		return
	end

	if AcidRedirect.Loading then
		notify("Acid-Redirect", "Still loading.")
		return
	end

	AcidRedirect.Enabled = true
	AcidRedirect.Loading = true
	AcidRedirect.LoadToken += 1
	AcidRedirect.LastError = nil

	local loadToken = AcidRedirect.LoadToken

	setAcidStatus("Loading APIs...", true)
	notify("Acid-Redirect", "Checking trajectory and redirect APIs.")

	task.spawn(function()
		local trajectoryOk, trajectoryError, predictor = checkTrajectoryApi()

		if loadToken ~= AcidRedirect.LoadToken or not AcidRedirect.Enabled then
			return
		end

		if not trajectoryOk then
			AcidRedirect.Enabled = false
			AcidRedirect.Loading = false
			AcidRedirect.LastError = tostring(trajectoryError)
			setAcidStatus("Trajectory failed", false)

			if acidToggleSetState then
				acidToggleSetState(false, true)
			end

			notify("Acid-Redirect", "Trajectory API failed: " .. AcidRedirect.LastError, 5)
			return
		end

		AcidRedirect.Predictor = predictor

		local redirectChunk, redirectError = loadRemoteChunk(ACID_REDIRECT_API_URL)

		if loadToken ~= AcidRedirect.LoadToken or not AcidRedirect.Enabled then
			return
		end

		if not redirectChunk then
			AcidRedirect.Enabled = false
			AcidRedirect.Loading = false
			AcidRedirect.LastError = tostring(redirectError)
			setAcidStatus("Redirect failed", false)

			if acidToggleSetState then
				acidToggleSetState(false, true)
			end

			notify("Acid-Redirect", "Redirect API failed: " .. AcidRedirect.LastError, 5)
			return
		end

		local ok, resultOrError = pcall(redirectChunk, {
			PredictPlayerLanding = predictor,
			ShowTrajectoryArc = true,
			Notify = function(titleText, bodyText, duration)
				notify(titleText, bodyText, duration)
			end,
			Config = {
				ShowTrajectoryArc = true,
				ClearArcWhenIdle = true,
				EnableKeywordHazardDetection = true,
				EnableBroadHazardScan = true,
				EnableSlidePrediction = true,
				EnableRagdollSlidePrediction = true,
				EnableStandingSlidePrediction = false,
				EnableStandingVelocitySlidePrediction = false,
			},
		})

		if loadToken ~= AcidRedirect.LoadToken or not AcidRedirect.Enabled then
			return
		end

		if not ok then
			AcidRedirect.Enabled = false
			AcidRedirect.Loading = false
			AcidRedirect.LastError = tostring(resultOrError)
			setAcidStatus("Runtime failed", false)

			if acidToggleSetState then
				acidToggleSetState(false, true)
			end

			notify("Acid-Redirect", "Runtime failed: " .. AcidRedirect.LastError, 5)
			return
		end

		local controller = typeof(resultOrError) == "table" and resultOrError or global.__AcidRedirectController

		if typeof(controller) ~= "table" then
			AcidRedirect.Enabled = false
			AcidRedirect.Loading = false
			AcidRedirect.LastError = "Redirect API did not return a controller"
			setAcidStatus("No controller", false)

			if acidToggleSetState then
				acidToggleSetState(false, true)
			end

			notify("Acid-Redirect", AcidRedirect.LastError, 5)
			return
		end

		if typeof(controller.SetPredictor) == "function" then
			pcall(controller.SetPredictor, predictor)
		end

		if typeof(controller.ShowArc) == "function" then
			pcall(controller.ShowArc)
		end

		AcidRedirect.Loading = false
		AcidRedirect.Loaded = true
		AcidRedirect.Controller = controller

		setAcidStatus("Active", true)
		notify("Acid-Redirect", "Active. Hazard detection and redirect are running.")
	end)
end

local toggleButton = create("TextButton", {
	Name = "ToggleButton",
	Parent = gui,
	Size = UDim2.fromOffset(46, 46),
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 16, 0.5, 0),
	BackgroundColor3 = COLOR_PANEL,
	Text = "AF",
	Font = Enum.Font.GothamBold,
	TextSize = 14,
	TextColor3 = COLOR_TEXT,
	AutoButtonColor = false,
	BorderSizePixel = 0,
})

create("UICorner", { Parent = toggleButton, CornerRadius = UDim.new(1, 0) })
create("UIStroke", { Parent = toggleButton, Color = COLOR_BORDER, Thickness = 1 })

local panel = create("CanvasGroup", {
	Name = "Panel",
	Parent = gui,
	Size = UDim2.fromOffset(300, 436),
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 72, 0.5, 0),
	BackgroundColor3 = COLOR_BG,
	BorderSizePixel = 0,
	Visible = false,
	GroupTransparency = 1,
})

create("UICorner", { Parent = panel, CornerRadius = UDim.new(0, 14) })
create("UIStroke", { Parent = panel, Color = COLOR_BORDER, Thickness = 1 })

local header = create("Frame", {
	Parent = panel,
	Size = UDim2.new(1, 0, 0, 44),
	BackgroundTransparency = 1,
	Active = true,
})

create("TextLabel", {
	Parent = header,
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(16, 6),
	Size = UDim2.new(1, -70, 0, 16),
	Font = Enum.Font.GothamBold,
	Text = "ANTI-FLING",
	TextColor3 = COLOR_TEXT,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
})

local statusLabel = create("TextLabel", {
	Parent = header,
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(16, 23),
	Size = UDim2.new(1, -70, 0, 14),
	Font = Enum.Font.Gotham,
	Text = "Protection Disabled",
	TextColor3 = COLOR_SUBTEXT,
	TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Left,
})

local function createToggle(parent, initial, onChanged)
	local track = create("Frame", {
		Parent = parent,
		Size = UDim2.fromOffset(38, 20),
		BackgroundColor3 = COLOR_FIELD,
		BorderSizePixel = 0,
	})

	create("UICorner", { Parent = track, CornerRadius = UDim.new(1, 0) })
	create("UIStroke", { Parent = track, Color = COLOR_BORDER, Thickness = 1 })

	local knob = create("Frame", {
		Parent = track,
		Size = UDim2.fromOffset(16, 16),
		Position = initial and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8),
		BackgroundColor3 = initial and COLOR_ACCENT or COLOR_SUBTEXT,
		BorderSizePixel = 0,
	})

	create("UICorner", { Parent = knob, CornerRadius = UDim.new(1, 0) })

	local hitbox = create("TextButton", {
		Parent = track,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
	})

	local state = initial

	local function setState(nextState, skipCallback)
		state = nextState

		TweenService:Create(knob, TweenInfo.new(0.15), {
			Position = state and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8),
			BackgroundColor3 = state and COLOR_ACCENT or COLOR_SUBTEXT,
		}):Play()

		if not skipCallback then
			onChanged(state)
		end
	end

	hitbox.MouseButton1Click:Connect(function()
		setState(not state, false)
	end)

	return track, setState
end

local masterToggle = createToggle(header, Settings.Enabled, function(state)
	Settings.Enabled = state
	statusLabel.Text = state and "Protection Active" or "Protection Disabled"
	statusLabel.TextColor3 = state and COLOR_TEXT or COLOR_SUBTEXT
	notify("Anti-Fling", state and "Protection enabled." or "Protection disabled.")
end)

masterToggle.AnchorPoint = Vector2.new(1, 0.5)
masterToggle.Position = UDim2.new(1, -16, 0.5, 0)

local content = create("Frame", {
	Parent = panel,
	Position = UDim2.fromOffset(16, 58),
	Size = UDim2.new(1, -32, 1, -72),
	BackgroundTransparency = 1,
})

local function buildToggleRow(y, label, sub, initial, callback)
	local row = create("Frame", {
		Parent = content,
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.new(1, 0, 0, 38),
		BackgroundTransparency = 1,
	})

	create("TextLabel", {
		Parent = row,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 1),
		Size = UDim2.new(1, -54, 0, 16),
		Font = Enum.Font.GothamBold,
		Text = label,
		TextColor3 = COLOR_TEXT,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	local status = create("TextLabel", {
		Parent = row,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 20),
		Size = UDim2.new(1, -54, 0, 14),
		Font = Enum.Font.Gotham,
		Text = sub,
		TextColor3 = COLOR_SUBTEXT,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	local toggle, setToggle = createToggle(row, initial, callback)
	toggle.AnchorPoint = Vector2.new(1, 0.5)
	toggle.Position = UDim2.new(1, 0, 0.5, 0)

	return status, setToggle
end

local function buildNumberRow(y, label, key, minValue, maxValue)
	local row = create("Frame", {
		Parent = content,
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
	})

	create("TextLabel", {
		Parent = row,
		BackgroundTransparency = 1,
		Size = UDim2.new(0.58, 0, 1, 0),
		Font = Enum.Font.Gotham,
		Text = label,
		TextColor3 = COLOR_SUBTEXT,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	local box = create("TextBox", {
		Parent = row,
		Position = UDim2.new(0.58, 8, 0, 0),
		Size = UDim2.new(0.42, -8, 1, 0),
		BackgroundColor3 = COLOR_FIELD,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium,
		Text = tostring(Settings[key]),
		TextColor3 = COLOR_TEXT,
		TextSize = 12,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	create("UICorner", { Parent = box, CornerRadius = UDim.new(0, 8) })

	box.FocusLost:Connect(function()
		local n = tonumber(box.Text)

		if n then
			n = math.clamp(n, minValue, maxValue)
			Settings[key] = n
			box.Text = tostring(n)
		else
			box.Text = tostring(Settings[key])
		end
	end)

	return box
end

acidStatusLabel, acidToggleSetState = buildToggleRow(0, "Acid-Redirect", "Disabled", false, function(state)
	if state then
		startAcidRedirect()
	else
		stopAcidRedirect()
	end
end)

local fields = {
	HorizontalMultiplier = buildNumberRow(48, "Horizontal Multiplier", "HorizontalMultiplier", 0, 5),
	JumpVelocityBuffer = buildNumberRow(92, "Jump Velocity Buffer", "JumpVelocityBuffer", 0.1, 10),
	RagdollMaxUpward = buildNumberRow(136, "Ragdoll Max Upward", "RagdollMaxUpward", 0, 50),
	RagdollMaxDownward = buildNumberRow(180, "Ragdoll Max Downward", "RagdollMaxDownward", -2000, 0),
	MaxAngularSpeed = buildNumberRow(224, "Max Angular Speed", "MaxAngularSpeed", 0, 50),
	AngularDamping = buildNumberRow(268, "Angular Damping", "AngularDamping", 0, 1),
}

local resetButton = create("TextButton", {
	Parent = content,
	Position = UDim2.fromOffset(0, 316),
	Size = UDim2.new(1, 0, 0, 32),
	BackgroundColor3 = COLOR_FIELD,
	BorderSizePixel = 0,
	Text = "RESET TO DEFAULTS",
	Font = Enum.Font.GothamBold,
	TextSize = 11,
	TextColor3 = COLOR_SUBTEXT,
	AutoButtonColor = false,
})

create("UICorner", { Parent = resetButton, CornerRadius = UDim.new(0, 8) })
create("UIStroke", { Parent = resetButton, Color = COLOR_BORDER, Thickness = 1 })

resetButton.MouseButton1Click:Connect(function()
	for key, value in pairs(DEFAULTS) do
		Settings[key] = value
		if fields[key] then
			fields[key].Text = tostring(value)
		end
	end

	notify("Anti-Fling", "Settings reset to defaults.")
end)

local panelOpen = false

local function openPanel()
	panel.Visible = true
	panelOpen = true
	TweenService:Create(panel, TweenInfo.new(0.18), { GroupTransparency = 0 }):Play()
end

local function closePanel()
	panelOpen = false
	local tween = TweenService:Create(panel, TweenInfo.new(0.15), { GroupTransparency = 1 })
	tween:Play()
	tween.Completed:Connect(function()
		if not panelOpen then
			panel.Visible = false
		end
	end)
end

toggleButton.MouseButton1Click:Connect(function()
	if panelOpen then
		closePanel()
	else
		openPanel()
	end
end)

local dragging = false
local dragInput, dragStart, startPos

header.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPos = panel.Position

		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
			end
		end)
	end
end)

header.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		dragInput = input
	end
end)

table.insert(MainConnections, UserInputService.InputChanged:Connect(function(input)
	if input == dragInput and dragging then
		local delta = input.Position - dragStart

		panel.Position = UDim2.new(
			startPos.X.Scale,
			startPos.X.Offset + delta.X,
			startPos.Y.Scale,
			startPos.Y.Offset + delta.Y
		)
	end
end))

global.__AntiFlingGuiController = {
	Destroy = function()
		pcall(stopAcidRedirect)

		for _, conn in ipairs(MainConnections) do
			pcall(function()
				conn:Disconnect()
			end)
		end

		MainConnections = {}
		teardownCharacter()

		if gui and gui.Parent then
			gui:Destroy()
		end
	end,
}

notify("Safety GUI", "Loaded. Anti-Fling is off; Acid-Redirect is ready. Latest update: 7:25 PM")
notify("Warning", "This script has not been fully anti-cheat tested to CFE guidelines. Use with caution.", 6)
