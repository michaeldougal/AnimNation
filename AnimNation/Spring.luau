--[[ File Info
	Author(s): ChiefWildin, TactBacon, Quenty
]]

-- Types

--[=[
	@type Springable Vector3 | Vector2 | number | UDim2 | UDim | CFrame | Color3
	@within Spring
]=]
export type Springable = Vector3 | Vector2 | number | UDim2 | UDim | CFrame | Color3
type Converter = (
	a: number,
	b: number,
	sine: number,
	cosH: number,
	damperSin: number,
	speed: number,
	start: Springable | { number },
	velocity: Springable | { number },
	target: Springable | { number }
) -> (Springable, Springable)
type VelocityConverter = (self: Spring, velocity: Springable) -> ()
export type SpringImpl = {
	-- Metatable members

	__index: (Spring, string) -> any,
	__newindex: (Spring, string, any) -> (),

	-- Public members

	new: (initial: Springable, clock: ((number) -> ())?) -> Spring,
	Bind: (self: Spring, label: string, callback: (position: Springable, velocity: Springable) -> ()) -> (),
	Destroy: (self: Spring) -> (),
	Disconnect: (self: Spring) -> (),
	Impulse: (self: Spring, force: Springable) -> (),
	IsAnimating: (self: Spring, epsilon: number?) -> (boolean, Springable),
	TimeSkip: (self: Spring, delta: number) -> (),
	Unbind: (self: Spring, label: string) -> (),

	Position: Springable,
	Velocity: Springable,
	Target: Springable,
	Damper: number,
	Speed: number,
	Clock: () -> number,
	Type: string,

	-- Private members

	_positionVelocity: (self: Spring, now: number) -> (Springable, Springable),
	_updateCallbacks: (self: Spring) -> (),
}
export type Spring = typeof(setmetatable(
	{} :: {
		-- Constructed public members
		Position: Springable,
		Velocity: Springable,
		Target: Springable,
		Damper: number,
		Speed: number,
		Clock: () -> number,
		Type: string,
		Impulse: (Spring, force: Springable) -> (),
		TimeSkip: (Spring, delta: number) -> (),
		Bind: (Spring, label: string, callback: (position: Springable, velocity: Springable) -> ()) -> (),
		Unbind: (Spring, label: string) -> (),
		IsAnimating: (Spring, epsilon: number?) -> (boolean, Vector3),

		-- Constructed private members
		_type: string,
		_target: Springable | { number },
		_position0: Springable | { number },
		_velocity0: Springable | { number },

		_clock: () -> number,
		_time0: number,
		_damper: number,
		_speed: number,
		_updating: boolean,
		_isBound: boolean,
		_callbacks: { [string]: (position: Springable, velocity: Springable) -> () },
	},
	{} :: SpringImpl
))

-- Module Declaration

--[=[
	@class Spring

	A physical model of a spring for Roblox. Based off of Quenty's open source
	version
	(https://github.com/Quenty/NevermoreEngine/blob/main/src/spring/src/Shared/Spring.lua)

	Visualization (by Defaultio): https://www.desmos.com/calculator/hn2i9shxbz
]=]
--[=[
	@prop Position Springable
	@within Spring
	Returns the current position of the spring
]=]
--[=[
	@prop Velocity Springable
	@within Spring
	Returns the current velocity of the spring
]=]
--[=[
	@prop Target Springable
	@within Spring
	Returns the target of the spring
]=]
--[=[
	@prop Damper number
	@within Spring
	Returns the damper of the spring, defaults to 1. [0, 1]
]=]
--[=[
	@prop Speed number
	@within Spring
	Returns the speed of the spring, defaults to 30. [0, infinity)
]=]
--[=[
	@prop Clock number
	@within Spring
	Returns the clock function used to track time
]=]
--[=[
	@prop Type string
	@within Spring
	Returns the type of value being tracked
]=]
local Spring: SpringImpl = {} :: SpringImpl

-- Constants

local EULER = 2.7182818284590452353602874713527
local EPSILON = 1e-4
local PI2 = math.pi * 2
local ZEROS = {
	["number"] = 0,
	["Vector2"] = Vector2.zero,
	["Vector3"] = Vector3.zero,
	["UDim2"] = UDim2.new(),
	["UDim"] = UDim.new(),
	["Color3"] = Color3.new(),
}

-- Aliases

local clamp = math.clamp
local cos = math.cos
local sin = math.sin
local abs = math.abs
local udim2 = UDim2.new
local udim = UDim.new
local color3 = Color3.new
local cframe = CFrame.new
local angles = CFrame.fromEulerAnglesYXZ
local vector3 = Vector3.new

-- Private Functions

local function directConversion(a, b, sine, cosH, damperSin, speed, start, velocity, target)
	return a * start + (1 - a) * target + (sine / speed) * velocity,
		-b * start + b * target + (cosH - damperSin) * velocity
end

local Converters: { [string]: Converter } = {
	["number"] = directConversion,
	["Vector2"] = directConversion,
	["Vector3"] = directConversion,
	["UDim2"] = function(a, b, sine, cosH, damperSin, speed, start, velocity, target)
		local c = 1 - a
		local d = sine / speed
		local e = cosH - damperSin
		return udim2(
			a * start.X.Scale + c * target.X.Scale + d * velocity.X.Scale,
			a * start.X.Offset + c * target.X.Offset + d * velocity.X.Offset,
			a * start.Y.Scale + c * target.Y.Scale + d * velocity.Y.Scale,
			a * start.Y.Offset + c * target.Y.Offset + d * velocity.Y.Offset
		),
			udim2(
				-b * start.X.Scale + b * target.X.Scale + e * velocity.X.Scale,
				-b * start.X.Offset + b * target.X.Offset + e * velocity.X.Offset,
				-b * start.Y.Scale + b * target.Y.Scale + e * velocity.Y.Scale,
				-b * start.X.Offset + b * target.X.Offset + e * velocity.X.Offset
			)
	end,
	["UDim"] = function(a, b, sine, cosH, damperSin, speed, start, velocity, target)
		local c = 1 - a
		local d = sine / speed
		local e = cosH - damperSin
		return udim(
			a * start.Scale + c * target.Scale + d * velocity.Scale,
			a * start.Offset + c * target.Offset + d * velocity.Offset
		),
			udim(
				-b * start.Scale + b * target.Scale + e * velocity.Scale,
				-b * start.Offset + b * target.Offset + e * velocity.Offset
			)
	end,
	["CFrame"] = function(a, b, sine, cosH, damperSin, speed, start, velocity, target)
		local c = 1 - a
		local d = sine / speed
		local e = cosH - damperSin

		local startPos = vector3(start[1], start[2], start[3])
		local startAngle = vector3(start[4], start[5], start[6])
		local targetPos = vector3(target[1], target[2], target[3])
		local targetAngle = vector3(target[4], target[5], target[6])
		local velocityPos = vector3(velocity[1], velocity[2], velocity[3])
		local velocityAngle = vector3(velocity[4], velocity[5], velocity[6])

		local pos = a * startPos + c * targetPos + d * velocityPos
		local posRot = a * startAngle + c * targetAngle + d * velocityAngle

		local vel = -b * startPos + b * targetPos + e * velocityPos
		local velRot = -b * startAngle + b * targetAngle + e * velocityAngle

		return { pos.X, pos.Y, pos.Z, posRot.X, posRot.Y, posRot.Z }, {
			vel.X,
			vel.Y,
			vel.Z,
			velRot.X,
			velRot.Y,
			velRot.Z,
		}
	end,
	["Color3"] = function(a, b, sine, cosH, damperSin, speed, start, velocity, target)
		local c = 1 - a
		local d = sine / speed
		local e = cosH - damperSin
		return color3(
			clamp(a * start.R + c * target.R + d * velocity.R, 0, 1),
			clamp(a * start.G + c * target.G + d * velocity.G, 0, 1),
			clamp(a * start.B + c * target.B + d * velocity.B, 0, 1)
		),
			color3(
				clamp(-b * start.R + b * target.R + e * velocity.R, 0, 1),
				clamp(-b * start.G + b * target.G + e * velocity.G, 0, 1),
				clamp(-b * start.B + b * target.B + e * velocity.B, 0, 1)
			)
	end,
}

local function directVelocity(self, velocity)
	self.Velocity += velocity
end

local VelocityConverters: { [string]: VelocityConverter } = {
	["number"] = directVelocity,
	["Vector2"] = directVelocity,
	["Vector3"] = directVelocity,
	["UDim2"] = directVelocity,
	["UDim"] = directVelocity,
	["CFrame"] = function(self, velocity)
		velocity = { velocity.X, velocity.Y, velocity.Z, velocity:ToEulerAnglesYXZ() }
		self:_positionVelocity(self._clock())
		self._velocity0 = {
			self._velocity0[1] + velocity[1],
			self._velocity0[2] + velocity[2],
			self._velocity0[3] + velocity[3],
			self._velocity0[4] + velocity[4],
			self._velocity0[5] + velocity[5],
			self._velocity0[6] + velocity[6],
		}
		self._time0 = self._clock()
	end,
	["Color3"] = function(self, velocity)
		self.Velocity = color3(self.Velocity.R + velocity.R, self.Velocity.G + velocity.G, self.Velocity.B + velocity.B)
	end,
}

local function convertToClosestAngle(currentAngle, givenTargetAngle)
	local backward = givenTargetAngle - currentAngle
	local forward = PI2 + backward

	if abs(forward) < abs(backward) then
		return currentAngle + forward
	else
		return currentAngle + backward
	end
end

function Spring:__index(index: string)
	if Spring[index] then
		return Spring[index]
	elseif index == "Value" or index == "Position" or index == "p" then
		local position, _ = self:_positionVelocity(self._clock())
		if self._type == "CFrame" then
			position = cframe(position[1], position[2], position[3]) * angles(position[4], position[5], position[6])
		end
		return position
	elseif index == "Velocity" or index == "v" then
		local _, velocity = self:_positionVelocity(self._clock())
		if self._type == "CFrame" then
			velocity = cframe(velocity[1], velocity[2], velocity[3]) * angles(velocity[4], velocity[5], velocity[6])
		end
		return velocity
	elseif index == "Target" or index == "t" then
		if self._type == "CFrame" then
			return cframe(self._target[1], self._target[2], self._target[3])
				* angles(self._target[4], self._target[5], self._target[6])
		end
		return self._target
	elseif index == "Damper" or index == "d" then
		return self._damper
	elseif index == "Speed" or index == "s" then
		return self._speed
	elseif index == "Clock" then
		return self._clock
	elseif index == "Type" then
		return self._type
	else
		error(("%q is not a valid member of Spring"):format(tostring(index)), 2)
	end
end

function Spring:__newindex(index: string, value: any)
	local now = self._clock()

	if index == "Value" or index == "Position" or index == "p" then
		local _, velocity = self:_positionVelocity(now)
		if self._type == "CFrame" then
			value = { value.X, value.Y, value.Z, value:ToEulerAnglesYXZ() }
			self._position0 = table.clone(value)
		else
			self._position0 = value
		end
		self._velocity0 = velocity
		self._time0 = now
	elseif index == "Velocity" or index == "v" then
		local position, _ = self:_positionVelocity(now)
		self._position0 = position
		if self._type == "CFrame" then
			value = { value.X, value.Y, value.Z, value:ToEulerAnglesYXZ() }
			self._velocity0 = table.clone(value)
		else
			self._velocity0 = value
		end
		self._time0 = now
	elseif index == "Target" or index == "t" then
		local position, velocity = self:_positionVelocity(now)
		self._position0 = position
		self._velocity0 = velocity
		if self._type == "CFrame" then
			local posRotX, posRotY, posRotZ = position[4], position[5], position[6]
			local targetRotX, targetRotY, targetRotZ = value:ToEulerAnglesYXZ()
			value = {
				value.X,
				value.Y,
				value.Z,
				convertToClosestAngle(posRotX, targetRotX),
				convertToClosestAngle(posRotY, targetRotY),
				convertToClosestAngle(posRotZ, targetRotZ),
			}
			self._target = table.clone(value)
		else
			self._target = value
		end
		self._time0 = now
	elseif index == "Damper" or index == "d" then
		local position, velocity = self:_positionVelocity(now)
		self._position0 = position
		self._velocity0 = velocity
		self._damper = value
		self._time0 = now
	elseif index == "Speed" or index == "s" then
		local position, velocity = self:_positionVelocity(now)
		self._position0 = position
		self._velocity0 = velocity
		self._speed = value < 0 and 0 or value
		self._time0 = now
	elseif index == "Clock" then
		local position, velocity = self:_positionVelocity(now)
		self._position0 = position
		self._velocity0 = velocity
		self._clock = value
		self._time0 = value()
	else
		error(("%q is not a valid member of Spring"):format(tostring(index)), 2)
	end

	self:_updateCallbacks()
end

function Spring:_positionVelocity(now: number)
	local damper = self._damper
	local speed = self._speed
	local t = speed * (now - self._time0)
	local damperSquared = damper * damper
	local h, sine, cosine

	if damperSquared < 1 then
		h = (1 - damperSquared) ^ 0.5
		local ep = EULER ^ (-damper * t) / h
		cosine = ep * cos(h * t)
		sine = ep * sin(h * t)
	elseif damperSquared == 1 then
		h = 1
		local ep = EULER ^ (-damper * t) / h
		cosine = ep
		sine = ep * t
	else
		h = (damperSquared - 1) ^ 0.5
		local u = EULER ^ ((-damper + h) * t) / (2 * h)
		local v = EULER ^ ((-damper - h) * t) / (2 * h)
		cosine = u + v
		sine = u - v
	end

	local cosH = h * cosine
	local damperSin = damper * sine
	local a = cosH + damperSin
	local b = speed * sine

	return Converters[self._type](a, b, sine, cosH, damperSin, speed, self._position0, self._velocity0, self._target)
end

function Spring:_updateCallbacks()
	if not self._isBound or self._updating then
		return
	end

	self._updating = true

	task.spawn(function()
		while self._isBound and self:IsAnimating() do
			for _, callback in self._callbacks do
				task.spawn(callback, self.Position, self.Velocity)
			end
			task.wait()
		end
		-- One more pass because callbacks may not have been called with the
		-- final values (happens frequently during low frame rates)
		for _, callback in self._callbacks do
			task.spawn(callback, self.Position, self.Velocity)
		end
		self._updating = false
	end)
end

-- Public Functions

--[=[
	Impulse the spring with a change in velocity
	@param velocity Springable -- The velocity to impulse with
]=]
function Spring:Impulse(velocity: Springable)
	VelocityConverters[self.Type](self, velocity)
	self:_updateCallbacks()
end

--[=[
	Skips the spring forward by the specified amount of time
	@param delta number -- The amount of time to skip forward in seconds
]=]
function Spring:TimeSkip(delta: number)
	local now = self._clock()
	local position, velocity = self:_positionVelocity(now + delta)
	self._position0 = position
	self._velocity0 = velocity
	self._time0 = now
end

--[=[
	Binds a callback function to the given spring's position and velocity. Can be
	used to create more complex and constant interactions with spring values than
	just a quick impulse or target.

	@param label string -- The label to bind the callback to.
	@param callback (position: Springable, velocity: Springable) -> () -- The callback function to bind
]=]
function Spring:Bind(label: string, callback: (position: Springable, velocity: Springable) -> ())
	if self._callbacks[label] then
		warn("Spring already had a bound callback for label '" .. label .. "', overwriting...\n" .. debug.traceback())
	end
	self._isBound = true
	self._callbacks[label] = callback
	self:_updateCallbacks()
end

--[=[
	Unbinds the given callback label from the spring.

	@param label string -- The label to unbind the callback from.
]=]
function Spring:Unbind(label: string)
	self._callbacks[label] = nil

	-- Check if any other callbacks still exist
	for _ in pairs(self._callbacks) do
		return
	end

	-- If not, mark it as unbound to avoid busy work
	self._isBound = false
end

--[=[
	Returns whether or not the spring is animating, and the current position.

	@param epsilon number? -- The epsilon value to use for determining if the spring is animating. Defaults to 0.0001.
	@return (boolean, Springable) -- Whether or not the spring is animating, and the current position.
]=]
function Spring:IsAnimating(epsilon: number?): (boolean, Springable)
	epsilon = epsilon or EPSILON

	local position, velocity = self:_positionVelocity(self._clock())
	local isCFrame = self._type == "CFrame"
	local target = isCFrame and self._target or self.Target
	local animating

	if self._type == "number" then
		animating = abs(position - target) > epsilon or abs(velocity) > epsilon
	elseif self._type == "Vector3" or self._type == "Vector2" then
		animating = (position - target).Magnitude > epsilon or velocity.Magnitude > epsilon
	elseif self._type == "UDim2" then
		animating = abs(position.X.Scale - target.X.Scale) > epsilon
			or abs(velocity.X.Scale) > epsilon
			or abs(position.X.Offset - target.X.Offset) > epsilon
			or abs(velocity.X.Offset) > epsilon
			or abs(position.Y.Scale - target.Y.Scale) > epsilon
			or abs(velocity.Y.Scale) > epsilon
			or abs(position.Y.Offset - target.Y.Offset) > epsilon
			or abs(velocity.Y.Offset) > epsilon
	elseif self._type == "UDim" then
		animating = abs(position.Scale - target.Scale) > epsilon
			or abs(velocity.Scale) > epsilon
			or abs(position.Offset - target.Offset) > epsilon
			or abs(velocity.Offset) > epsilon
	elseif isCFrame then
		local startPos = vector3(position[1], position[2], position[3])
		local startAngle = vector3(position[4], position[5], position[6])
		local targetPos = vector3(target[1], target[2], target[3])
		local targetAngle = vector3(target[4], target[5], target[6])
		local velocityPos = vector3(velocity[1], velocity[2], velocity[3])
		local velocityAngle = vector3(velocity[4], velocity[5], velocity[6])

		animating = (startPos - targetPos).Magnitude > epsilon
			or velocityPos.Magnitude > epsilon
			or (startAngle - targetAngle).Magnitude > epsilon
			or velocityAngle.Magnitude > epsilon
	elseif self._type == "Color3" then
		local startVector = vector3(position.R, position.G, position.B)
		local velocityVector = vector3(velocity.R, velocity.G, velocity.B)
		local targetVector = vector3(target.R, target.G, target.B)
		animating = (startVector - targetVector).Magnitude > epsilon or velocityVector.Magnitude > epsilon
	else
		error("Unknown type")
	end

	if animating then
		if isCFrame then
			return true, cframe(position[1], position[2], position[3]) * angles(position[4], position[5], position[6])
		end
		return true, position
	else
		-- We need to return the target so we use the actual target value (i.e.
		-- pretend like the spring is asleep)
		if isCFrame then
			return false, cframe(target[1], target[2], target[3]) * angles(target[4], target[5], target[6])
		end
		return false, target
	end
end

--[=[
	Cleans up any bindings.
]=]
function Spring:Destroy()
	for key in self._callbacks do
		self:Unbind(key)
	end
end

--[=[
	Alias for :Destroy()
]=]
function Spring:Disconnect()
	self:Destroy()
end

--[=[
	Creates a new spring.

	@param initial Springable -- The starting position of the spring.
	@param clock (() -> number)? -- function to use to update spring
]=]
function Spring.new(initial: Springable, clock: (() -> number)?)
	local self = {}

	initial = initial or 0

	self._type = typeof(initial)

	if self._type == "CFrame" then
		local unpacked = { initial.X, initial.Y, initial.Z, initial:ToEulerAnglesYXZ() }
		self._target = table.clone(unpacked)
		self._position0 = table.clone(unpacked)
		self._velocity0 = { 0, 0, 0, 0, 0, 0 }
	else
		self._target = initial
		self._position0 = initial
		self._velocity0 = ZEROS[self._type]
	end

	self._clock = clock or tick
	self._time0 = self._clock()
	self._damper = 1
	self._speed = 1
	self._updating = false
	self._isBound = false
	self._callbacks = {}

	return setmetatable(self, Spring)
end

return Spring
