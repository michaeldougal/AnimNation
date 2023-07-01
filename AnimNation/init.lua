--[[ File Info
	Author: ChiefWildin
	Created: 10/12/2022
	Version: 1.7.0

	A streamlined Roblox animation utility that simplifies the use of springs
	and tweens on object properties.
--]]

--[[ Types

	SpringInfo
		A dictionary of spring properties such as {s = 10, d = 0.5}. Can be
		constructed using any keys that you could use to create a Spring object.
		Possible keys:
		Initial = Initial | i
		Speed = Speed | s
		Damper = Damper | d
		Target = Target | t
		Velocity = Velocity | v
		Position = Position | Value | p
		Clock = Clock

	AnimChain
		An object that listens for the end of a tween/spring animation and then
		fires any connected :AndThen() callbacks. :AndThen() always	returns the
		same AnimChain object, so you can chain as many	callbacks together as
		you want.

	TweenInfo
		TweenInfo can be passed to the tweening functions as either a TweenInfo
		object or a dictionary of the desired parameters. Keys are either the
		TweenInfo parameter name or shortened versions:
		Time = Time | t
		EasingStyle = EasingStyle | Style | s
		EasingDirection = EasingDirection | Direction | d
		RepeatCount = RepeatCount | Repeat | rc
		Reverses = Reverses | Reverse | r
		DelayTime = DelayTime | Delay | dt
--]]

--[[ Tweens

	AnimNation tweens support all properties that are supported by TweenService,
	as well as tweening Models by CFrame/Scale and tweening
	NumberSequence/ColorSequence values	(given that the target sequence has the
	same number of keypoints).

	.tween(object: Instance, tweenInfo: TweenInfo | {}, properties: {[string]: any}, waitToKill: boolean?): AnimChain
		Asynchronously performs a tween on the given object. Parameters are
		identical to TweenService:Create(), with the addition of waitToKill,
		which will make	the operation synchronous (yielding) if true. :AndThen()
		can be used to link another function that will be called when the tween
		completes.

	.tweenFromAlpha(object: Instance, tweenInfo: TweenInfo | {}, properties: {[string]: any}, alpha: number, waitToKill: boolean?): AnimChain
		Asynchronously performs a tween on the given object, starting from the
		specified alpha percentage. Otherwise identical to AnimNation.tween.
		Currently supports number, Vector2, Vector3, CFrame, Color3, UDim2, UDim
		and any other type that supports scalar	multiplication/addition.
			NOTE: Currently supports tweening Models by CFrame, but does not yet
			support tweening NumberSequence/ColorSequence values. Using
			.getTweenFromInstance() will also not return a Tween if using this
			function. This is due to the backend being a custom solution since
			Roblox doesn't natively support skipping around	in Tween objects :)

	.lerp(object: Instance, tweenInfo: TweenInfo | {}, properties: {[string]: any}, alpha: number)
		Instantly set the given object's properties to a lerped value between
		its current state and the given properties. Functions like
		`.tweenFromAlpha()`, except that it doesn't continue to play the tween.
		Naturally, the time value used in the provided TweenInfo or table has no
		effect on this function.

	.getTweenFromInstance(object: Instance): Tween?
		Returns the last tween played on the given object, or nil if none exists
--]]

--[[ Springs

	AnimNation springs support the following types: number, Vector2, Vector3,
	UDim, UDim2, CFrame, and Color3. These are natively supported by the
	provided Spring class as well.

	.impulse(object: Instance, springInfo: SpringInfo, properties: {[string]: any}, waitToKill: boolean?): AnimChain
		Asynchronously performs a spring impulse on the given object. The
		optional waitToKill flag will make the operation synchronous (yielding)
		if true. :AndThen() can be used on this function's return value to link
		another function that will be called when the spring completes (reaches
		epsilon).

	.target(object: Instance, springInfo: SpringInfo, properties: {[string]: any}, waitToKill: boolean?)
		Asynchronously uses a spring to transition the given object's
		properties to the specified values. The optional waitToKill flag will
		make the operation synchronous (yielding) if true.
			NOTE: No AnimChain is currently returned to enable :AndThen()
			behavior. I plan to add support for this in a future update.

	.bind(springs: {Spring}, label: string, callback: (positions: {Springable}, velocities: {Springable}) -> ())
	    Binds a callback function to the given springs' positions and
	    velocities.	Can be used to create more complex and constant	interactions
		with spring values than just a quick impulse or target.

	.unbind(spring: Spring, label: string)
		Unbinds the callback associated with the specified label from updates.

	.createSpring(springInfo: SpringInfo, name: string?): Spring
		Creates a new spring with the given properties and maps it to the
		specified name, if provided. An initial value can be provided in the
		SpringInfo table. Aliases: .register()

	.getSpring(name: string): Spring?
		Returns the spring with the given name. If none exists, it will return
		nil with a warning, or an error depending on the set ERROR_POLICY.
		Aliases: .inquire()
--]]

--[[ Splines

	AnimNation splines are used in animation for interpolating between a series
	of points in a smoothed curving fashion.

	.getSpline(name: string): Spline?
	    Returns the spline with the given name. If none exists, it will return
	    nil with a warning, or an error depending on the set ERROR_POLICY.

	.createSpline(controlPoints: {CFrame}, name: string?): Spline
		Creates a new spline from the given control points. This should be a
		table of CFrame values with at least 4 entries.

	.slerpTweenFromAlpha(object: Instance, tweenInfo: TweenInfo | {}, spline: Spline | {CFrame}, alignment: ("Track" | "Nodes")?, alpha: number?, waitToKill: boolean?): AnimChain
	    Asynchronously performs tween-based spherical interpolation on the given
		object, starting from the specified `alpha` percentage. Parameters are
		similar to `AnimNation.tweenFromAlpha()`, with the addition of alignment
		which determines whether the object being tweened is aligned to the
		track orientation or the nodes' orientations. A spline argument is also
		required, which can be supplied as previously constructed Spline object
		or an array of points to create a new one from. :AndThen() can be used
		to link a callback function when the tween completes. Currently supports
		number, Vector2, Vector3, CFrame, Color3, UDim2, UDim and any other type
		that supports scalar multiplication/addition.
--]]

-- Services

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- Module Declaration

local AnimNation = {}

-- Dependencies

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
type Spring = Spring.Spring
type Spline = Spline.Spline

export type SpringInfo = {
	Position: Springable?,
	Velocity: number?,
	Target: Springable?,
	Damper: number?,
	Speed: number?,
	Initial: Springable?,
	Clock: (() -> number)?,
}

export type AnimChain = {
	_anim: Spring | Tween,
	_type: "Spring" | "Tween",
	AndThen: (AnimChain, callback: () -> ()) -> AnimChain,
}

local AnimChain: AnimChain = {}
AnimChain.__index = AnimChain

function AnimChain.new(original: Spring | Tween)
	local self = setmetatable({}, AnimChain)
	self._anim = original
	self._type = if typeof(original) == "Instance" then "Tween" else "Spring"
	return self
end

function AnimChain:AndThen(callback: () -> ()): AnimChain
	if self._type == "Spring" then
		task.spawn(function()
			while self._anim:IsAnimating() do
				task.wait()
			end
			callback()
		end)
	elseif self._type == "Tween" then
		if self._anim then
			if self._anim.PlaybackState == Enum.PlaybackState.Completed then
				task.spawn(callback)
			else
				self._anim.Completed:Connect(function(playbackState)
					if playbackState == Enum.PlaybackState.Completed then
						callback()
					end
				end)
			end
		else
			callback()
		end
	end
	return self :: AnimChain
end

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
local ActiveSequences: { [Instance]: { [string]: { [string]: NumberValue | Color3Value } } } = {}

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

local function murderTweenWhenDone(tween: Tween)
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

local function tweenByPivot(object: Model, tweenInfo: TweenInfo, properties: {}, waitToKill: boolean?): AnimChain
	if not object or not object:IsA("PVInstance") then
		error("Tween by pivot failure - invalid object passed")
		if waitToKill then
			task.wait(tweenInfo.Time)
		end
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

	return AnimNation.tween(fakeCenter, tweenInfo, properties, waitToKill)
end

local function tweenByScale(object: Model, tweenInfo: TweenInfo, properties: {}, waitToKill: boolean?): AnimChain
	if not object or not object:IsA("PVInstance") then
		error("Tween by scale failure - invalid object passed")
		if waitToKill then
			task.wait(tweenInfo.Time)
		end
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

	return AnimNation.tween(scaleRef, tweenInfo, properties, waitToKill)
end

local function tweenSequence(
	object: Instance,
	sequenceName: string,
	tweenInfo: TweenInfo,
	newSequence: NumberSequence | ColorSequence,
	waitToKill: boolean?
): AnimChain
	local originalSequence = object[sequenceName]
	local sequenceType = typeof(originalSequence)
	local numPoints = #originalSequence.Keypoints
	if numPoints ~= #newSequence.Keypoints then
		error("Tween sequence failure - keypoint count mismatch")
		if waitToKill then
			task.wait(tweenInfo.Time)
		end
		return AnimChain.new()
	end

	local function updateSequence()
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

	for index, _ in pairs(originalSequence.Keypoints) do
		local point = ActiveSequences[object][sequenceName][index]
		local isLast = index == numPoints
		local shouldWait = isLast and waitToKill
		if sequenceType == "NumberSequence" then
			AnimNation.tween(point.Envelope, tweenInfo, { Value = newSequence.Keypoints[index].Envelope })
		end
		AnimNation.tween(point.Value, tweenInfo, { Value = newSequence.Keypoints[index].Value })
		local tweenObject = AnimNation.tween(
			point.Time,
			tweenInfo,
			{ Value = newSequence.Keypoints[index].Time },
			shouldWait
		)
			:AndThen(function()
				if index == numPoints then
					for _, pointData in pairs(ActiveSequences[object][sequenceName]) do
						pointData.Value:Destroy()
						pointData.Time:Destroy()
						if sequenceType == "NumberSequence" then
							pointData.Envelope:Destroy()
						end
					end

					ActiveSequences[object][sequenceName] = nil

					local remainingTweens = 0
					for _, _ in pairs(ActiveSequences[object]) do
						remainingTweens += 1
						break
					end
					if remainingTweens == 0 then
						ActiveSequences[object] = nil
					end

					object[sequenceName] = newSequence
				end
			end)

		if isLast then
			return tweenObject
		end
	end
end

local function createTweenInfoFromTable(info: {})
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

local function updateSpringFromInfo(spring: Spring, springInfo: SpringInfo): Spring
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

-- Asynchronously performs a tween on the given object.
--
-- Parameters are identical to `TweenService:Create()`, with the addition of
-- `waitToKill`, which will make the operation synchronous if true.
--
-- `:AndThen()` can be used to link a callback function when the tween
-- completes.
function AnimNation.tween(
	object: Instance,
	tweenInfo: TweenInfo | {},
	properties: { [string]: any },
	waitToKill: boolean?
): AnimChain
	if not object then
		error("Tween failure - invalid object passed")
		if waitToKill then
			task.wait(tweenInfo.Time)
		end
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
			alternativeAnimChain = tweenByPivot(object, tweenInfo, { CFrame = newValue })
			properties[property] = nil
		elseif isModel and not isScale and property == "Scale" then
			alternativeAnimChain = tweenByScale(object, tweenInfo, { Scale = newValue })
			properties[property] = nil
		else
			local propertyType = typeof(object[property])
			if propertyType == "ColorSequence" or propertyType == "NumberSequence" then
				alternativeAnimChain = tweenSequence(object, property, tweenInfo, newValue)
				properties[property] = nil
			else
				normalCount += 1
			end
		end
	end

	if normalCount == 0 then
		if waitToKill then
			task.wait(tweenInfo.Time)
		end
		return alternativeAnimChain or AnimChain.new()
	end

	local thisTween = TweenService:Create(object, tweenInfo, properties)
	local tweenChain = AnimChain.new(thisTween)

	thisTween:Play()
	TweenDirectory[object] = thisTween

	if not skipControlReset then
		CustomTweens[object] = nil
	end

	if waitToKill then
		murderTweenWhenDone(thisTween)
	else
		task.spawn(murderTweenWhenDone, thisTween)
	end

	return tweenChain :: AnimChain
end

-- Asynchronously performs a tween on the given object, starting from the
-- specified `alpha` percentage.
--
-- Parameters are identical to `TweenService:Create()`, with the addition of
-- `waitToKill` which will make the operation synchronous if true.
--
-- `:AndThen()` can be used to link a callback function when the tween
-- completes.
--
-- Currently supports number, Vector2, Vector3, CFrame, Color3, UDim2, UDim and
-- any other type that supports scalar multiplication/addition.
function AnimNation.tweenFromAlpha(
	object: Instance,
	tweenInfo: TweenInfo | {},
	properties: { [string]: any },
	alpha: number,
	waitToKill: boolean?
): AnimChain
	if typeof(alpha) ~= "number" then
		error("Tween failure - alpha must be a number")
		return AnimChain.new()
	elseif not object then
		error("Tween failure - invalid object passed")
		if waitToKill then
			task.wait(tweenInfo.Time * (1 - alpha))
		end
		return AnimChain.new()
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

	for property, value in pairs(properties) do
		startingProperties[property] = if isPVInstance and property == "CFrame" then object:GetPivot() else object[property]
		firstIteration[property] = lerp(startingProperties[property], value, startingAlpha)
		-- Set custom tween control to this process
		CustomTweens[object][property] = thisTweenId
	end

	-- Instantly apply starting values through TweenService, overriding any
	-- regular tweens from calling .tween()
	AnimNation.tween(object, {t = 0, _skipControlReset = true}, firstIteration, true)

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
							object:PivotTo(newValue)
						elseif isModel and property == "Scale" then
							object:ScaleTo(newValue)
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
						object:PivotTo(properties[property])
					elseif isModel and property == "Scale" then
						object:ScaleTo(properties[property])
					else
						object[property] = properties[property]
					end
				end
			end
		end

		if CustomTweens[object] then
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

	if waitToKill then
		performTween()
	else
		task.spawn(performTween)
	end
end

-- Returns the last tween played on the given object, or `nil` if none exists.
function AnimNation.getTweenFromInstance(object: Instance): Tween?
	return TweenDirectory[object]
end

-- Instantly set the given object's properties to a lerped value between it's
-- current state and the given properties. Functions like `.tweenFromAlpha()`,
-- except that it doesn't continue to play the tween. Naturally, the time value
-- used in the provided TweenInfo or table has no effect on this function.
--
-- Currently supports number, Vector2, Vector3, CFrame, Color3, UDim2, UDim and
-- any other type that supports scalar multiplication/addition.
function AnimNation.lerp(
	object: Instance,
	tweenInfo: TweenInfo | {},
	properties: { [string]: any },
	alpha: number
)
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
		local start = if object:IsA("PVInstance") and typeof(value) == "CFrame" then object:GetPivot() else object[property]
		lerpedValues[property] = lerp(start, value, startingAlpha)
	end

	-- Instantly apply starting values, overriding any other tweens on this
	-- object
	AnimNation.tween(object, TweenInfo.new(0), lerpedValues, true)
end

-- Asynchronously performs a spring impulse on the given object.
--
-- `SpringInfo` is a table of spring properties such as `{s = 10, d = 0.5}`. The
-- optional `waitToKill` flag will make the operation synchronous if true.
--
-- `:AndThen()` can be used on this function's return value to link another
-- function that will be called when the spring completes (reaches epsilon).
function AnimNation.impulse(
	object: Instance,
	springInfo: SpringInfo,
	properties: { [string]: any },
	waitToKill: boolean?
): AnimChain
	if not object then
		error("Spring failure - invalid object passed")
		return AnimChain.new()
	end

	local animChain: AnimChain
	local impulsesWorking = 0
	local isPVInstance = object:IsA("PVInstance")
	local isModel = object:IsA("Model")

	for property, impulse in pairs(properties) do
		local impulseType = typeof(impulse)
		if SUPPORTED_TYPES[impulseType] then
			local needsAnimationLink = true

			if isPVInstance and property == "CFrame" then
				springInfo.Initial = object:GetPivot()
			elseif isModel and property == "Scale" then
				springInfo.Initial = object:GetScale()
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
				animChain = AnimChain.new(newSpring)
			end

			newSpring:Impulse(impulse)

			if needsAnimationLink then
				if waitToKill and animChain then
					impulsesWorking += 1
					task.spawn(function()
						animate(newSpring, object, property)
						impulsesWorking -= 1
					end)
				else
					task.spawn(animate, newSpring, object, property)
				end
			end
		else
			error(string.format("Spring failure - invalid impulse type '%s' for property '%s'", impulseType, property))
		end
	end

	while impulsesWorking > 0 do
		task.wait()
	end

	return animChain :: AnimChain
end

-- Asynchronously uses a spring to transition the given object's properties to
-- the specified values.
--
--`SpringInfo` is a table of spring properties such as `{s = 10, d = 0.5}`. The
-- optional `waitToKill` flag will make the operation synchronous if true.
--
-- NOTE: Currently there is no `AnimChain` returned to enable `:AndThen()`
-- behavior. I plan to fix this in a future update.
function AnimNation.target(
	object: Instance,
	springInfo: SpringInfo,
	properties: { [string]: any },
	waitToKill: boolean?
)
	local springsWorking = 0
	for property, target in pairs(properties) do
		local targetType = typeof(target)
		if not ZEROS[targetType] then
			error("Spring failure - unsupported target type '" .. targetType .. "' passed")
			continue
		end
		springInfo.Target = target
		springsWorking += 1
		AnimNation.impulse(object, springInfo, { [property] = ZEROS[targetType] }):AndThen(function()
			springsWorking -= 1
		end)
		springInfo.Target = nil
	end

	if waitToKill then
		while springsWorking > 0 do
			task.wait()
		end
	end
end

-- Binds a callback function to the given springs' position and velocity. Can be
-- used to create more complex and constant interactions with spring values than
-- just a quick impulse or target.
function AnimNation.bind(
	springs: { Spring },
	label: string,
	callback: (positions: { Springable }, velocities: { Springable }) -> ()
)
	SpringBinds[label] = { springs, callback, false }
	springBindLoop()
end

-- Unbinds the callback associated with the specified label from updates.
function AnimNation.unbind(label: string)
	SpringBinds[label] = nil
end

-- Creates a new spring with the given properties. `SpringInfo` is a table of
-- spring properties such as `{s = 10, d = 0.5}`. Optionally allows you to
-- provide a name for lookup with `AnimNation.getSpring()`.
function AnimNation.createSpring(springInfo: SpringInfo, name: string?): Spring
	local newSpring = createSpringFromInfo(springInfo)
	if name then
		SpringDirectory[name] = newSpring
	end
	return newSpring
end

-- Returns the spring with the given name. If none exists, it will return `nil`
-- with a warning, or an error depending on the set `ERROR_POLICY`.
function AnimNation.getSpring(name: string): Spring?
	if SpringDirectory[name] then
		return SpringDirectory[name]
	else
		error(string.format("Spring '%s' does not exist", name))
	end
end

-- Creates a new spline from the given control points. This should be a table of
-- CFrame values with at least 4 entries. Optionally allows you to provide a
-- name for lookup with `AnimNation.getSpline()`.
function AnimNation.createSpline(controlPoints: {CFrame}, name: string?): Spline
	local newSpline = Spline.new(controlPoints) :: Spline
	if name then
		SplineDirectory[name] = newSpline
	end
	return newSpline
end

---Returns the spline with the given name. If none exists, it will return `nil`
-- with a warning, or an error depending on the set `ERROR_POLICY`.
function AnimNation.getSpline(name: string): Spline?
	if SplineDirectory[name] then
		return SplineDirectory[name]
	else
		error(string.format("Spline '%s' does not exist", name))
	end
end

-- Asynchronously performs tween-based spherical interpolation on the given
-- object, starting from the specified `alpha` percentage.
--
-- Parameters are similar to `AnimNation.tweenFromAlpha()`, with the addition of
-- `alignment` which determines whether the object being tweened is aligned to
-- the track orientation or the nodes' orientations. A spline argument is also
-- required, which can be supplied as previously constructed Spline object or an
-- array of points to create a new one from.
--
-- `:AndThen()` can be used to link a callback function when the tween
-- completes.
--
-- Currently supports number, Vector2, Vector3, CFrame, Color3, UDim2, UDim and
-- any other type that supports scalar multiplication/addition.
function AnimNation.slerpTweenFromAlpha(
	object: Instance,
	tweenInfo: TweenInfo | {},
	spline: Spline | {CFrame},
	alignment: ("Track" | "Nodes")?,
	alpha: number?,
	waitToKill: boolean?
): AnimChain
	alpha = alpha or 0
	alignment = alignment or "Nodes"

	if typeof(alpha) ~= "number" then
		error("Slerp tween failure - alpha must be a number")
		return AnimChain.new()
	elseif typeof(spline) ~= "table" then
		error("Slerp tween failure - spline must be a table")
		return AnimChain.new()
	elseif alignment ~= "Track" and alignment ~= "Nodes" then
		error("Slerp tween failure - alignment must be 'Track' or 'Nodes'")
		return AnimChain.new()
	elseif not object then
		error("Slerp tween failure - invalid object passed")
		if waitToKill then
			task.wait(tweenInfo.Time * (1 - alpha))
		end
		return AnimChain.new()
	end

	if spline[1] then
		spline = Spline.new(spline)
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
	local startingProperties = {CFrame = spline:GetLinearCFrameFromAlpha(0, alignment)}
	local properties = {CFrame = spline:GetLinearCFrameAtAlpha(1, alignment)}
	local isPVInstance = object:IsA("PVInstance")
	local isModel = object:IsA("Model")

	for property, value in pairs(properties) do
		startingProperties[property] = if object:IsA("PVInstance") and typeof(value) == "CFrame" then object:GetPivot() else object[property]
		firstIteration[property] = lerp(startingProperties[property], value, startingAlpha)
		-- Set custom tween control to this process
		CustomTweens[object][property] = thisTweenId
	end

	-- Instantly apply starting values through TweenService, overriding any
	-- regular tweens from calling .tween()
	AnimNation.tween(object, {t = 0, _skipControlReset = true}, firstIteration, true)

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
						local newValue = spline:GetCFrameFromAlpha(currentAlpha, alignment)
						if isPVInstance and property == "CFrame" then
							object:PivotTo(newValue)
						elseif isModel and property == "Scale" then
							object:ScaleTo(newValue)
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
						object:PivotTo(properties[property])
					elseif isModel and property == "Scale" then
						object:ScaleTo(properties[property])
					else
						object[property] = properties[property]
					end
				end
			end
		end

		if CustomTweens[object] then
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

	if waitToKill then
		performTween()
	else
		task.spawn(performTween)
	end
end

-- Public Function Aliases

AnimNation.inquire = AnimNation.getSpring
AnimNation.register = AnimNation.createSpring

return AnimNation
