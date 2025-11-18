--[[ File Info
	Author(s): ChiefWildin, EgoMoose
]]

-- Types

export type QuaternionImpl = {
	-- Metatable members

	__index: QuaternionImpl,
	__mul: (x: Quaternion, y: Quaternion) -> Quaternion,
	__pow: (x: Quaternion, power: number) -> Quaternion,

	-- Public members

	ClassName: "Quaternion",

	new: (w: number, v: Vector3) -> Quaternion,
	fromCFrame: (cframe: CFrame) -> Quaternion,
	fromOrientation: (orientation: Vector3) -> Quaternion,

	Inverse: (self: Quaternion) -> Quaternion,
	AxisAngle: (self: Quaternion) -> (Vector3, number),
	Slerp: (self: Quaternion, target: Quaternion, alpha: number) -> Quaternion,
	ToCFrame: (self: Quaternion) -> CFrame,
	ToOrientation: (self: Quaternion) -> Vector3,

	-- Private members
}
export type Quaternion = typeof(setmetatable(
	{} :: {
		-- Constructed public members

		Vector: Vector3,
		W: number,

		-- Constructed private members
	},
	{} :: QuaternionImpl
))
-- Constructors

--[=[
	@class Quaternion

	A quaternion class implementation for Roblox. Based on EgoMoose's version
	(https://github.com/EgoMooseOldProjects/ExampleDump/blob/master/Scripts/slerp.lua)
	provided under the open-source MIT license.
]=]
local Quaternion: QuaternionImpl = { ClassName = "Quaternion" } :: QuaternionImpl

--[=[
	Constructs a new Quaternion object from a given scalar value and vector

	@param w number -- The scalar part of the quaternion
	@param v Vector3 -- The vector part of the quaternion
	@return Quaternion -- The constructed Quaternion object
]=]
function Quaternion.new(w: number, v: Vector3)
	local self = setmetatable({}, {
		__index = Quaternion,
		__mul = function(x: Quaternion, y: Quaternion)
			if y.ClassName and y.ClassName == "Quaternion" then
				local WProduct = x.W * y.W - x.Vector:Dot(y.Vector)
				local VectorProduct = x.Vector * y.W + y.Vector * x.W + x.Vector:Cross(y.Vector)

				return Quaternion.new(WProduct, VectorProduct)
			end

			error(`Quaternion multiplication requires a Quaternion as the second operand, given {tostring(y)}`)
		end,
		__pow = function(x: Quaternion, power: number)
			local axis, angle = x:AxisAngle()
			angle *= power
			local halfAngle = angle * 0.5

			return Quaternion.new(math.cos(halfAngle), math.sin(halfAngle) * axis)
		end,
	})

	self.W = w
	self.Vector = v

	return self
end

--[=[
	Constructs a new Quaternion object from a given CFrame
	Originally sourced from the wiki (source no longer available):
	http://wiki.roblox.com/index.php?title=Quaternions_for_rotation#Quaternion_from_a_Rotation_Matrix

	@param cframe CFrame -- The CFrame to convert to a Quaternion
	@return Quaternion -- The constructed Quaternion object
]=]
function Quaternion.fromCFrame(cframe: CFrame)
	local _, _, _, m00, m01, m02, m10, m11, m12, m20, m21, m22 = cframe:GetComponents()
	local trace = m00 + m11 + m22
	if trace > 0 then
		local s = math.sqrt(1 + trace)
		local r = 0.5 / s
		return Quaternion.new(s * 0.5, Vector3.new((m21 - m12) * r, (m02 - m20) * r, (m10 - m01) * r))
	else
		-- Find the largest diagonal element
		local big = math.max(m00, m11, m22)
		if big == m00 then
			local s = math.sqrt(1 + m00 - m11 - m22)
			local r = 0.5 / s
			return Quaternion.new((m21 - m12) * r, Vector3.new(0.5 * s, (m10 + m01) * r, (m02 + m20) * r))
		elseif big == m11 then
			local s = math.sqrt(1 - m00 + m11 - m22)
			local r = 0.5 / s
			return Quaternion.new((m02 - m20) * r, Vector3.new((m10 + m01) * r, 0.5 * s, (m21 + m12) * r))
		else -- big == m22
			local s = math.sqrt(1 - m00 - m11 + m22)
			local r = 0.5 / s
			return Quaternion.new((m10 - m01) * r, Vector3.new((m02 + m20) * r, (m21 + m12) * r, 0.5 * s))
		end
	end
end

--[=[
	Constructs a new Quaternion object from a given Orientation (in degrees)

	@param orientation Vector3 -- The Orientation (in degrees) to convert to a Quaternion
	@return Quaternion -- The constructed Quaternion object
]=]
function Quaternion.fromOrientation(orientation: Vector3)
	-- Convert to radians
	orientation *= math.pi / 180

	-- Construct CFrame from radian orientation
	local cframe = CFrame.fromOrientation(orientation.X, orientation.Y, orientation.Z)

	-- Convert CFrame to Quaternion
	return Quaternion.fromCFrame(cframe)
end

-- Public Functions

--[=[
	@return Quaternion -- The inverse of the quaternion
]=]
function Quaternion:Inverse(): Quaternion
	local conjugate = self.W ^ 2 + self.Vector.Magnitude ^ 2

	local invertedW = self.W / conjugate
	local invertedVector = -self.Vector / conjugate

	return Quaternion.new(invertedW, invertedVector)
end

--[=[
	@return (Vector3, number) -- The axis and angle of the quaternion
]=]
function Quaternion:AxisAngle(): (Vector3, number)
	local axis = self.Vector.Unit
	local angle = math.acos(self.W) * 2

	if self.Vector.Magnitude == 0 then
		axis = Vector3.new(0, 0, 0)
	end

	return axis, angle
end

--[=[
	Returns a quaternion interpolated by the alpha value between this one and
	the target

	@param target Quaternion -- The target quaternion to interpolate towards
	@param alpha number -- The alpha value to interpolate by (0-1)
	@return Quaternion -- The interpolated quaternion
]=]
function Quaternion:Slerp(target: Quaternion, alpha: number): Quaternion
	return ((target * self:Inverse()) ^ alpha) * self
end

--[=[
	@return CFrame -- The CFrame representation of the quaternion
]=]
function Quaternion:ToCFrame(): CFrame
	local result = CFrame.fromAxisAngle(self:AxisAngle())

	if result ~= result then
		return CFrame.new()
	end

	return result.Rotation
end

--[=[
	@return Vector3 -- The Orientation (in degrees) representation of the quaternion
]=]
function Quaternion:ToOrientation(): Vector3
	-- Get CFrame, convert to orientation order, convert to degrees
	return Vector3.new(self:ToCFrame():ToOrientation()) * (180 / math.pi)
end

return Quaternion
