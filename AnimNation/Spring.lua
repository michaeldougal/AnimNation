--[[
Description:
	A physical model of a spring, useful in many applications. Originally by
	Quenty, modified heavily by ChiefWildin and TactBacon.

API:
	Spring.new(position: Vector3 | Vector2 | number | UDim2 | UDim | CFrame | Color3)
		Creates a new spring

	[Accessing]
		Spring.Position
			Returns the current position
		Spring.Velocity
			Returns the current velocity
		Spring.Target
			Returns the target
		Spring.Damper
			Returns the damper
		Spring.Speed
			Returns the speed
		Spring.Clock
			Returns the clock function used to track time
		Spring.Type
			Returns the type of value being tracked

	[Setting]
		Target: Vector3 | Vector2 | number | UDim2 | UDim | CFrame | Color3
			Sets the target
		Position: Vector3 | Vector2 | number | UDim2 | UDim | CFrame | Color3
			Sets the position
		Velocity: Vector3 | Vector2 | number | UDim2 | UDim | CFrame | Color3
			Sets the velocity
		Damper: number [0, 1]
			Sets the spring damper, defaults to 1
		Speed: number [0, infinity)
			Sets the spring speed, defaults to 1

	[Functions]
		:TimeSkip(number DeltaTime)
			Instantly skips the spring forwards by that amount of now
		:Impulse(velocity: Vector3 | Vector2 | number | UDim2 | UDim | CFrame | Color3)
			Impulses the spring, increasing velocity by the amount given
		:Bind(label: string, callback: function)
			Binds a callback function to the given spring's position and
			velocity. Can be used to create more complex and constant
			interactions with spring values than just a quick impulse or target
		:Unbind(label: string)
			Unbinds the given callback label from the spring
		:IsAnimating(epsilon: number?): (boolean, Vector3)
			Returns whether or not the spring is animating, and the current
			position

Visualization (by Defaultio):
	https://www.desmos.com/calculator/hn2i9shxbz
]]


local Spring = {}

export type Springable = Vector3 | Vector2 | number | UDim2 | UDim | CFrame | Color3
export type Spring = {
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
	IsAnimating: (Spring, epsilon: number?) -> (boolean, Vector3)
}

local EULER = 2.7182818284590452353602874713527
local EPSILON = 1e-4
local ZEROS = {
	["number"] = 0,
	["Vector2"] = Vector2.zero,
	["Vector3"] = Vector3.zero,
	["UDim2"] = UDim2.new(),
	["UDim"] = UDim.new(),
	["CFrame"] = CFrame.new(),
	["Color3"] = Color3.new(),
}

-- Aliases (for super speeeeeeeeed)
local clamp = math.clamp
local cos = math.cos
local sin = math.sin
local abs = math.abs
local udim2 = UDim2.new
local udim = UDim.new
local color3 = Color3.new
local cframe = CFrame.new
local cframeFromOrientation = CFrame.fromOrientation
local cframeToOrientation = CFrame.identity.ToOrientation
local vector3 = Vector3.new

local function directConversion(a, b, sine, cosH, damperSin, speed, start, velocity, target)
	return a * start + (1 - a) * target + (sine / speed) * velocity,
		-b * start + b * target + (cosH - damperSin) * velocity
end

local Converters = {
	["number"] = directConversion,
	["Vector2"] = directConversion,
	["Vector3"] = directConversion,
	["UDim2"] = function(a, b, sine, cosH, damperSin, speed, start, velocity, target)
		local c = 1 - a
		local d = sine / speed
		local e = cosH - damperSin
		return
			udim2(
				a * start.X.Scale + c * target.X.Scale + d * velocity.X.Scale,
				a * start.X.Offset + c * target.X.Offset + d * velocity.X.Offset,
				a * start.Y.Scale + c * target.Y.Scale + d * velocity.Y.Scale,
				a * start.Y.Offset + c * target.Y.Offset + d * velocity.Y.Offset),
			udim2(
				-b * start.X.Scale + b * target.X.Scale + e * velocity.X.Scale,
				-b * start.X.Offset + b * target.X.Offset + e * velocity.X.Offset,
				-b * start.Y.Scale + b * target.Y.Scale + e * velocity.Y.Scale,
				-b * start.X.Offset + b * target.X.Offset + e * velocity.X.Offset)
	end,
	["UDim"] = function(a, b, sine, cosH, damperSin, speed, start, velocity, target)
		local c = 1 - a
		local d = sine / speed
		local e = cosH - damperSin
		return
			udim(
				a * start.Scale + c * target.Scale + d * velocity.Scale,
				a * start.Offset + c * target.Offset + d * velocity.Offset),
			udim(
				-b * start.Scale + b * target.Scale + e * velocity.Scale,
				-b * start.Offset + b * target.Offset + e * velocity.Offset)
	end,
	["CFrame"] = function(a, b, sine, cosH, damperSin, speed, start: CFrame, velocity: CFrame, target: CFrame)
		local c = 1 - a
		local d = sine / speed
		local e = cosH - damperSin

		local startAngle = vector3(cframeToOrientation(start))
		local targetAngle = vector3(cframeToOrientation(target))
		local velocityAngle = vector3(cframeToOrientation(velocity))

		local pos = cframe(a * start.Position + c * target.Position + d * velocity.Position)
		local posRot = a * startAngle + c * targetAngle + d * velocityAngle
		pos *= cframeFromOrientation(posRot.X, posRot.Y, posRot.Z)

		local vel = cframe(-b * start.Position + b * target.Position + e * velocity.Position)
		local velRot = -b * startAngle + b * targetAngle + e * velocityAngle
		vel *= cframeFromOrientation(velRot.X, velRot.Y, velRot.Z)

		return pos, vel
	end,
	["Color3"] = function(a, b, sine, cosH, damperSin, speed, start: Color3, velocity: Color3, target: Color3)
		local c = 1 - a
		local d = sine / speed
		local e = cosH - damperSin
		return
			color3(
				clamp(a * start.R + c * target.R + d * velocity.R, 0, 1),
				clamp(a * start.G + c * target.G + d * velocity.G, 0, 1),
				clamp(a * start.B + c * target.B + d * velocity.B, 0, 1)),
			color3(
				clamp(-b * start.R + b * target.R + e * velocity.R, 0, 1),
				clamp(-b * start.G + b * target.G + e * velocity.G, 0, 1),
				clamp(-b * start.B + b * target.B + e * velocity.B, 0, 1))
	end
}

local function directVelocity(self, velocity)
	self.Velocity += velocity
end

local VelocityConverters = {
	["number"] = directVelocity,
	["Vector2"] = directVelocity,
	["Vector3"] = directVelocity,
	["UDim2"] = directVelocity,
	["UDim"] = directVelocity,
	["CFrame"] = function(self, velocity)
		self.Velocity *= velocity
	end,
	["Color3"] = function(self, velocity)
		self.Velocity = color3(
			self.Velocity.R + velocity.R,
			self.Velocity.G + velocity.G,
			self.Velocity.B + velocity.B)
	end
}

--- Creates a new spring
---@param initial Vector3 | Vector2 | number | UDim2 | UDim | CFrame | Color3 The starting position of the spring
---@param clock number function to use to update spring
function Spring.new(initial: Springable, clock): Spring
	local target = initial or 0
	clock = clock or os.clock
	return setmetatable({
		_clock = clock,
		_time0 = clock(),
		_position0 = target,
		_velocity0 = ZEROS[typeof(target)],
		_target = target,
		_damper = 1,
		_speed = 1,
		_type = typeof(target),
		_updating = false,
		_callbacks = {},
		_isBound = false,
	}, Spring)
end

--- Impulse the spring with a change in velocity
---@param velocity Vector3 | Vector2 | number | UDim2 | UDim | CFrame | Color3 The velocity to impulse with
function Spring:Impulse(velocity: Springable)
	VelocityConverters[self.Type](self, velocity)
	self:_updateCallbacks()
end

--- Skips the spring forward by the specified amount of time
---@param delta number The amount of time to skip forward in seconds
function Spring:TimeSkip(delta: number)
	local now = self._clock()
	local position, velocity = self:_positionVelocity(now + delta)
	self._position0 = position
	self._velocity0 = velocity
	self._time0 = now
end

-- Binds a callback function to the given spring's position and velocity. Can be
-- used to create more complex and constant interactions with spring values than
-- just a quick impulse or target.
function Spring:Bind(label: string, callback: (position: Springable, velocity: Springable) -> ())
	if self._callbacks[label] then
		warn("Spring already had a bound callback for label '" .. label .. "', overwriting...\n" .. debug.traceback())
	end
	self._isBound = true
	self._callbacks[label] = callback
	self:_updateCallbacks()
end

-- Unbinds the given callback label from the spring.
function Spring:Unbind(label: string)
	self._callbacks[label] = nil

	-- Check if any other callbacks still exist
	for _ in pairs(self._callbacks) do
		return
	end

	-- If not, mark it as unbound to avoid busy work
	self._isBound = false
end

-- Returns whether or not the spring is animating, and the current position
function Spring:IsAnimating(epsilon: number?): (boolean, Vector3)
	epsilon = epsilon or EPSILON

	local position = self.Position
	local velocity = self.Velocity
	local target = self.Target
	local animating

	if self.Type == "number" then
		animating = abs(position - target) > epsilon or abs(velocity) > epsilon
	elseif self.Type == "Vector3" or self.Type == "Vector2" then
		animating = (position - target).Magnitude > epsilon or velocity.Magnitude > epsilon
	elseif self.Type == "UDim2" then
		animating = abs(position.X.Scale - target.X.Scale) > epsilon
			or abs(velocity.X.Scale) > epsilon
			or abs(position.X.Offset - target.X.Offset) > epsilon
			or abs(velocity.X.Offset) > epsilon
			or abs(position.Y.Scale - target.Y.Scale) > epsilon
			or abs(velocity.Y.Scale) > epsilon
			or abs(position.Y.Offset - target.Y.Offset) > epsilon
			or abs(velocity.Y.Offset) > epsilon
	elseif self.Type == "UDim" then
		animating = abs(position.Scale - target.Scale) > epsilon
			or abs(velocity.Scale) > epsilon
			or abs(position.Offset - target.Offset) > epsilon
			or abs(velocity.Offset) > epsilon
	elseif self.Type == "CFrame" then
		local startAngle = vector3(cframeToOrientation(position))
		local targetAngle = vector3(cframeToOrientation(target))
		local velocityAngle = vector3(cframeToOrientation(velocity))
		animating = (position.Position - target.Position).Magnitude > epsilon
			or velocity.Position.Magnitude > epsilon
			or (startAngle - targetAngle).Magnitude > epsilon
			or velocityAngle.Magnitude > epsilon
	elseif self.Type == "Color3" then
		local startVector = vector3(position.R, position.G, position.B)
		local velocityVector = vector3(velocity.R, velocity.G, velocity.B)
		local targetVector = vector3(target.R, target.G, target.B)
		animating = (startVector - targetVector).Magnitude > epsilon or velocityVector.Magnitude > epsilon
	else
		error("Unknown type")
	end

	if animating then
		return true, position
	else
		-- We need to return the target so we use the actual target value (i.e. pretend like the spring is asleep)
		return false, target
	end
end

function Spring:__index(index: string)
	if Spring[index] then
		return Spring[index]
	elseif index == "Value" or index == "Position" or index == "p" then
		local position, _ = self:_positionVelocity(self._clock())
		return position
	elseif index == "Velocity" or index == "v" then
		local _, velocity = self:_positionVelocity(self._clock())
		return velocity
	elseif index == "Target" or index == "t" then
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

function Spring:__newindex(index: string, value)
	local now = self._clock()

	if index == "Value" or index == "Position" or index == "p" then
		local _, velocity = self:_positionVelocity(now)
		self._position0 = value
		self._velocity0 = velocity
		self._time0 = now
	elseif index == "Velocity" or index == "v" then
		local position, _ = self:_positionVelocity(now)
		self._position0 = position
		self._velocity0 = value
		self._time0 = now
	elseif index == "Target" or index == "t" then
		local position, velocity = self:_positionVelocity(now)
		self._position0 = position
		self._velocity0 = velocity
		self._target = value
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
		local u = EULER ^ (((-damper + h) * t)) / (2 * h)
		local v = EULER ^ (((-damper - h) * t)) / (2 * h)
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
	if self._isBound and not self._updating then
		task.spawn(function()
			self._updating = true
			while self:IsAnimating() do
				for _, callback in pairs(self._callbacks) do
					callback(self.Position, self.Velocity)
				end
				task.wait()
			end
			self._updating = false
		end)
	end
end

return Spring
