--[[ File Info
	Author(s): ChiefWildin
	Version: 1.13.0
]]

-- Services

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- Module Declaration

--[=[
	@class AnimNation

	An animation library that enables quick one-shot style animations for most
	instances and properties.

	# Tweens

	AnimNation tweens support all properties that are supported by TweenService,
	as well as tweening Models by CFrame/Scale and tweening
	NumberSequence/ColorSequence values	(given that the target sequence has the
	same number of keypoints).

	# Springs

	AnimNation springs support the following types: number, Vector2, Vector3,
	UDim, UDim2, CFrame, and Color3. These are natively supported by the
	provided Spring class as well.

	# Splines

	AnimNation splines are used in animation for interpolating between a series
	of points in a smoothed curving fashion. They currently only support CFrame
	types and do not yet return AnimChains.
]=]
local AnimNation = {}

-- Dependencies

local AnimChain = require(script:WaitForChild("AnimChain")) ---@module AnimChain
local Spring = require(script:WaitForChild("Spring")) ---@module Spring
local Spline = require(script:WaitForChild("Spline")) ---@module Spline

-- Constants

local ERROR_POLICY: "Warn" | "Error" = if RunService:IsStudio() then "Error" else "Warn"
local BIND_CONNECTION_TYPE: "Heartbeat" | "Stepped" | "RenderStepped" = "Heartbeat"
local SUPPORTED_TYPES = {
	number = true,
	Vector2 = true,
	Vector3 = true,
	UDim2 = true,
	UDim = true,
	CFrame = true,
	Color3 = true,
}
local ZEROS = {
	number = 0,
	Vector2 = Vector2.zero,
	Vector3 = Vector3.zero,
	UDim2 = UDim2.new(),
	UDim = UDim.new(),
	CFrame = CFrame.identity,
	Color3 = Color3.new(),
}

-- Overloads

local StdError = error
local function error(message: string)
	if ERROR_POLICY == "Warn" then
		warn(message .. "\n" .. debug.traceback())
	else
		StdError(message)
	end
end

-- Classes and Types

type Springable = Spring.Springable
export type AnimChain = AnimChain.AnimChain
export type Spring = Spring.Spring
export type Spline = Spline.Spline

--[=[
	@interface SpringInfo
	@within AnimNation
	@field Position Springable?
	@field Velocity number?
	@field Target Springable?
	@field Damper number?
	@field Speed number?
	@field Initial Springable?
	@field Clock (() -> number)?

	A dictionary of spring properties such as {s = 10, d = 0.5}. Can be
	constructed using any keys that you could use to create a Spring object.

	Possible keys:
	```
	Initial = Initial | i
	Speed = Speed | s
	Damper = Damper | d
	Target = Target | t
	Velocity = Velocity | v
	Position = Position | Value | p
	Clock = Clock
	```
]=]
export type SpringInfo = {
	Position: Springable?,
	Value: Springable?,
	p: Springable?,

	Velocity: number?,
	v: number?,

	Target: Springable?,
	t: Springable?,

	Damper: number?,
	d: number?,

	Speed: number?,
	s: number?,

	Initial: Springable?,
	i: Springable?,

	Clock: (() -> number)?,
}

--[=[
	@interface TweenInfoTable
	@within AnimNation
	@field Time number?
	@field EasingStyle Enum.EasingStyle?
	@field EasingDirection Enum.EasingDirection?
	@field RepeatCount number?
	@field Reverses boolean?
	@field DelayTime number?

	TweenInfo can be passed to the tweening functions as either a TweenInfo
	object or a dictionary of the desired parameters. Keys are either the
	TweenInfo parameter name or shortened versions:
	```
	Time = Time | t
	EasingStyle = EasingStyle | Style | s
	EasingDirection = EasingDirection | Direction | d
	RepeatCount = RepeatCount | Repeat | rc
	Reverses = Reverses | Reverse | r
	DelayTime = DelayTime | Delay | dt
	```
]=]
export type TweenInfoTable = {
	Time: number?,
	t: number?,

	EasingStyle: Enum.EasingStyle?,
	Style: Enum.EasingStyle?,
	s: Enum.EasingStyle?,

	EasingDirection: Enum.EasingDirection?,
	Direction: Enum.EasingDirection?,
	d: Enum.EasingDirection?,

	RepeatCount: number?,
	Repeat: number?,
	rc: number?,

	Reverses: boolean?,
	Reverse: boolean?,
	r: boolean?,

	DelayTime: number?,
	Delay: number?,
	dt: number?,

	_skipControlReset: boolean?,
}

-- Global Variables

-- A dictionary that keeps track of custom splines by name.
local SplineDirectory: { [string]: Spline } = {}

-- A dictionary that keeps track of custom springs by name.
local SpringDirectory: { [string]: Spring } = {}

-- A dictionary that keeps track of the internal springs controlling instance
-- properties.
local SpringEvents: { [Instance]: { [string]: Spring } } = {}

-- A dictionary that keeps track of different callbacks bound to groups of
-- springs. The label key references a table containing a table of springs in
-- the first index, and the callback function in the second index.
local SpringBinds: { [string]: {} } = {}

-- A dictionary that keeps track of the last tween played on each instance.
local TweenDirectory: { [Instance]: Tween } = {}

-- A dictionary that keeps track of the states of NumberSequence/ColorSequence
-- values.
local ActiveSequences: { [Instance]: { [string]: { [number]: NumberValue | Color3Value } } } = {}

-- A dictionary that keeps track of any custom tween processes (tweenFromAlpha).
-- Instances are used as keys to a sub-dictionary that maps properties to the
-- ID of the custom tween being used to animate them.
local CustomTweens: { [Instance]: { [string]: number } } = {}

-- The last ID used to identify which custom tween is controlling a property.
local LastCustomTweenId = 0

-- The connection currently handling spring bind callbacks
local BindLoopConnection

-- Objects

-- Private Functions

local function scheduleTweenCleanup(tween: Tween)
	if tween.TweenInfo.Time >= 1e-7 then
		tween.Completed:Wait()
	end
	tween:Destroy()

	-- Clean up if this was the last tween played on the instance, might not be
	-- if another property was changed before this one finished.
	if TweenDirectory[tween.Instance] == tween then
		TweenDirectory[tween.Instance] = nil
	end
end

local function tweenByPivot(
	object: Model,
	tweenInfo: TweenInfo | TweenInfoTable,
	properties: { CFrame: CFrame }
): AnimChain
	if not object or not object:IsA("PVInstance") then
		error("Tween by pivot failure - invalid object passed")
		return AnimChain.new()
	end

	local fakeCenter = Instance.new("Part")
	fakeCenter.CFrame = object:GetPivot()
	fakeCenter:SetAttribute("ANIMNATION_PIVOT", true)
	fakeCenter:GetPropertyChangedSignal("CFrame"):Connect(function()
		object:PivotTo(fakeCenter.CFrame)
	end)

	task.delay(tweenInfo.Time, function()
		fakeCenter:Destroy()
	end)

	return AnimNation.tween(fakeCenter, tweenInfo, properties)
end

local function tweenByScale(
	object: Model,
	tweenInfo: TweenInfo | TweenInfoTable,
	properties: { [string]: any }
): AnimChain
	if not object or not object:IsA("PVInstance") then
		error("Tween by scale failure - invalid object passed")
		return AnimChain.new()
	end

	local scaleRef = Instance.new("NumberValue")
	scaleRef.Value = object:GetScale()
	scaleRef:SetAttribute("ANIMNATION_SCALE", true)
	scaleRef:GetPropertyChangedSignal("Value"):Connect(function()
		object:ScaleTo(scaleRef.Value)
	end)

	task.delay(tweenInfo.Time, function()
		scaleRef:Destroy()
	end)

	properties.Value = properties.Scale
	properties.Scale = nil

	return AnimNation.tween(scaleRef, tweenInfo, properties)
end

local function animateSequence(
	object: Instance,
	sequenceName: string,
	method: "tween" | "target",
	methodInfo: TweenInfo | SpringInfo,
	newSequence: NumberSequence | ColorSequence,
	waitToKill: boolean?
): AnimChain
	local originalSequence = object[sequenceName]
	local sequenceType = typeof(originalSequence)
	local numPoints = #originalSequence.Keypoints
	if numPoints ~= #newSequence.Keypoints then
		error("Animate sequence failure - keypoint count mismatch")
		if waitToKill and methodInfo.Time then
			task.wait(methodInfo.Time)
		end
		return AnimChain.new()
	end

	local function updateSequence()
		if not ActiveSequences[object] or not ActiveSequences[object][sequenceName] then
			return
		end

		local newKeypoints = table.create(numPoints)
		for index, point in pairs(ActiveSequences[object][sequenceName]) do
			if sequenceType == "NumberSequence" then
				newKeypoints[index] =
					NumberSequenceKeypoint.new(point.Time.Value, point.Value.Value, point.Envelope.Value)
			else
				newKeypoints[index] = ColorSequenceKeypoint.new(point.Time.Value, point.Value.Value)
			end
		end
		if sequenceType == "NumberSequence" then
			object[sequenceName] = NumberSequence.new(newKeypoints)
		else
			object[sequenceName] = ColorSequence.new(newKeypoints)
		end
	end

	if not ActiveSequences[object] then
		ActiveSequences[object] = {}
	end
	if not ActiveSequences[object][sequenceName] then
		ActiveSequences[object][sequenceName] = table.create(numPoints)

		for index, keypoint in pairs(originalSequence.Keypoints) do
			-- Set up value Instances that we'll use to track and modify each
			-- keypoint of the sequence
			local point
			if sequenceType == "NumberSequence" then
				point = {
					Time = Instance.new("NumberValue"),
					Value = Instance.new("NumberValue"),
					Envelope = Instance.new("NumberValue"),
				}

				point.Envelope.Value = keypoint.Envelope
				point.Envelope:GetPropertyChangedSignal("Value"):Connect(updateSequence)
			elseif sequenceType == "ColorSequence" then
				point = {
					Time = Instance.new("NumberValue"),
					Value = Instance.new("Color3Value"),
				}
			end

			point.Value.Value = keypoint.Value
			point.Time.Value = keypoint.Time

			point.Value:GetPropertyChangedSignal("Value"):Connect(updateSequence)
			point.Time:GetPropertyChangedSignal("Value"):Connect(updateSequence)

			ActiveSequences[object][sequenceName][index] = point
		end
	end

	for index in pairs(originalSequence.Keypoints) do
		local point = ActiveSequences[object][sequenceName][index]
		local isLast = index == numPoints
		local shouldWait = isLast and waitToKill
		if sequenceType == "NumberSequence" then
			AnimNation[method](point.Envelope, methodInfo, { Value = newSequence.Keypoints[index].Envelope })
		end
		AnimNation[method](point.Value, methodInfo, { Value = newSequence.Keypoints[index].Value })
		local animChain = AnimNation[method](
			point.Time,
			methodInfo,
			{ Value = newSequence.Keypoints[index].Time },
			shouldWait
		)
			:AndThen(function()
				if index == numPoints and ActiveSequences[object] then
					for _, pointData in pairs(ActiveSequences[object][sequenceName]) do
						pointData.Value:Destroy()
						pointData.Time:Destroy()
						if sequenceType == "NumberSequence" then
							pointData.Envelope:Destroy()
						end
					end

					ActiveSequences[object][sequenceName] = nil

					local remainingAnims = 0
					for _, _ in pairs(ActiveSequences[object]) do
						remainingAnims += 1
						break
					end
					if remainingAnims == 0 then
						ActiveSequences[object] = nil
					end

					object[sequenceName] = newSequence
				end
			end)

		if isLast then
			return animChain
		end
	end
end

local function createTweenInfoFromTable(info: { [string]: any })
	return TweenInfo.new(
		info.Time or info.t or 1,
		info.EasingStyle or info.Style or info.s or Enum.EasingStyle.Quad,
		info.EasingDirection or info.Direction or info.d or Enum.EasingDirection.Out,
		info.RepeatCount or info.Repeat or info.rc or 0,
		info.Reverses or info.Reverse or info.r or false,
		info.DelayTime or info.Delay or info.dt or 0
	)
end

local function createSpringFromInfo(springInfo: SpringInfo): Spring
	local spring = Spring.new(springInfo.Initial or springInfo.i, springInfo.Clock)
	for key, value in pairs(springInfo) do
		if key ~= "Initial" and key ~= "i" and key ~= "Clock" then
			spring[key] = value
		end
	end
	return spring
end

local function updateSpringFromInfo(spring: Spring, springInfo: SpringInfo)
	for key, value in pairs(springInfo) do
		if key ~= "Initial" and key ~= "i" and key ~= "Clock" and key ~= "Position" then
			spring[key] = value
		end
	end
end

local function animate(spring, object, property)
	local animating, position = spring:IsAnimating()
	if object:IsA("PVInstance") and property == "CFrame" then
		while animating do
			object:PivotTo(position)
			task.wait()
			animating, position = spring:IsAnimating()
		end
		object:PivotTo(spring.Target)
	elseif object:IsA("Model") and property == "Scale" then
		while animating do
			object:ScaleTo(position)
			task.wait()
			animating, position = spring:IsAnimating()
		end
		object:ScaleTo(spring.Target)
	else
		while animating do
			object[property] = position
			task.wait()
			animating, position = spring:IsAnimating()
		end
		object[property] = spring.Target
	end

	if SpringEvents[object] then
		SpringEvents[object][property] = nil

		local stillHasSprings = false
		for _, _ in pairs(SpringEvents[object]) do
			stillHasSprings = true
			break
		end
		if not stillHasSprings then
			SpringEvents[object] = nil
		end
	end
end

local function springBindLoop()
	if not BindLoopConnection then
		BindLoopConnection = RunService[BIND_CONNECTION_TYPE]:Connect(function()
			local activeBind = false
			for _, bind in pairs(SpringBinds) do
				activeBind = true
				local springs = bind[1]
				local callback = bind[2]
				local idle = bind[3]
				local springCount = #springs
				local positions = table.create(springCount)
				local velocities = table.create(springCount)
				local thisIterationIdle = true
				for index, spring: Spring in pairs(springs) do
					local animating, position = spring:IsAnimating()
					if animating then
						positions[index] = position
						velocities[index] = spring.Velocity
						thisIterationIdle = false
					else
						positions[index] = spring.Target
						velocities[index] = ZEROS[spring.Type]
					end
				end
				if not thisIterationIdle or not idle then
					callback(positions, velocities)
				end
				bind[3] = thisIterationIdle
			end
			if not activeBind then
				BindLoopConnection:Disconnect()
				BindLoopConnection = nil
			end
		end)
	end
end

local function lerp(start: any, target: any, a: number): any
	local valueType = typeof(target)
	if valueType == "Color3" or valueType == "UDim2" or valueType == "CFrame" then
		return start:Lerp(target, a)
	elseif valueType == "UDim" then
		local currentUDim: UDim = start
		return UDim.new(
			currentUDim.Scale + (target.Scale - currentUDim.Scale) * a,
			currentUDim.Offset + (target.Offset - currentUDim.Offset) * a
		)
	end
	return start + (target - start) * a
end

-- Public Functions

--[=[
	Asynchronously performs a tween on the given object. Tween parameters are
	identical to `TweenService:Create()`.

	```lua
	AnimNation.tween(part, TweenInfo.new(2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = Vector3.new(10, 20, 30),
		Rotation = Vector3.new(45, 90, 0),
	}):Await()
	```

	@param object Instance | { Instance } -- The object or objects to apply the tween to.
	@param tweenInfo TweenInfo | TweenInfoTable -- The tween information or a table of tween parameters.
	@param properties { [string]: any } -- A dictionary of properties to tween to.
	@return AnimChain -- An AnimChain representing the tween.
]=]
function AnimNation.tween(
	object: Instance | { Instance },
	tweenInfo: TweenInfo | TweenInfoTable,
	properties: { [string]: any }
): AnimChain
	if typeof(object) == "table" then
		local lastChain
		for _, obj in object do
			lastChain = AnimNation.tween(obj, tweenInfo, properties)
		end
		return lastChain
	end

	if not object then
		error("Tween failure - invalid object passed")
		return AnimChain.new()
	end

	local skipControlReset

	if typeof(tweenInfo) == "table" then
		skipControlReset = tweenInfo._skipControlReset
		tweenInfo = createTweenInfoFromTable(tweenInfo)
	end

	local alternativeAnimChain: AnimChain?
	local normalCount = 0
	local isPVInstance = object:IsA("PVInstance")
	local isModel = object:IsA("Model")
	local isPivot = object:GetAttribute("ANIMNATION_PIVOT")
	local isScale = object:GetAttribute("ANIMNATION_SCALE")

	for property, newValue in pairs(properties) do
		if isPVInstance and not isPivot and property == "CFrame" then
			local model: Model = object :: Model
			alternativeAnimChain = tweenByPivot(model, tweenInfo, { CFrame = newValue })
			properties[property] = nil
		elseif isModel and not isScale and property == "Scale" then
			local model: Model = object :: Model
			alternativeAnimChain = tweenByScale(model, tweenInfo, { Scale = newValue })
			properties[property] = nil
		else
			local propertyType = typeof(object[property])
			if propertyType == "ColorSequence" or propertyType == "NumberSequence" then
				alternativeAnimChain = animateSequence(object, property, "tween", tweenInfo, newValue)
				properties[property] = nil
			else
				normalCount += 1
			end
		end
	end

	if normalCount == 0 then
		return alternativeAnimChain or AnimChain.new()
	end

	local thisTween = TweenService:Create(object, tweenInfo, properties)
	local tweenChain = AnimChain.new({ thisTween })

	thisTween:Play()
	TweenDirectory[object] = thisTween

	if not skipControlReset then
		CustomTweens[object] = nil
	end

	task.spawn(scheduleTweenCleanup, thisTween)

	return tweenChain :: AnimChain
end

--[=[
	Asynchronously performs a tween on the given object, starting from the
	specified alpha percentage. Otherwise identical to `AnimNation.tween`.

	```lua
	AnimNation.tweenFromAlpha(part, TweenInfo.new(2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = Vector3.new(10, 20, 30),
		Rotation = Vector3.new(45, 90, 0),
	}, 0.5)
	```

	@param objects Instance | { Instance } -- The object or objects to apply the tween to.
	@param tweenInfo TweenInfo | TweenInfoTable -- The tween information or a table of tween parameters.
	@param properties { [string]: any } -- A dictionary of properties to tween to.
	@param alpha number -- The alpha percentage to start from (0-1).
	@param yield boolean? -- Whether to yield until the tween is complete.
]=]
function AnimNation.tweenFromAlpha(
	objects: Instance | { Instance },
	tweenInfo: TweenInfo | TweenInfoTable,
	properties: { [string]: any },
	alpha: number,
	yield: boolean?
)
	if typeof(objects) == "table" then
		for _, obj in objects do
			AnimNation.tweenFromAlpha(obj, tweenInfo, properties, alpha, yield)
		end
	end

	local object: Instance = objects :: Instance

	if typeof(alpha) ~= "number" then
		error("Tween failure - alpha must be a number")
	elseif not object then
		error("Tween failure - invalid object passed")
	end

	alpha = math.clamp(alpha, 0, 1)

	if typeof(tweenInfo) == "table" then
		tweenInfo = createTweenInfoFromTable(tweenInfo)
	end

	local thisTweenId = LastCustomTweenId + 1
	LastCustomTweenId = thisTweenId

	if not CustomTweens[object] then
		CustomTweens[object] = {}
	end

	local startingAlpha = TweenService:GetValue(alpha, tweenInfo.EasingStyle, tweenInfo.EasingDirection)
	local firstIteration = {}
	local startingProperties = {}
	local isPVInstance = object:IsA("PVInstance")
	local isModel = object:IsA("Model")
	local model: Model = object :: Model

	for property, value in pairs(properties) do
		startingProperties[property] = if isPVInstance and property == "CFrame"
			then model:GetPivot()
			else object[property]
		firstIteration[property] = lerp(startingProperties[property], value, startingAlpha)
		-- Set custom tween control to this process
		CustomTweens[object][property] = thisTweenId
	end

	-- Instantly apply starting values through TweenService, overriding any
	-- regular tweens from calling .tween()
	AnimNation.tween(object, { t = 0, _skipControlReset = true }, firstIteration):Await()

	-- Perform remainder of tween
	local function performTween()
		local remainingAlpha = 1 - alpha
		local tweenLength = tweenInfo.Time * remainingAlpha
		local endTime = os.clock() + tweenLength
		while os.clock() < endTime do
			local stillControllingSomething = false
			if CustomTweens[object] then
				local percentComplete = 1 - ((endTime - os.clock()) / tweenLength)
				local currentAlpha = TweenService:GetValue(
					alpha + (remainingAlpha * percentComplete),
					tweenInfo.EasingStyle,
					tweenInfo.EasingDirection
				)
				for property, tweenId in pairs(CustomTweens[object]) do
					-- Only apply properties if this tween is still the most
					-- recent
					if tweenId == thisTweenId then
						local newValue = lerp(startingProperties[property], properties[property], currentAlpha)
						if isPVInstance and property == "CFrame" then
							model:PivotTo(newValue)
						elseif isModel and property == "Scale" then
							model:ScaleTo(newValue)
						else
							object[property] = newValue
						end
						stillControllingSomething = true
					end
				end
			end

			task.wait()

			if not stillControllingSomething then
				break
			end
		end

		-- If we're still controlling this object, apply the final values
		if CustomTweens[object] then
			for property, tweenId in pairs(CustomTweens[object]) do
				if tweenId == thisTweenId then
					if isPVInstance and property == "CFrame" then
						model:PivotTo(properties[property])
					elseif isModel and property == "Scale" then
						model:ScaleTo(properties[property])
					else
						object[property] = properties[property]
					end
				end
			end

			-- Clean up now that the tween has finished
			for property, tweenId in pairs(CustomTweens[object]) do
				if tweenId == thisTweenId then
					CustomTweens[object][property] = nil
				end
			end

			-- If there are still any other tweens playing on this object, we're
			-- done
			for _, _ in CustomTweens[object] do
				return
			end

			-- Otherwise, clean up the table
			CustomTweens[object] = nil
		end
	end

	if yield then
		performTween()
	else
		task.spawn(performTween)
	end
end

--[=[
	Returns the last tween played on the given object, or nil if none exists.

	@param object Instance -- The object to get the tween from.
	@return Tween? -- The last tween played on the object.
]=]
function AnimNation.getTweenFromInstance(object: Instance): Tween?
	return TweenDirectory[object]
end

--[=[
	Instantly set the given object's properties to a lerped value between its
	current state and the given properties. Functions like `.tweenFromAlpha()`,
	except that it doesn't continue to play the tween. Naturally, the time value
	used in the provided TweenInfo or table has no effect on this function.

	Currently supports number, Vector2, Vector3, CFrame, Color3, UDim2, UDim and
	any other type that supports scalar	multiplication/addition.

	```lua
	AnimNation.lerp(part, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = Vector3.new(10, 20, 30),
		Rotation = Vector3.new(45, 90, 0),
	}, 0.5)
	```

	@param object Instance | { Instance } -- The object or objects to apply the lerp to.
	@param tweenInfo TweenInfo | TweenInfoTable -- The tween information or a table of tween parameters.
	@param properties { [string]: any } -- A dictionary of properties to lerp to.
	@param alpha number -- The alpha percentage to lerp to (0-1).
]=]
function AnimNation.lerp(
	object: Instance | { Instance },
	tweenInfo: TweenInfo | TweenInfoTable,
	properties: { [string]: any },
	alpha: number
)
	if typeof(object) == "table" then
		for _, obj in object do
			AnimNation.lerp(obj, tweenInfo, properties, alpha)
		end
		return
	end

	if typeof(alpha) ~= "number" then
		error("Lerp failure - alpha must be a number")
		return
	elseif not object then
		error("Lerp failure - invalid object passed")
		return
	end

	alpha = math.clamp(alpha, 0, 1)

	if typeof(tweenInfo) == "table" then
		tweenInfo = createTweenInfoFromTable(tweenInfo)
	end

	local startingAlpha = TweenService:GetValue(alpha, tweenInfo.EasingStyle, tweenInfo.EasingDirection)
	local lerpedValues = {}
	for property, value in pairs(properties) do
		local start = if object:IsA("PVInstance") and typeof(value) == "CFrame"
			then object:GetPivot()
			else object[property]
		lerpedValues[property] = lerp(start, value, startingAlpha)
	end

	-- Instantly apply starting values, overriding any other tweens on this
	-- object
	AnimNation.tween(object, TweenInfo.new(0), lerpedValues):Await()
end

--[=[
	Asynchronously performs a spring impulse on the given object.

	```lua
	AnimNation.impulse(part, { s = 15, d = 0.7 }, {
		Position = Vector3.new(10, 20, 30),
		Rotation = Vector3.new(45, 90, 0),
	}):Await()
	```

	@param object Instance | { Instance } -- The object or objects to apply the impulse to.
	@param springInfo SpringInfo -- A table of spring properties such as `{s = 10, d = 0.5}`.
	@param properties { [string]: any } -- A dictionary of properties to apply impulses to.
	@return AnimChain -- An AnimChain representing the spring animations.
]=]
function AnimNation.impulse(
	object: Instance | { Instance },
	springInfo: SpringInfo,
	properties: { [string]: any }
): AnimChain
	if typeof(object) == "table" then
		local lastChain
		for _, obj in object do
			lastChain = AnimNation.impulse(obj, springInfo, properties)
		end
		return lastChain
	end

	if not object then
		error("Spring failure - invalid object passed")
		return AnimChain.new()
	end

	local animChain: AnimChain
	local isPVInstance = object:IsA("PVInstance")
	local isModel = object:IsA("Model")

	for property, impulse in pairs(properties) do
		local impulseType = typeof(impulse)
		if SUPPORTED_TYPES[impulseType] then
			local needsAnimationLink = true

			local model: Model = object :: Model
			if isPVInstance and property == "CFrame" then
				springInfo.Initial = model:GetPivot()
			elseif isModel and property == "Scale" then
				springInfo.Initial = model:GetScale()
			else
				springInfo.Initial = object[property]
			end

			if not SpringEvents[object] then
				SpringEvents[object] = {}
			end

			if not SpringEvents[object][property] then
				SpringEvents[object][property] = createSpringFromInfo(springInfo)
			else
				updateSpringFromInfo(SpringEvents[object][property], springInfo)
				needsAnimationLink = false
			end

			springInfo.Initial = nil

			local newSpring = SpringEvents[object][property]

			if not animChain then
				animChain = AnimChain.new({ newSpring })
			else
				animChain:_addAnimator(newSpring)
			end

			newSpring:Impulse(impulse)

			if needsAnimationLink then
				task.spawn(animate, newSpring, object, property)
			end
		else
			error(string.format("Spring failure - invalid impulse type '%s' for property '%s'", impulseType, property))
		end
	end

	return animChain :: AnimChain
end

--[=[
	Asynchronously uses a spring to transition the given object's properties to
	the specified values.

	```lua
	AnimNation.target(part, { s = 15, d = 0.7 }, {
		Position = Vector3.new(10, 20, 30),
		Rotation = Vector3.new(45, 90, 0),
	}):Await()
	```

	@param object Instance | { Instance } -- The object or objects to apply the target to.
	@param springInfo SpringInfo -- A table of spring properties such as `{s = 10, d = 0.5}`.
	@param properties { [string]: any } -- A dictionary of properties to target.
	@return AnimChain -- An AnimChain representing the spring animations.
]=]
function AnimNation.target(
	object: Instance | { Instance },
	springInfo: SpringInfo,
	properties: { [string]: any }
): AnimChain
	if typeof(object) == "table" then
		local lastChain
		for _, obj in object do
			lastChain = AnimNation.target(obj, springInfo, properties)
		end
		return lastChain
	end

	local animChain = AnimChain.new()

	--TODO: Add sequence support
	for property, target in pairs(properties) do
		local targetZero = ZEROS[typeof(target)]
		if not targetZero then
			error("Spring failure - unsupported target type '" .. typeof(target) .. "' passed")
			continue
		end

		springInfo.Target = target

		local animator = AnimNation.impulse(object, springInfo, { [property] = targetZero })._animators[1]

		animChain:_addAnimator(animator)

		springInfo.Target = nil
	end

	return animChain
end

--[=[
	Binds a callback function to the given springs' position and velocity. Can be
	used to create more complex and constant interactions with spring values
	than just a quick impulse or target.

	```lua
	AnimNation.bind({ spring1, spring2 }, "MyBind", function(positions, velocities)
		print("Spring 1 Position:", positions[1], "Velocity:", velocities[1])
		print("Spring 2 Position:", positions[2], "Velocity:", velocities[2])
	end)
	```

	@param springs { Spring } -- A table of springs to bind to.
	@param label string -- A unique label to identify this bind.
	@param callback (positions: { Springable }, velocities: { Springable }) -> () -- The function to call on each update.
]=]
function AnimNation.bind(
	springs: { Spring },
	label: string,
	callback: (positions: { Springable }, velocities: { Springable }) -> ()
)
	SpringBinds[label] = { springs, callback, false }
	springBindLoop()
end

--[=[
	Unbinds the callback associated with the specified label from updates.
]=]
function AnimNation.unbind(label: string)
	SpringBinds[label] = nil
end

--[=[
	Creates a new spring with the given properties.

	```lua
	local mySpring = AnimNation.createSpring({ s = 10, d = 0.5 }, "MySpring")
	```

	@param springInfo SpringInfo -- A table of spring properties such as `{s = 10, d = 0.5}`.
	@param name string? -- An optional name for lookup with `AnimNation.getSpring()`.
	@return Spring -- The newly created spring.
]=]
function AnimNation.createSpring(springInfo: SpringInfo, name: string?): Spring
	local newSpring = createSpringFromInfo(springInfo)
	if name then
		SpringDirectory[name] = newSpring
	end

	return newSpring
end

--[=[
	Returns the spring with the given name.If none exists, it will return `nil`
	with a warning, or an error depending on the set `ERROR_POLICY`.

	```lua
	local mySpring = AnimNation.getSpring("MySpring")
	```

	@param name string -- The name of the spring to retrieve.
	@return Spring -- The spring with the given name.
]=]
function AnimNation.getSpring(name: string): Spring
	if not SpringDirectory[name] then
		error(string.format("Spring '%s' does not exist", name))
	end

	return SpringDirectory[name]
end

--[=[
	Creates a new spline from the given control points. This should be a table
	of CFrame values with at least 4 entries. Optionally allows you to provide a
	name for lookup with `AnimNation.getSpline()`.

	```lua
	local mySpline = AnimNation.createSpline({
		CFrame.new(0, 0, 0),
		CFrame.new(5, 10, 0),
		CFrame.new(10, 0, 0),
		CFrame.new(15, 10, 0),
	}, "MySpline")
	```

	@param controlPoints { CFrame } -- A table of CFrame control points with at least 4 entries.
	@param name string? -- An optional name for lookup with `AnimNation.getSpline()`.
	@return Spline -- The newly created spline.
]=]
function AnimNation.createSpline(controlPoints: { CFrame }, name: string?): Spline
	local newSpline = Spline.new(controlPoints) :: Spline
	if name then
		SplineDirectory[name] = newSpline
	end

	return newSpline
end

--[=[
	Returns the spline with the given name. If none exists, it will return `nil`
	with a warning, or an error depending on the set `ERROR_POLICY`.

	```lua
	local mySpline = AnimNation.getSpline("MySpline")
	```

	@param name string -- The name of the spline to retrieve.
	@return Spline -- The spline with the given name.
]=]
function AnimNation.getSpline(name: string): Spline?
	if not SplineDirectory[name] then
		error(string.format("Spline '%s' does not exist", name))
	end

	return SplineDirectory[name]
end

--[=[
	Asynchronously performs tween-based spherical interpolation on the given
	object, starting from the specified `alpha` percentage.

	Parameters are similar to `AnimNation.tweenFromAlpha()`, with the addition of
	`alignment` which determines whether the object being tweened is aligned to
	the track orientation or the nodes' orientations. A spline argument is also
	required, which can be supplied as previously constructed Spline object or an
	array of points to create a new one from.

	Currently supports number, Vector2, Vector3, CFrame, Color3, UDim2, UDim and
	any other type that supports scalar multiplication/addition.

	```lua
	AnimNation.slerpTweenFromAlpha(part, {
		t = 2,
		s = Enum.EasingStyle.Quad,
		d = Enum.EasingDirection.Out,
	}, {
		CFrame = AnimNation.createSpline({
			CFrame.new(0, 0, 0),
			CFrame.new(5, 10, 0),
			CFrame.new(10, 0, 0),
			CFrame.new(15, 10, 0),
		}),
	}, "Track", 0.25, true)
	```

	@param object Instance -- The object to perform the slerp tween on.
	@param tweenInfo TweenInfo | TweenInfoTable -- A TweenInfo or table describing the tween parameters.
	@param splineInfo Spline | { CFrame } -- A Spline object or table of CFrame control points.
	@param alignment ("Track" | "Nodes")? -- Optional; whether to align to the track or nodes. Defaults to "Nodes".
	@param alpha number? -- Optional; the starting alpha percentage (0-1). Defaults to 0.
	@param yield boolean? -- Optional; whether to yield until the tween is complete. Defaults to false.
]=]
function AnimNation.slerpTweenFromAlpha(
	object: Instance,
	tweenInfo: TweenInfo | TweenInfoTable,
	splineInfo: Spline | { CFrame },
	alignment: ("Track" | "Nodes")?,
	alpha: number?,
	yield: boolean?
)
	local initialAlpha = alpha or 0
	alignment = alignment or "Nodes"

	if typeof(initialAlpha) ~= "number" then
		error("Slerp tween failure - alpha must be a number")
	elseif typeof(splineInfo) ~= "table" then
		error("Slerp tween failure - spline must be a table")
	elseif alignment ~= "Track" and alignment ~= "Nodes" then
		error("Slerp tween failure - alignment must be 'Track' or 'Nodes'")
	elseif not object then
		error("Slerp tween failure - invalid object passed")
	end

	local spline: Spline = splineInfo[1] and Spline.new(splineInfo) or splineInfo :: Spline

	initialAlpha = math.clamp(initialAlpha, 0, 1)

	if typeof(tweenInfo) == "table" then
		tweenInfo = createTweenInfoFromTable(tweenInfo)
	end

	local thisTweenId = LastCustomTweenId + 1
	LastCustomTweenId = thisTweenId

	if not CustomTweens[object] then
		CustomTweens[object] = {}
	end

	local startingAlpha = TweenService:GetValue(initialAlpha, tweenInfo.EasingStyle, tweenInfo.EasingDirection)
	local firstIteration = {}
	local startingProperties = { CFrame = spline:GetLinearCFrameFromAlpha(0, alignment) }
	local properties = { CFrame = spline:GetLinearCFrameFromAlpha(1, alignment) }
	local isPVInstance = object:IsA("PVInstance")
	local isModel = object:IsA("Model")
	local model: Model = object :: Model

	for property, value in pairs(properties) do
		startingProperties[property] = if object:IsA("PVInstance") and typeof(value) == "CFrame"
			then object:GetPivot()
			else object[property]
		firstIteration[property] = lerp(startingProperties[property], value, startingAlpha)
		-- Set custom tween control to this process
		CustomTweens[object][property] = thisTweenId
	end

	-- Instantly apply starting values through TweenService, overriding any
	-- regular tweens from calling .tween()
	AnimNation.tween(object, { t = 0, _skipControlReset = true }, firstIteration):Await()

	-- Perform remainder of tween
	local function performTween()
		local remainingAlpha = 1 - initialAlpha
		local tweenLength = tweenInfo.Time * remainingAlpha
		local endTime = os.clock() + tweenLength
		while os.clock() < endTime do
			local stillControllingSomething = false
			if CustomTweens[object] then
				local percentComplete = 1 - ((endTime - os.clock()) / tweenLength)
				local currentAlpha = TweenService:GetValue(
					initialAlpha + (remainingAlpha * percentComplete),
					tweenInfo.EasingStyle,
					tweenInfo.EasingDirection
				)
				for property, tweenId in pairs(CustomTweens[object]) do
					-- Only apply properties if this tween is still the most
					-- recent
					if tweenId == thisTweenId then
						local newValue = spline:GetCFrameFromAlpha(currentAlpha, alignment)
						if isPVInstance and property == "CFrame" then
							model:PivotTo(newValue)
						elseif isModel and property == "Scale" then
							model:ScaleTo(newValue)
						else
							object[property] = newValue
						end
						stillControllingSomething = true
					end
				end
			end

			task.wait()

			if not stillControllingSomething then
				break
			end
		end

		-- If we're still controlling this object, apply the final values
		if CustomTweens[object] then
			for property, tweenId in pairs(CustomTweens[object]) do
				if tweenId == thisTweenId then
					if isPVInstance and property == "CFrame" then
						model:PivotTo(properties[property])
					elseif isModel and property == "Scale" then
						model:ScaleTo(properties[property])
					else
						object[property] = properties[property]
					end
				end
			end

			-- Clean up now that the tween has finished
			for property, tweenId in pairs(CustomTweens[object]) do
				if tweenId == thisTweenId then
					CustomTweens[object][property] = nil
				end
			end

			-- If there are still any other tweens playing on this object, we're
			-- done
			for _ in CustomTweens[object] do
				return
			end

			-- Otherwise, clean up the table
			CustomTweens[object] = nil
		end
	end

	if yield then
		performTween()
	else
		task.spawn(performTween)
	end
end

-- Public Function Aliases

AnimNation.inquire = AnimNation.getSpring
AnimNation.register = AnimNation.createSpring

return AnimNation
