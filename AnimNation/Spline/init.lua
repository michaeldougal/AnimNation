--[[
    Spline.lua
    TactBacon, ChiefWildin (feat. eliphant)

    A spline curve class for Roblox.

    Constants:
        SEGMENTS_PER_CURVE: number
            - The number of segments per curve. The higher this number, the more
            accurate the curve will be, but the more expensive it will be to
            calculate

    Properties:
        Spline.ControlPoints: {CFrame}
            - A table of CFrames that are used as control points for the spline
            curve
        Spline.Curve: Model
            - A model containing the parts that make up the spline curve. This
            is updated whenever the control points are moved or the Segments
            property is updated
		Spline.Visible: boolean
			- Whether or not the curve is visible in the workspace
			- Default: false
		Spline.Parent: Instance?
			- The parent of the curve model (Spline.Curve)
			- Default: workspace
		Spline.Segments: number
	        - The number of segments per curve. The higher this number, the more
	        accurate the curve will be, but the more expensive it will be to
	        calculate
			- Default: 10

    Functions:
        Spline.new(controlPoints: {CFrame}) -> Spline
            - controlPoints: A table of CFrames that are used as control points
            for the spline curve
            - Returns a new spline curve object
        Spline:GetCFrameFromAlpha(alpha: number, alignment: ("Track" | "Nodes")?) -> CFrame
            - alpha: A number between 0 and 1 that represents the CFrame along
            the curve
	        - alignment: The alignment of the CFrame. "Track" will align the
	        CFrame to the direction of the curve, and "Nodes" will align the
	        CFrame to the direction of the control points
            - Returns the CFrame along the curve at the given alpha value using
            the segments for distances
		Spline:GetLinearCFrameFromAlpha(alpha: number, alignment: ("Track" | "Nodes")?) -> CFrame
	        - alpha: A number between 0 and 1 that represents the CFrame along
	        the curve
	        - alignment: The alignment of the CFrame. "Track" will align the
	        CFrame to the direction of the curve, and "Nodes" will align the
	        CFrame to the direction of the control points
	        - Returns the CFrame along the curve at the given alpha value using
	        the distance between the first and last control points for distances
        Spline:Destroy()
            - Destroys the spline curve.

	Events:
		Spline.Destroying: () -> ()
			- Fires when the spline curve is destroyed.
]]

-- Types

export type Spline = {
    ControlPoints: {CFrame},
    Curve: Model,
	Visible: boolean,
	Parent: Instance?,

    Destroy: (self: Spline) -> (),
    GetCFrameFromAlpha: (self: Spline, alpha: number, alignment: ("Track" | "Nodes")?) -> CFrame,
	GetLinearCFrameFromAlpha: (self: Spline, alpha: number, alignment: ("Track" | "Nodes")?) -> CFrame,
	new: (curveModel: Model) -> Spline
}

-- Constants

local CURVE_DISPLAY_COLOR = BrickColor.new("Toothpaste").Color

-- Dependencies

local Slerp = require(script.Slerp)

-- Main Module

local Spline: Spline = {}
Spline.__index = function(this, key)
	if key == "Visible" then
		return rawget(this, "_visible")
	elseif key == "Parent" then
		return rawget(this, "_parent")
	elseif key == "Segments" then
		return rawget(this, "_segments")
	elseif key == "ControlPoints" then
		return rawget(this, "_controlPoints")
	else
		return Spline[key]
	end
end
Spline.__newindex = function(this, key, value)
	if key == "Visible" then
		rawset(this, "_visible", value)
		if value and not this._curveDrawn then
			this:_drawCurve()
		end
		this.Curve.Parent = value and this._parent or nil
	elseif key == "Parent" then
		rawset(this, "_parent", value)
		this.Curve.Parent = this.Visible and this._parent or nil
	elseif key == "Segments" then
		rawset(this, "_segments", value)
		this:_update()
	elseif key == "ControlPoints" then
		rawset(this, "_controlPoints", value)
		this:_update()
	else
		rawset(this, key, value)
	end
end

-- Internal functions

local function CatmullRom(p0, p1, p2, p3)
	return p1, 0.5*(p2 - p0), p0 - 2.5*p1 + 2*p2 - 0.5*p3, 1.5*(p1 - p2) + 0.5*(p3 - p0)
end

-- Private functions

function Spline:_drawCurve()
	self.Curve:ClearAllChildren()

	local controlPointCount = #self._controlPoints
	self._curveDrawn = true

	local lastPoint = nil
	for i = 0, (self._segments * controlPointCount) do
        local alpha = (i) / (self._segments * controlPointCount)
		local cf = self:GetCFrameFromAlpha(alpha)
		local segmentIndex = 0
		for j = 1, controlPointCount - 1 do
			if self._normalizedDistancePoints[j] >= alpha then
				segmentIndex = j
				break
			end
		end
		local point = Instance.new("Part")
		point.Name = "Point" .. segmentIndex
		point.Anchored = true
		point.CanCollide = false
		point.CanTouch = false
		point.CanQuery = false
		point.Color = CURVE_DISPLAY_COLOR
		point.Material = Enum.Material.Neon
		point.Size = Vector3.new(0.1, 0.1, lastPoint and (lastPoint - cf.Position).Magnitude or 0.1)
		point.CFrame = CFrame.new(cf.Position, lastPoint or cf.Position) * CFrame.new(0, 0, -point.Size.Z/2)
        point:SetAttribute("Alpha", alpha)
		point.Parent = self.Curve
		lastPoint = cf.Position
	end
end

function Spline:_update()
	local controlPointCount = #self._controlPoints
	if self._controlPoints and controlPointCount >= 3 then

		self._curveLength = 0
		self._distancePoints = {}
		self._normalizedDistancePoints = {}
		self._curveDrawn = false

		local function getLengthsPerSegment()
			for i = 1, controlPointCount - 1 do
				local length = 0
				local step = 0.01
				local p0, p1, p2, p3, a, b, c, d, position
				local lastPosition = self._controlPoints[i].Position
				for t = 0, 1 - step, step do
					p0 = self._controlPoints[math.max(i - 1, 1)]
					p1 = self._controlPoints[i]
					p2 = self._controlPoints[math.min(i + 1, controlPointCount)]
					p3 = self._controlPoints[math.min(i + 2, controlPointCount)]
					a, b, c, d = CatmullRom(p0.Position, p1.Position, p2.Position, p3.Position)
					position = a + b * t + c * t^2 + d * t^3
					length += (position - lastPosition).Magnitude
					lastPosition = position
				end
				self._curveLength += length
				self._distancePoints[i] = self._curveLength
			end

			for i = 1, #self._controlPoints - 1 do
				self._normalizedDistancePoints[i] = self._distancePoints[i] / self._curveLength
			end
		end
		getLengthsPerSegment()

		if rawget(self, "_visible") then
			self:_drawCurve()
		end
	end
end

-- Public Functions

---Gets a CFrame along the spline at a given alpha value using the natural Catmull-Rom spline algorithm.
---@param alpha number The alpha value to get the point at. This should be a value between 0 and 1.
---@param alignment string? This will orient the rotation of the result to either follow the rotation of the path (`"Track"`) or the rotation of the nodes (`"Nodes"`)
---@return CFrame point The CFrame along the curve at the given alpha value using the segments for distances.
function Spline:GetCFrameFromAlpha(alpha: number, alignment: ("Track" | "Nodes")?): CFrame
	alignment = alignment or "Track"
	if alpha == 1 then
		return self._controlPoints[#self._controlPoints]
	end
	local segmentCount = #self._controlPoints - 1
	local previousControlPoint, remainder = math.modf(segmentCount * alpha + 1)
	local targetControlPoint = previousControlPoint + 1
	local c0 = self._controlPoints[math.max(previousControlPoint - 1, 1)]
	local c1 = self._controlPoints[previousControlPoint]
	local c2 = self._controlPoints[targetControlPoint]
	local c3 = self._controlPoints[math.min(targetControlPoint+1, segmentCount + 1)]
	local a, b, c, d = CatmullRom(c0.Position, c1.Position, c2.Position, c3.Position)
	local position = a + b * remainder + c * remainder^2 + d * remainder^3
	if alignment == "Track" then
		local tangent = b + 2 * c * remainder + 3 * d * remainder^2
		return CFrame.lookAt(position, position + tangent)
	else
		local cf = CFrame.new(position)
		local cubicInOutT = remainder * remainder * (3 - 2 * remainder)
		return cf * Slerp(c1, c2, cubicInOutT).Rotation
	end
end

---Gets a CFrame along the spline using a close approximation to where the point would be linearly to
---a given alpha value using the Catmull-Rom spline algorithm.
---@param alpha number The alpha value to get the point at. This should be a value between 0 and 1.
---@param alignment string? This will orient the rotation of the result to either follow the rotation of the path (`"Track"`) or the rotation of the nodes (`"Nodes"`)
---@return CFrame point The CFrame along the curve at the given alpha value using the segments for distances.
function Spline:GetLinearCFrameFromAlpha(alpha: number, alignment: ("Track" | "Nodes")?): CFrame
	alignment = alignment or "Track"
	local controlPointCount = #self._controlPoints
	local targetControlPoint = 1
	for i = 1, controlPointCount do
		if self._normalizedDistancePoints[i] >= alpha then
			targetControlPoint = i
			break
		end
	end
	local previousControlPoint = targetControlPoint - 1
	local normalizedPrevious = self._normalizedDistancePoints[previousControlPoint] or 0
	local normalizedTarget = self._normalizedDistancePoints[targetControlPoint]
	local t = (alpha - normalizedPrevious) / (normalizedTarget - normalizedPrevious)
	previousControlPoint = math.max(previousControlPoint, 1)
	local c0 = self._controlPoints[previousControlPoint]
	local c1 = self._controlPoints[targetControlPoint]
	local c2 = self._controlPoints[math.min(targetControlPoint+1, controlPointCount)]
	local c3 = self._controlPoints[math.min(targetControlPoint+2, controlPointCount)]
	local a, b, c, d = CatmullRom(c0.Position, c1.Position, c2.Position, c3.Position)
	local position = a + b * t + c * t^2 + d * t^3
	if alignment == "Track" then
		local tangent = b + 2 * c * t + 3 * d * t^2
		return CFrame.lookAt(position, position + tangent)
	else
		local cf = CFrame.new(position)
		local cubicInOutT = t * t * (3 - 2 * t)
		return cf * Slerp(c1, c2, cubicInOutT).Rotation
	end
end

---Destroys the spline and cleans up any listeners.
function Spline:Destroy()
	self._destroying:Fire()
	self._destroying:Destroy()
    self.Curve:Destroy()
	for _, listener in (self._listeners) do
		listener:Disconnect()
	end
	self._listeners = {}
end

-- Constructor

---Constructor for the Spline class. Takes in a curve model and returns a new Spline object.
---@param controlPoints table A table of CFrame objects that will be used as control points for the spline.
---@return table Spline The new Spline object.
function Spline.new(controlPoints: {CFrame}): Spline
	local self: Spline = setmetatable({}, Spline)

	self._listeners = {} :: {RBXScriptConnection}
	self._visible = false
	self._parent = workspace
	self._segments = 10

	self._controlPoints = controlPoints

	self.Curve = Instance.new("Model")
	self.Curve.Name = "Curve"

	self._destroying = Instance.new("BindableEvent")
	self.Destroying = self._destroying.Event

	self:_update()

	return self
end

return Spline :: Spline
