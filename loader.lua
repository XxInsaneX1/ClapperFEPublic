--------------------------------------------------------------------------
-- AntiFling Loader / GUI rewritten
-- Luau Roblox client executor
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
local characterConnections = {}
local ragdolled = false

local COLOR_BG = Color3.fromRGB(14, 14, 16)
local COLOR_PANEL = Color3.fromRGB(18, 18, 21)
local COLOR_FIELD = Color3.fromRGB(26, 26, 30)
local COLOR_HOVER = Color3.fromRGB(34, 34, 39)
local COLOR_BORDER = Color3.fromRGB(44, 44, 50)
local COLOR_BRIGHT = Color3.fromRGB(90, 90, 102)
local COLOR_TEXT = Color3.fromRGB(235, 235, 238)
local COLOR_SUB = Color3.fromRGB(150, 150, 160)
local COLOR_ACCENT = Color3.fromRGB(255, 255, 255)

local function create(className, props)
	local inst = Instance.new(className)
	for k, v in pairs(props or {}) do
		inst[k] = v
	end
	return inst
end

local function disconnectAll(list)
	for _, c in ipairs(list) do
		pcall(function()
			c:Disconnect()
		end)
	end
	table.clear(list)
end

local function sanitizeNumber(v, minV, maxV)
	return math.clamp(v, minV, maxV)
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

	return controller.Enabled == true and controller.LastDanger ~= nil
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

local function getRedirectHorizontalAllowance()
	local controller = getAcidController()
	local fallback = 100

	if typeof(controller) == "table"
		and typeof(controller.Config) == "table"
		and typeof(controller.Config.RedirectMaxHorizontalSpeed) == "number" then
		return controller.Config.RedirectMaxHorizontalSpeed + 8
	end

	return fallback
end

local function getRedirectUpwardAllowance()
	local controller = getAcidController()
	local fallback = 36

	if typeof(controller) == "table"
		and typeof(controller.Config) == "table"
		and typeof(controller.Config.RedirectLift) == "number" then
		return controller.Config.RedirectLift + 12
	end

	return fallback
end

local function clampVelocity()
	if not Settings.Enabled then
		return
	end

	if not RootPart or not RootPart.Parent or not Humanoid or not Humanoid.Parent then
		return
	end

	local velocity = RootPart.AssemblyLinearVelocity
	local angular = RootPart.AssemblyAngularVelocity
	local redirecting = isAcidRedirecting()

	local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
	local maxHorizontal = Humanoid.WalkSpeed * Settings.HorizontalMultiplier

	if redirecting then
		maxHorizontal = math.max(maxHorizontal, getRedirectHorizontalAllowance())
	end

	local newHorizontal = horizontal
	if horizontal.Magnitude > maxHorizontal then
		newHorizontal = horizontal.Magnitude > 0 and horizontal.Unit * maxHorizontal or Vector3.zero
	end

	local maxUpward = getMaxUpwardVelocity()
	local minDownward = -math.huge

	if ragdolled then
		if redirecting then
			maxUpward = math.max(maxUpward, getRedirectUpwardAllowance())
		else
			maxUpward = math.min(maxUpward, Settings.RagdollMaxUpward)
		end

		minDownward = Settings.RagdollMaxDownward
	end

	local newY = math.clamp(velocity.Y, minDownward, maxUpward)
	local newVelocity = Vector3.new(newHorizontal.X, newY, newHorizontal.Z)

	if (newVelocity - velocity).Magnitude > 0.01 then
		RootPart.AssemblyLinearVelocity = newVelocity
	end

	if angular.Magnitude > Settings.MaxAngularSpeed then
		RootPart.AssemblyAngularVelocity = angular * Settings.AngularDamping
	end
end

local function teardownCharacter()
	disconnectAll(characterConnections)
	Character = nil
	Humanoid = nil
	RootPart = nil
	ragdolled = false
end

local function setupCharacter(character)
	teardownCharacter()

	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 8)
	local root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 8)

	if not humanoid or not root then
		return
	end

	Character = character
	Humanoid = humanoid
	RootPart = root
	ragdolled = isRagdollState(humanoid:GetState())

	table.insert(characterConnections, humanoid.StateChanged:Connect(function(_, newState)
		ragdolled = isRagdollState(newState)
		clampVelocity()
	end))

	table.insert(characterConnections, root:GetPropertyChangedSignal("AssemblyLinearVelocity"):Connect(clampVelocity))
	table.insert(characterConnections, root:GetPropertyChangedSignal("AssemblyAngularVelocity"):Connect(clampVelocity))

	table.insert(characterConnections, character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			teardownCharacter()
		end
	end))
end

if LocalPlayer.Character then
	task.spawn(setupCharacter, LocalPlayer.Character)
end

table.insert(MainConnections, LocalPlayer.CharacterAdded:Connect(function(character)
	task.spawn(setupCharacter, character)
end))

table.insert(MainConnections, RunService.Heartbeat:Connect(clampVelocity))

--------------------------------------------------------------------------
-- GUI
--------------------------------------------------------------------------

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
	Size = UDim2.fromOffset(280, 360),
	BackgroundTransparency = 1,
})

create("UIListLayout", {
	Parent = notifications,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 8),
	HorizontalAlignment = Enum.HorizontalAlignment.Right,
	VerticalAlignment = Enum.VerticalAlignment.Top,
})

local toastOrder = 0

local function notify(title, body, duration)
	toastOrder -= 1

	local toast = create("CanvasGroup", {
		Parent = notifications,
		LayoutOrder = toastOrder,
		Size = UDim2.fromOffset(280, 74),
		BackgroundColor3 = COLOR_PANEL,
		BorderSizePixel = 0,
		GroupTransparency = 1,
	})

	create("UICorner", { Parent = toast, CornerRadius = UDim.new(0, 12) })
	create("UIStroke", { Parent = toast, Color = COLOR_BORDER, Thickness = 1 })

	create("TextLabel", {
		Parent = toast,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 9),
		Size = UDim2.new(1, -28, 0, 18),
		Font = Enum.Font.GothamBold,
		Text = tostring(title),
		TextColor3 = COLOR_TEXT,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	create("TextLabel", {
		Parent = toast,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 30),
		Size = UDim2.new(1, -28, 0, 34),
		Font = Enum.Font.Gotham,
		Text = tostring(body),
		TextColor3 = COLOR_SUB,
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

		local tween = TweenService:Create(toast, TweenInfo.new(0.18), { GroupTransparency = 1 })
		tween:Play()
		tween.Completed:Once(function()
			if toast.Parent then
				toast:Destroy()
			end
		end)
	end)
end

local function tweenButton(obj, hover)
	TweenService:Create(obj, TweenInfo.new(0.12), {
		BackgroundColor3 = hover and COLOR_HOVER or COLOR_FIELD,
	}):Play()
end

local toggleButton = create("TextButton", {
	Parent = gui,
	Size = UDim2.fromOffset(46, 46),
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 16, 0.5, 0),
	BackgroundColor3 = COLOR_PANEL,
	BorderSizePixel = 0,
	Text = "AF",
	Font = Enum.Font.GothamBold,
	TextSize = 14,
	TextColor3 = COLOR_TEXT,
	AutoButtonColor = false,
})

create("UICorner", { Parent = toggleButton, CornerRadius = UDim.new(1, 0) })
create("UIStroke", { Parent = toggleButton, Color = COLOR_BORDER, Thickness = 1 })

local panel = create("CanvasGroup", {
	Parent = gui,
	Size = UDim2.fromOffset(310, 438),
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
	Size = UDim2.new(1, 0, 0, 50),
	BackgroundTransparency = 1,
	Active = true,
})

create("TextLabel", {
	Parent = header,
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(16, 8),
	Size = UDim2.new(1, -84, 0, 18),
	Font = Enum.Font.GothamBold,
	Text = "ANTI-FLING",
	TextColor3 = COLOR_TEXT,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
})

local statusLabel = create("TextLabel", {
	Parent = header,
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(16, 27),
	Size = UDim2.new(1, -84, 0, 16),
	Font = Enum.Font.Gotham,
	Text = "Protection Disabled",
	TextColor3 = COLOR_SUB,
	TextSize = 11,
	TextXAlignment = Enum.TextXAlignment.Left,
})

create("Frame", {
	Parent = panel,
	Position = UDim2.fromOffset(16, 50),
	Size = UDim2.new(1, -32, 0, 1),
	BackgroundColor3 = COLOR_BORDER,
	BorderSizePixel = 0,
})

local body = create("Frame", {
	Parent = panel,
	Position = UDim2.fromOffset(16, 66),
	Size = UDim2.new(1, -32, 1, -82),
	BackgroundTransparency = 1,
})

local function makeToggle(parent, initial, callback)
	local track = create("Frame", {
		Parent = parent,
		Size = UDim2.fromOffset(40, 22),
		BackgroundColor3 = COLOR_FIELD,
		BorderSizePixel = 0,
	})

	create("UICorner", { Parent = track, CornerRadius = UDim.new(1, 0) })
	local stroke = create("UIStroke", { Parent = track, Color = initial and COLOR_BRIGHT or COLOR_BORDER, Thickness = 1 })

	local knob = create("Frame", {
		Parent = track,
		Size = UDim2.fromOffset(18, 18),
		Position = initial and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9),
		BackgroundColor3 = initial and COLOR_ACCENT or COLOR_SUB,
		BorderSizePixel = 0,
	})

	create("UICorner", { Parent = knob, CornerRadius = UDim.new(1, 0) })

	local hit = create("TextButton", {
		Parent = track,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
	})

	local state = initial

	local function setState(nextState, silent)
		state = nextState

		TweenService:Create(knob, TweenInfo.new(0.15), {
			Position = state and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9),
			BackgroundColor3 = state and COLOR_ACCENT or COLOR_SUB,
		}):Play()

		TweenService:Create(stroke, TweenInfo.new(0.15), {
			Color = state and COLOR_BRIGHT or COLOR_BORDER,
		}):Play()

		if not silent and callback then
			callback(state)
		end
	end

	hit.MouseButton1Click:Connect(function()
		setState(not state, false)
	end)

	return track, setState
end

local masterToggle = makeToggle(header, Settings.Enabled, function(state)
	Settings.Enabled = state
	statusLabel.Text = state and "Protection Active" or "Protection Disabled"
	statusLabel.TextColor3 = state and COLOR_TEXT or COLOR_SUB
	notify("Anti-Fling", state and "Protection enabled." or "Protection disabled.")
end)

masterToggle.AnchorPoint = Vector2.new(1, 0.5)
masterToggle.Position = UDim2.new(1, -16, 0.5, 0)

local acidStatusLabel
local acidToggleSetState

local function setAcidStatus(text, active)
	if acidStatusLabel then
		acidStatusLabel.Text = text
		acidStatusLabel.TextColor3 = active and COLOR_TEXT or COLOR_SUB
	end
end

local function makeToggleRow(y, label, sub, initial, callback)
	local row = create("Frame", {
		Parent = body,
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.new(1, 0, 0, 42),
		BackgroundTransparency = 1,
	})

	create("TextLabel", {
		Parent = row,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 1),
		Size = UDim2.new(1, -54, 0, 18),
		Font = Enum.Font.GothamBold,
		Text = label,
		TextColor3 = COLOR_TEXT,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	local status = create("TextLabel", {
		Parent = row,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 22),
		Size = UDim2.new(1, -54, 0, 16),
		Font = Enum.Font.Gotham,
		Text = sub,
		TextColor3 = COLOR_SUB,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	local toggle, setter = makeToggle(row, initial, callback)
	toggle.AnchorPoint = Vector2.new(1, 0.5)
	toggle.Position = UDim2.new(1, 0, 0.5, 0)

	return status, setter
end

local function makeNumberRow(y, label, key, minV, maxV)
	local row = create("Frame", {
		Parent = body,
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
		TextColor3 = COLOR_SUB,
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
	create("UIStroke", { Parent = box, Color = COLOR_BORDER, Thickness = 1 })

	box.MouseEnter:Connect(function()
		tweenButton(box, true)
	end)

	box.MouseLeave:Connect(function()
		if not box:IsFocused() then
			tweenButton(box, false)
		end
	end)

	box.FocusLost:Connect(function()
		local n = tonumber(box.Text)
		if n then
			n = sanitizeNumber(n, minV, maxV)
			Settings[key] = n
			box.Text = tostring(n)
		else
			box.Text = tostring(Settings[key])
		end

		tweenButton(box, false)
	end)

	return box
end

--------------------------------------------------------------------------
-- Remote loading
--------------------------------------------------------------------------

local function loadRemoteChunk(url)
	if typeof(game.HttpGet) ~= "function" then
		return nil, "game:HttpGet is unavailable"
	end

	local ok, source = pcall(function()
		return game:HttpGet(url)
	end)

	if not ok then
		return nil, tostring(source)
	end

	if typeof(source) ~= "string" or source == "" then
		return nil, "empty source returned from " .. tostring(url)
	end

	if typeof(loadstring) ~= "function" then
		return nil, "loadstring is unavailable"
	end

	local chunk, compileError = loadstring(source)

	if not chunk then
		return nil, compileError or "loadstring failed"
	end

	return chunk
end

local function checkTrajectoryApi()
	local chunk, err = loadRemoteChunk(TRAJECTORY_API_URL)
	if not chunk then
		return false, err
	end

	local ok, predictor = pcall(chunk)
	if not ok then
		return false, tostring(predictor)
	end

	if typeof(predictor) ~= "function" then
		return false, "Trajectory API did not return a function"
	end

	local results = table.pack(pcall(predictor, LocalPlayer, {
		MaxTime = 0.25,
		TimeStep = 1 / 60,
		CastMode = "Sphere",
		CastRadius = 1.65,
		DrawArc = false,
		ClearArc = false,
	}))

	if not results[1] then
		return false, tostring(results[2])
	end

	if typeof(results[5]) ~= "table" then
		return false, "Trajectory API returned no prediction table"
	end

	return true, nil, predictor
end

local function stopAcidRedirect()
	AcidRedirect.LoadToken += 1

	local controller = getAcidController()

	if typeof(controller) == "table" then
		if typeof(controller.HideArc) == "function" then
			pcall(controller.HideArc)
		elseif typeof(controller.ClearArc) == "function" then
			pcall(controller.ClearArc)
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
		local controller = getAcidController()

		if typeof(controller) == "table" then
			if typeof(controller.Start) == "function" then
				pcall(controller.Start)
			end

			if typeof(controller.ShowArc) == "function" then
				pcall(controller.ShowArc)
			end
		end

		AcidRedirect.Enabled = true
		setAcidStatus("Active", true)
		notify("Acid-Redirect", "Already loaded and active.")
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

	local token = AcidRedirect.LoadToken

	setAcidStatus("Loading APIs...", true)
	notify("Acid-Redirect", "Checking trajectory and redirect APIs.")

	task.spawn(function()
		local trajectoryOk, trajectoryErr, predictor = checkTrajectoryApi()

		if token ~= AcidRedirect.LoadToken or not AcidRedirect.Enabled then
			return
		end

		if not trajectoryOk then
			AcidRedirect.Enabled = false
			AcidRedirect.Loading = false
			AcidRedirect.LastError = tostring(trajectoryErr)

			setAcidStatus("Trajectory failed", false)

			if acidToggleSetState then
				acidToggleSetState(false, true)
			end

			notify("Acid-Redirect", "Trajectory API failed: " .. AcidRedirect.LastError, 5)
			return
		end

		local redirectChunk, redirectErr = loadRemoteChunk(ACID_REDIRECT_API_URL)

		if token ~= AcidRedirect.LoadToken or not AcidRedirect.Enabled then
			return
		end

		if not redirectChunk then
			AcidRedirect.Enabled = false
			AcidRedirect.Loading = false
			AcidRedirect.LastError = tostring(redirectErr)

			setAcidStatus("Redirect failed", false)

			if acidToggleSetState then
				acidToggleSetState(false, true)
			end

			notify("Acid-Redirect", "Redirect API failed: " .. AcidRedirect.LastError, 5)
			return
		end

		local ok, result = pcall(redirectChunk, {
			PredictPlayerLanding = predictor,
			ShowTrajectoryArc = true,
			Notify = notify,
			Config = {
				ShowTrajectoryArc = true,
				DrawSafeTrajectoryArc = true,
				ClearArcWhenIdle = true,

				EnableKeywordHazardDetection = true,
				EnableBroadHazardScan = true,

				EnableSlidePrediction = true,
				EnableRagdollSlidePrediction = true,
				EnableStandingSlidePrediction = false,
				EnableStandingVelocitySlidePrediction = false,
			},
		})

		if token ~= AcidRedirect.LoadToken or not AcidRedirect.Enabled then
			return
		end

		if not ok then
			AcidRedirect.Enabled = false
			AcidRedirect.Loading = false
			AcidRedirect.LastError = tostring(result)

			setAcidStatus("Runtime failed", false)

			if acidToggleSetState then
				acidToggleSetState(false, true)
			end

			notify("Acid-Redirect", "Runtime failed: " .. AcidRedirect.LastError, 5)
			return
		end

		local controller = typeof(result) == "table" and result or global.__AcidRedirectController

		if typeof(controller) ~= "table" then
			AcidRedirect.Enabled = false
			AcidRedirect.Loading = false
			AcidRedirect.Loaded = false
			AcidRedirect.LastError = "Redirect API did not return controller table"

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
		AcidRedirect.Predictor = predictor

		setAcidStatus("Active", true)
		notify("Acid-Redirect", "Active. Trajectory and hazard redirect synced.")
	end)
end

acidStatusLabel, acidToggleSetState = makeToggleRow(0, "Acid-Redirect", "Disabled", AcidRedirect.Enabled, function(state)
	if state then
		startAcidRedirect()
	else
		stopAcidRedirect()
	end
end)

local fields = {}
fields.HorizontalMultiplier = makeNumberRow(54, "Horizontal Multiplier", "HorizontalMultiplier", 0, 5)
fields.JumpVelocityBuffer = makeNumberRow(98, "Jump Velocity Buffer", "JumpVelocityBuffer", 0.1, 10)
fields.RagdollMaxUpward = makeNumberRow(142, "Ragdoll Max Upward", "RagdollMaxUpward", 0, 50)
fields.RagdollMaxDownward = makeNumberRow(186, "Ragdoll Max Downward", "RagdollMaxDownward", -2000, 0)
fields.MaxAngularSpeed = makeNumberRow(230, "Max Angular Speed", "MaxAngularSpeed", 0, 50)
fields.AngularDamping = makeNumberRow(274, "Angular Damping", "AngularDamping", 0, 1)

local resetButton = create("TextButton", {
	Parent = body,
	Position = UDim2.fromOffset(0, 324),
	Size = UDim2.new(1, 0, 0, 34),
	BackgroundColor3 = COLOR_FIELD,
	BorderSizePixel = 0,
	Text = "RESET TO DEFAULTS",
	Font = Enum.Font.GothamBold,
	TextSize = 11,
	TextColor3 = COLOR_SUB,
	AutoButtonColor = false,
})

create("UICorner", { Parent = resetButton, CornerRadius = UDim.new(0, 8) })
create("UIStroke", { Parent = resetButton, Color = COLOR_BORDER, Thickness = 1 })

resetButton.MouseEnter:Connect(function()
	TweenService:Create(resetButton, TweenInfo.new(0.12), {
		BackgroundColor3 = COLOR_HOVER,
		TextColor3 = COLOR_TEXT,
	}):Play()
end)

resetButton.MouseLeave:Connect(function()
	TweenService:Create(resetButton, TweenInfo.new(0.12), {
		BackgroundColor3 = COLOR_FIELD,
		TextColor3 = COLOR_SUB,
	}):Play()
end)

resetButton.MouseButton1Click:Connect(function()
	for k, v in pairs(DEFAULTS) do
		Settings[k] = v
		if fields[k] then
			fields[k].Text = tostring(v)
		end
	end

	notify("Anti-Fling", "Settings reset.")
end)

--------------------------------------------------------------------------
-- Panel open / close / dragging
--------------------------------------------------------------------------

local panelOpen = false

local function openPanel()
	panel.Visible = true
	panelOpen = true
	panel.GroupTransparency = 1

	TweenService:Create(panel, TweenInfo.new(0.18), {
		GroupTransparency = 0,
	}):Play()
end

local function closePanel()
	panelOpen = false

	local tween = TweenService:Create(panel, TweenInfo.new(0.15), {
		GroupTransparency = 1,
	})

	tween:Play()
	tween.Completed:Once(function()
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
local dragInput
local dragStart
local startPos

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
	if dragging and input == dragInput then
		local delta = input.Position - dragStart

		panel.Position = UDim2.new(
			startPos.X.Scale,
			startPos.X.Offset + delta.X,
			startPos.Y.Scale,
			startPos.Y.Offset + delta.Y
		)
	end
end))

--------------------------------------------------------------------------
-- Cleanup
--------------------------------------------------------------------------

global.__AntiFlingGuiController = {
	Destroy = function()
		pcall(stopAcidRedirect)

		disconnectAll(MainConnections)
		teardownCharacter()

		if gui and gui.Parent then
			gui:Destroy()
		end
	end,
}

notify("Safety GUI", "Loaded. Anti-Fling is off; Acid-Redirect is ready.")
notify("Warning", "Client-executor behavior may vary by game and anti-cheat.", 6)
