--------------------------------------------------------------------------
-- AntiFling -- core protection + sleek black settings GUI
-- Synced with AcidRedirect + Trajectory API
-- Updated:
--   - Added manual Velocity Tracers toggle
--   - Tracers use Trajectory API directly
--   - Tracers work everywhere, not only near acid
--   - AcidRedirect no longer auto-draws trajectory arcs
--------------------------------------------------------------------------

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local Workspace        = game:GetService("Workspace")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

local global = if getgenv then getgenv() else _G

if global.__AntiFlingGuiController and typeof(global.__AntiFlingGuiController.Destroy) == "function" then
	pcall(global.__AntiFlingGuiController.Destroy)
end

local MainConnections = {}

local TRAJECTORY_API_URL    = "https://raw.githubusercontent.com/XxInsaneX1/ClapperFEPublic/refs/heads/main/TJFPublicRelease"
local ACID_REDIRECT_API_URL = "https://raw.githubusercontent.com/XxInsaneX1/ClapperFEPublic/refs/heads/main/AcidRedirectAsync"

local DEFAULTS = {
	HorizontalMultiplier = 1,
	JumpVelocityBuffer   = 2,
	RagdollMaxUpward     = 0.1,
	RagdollMaxDownward   = -400,
	MaxAngularSpeed      = 1,
	AngularDamping       = 0.2,
}

local Settings = {
	Enabled              = false,
	HorizontalMultiplier = DEFAULTS.HorizontalMultiplier,
	JumpVelocityBuffer   = DEFAULTS.JumpVelocityBuffer,
	RagdollMaxUpward     = DEFAULTS.RagdollMaxUpward,
	RagdollMaxDownward   = DEFAULTS.RagdollMaxDownward,
	MaxAngularSpeed      = DEFAULTS.MaxAngularSpeed,
	AngularDamping       = DEFAULTS.AngularDamping,
}

local AcidRedirect = {
	Enabled    = false,
	Loading    = false,
	Loaded     = false,
	LoadToken  = 0,
	Controller = nil,
	Predictor  = nil,
	LastError  = nil,
}

local VelocityTracers = {
	Enabled   = false,
	Loading   = false,
	LoadToken = 0,
	Predictor = nil,
	LastError = nil,
	Accum     = 0,
	UpdateRate = 1 / 20,
}

local EPSILON = 0.01

local Character, Humanoid, RootPart
local ragdolled = false
local characterConnections = {}

local function isRagdollState(state)
	return state == Enum.HumanoidStateType.Physics
		or state == Enum.HumanoidStateType.Ragdoll
		or state == Enum.HumanoidStateType.FallingDown
end

local function getAcidController()
	return AcidRedirect.Controller or global.__AcidRedirectController
end

local function isAcidRedirecting()
	local controller = getAcidController()

	if not AcidRedirect.Enabled then return false end
	if typeof(controller) ~= "table" then return false end

	if typeof(controller.IsRedirecting) == "function" then
		local ok, result = pcall(controller.IsRedirecting)
		if ok then return result == true end
	end

	return controller.LastDanger ~= nil
end

local function getMaxUpwardVelocity()
	if not Humanoid then return 0 end

	local jumpVelocity

	if Humanoid.UseJumpPower then
		jumpVelocity = Humanoid.JumpPower
	else
		jumpVelocity = math.sqrt(2 * Workspace.Gravity * Humanoid.JumpHeight)
	end

	return jumpVelocity * Settings.JumpVelocityBuffer
end

local function clampVelocity()
	if not Settings.Enabled then return end
	if not RootPart or not RootPart.Parent or not Humanoid then return end

	local velocity            = RootPart.AssemblyLinearVelocity
	local redirectingFromAcid = isAcidRedirecting()

	local horizontal    = Vector3.new(velocity.X, 0, velocity.Z)
	local maxHorizontal = Humanoid.WalkSpeed * Settings.HorizontalMultiplier

	if redirectingFromAcid then
		-- Expanded boundary limit during redirection saves to prevent anti-fling choke kicks
		maxHorizontal = math.max(maxHorizontal, 115)
	end

	local newHorizontal = horizontal

	if horizontal.Magnitude > maxHorizontal then
		newHorizontal = horizontal.Magnitude > 0
			and horizontal.Unit * maxHorizontal
			or Vector3.zero
	end

	local maxUpward   = getMaxUpwardVelocity()
	local minDownward = -math.huge

	if ragdolled then
		if redirectingFromAcid then
			maxUpward = math.max(maxUpward, 45) -- Scaled limit to support emergency heights
		else
			maxUpward = math.min(maxUpward, Settings.RagdollMaxUpward)
		end

		minDownward = Settings.RagdollMaxDownward
	end

	local y           = math.clamp(velocity.Y, minDownward, maxUpward)
	local newVelocity = Vector3.new(newHorizontal.X, y, newHorizontal.Z)

	if (newVelocity - velocity).Magnitude > EPSILON then
		RootPart.AssemblyLinearVelocity = newVelocity
	end

	local angular = RootPart.AssemblyAngularVelocity
	if angular.Magnitude > Settings.MaxAngularSpeed then
		RootPart.AssemblyAngularVelocity = angular * Settings.AngularDamping
	end
end

local function teardownCharacter()
	for _, conn in ipairs(characterConnections) do
		pcall(function() conn:Disconnect() end)
	end

	table.clear(characterConnections)
	Character, Humanoid, RootPart = nil, nil, nil
	ragdolled = false
end

local function setupCharacter(character)
	teardownCharacter()

	local humanoid = character:WaitForChild("Humanoid")
	local rootPart = character:WaitForChild("HumanoidRootPart")

	Character = character
	Humanoid  = humanoid
	RootPart  = rootPart
	ragdolled = isRagdollState(humanoid:GetState())

	table.insert(characterConnections, humanoid.StateChanged:Connect(function(_, newState)
		ragdolled = isRagdollState(newState)
		clampVelocity()
	end))

	table.insert(characterConnections, character.AncestryChanged:Connect(function(_, parent)
		if not parent then teardownCharacter() end
	end))
end

if LocalPlayer.Character then
	setupCharacter(LocalPlayer.Character)
end

table.insert(MainConnections, LocalPlayer.CharacterAdded:Connect(setupCharacter))
table.insert(MainConnections, RunService.Heartbeat:Connect(clampVelocity))

------------------------------------------------------------------------
-- GUI colors / helpers
------------------------------------------------------------------------

local COLOR_BG      = Color3.fromRGB(14, 14, 16)
local COLOR_PANEL   = Color3.fromRGB(18, 18, 21)
local COLOR_FIELD   = Color3.fromRGB(26, 26, 30)
local COLOR_BORDER  = Color3.fromRGB(38, 38, 43)
local COLOR_TEXT    = Color3.fromRGB(235, 235, 238)
local COLOR_SUBTEXT = Color3.fromRGB(140, 140, 148)
local COLOR_ACCENT  = Color3.fromRGB(255, 255, 255)

local PANEL_WIDTH  = 300
local PANEL_HEIGHT = 486

local function create(className, props)
	local inst = Instance.new(className)

	for prop, value in pairs(props) do
		inst[prop] = value
	end

	return inst
end

local function flash(stroke)
	local original = stroke.Color
	stroke.Color = COLOR_ACCENT
	TweenService:Create(stroke, TweenInfo.new(0.355), { Color = original }):Play()
end

local function sanitize(value, minVal, maxVal)
	return math.clamp(value, minVal, maxVal)
end

local function clearTrajectoryApiArc()
	local folder = Workspace:FindFirstChild("__TrajectoryArcVisuals")
	if folder then
		folder:ClearAllChildren()
	end
end

------------------------------------------------------------------------
-- Screen GUI
------------------------------------------------------------------------

local gui = create("ScreenGui", {
	Name           = "AntiFlingGui",
	ResetOnSpawn   = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent         = PlayerGui,
})

------------------------------------------------------------------------
-- Notification stack
------------------------------------------------------------------------

local notificationStack = create("Frame", {
	Name                   = "Notifications",
	Parent                 = gui,
	AnchorPoint            = Vector2.new(1, 0),
	Position               = UDim2.new(1, -18, 0, 18),
	Size                   = UDim2.fromOffset(250, 320),
	BackgroundTransparency = 1,
})

create("UIListLayout", {
	Parent              = notificationStack,
	SortOrder           = Enum.SortOrder.LayoutOrder,
	Padding             = UDim.new(0, 8),
	HorizontalAlignment = Enum.HorizontalAlignment.Right,
	VerticalAlignment   = Enum.VerticalAlignment.Top,
})

local notificationCount = 0

local function notify(titleText, bodyText, duration)
	notificationCount += 1

	local toast = create("CanvasGroup", {
		Name              = "Toast",
		Parent            = notificationStack,
		LayoutOrder       = -notificationCount,
		Size              = UDim2.fromOffset(250, 68),
		BackgroundColor3  = COLOR_PANEL,
		BorderSizePixel   = 0,
		GroupTransparency = 1,
	})

	create("UICorner", { Parent = toast, CornerRadius = UDim.new(0, 12) })
	create("UIStroke", { Parent = toast, Color = COLOR_BORDER, Thickness = 1 })

	create("TextLabel", {
		Parent                 = toast,
		BackgroundTransparency = 1,
		Position               = UDim2.fromOffset(14, 10),
		Size                   = UDim2.new(1, -28, 0, 16),
		Font                   = Enum.Font.GothamBold,
		Text                   = titleText,
		TextColor3             = COLOR_TEXT,
		TextSize               = 12,
		TextXAlignment         = Enum.TextXAlignment.Left,
		TextTruncate           = Enum.TextTruncate.AtEnd,
	})

	create("TextLabel", {
		Parent                 = toast,
		BackgroundTransparency = 1,
		Position               = UDim2.fromOffset(14, 30),
		Size                   = UDim2.new(1, -28, 0, 28),
		Font                   = Enum.Font.Gotham,
		Text                   = bodyText,
		TextColor3             = COLOR_SUBTEXT,
		TextSize               = 11,
		TextWrapped            = true,
		TextXAlignment         = Enum.TextXAlignment.Left,
		TextYAlignment         = Enum.TextYAlignment.Top,
	})

	TweenService:Create(toast, TweenInfo.new(0.18), { GroupTransparency = 0 }):Play()

	task.delay(duration or 3, function()
		if not toast.Parent then return end

		local fadeTween = TweenService:Create(toast, TweenInfo.new(0.16), { GroupTransparency = 1 })
		fadeTween:Play()

		local conn
		conn = fadeTween.Completed:Connect(function()
			conn:Disconnect()
			if toast.Parent then toast:Destroy() end
		end)
	end)
end

------------------------------------------------------------------------
-- Remote loader
------------------------------------------------------------------------

local function loadRemoteChunk(url)
	local httpOk, source = pcall(function()
		return game:HttpGet(url)
	end)

	if not httpOk then
		return nil, source
	end

	local chunk, compileError = loadstring(source)

	if not chunk then
		return nil, compileError or "loadstring failed"
	end

	return chunk, nil
end

local function loadTrajectoryPredictor()
	local chunk, loadError = loadRemoteChunk(TRAJECTORY_API_URL)
	if not chunk then return nil, loadError end

	local ok, result = pcall(chunk)
	if not ok then return nil, result end

	if typeof(result) ~= "function" then
		return nil, "trajectory API did not return PredictPlayerLanding function"
	end

	return result, nil
end

local function checkTrajectoryApi()
	local predictor, loadError = loadTrajectoryPredictor()
	if not predictor then return false, loadError, nil end

	local predictOk, trajectory, hitPart, hitResult, predictionData = pcall(
		predictor,
		LocalPlayer,
		{
			MaxTime    = 0.25,
			TimeStep   = 1 / 60,
			CastMode   = "Sphere",
			CastRadius = 1.65,
			DrawArc    = false,
			ClearArc   = false,
		}
	)

	if not predictOk then return false, trajectory, nil end

	if typeof(predictionData) ~= "table" then
		return false, "workspace layout verification returned invalid prediction formats", nil
	end

	return true, nil, predictor
end

------------------------------------------------------------------------
-- Velocity tracer lifecycle
------------------------------------------------------------------------

local tracerStatusLabel
local tracerToggleSetState

local function setTracerStatus(text, active)
	if tracerStatusLabel then
		tracerStatusLabel.Text = text
		tracerStatusLabel.TextColor3 = active and COLOR_TEXT or COLOR_SUBTEXT
	end
end

local function stopVelocityTracers()
	VelocityTracers.LoadToken += 1
	VelocityTracers.Enabled = false
	VelocityTracers.Loading = false
	VelocityTracers.Predictor = nil
	VelocityTracers.LastError = nil
	VelocityTracers.Accum = 0

	clearTrajectoryApiArc()
	setTracerStatus("Off", false)
	notify("Velocity Tracers", "Disabled.")
end

local function startVelocityTracers()
	if VelocityTracers.Enabled and VelocityTracers.Predictor then
		setTracerStatus("On", true)
		notify("Velocity Tracers", "Already enabled.")
		return
	end

	if VelocityTracers.Loading then
		notify("Velocity Tracers", "Still loading trajectory API.")
		return
	end

	VelocityTracers.Enabled = true
	VelocityTracers.Loading = true
	VelocityTracers.LoadToken += 1
	VelocityTracers.LastError = nil

	local token = VelocityTracers.LoadToken

	setTracerStatus("Loading API...", true)
	notify("Velocity Tracers", "Loading trajectory visualizer.")

	task.spawn(function()
		local predictor, err = loadTrajectoryPredictor()

		if token ~= VelocityTracers.LoadToken then return end

		if not predictor then
			VelocityTracers.Enabled = false
			VelocityTracers.Loading = false
			VelocityTracers.Predictor = nil
			VelocityTracers.LastError = tostring(err)

			clearTrajectoryApiArc()
			setTracerStatus("API failed", false)

			if tracerToggleSetState then
				tracerToggleSetState(false, true)
			end

			notify("Velocity Tracers", "Failed: " .. VelocityTracers.LastError, 5)
			return
		end

		VelocityTracers.Predictor = predictor
		VelocityTracers.Loading = false
		VelocityTracers.Accum = 999

		setTracerStatus("On", true)
		notify("Velocity Tracers", "Enabled everywhere.")
	end)
end

local function updateVelocityTracers(deltaTime)
	if not VelocityTracers.Enabled then return end
	if VelocityTracers.Loading then return end
	if typeof(VelocityTracers.Predictor) ~= "function" then return end

	VelocityTracers.Accum += deltaTime
	if VelocityTracers.Accum < VelocityTracers.UpdateRate then return end
	VelocityTracers.Accum = 0

	local ok, err = pcall(
		VelocityTracers.Predictor,
		LocalPlayer,
		{
			MaxTime    = 4,
			TimeStep   = 1 / 45,
			CastMode   = "Sphere",
			CastRadius = 1.65,

			DrawArc    = true,
			ClearArc   = true,

			ArcVisualStride = 1,
			ArcThickness    = 0.12,
			ArcTransparency = 0.08,

			RagdollExtraPath      = true,
			RagdollMaxVisualPaths = 2,
			RagdollSideVelocity   = 18,
			RagdollForwardBlend   = 0.35,
		}
	)

	if not ok then
		VelocityTracers.LastError = tostring(err)
	end
end

table.insert(MainConnections, RunService.Heartbeat:Connect(updateVelocityTracers))

------------------------------------------------------------------------
-- AcidRedirect lifecycle
------------------------------------------------------------------------

local acidToggleSetState
local acidStatusLabel

local function setAcidStatus(text, active)
	if acidStatusLabel then
		acidStatusLabel.Text = text
		acidStatusLabel.TextColor3 = active and COLOR_TEXT or COLOR_SUBTEXT
	end
end

local function stopAcidRedirect()
	local controller = AcidRedirect.Controller or global.__AcidRedirectController

	AcidRedirect.LoadToken += 1

	if controller then
		if typeof(controller.HideArc) == "function" then
			pcall(controller.HideArc)
		end

		if typeof(controller.ClearArc) == "function" then
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
	AcidRedirect.Loaded = false
	AcidRedirect.Loading = false
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

		if controller and typeof(controller.HideArc) == "function" then
			pcall(controller.HideArc)
		end

		AcidRedirect.Enabled = true
		setAcidStatus("Active", true)
		notify("Acid-Redirect", "Already active.")
		return
	end

	if AcidRedirect.Loading then
		notify("Acid-Redirect", "Still loading redirect service.")
		return
	end

	AcidRedirect.Enabled = true
	AcidRedirect.Loading = true
	AcidRedirect.LoadToken += 1
	AcidRedirect.LastError = nil

	local loadToken = AcidRedirect.LoadToken

	setAcidStatus("Loading APIs...", true)
	notify("Acid-Redirect", "Checking trajectory tracker and redirect API.")

	task.spawn(function()
		local trajectoryOk, trajectoryError, predictor = checkTrajectoryApi()

		if loadToken ~= AcidRedirect.LoadToken or not AcidRedirect.Enabled then return end

		if not trajectoryOk then
			AcidRedirect.Enabled = false
			AcidRedirect.Loading = false
			AcidRedirect.Predictor = nil
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

		if loadToken ~= AcidRedirect.LoadToken or not AcidRedirect.Enabled then return end

		if not redirectChunk then
			AcidRedirect.Enabled = false
			AcidRedirect.Loading = false
			AcidRedirect.Predictor = nil
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
			ShowTrajectoryArc = false,

			Notify = function(titleText, bodyText, duration)
				notify(titleText, bodyText, duration)
			end,

			Config = {
				ShowTrajectoryArc                     = false,
				ClearArcWhenIdle                      = true,

				EnableKeywordHazardDetection          = true,
				EnableBroadHazardScan                 = true,
				EnableWorkspaceHazardCache            = true,

				EnableSlidePrediction                 = true,
				EnableRagdollSlidePrediction          = true,

				EnableStandingSlidePrediction         = true,
				EnableStandingVelocitySlidePrediction = true,
			},
		})

		if loadToken ~= AcidRedirect.LoadToken or not AcidRedirect.Enabled then return end

		if not ok then
			AcidRedirect.Enabled = false
			AcidRedirect.Loading = false
			AcidRedirect.Predictor = nil
			AcidRedirect.LastError = tostring(resultOrError)

			setAcidStatus("Runtime failed", false)

			if acidToggleSetState then
				acidToggleSetState(false, true)
			end

			notify("Acid-Redirect", "Redirect runtime failed: " .. AcidRedirect.LastError, 5)
			return
		end

		local returnedController = typeof(resultOrError) == "table" and resultOrError or nil
		local controller = returnedController or global.__AcidRedirectController

		if typeof(controller) ~= "table" then
			AcidRedirect.Enabled = false
			AcidRedirect.Loading = false
			AcidRedirect.Loaded = false
			AcidRedirect.Controller = nil
			AcidRedirect.Predictor = nil
			AcidRedirect.LastError = "Redirect API did not return a controller table"

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

		if typeof(controller.HideArc) == "function" then
			pcall(controller.HideArc)
		end

		AcidRedirect.Loading = false
		AcidRedirect.Loaded = true
		AcidRedirect.Controller = controller

		setAcidStatus("Active", true)
		notify("Acid-Redirect", "Active. Hazard redirects are running.")
	end)
end

------------------------------------------------------------------------
-- Toggle widget factory
------------------------------------------------------------------------

local function createToggle(parent, initial, onChanged)
	local track = create("Frame", {
		Parent           = parent,
		Size             = UDim2.fromOffset(38, 20),
		BackgroundColor3 = COLOR_FIELD,
		BorderSizePixel  = 0,
	})

	create("UICorner", { Parent = track, CornerRadius = UDim.new(1, 0) })
	create("UIStroke", { Parent = track, Color = COLOR_BORDER, Thickness = 1 })

	local knob = create("Frame", {
		Parent           = track,
		Size             = UDim2.fromOffset(16, 16),
		Position         = initial and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8),
		BackgroundColor3 = initial and COLOR_ACCENT or COLOR_SUBTEXT,
		BorderSizePixel  = 0,
	})

	create("UICorner", { Parent = knob, CornerRadius = UDim.new(1, 0) })

	local hitbox = create("TextButton", {
		Parent                 = track,
		Size                   = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text                   = "",
		AutoButtonColor        = false,
	})

	local state = initial

	local function setState(nextState, skipCallback)
		state = nextState

		local pos = state and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)

		TweenService:Create(knob, TweenInfo.new(0.15), {
			Position         = pos,
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

------------------------------------------------------------------------
-- GUI layout
------------------------------------------------------------------------

local toggleButton = create("TextButton", {
	Name             = "ToggleButton",
	Parent           = gui,
	Size             = UDim2.fromOffset(46, 46),
	AnchorPoint      = Vector2.new(0, 0.5),
	Position         = UDim2.new(0, 16, 0.5, 0),
	BackgroundColor3 = COLOR_PANEL,
	Text             = "AF",
	Font             = Enum.Font.GothamBold,
	TextSize          = 14,
	TextColor3        = COLOR_TEXT,
	AutoButtonColor   = false,
	BorderSizePixel   = 0,
})

create("UICorner", { Parent = toggleButton, CornerRadius = UDim.new(1, 0) })
create("UIStroke", { Parent = toggleButton, Color = COLOR_BORDER, Thickness = 1 })

toggleButton.MouseEnter:Connect(function()
	TweenService:Create(toggleButton, TweenInfo.new(0.12), { BackgroundColor3 = COLOR_FIELD }):Play()
end)

toggleButton.MouseLeave:Connect(function()
	TweenService:Create(toggleButton, TweenInfo.new(0.12), { BackgroundColor3 = COLOR_PANEL }):Play()
end)

local panel = create("CanvasGroup", {
	Name              = "Panel",
	Parent            = gui,
	Size              = UDim2.fromOffset(PANEL_WIDTH, PANEL_HEIGHT),
	AnchorPoint       = Vector2.new(0, 0.5),
	Position          = UDim2.new(0, 72, 0.5, 0),
	BackgroundColor3  = COLOR_BG,
	BorderSizePixel   = 0,
	Visible           = false,
	GroupTransparency = 1,
})

create("UICorner", { Parent = panel, CornerRadius = UDim.new(0, 14) })
create("UIStroke", { Parent = panel, Color = COLOR_BORDER, Thickness = 1 })

local header = create("Frame", {
	Name                   = "Header",
	Parent                 = panel,
	Size                   = UDim2.new(1, 0, 0, 44),
	BackgroundTransparency = 1,
	Active                 = true,
})

create("TextLabel", {
	Parent                 = header,
	BackgroundTransparency = 1,
	Position               = UDim2.fromOffset(16, 6),
	Size                   = UDim2.new(1, -70, 0, 16),
	Font                   = Enum.Font.GothamBold,
	Text                   = "ANTI-FLING",
	TextColor3             = COLOR_TEXT,
	TextSize               = 13,
	TextXAlignment         = Enum.TextXAlignment.Left,
})

local statusLabel = create("TextLabel", {
	Parent                 = header,
	BackgroundTransparency = 1,
	Position               = UDim2.fromOffset(16, 23),
	Size                   = UDim2.new(1, -70, 0, 14),
	Font                   = Enum.Font.Gotham,
	Text                   = "Protection Disabled",
	TextColor3             = COLOR_SUBTEXT,
	TextSize               = 11,
	TextXAlignment         = Enum.TextXAlignment.Left,
})

create("Frame", {
	Parent           = panel,
	Position         = UDim2.fromOffset(16, 44),
	Size             = UDim2.new(1, -32, 0, 1),
	BackgroundColor3 = COLOR_BORDER,
	BorderSizePixel  = 0,
})

local body = create("Frame", {
	Parent                 = panel,
	Position               = UDim2.fromOffset(0, 53),
	Size                   = UDim2.new(1, 0, 1, -53),
	BackgroundTransparency = 1,
})

local masterToggle = createToggle(header, Settings.Enabled, function(state)
	Settings.Enabled = state
	statusLabel.Text = state and "Protection Active" or "Protection Disabled"
	statusLabel.TextColor3 = state and COLOR_TEXT or COLOR_SUBTEXT
	notify("Anti-Fling", state and "Protection enabled." or "Protection disabled.")
end)

masterToggle.AnchorPoint = Vector2.new(1, 0.5)
masterToggle.Position    = UDim2.new(1, -16, 0.5, 0)

------------------------------------------------------------------------
-- Loader / content
------------------------------------------------------------------------

local loaderContainer = create("Frame", {
	Name                   = "Loader",
	Parent                 = body,
	Size                   = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Visible                = true,
})

local ring = create("Frame", {
	Name                   = "Ring",
	Parent                 = loaderContainer,
	Size                   = UDim2.fromOffset(34, 34),
	AnchorPoint            = Vector2.new(0.5, 0.5),
	Position               = UDim2.fromScale(0.5, 0.5),
	BackgroundTransparency = 1,
})

create("UICorner", { Parent = ring, CornerRadius = UDim.new(1, 0) })

local ringStroke = create("UIStroke", {
	Parent    = ring,
	Color     = COLOR_TEXT,
	Thickness = 3,
})

create("UIGradient", {
	Parent = ringStroke,
	Color = ColorSequence.new(COLOR_TEXT),
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.85, 0.6),
		NumberSequenceKeypoint.new(1, 1),
	}),
})

local spinTween = nil

local function startSpin()
	ring.Rotation = 0
	spinTween = TweenService:Create(
		ring,
		TweenInfo.new(0.9, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1, false),
		{ Rotation = 360 }
	)
	spinTween:Play()
end

local function stopSpin()
	if spinTween then
		spinTween:Cancel()
		spinTween = nil
	end
end

local contentContainer = create("Frame", {
	Name                   = "Content",
	Parent                 = body,
	Size                   = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Visible                = false,
})

create("UIPadding", {
	Parent        = contentContainer,
	PaddingLeft   = UDim.new(0, 16),
	PaddingRight  = UDim.new(0, 16),
	PaddingTop    = UDim.new(0, 14),
	PaddingBottom = UDim.new(0, 14),
})

------------------------------------------------------------------------
-- Row builders
------------------------------------------------------------------------

local function buildToggleRow(parent, yOffset, labelText, subText, initial, onChanged)
	local row = create("Frame", {
		Parent                 = parent,
		Position               = UDim2.fromOffset(0, yOffset),
		Size                   = UDim2.new(1, 0, 0, 38),
		BackgroundTransparency = 1,
	})

	create("TextLabel", {
		Parent                 = row,
		BackgroundTransparency = 1,
		Position               = UDim2.fromOffset(0, 1),
		Size                   = UDim2.new(1, -54, 0, 16),
		Font                   = Enum.Font.GothamBold,
		Text                   = labelText,
		TextColor3             = COLOR_TEXT,
		TextSize               = 12,
		TextXAlignment         = Enum.TextXAlignment.Left,
	})

	local statusLbl = create("TextLabel", {
		Parent                 = row,
		BackgroundTransparency = 1,
		Position               = UDim2.fromOffset(0, 20),
		Size                   = UDim2.new(1, -54, 0, 14),
		Font                   = Enum.Font.Gotham,
		Text                   = subText,
		TextColor3             = COLOR_SUBTEXT,
		TextSize               = 11,
		TextXAlignment         = Enum.TextXAlignment.Left,
	})

	local toggle, setToggle = createToggle(row, initial, onChanged)
	toggle.AnchorPoint = Vector2.new(1, 0.5)
	toggle.Position = UDim2.new(1, 0, 0.5, 0)

	return statusLbl, toggle, setToggle
end

local function buildRow(parent, yOffset, labelText, settingKey, minVal, maxVal)
	local row = create("Frame", {
		Parent                 = parent,
		Position               = UDim2.fromOffset(0, yOffset),
		Size                   = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
	})

	create("TextLabel", {
		Parent                 = row,
		BackgroundTransparency = 1,
		Size                   = UDim2.new(0.58, 0, 1, 0),
		Font                   = Enum.Font.Gotham,
		Text                   = labelText,
		TextColor3             = COLOR_SUBTEXT,
		TextSize               = 12,
		TextXAlignment         = Enum.TextXAlignment.Left,
	})

	local field = create("TextBox", {
		Parent             = row,
		Position           = UDim2.new(0.58, 8, 0, 0),
		Size               = UDim2.new(0.42, -8, 1, 0),
		BackgroundColor3   = COLOR_FIELD,
		BorderSizePixel    = 0,
		Font               = Enum.Font.GothamMedium,
		Text               = tostring(Settings[settingKey]),
		TextColor3         = COLOR_TEXT,
		TextSize           = 12,
		ClearTextOnFocus   = false,
		TextXAlignment     = Enum.TextXAlignment.Center,
	})

	create("UICorner", { Parent = field, CornerRadius = UDim.new(0, 8) })

	local fieldStroke = create("UIStroke", {
		Parent    = field,
		Color     = COLOR_BORDER,
		Thickness = 1,
	})

	field.FocusLost:Connect(function()
		local num = tonumber(field.Text)

		if num then
			num = sanitize(num, minVal, maxVal)
			Settings[settingKey] = num
			field.Text = tostring(num)
			flash(fieldStroke)
		else
			field.Text = tostring(Settings[settingKey])
		end
	end)

	return field
end

------------------------------------------------------------------------
-- Build rows
------------------------------------------------------------------------

local acidToggleTrack
acidStatusLabel, acidToggleTrack, acidToggleSetState = buildToggleRow(
	contentContainer,
	0,
	"Acid-Redirect",
	"Disabled",
	AcidRedirect.Enabled,
	function(state)
		if state then
			startAcidRedirect()
		else
			stopAcidRedirect()
		end
	end
)

local tracerToggleTrack
tracerStatusLabel, tracerToggleTrack, tracerToggleSetState = buildToggleRow(
	contentContainer,
	44,
	"Velocity Tracers",
	"Off",
	VelocityTracers.Enabled,
	function(state)
		if state then
			startVelocityTracers()
		else
			stopVelocityTracers()
		end
	end
)

local horizontalField     = buildRow(contentContainer,  92, "Horizontal Multiplier", "HorizontalMultiplier", 0, 5)
local jumpBufferField     = buildRow(contentContainer, 136, "Jump Velocity Buffer", "JumpVelocityBuffer", 0.1, 10)
local ragdollUpField      = buildRow(contentContainer, 180, "Ragdoll Max Upward", "RagdollMaxUpward", 0, 50)
local ragdollDownField    = buildRow(contentContainer, 224, "Ragdoll Max Downward", "RagdollMaxDownward", -2000, 0)
local angularSpeedField   = buildRow(contentContainer, 268, "Max Angular Speed", "MaxAngularSpeed", 0, 50)
local angularDampingField = buildRow(contentContainer, 312, "Angular Damping", "AngularDamping", 0, 1)

local resetButton = create("TextButton", {
	Parent           = contentContainer,
	Position         = UDim2.fromOffset(0, 362),
	Size             = UDim2.new(1, 0, 0, 32),
	BackgroundColor3 = COLOR_FIELD,
	BorderSizePixel  = 0,
	Text             = "RESET TO DEFAULTS",
	Font             = Enum.Font.GothamBold,
	TextSize          = 11,
	TextColor3        = COLOR_SUBTEXT,
	AutoButtonColor   = false,
})

create("UICorner", { Parent = resetButton, CornerRadius = UDim.new(0, 8) })
create("UIStroke", { Parent = resetButton, Color = COLOR_BORDER, Thickness = 1 })

resetButton.MouseButton1Click:Connect(function()
	for key, value in pairs(DEFAULTS) do
		Settings[key] = value
	end

	horizontalField.Text     = tostring(DEFAULTS.HorizontalMultiplier)
	jumpBufferField.Text     = tostring(DEFAULTS.JumpVelocityBuffer)
	ragdollUpField.Text      = tostring(DEFAULTS.RagdollMaxUpward)
	ragdollDownField.Text    = tostring(DEFAULTS.RagdollMaxDownward)
	angularSpeedField.Text   = tostring(DEFAULTS.MaxAngularSpeed)
	angularDampingField.Text = tostring(DEFAULTS.AngularDamping)

	notify("Anti-Fling", "Settings reset to defaults.")
end)

------------------------------------------------------------------------
-- Panel open / close
------------------------------------------------------------------------

local panelOpen = false
local loaderToken = 0

local function showLoaderThenContent()
	loaderToken += 1
	local thisToken = loaderToken

	loaderContainer.Visible = true
	contentContainer.Visible = false
	startSpin()

	task.delay(0.65, function()
		if thisToken ~= loaderToken then return end

		stopSpin()
		loaderContainer.Visible = false
		contentContainer.Visible = true
	end)
end

local function openPanel()
	panel.Visible = true
	panel.GroupTransparency = 1

	TweenService:Create(panel, TweenInfo.new(0.18), {
		GroupTransparency = 0,
	}):Play()

	showLoaderThenContent()
	panelOpen = true
end

local function closePanel()
	loaderToken += 1
	stopSpin()

	local tween = TweenService:Create(panel, TweenInfo.new(0.15), {
		GroupTransparency = 1,
	})

	tween:Play()

	local conn
	conn = tween.Completed:Connect(function()
		conn:Disconnect()

		if not panelOpen then
			panel.Visible = false
		end
	end)

	panelOpen = false
end

toggleButton.MouseButton1Click:Connect(function()
	if panelOpen then
		closePanel()
	else
		openPanel()
	end
end)

------------------------------------------------------------------------
-- Drag panel
------------------------------------------------------------------------

local dragging = false
local dragStart = nil
local startPos = nil

header.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then

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

table.insert(MainConnections, UserInputService.InputChanged:Connect(function(input)
	if not dragging then return end

	if input.UserInputType ~= Enum.UserInputType.MouseMovement
		and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end

	local delta = input.Position - dragStart

	panel.Position = UDim2.new(
		startPos.X.Scale,
		startPos.X.Offset + delta.X,
		startPos.Y.Scale,
		startPos.Y.Offset + delta.Y
	)
end))

------------------------------------------------------------------------
-- Global controller
------------------------------------------------------------------------

global.__AntiFlingGuiController = {
	Destroy = function()
		pcall(stopAcidRedirect)
		pcall(stopVelocityTracers)

		for _, conn in ipairs(MainConnections) do
			pcall(function()
				conn:Disconnect()
			end)
		end

		table.clear(MainConnections)

		teardownCharacter()
		stopSpin()
		clearTrajectoryApiArc()

		if gui and gui.Parent then
			gui:Destroy()
		end
	end,
}

notify("Safety GUI", "Loaded. Anti-Fling is off; Acid-Redirect and Tracers are ready.")
notify("WARNING", "This GUI has not been fully Anti-Cheat Tested.", 10)
notify("Info", "Latest Release 6/20/2026 12:32 AM Change: Manual global velocity tracers + fixed AcidRedirect.", 99999999999999999)

print("[AntiFling] Loaded with fixed AcidRedirect and manual velocity tracers")
