-- Originally retrived from EgoMoose, provided under the open-source MIT license
-- https://github.com/EgoMooseOldProjects/ExampleDump/blob/master/Scripts/slerp.lua

local Quaternion = {__type = "Quaternion"}

-- Commonly what we'd been calling "a" is refered to as "w"
function Quaternion.new(w, v)
	local self = setmetatable({}, {
		__index = Quaternion,
		__mul = function(t, q)
			if q.__type and q.__type == "Quaternion" then
				local neww = t.w * q.w - t.v:Dot(q.v)
				local newv = t.v * q.w + q.v * t.w + t.v:Cross(q.v)
				return t.new(neww, newv)
			end
		end,
		__pow = function(q, t)
			local axis, angle = q:AxisAngle()
			angle = t * angle
			return q.new(math.cos(angle / 2), math.sin(angle / 2) * axis)
		end,
	})

	self.w = w
	self.v = v

	return self
end

function Quaternion:Inverse()
	local conjugate = self.w ^ 2 + self.v.magnitude ^ 2

	local newW = self.w / conjugate
	local newV = -self.v / conjugate

	return Quaternion.new(newW, newV)
end

function Quaternion:AxisAngle()
	local axis = self.v.unit
	local angle = math.acos(self.w) * 2

	return axis, angle
end

function Quaternion:Slerp(q2, t)
	return ((q2 * self:Inverse()) ^ t) * self
end

------------------------------------------------------------------

-- Now we're just converting CFrame to quaternion and so forth...

-- Taken directly from the wiki: http://wiki.roblox.com/index.php?title=Quaternions_for_rotation#Quaternion_from_a_Rotation_Matrix
local function QuaternionFromCFrame(cframe)
	local _, _, _, m00, m01, m02, m10, m11, m12, m20, m21, m22 = cframe:components()
	local trace = m00 + m11 + m22
	if trace > 0 then
		local s = math.sqrt(1 + trace)
		local r = 0.5 / s
		return s * 0.5, Vector3.new((m21 - m12) * r, (m02 - m20) * r, (m10 - m01) * r)
	else --Find the largest diagonal element
		local big = math.max(m00, m11, m22)
		if big == m00 then
			local s = math.sqrt(1 + m00 - m11 - m22)
			local r = 0.5 / s
			return (m21 - m12) * r, Vector3.new(0.5 * s, (m10 + m01) * r, (m02 + m20) * r)
		elseif big == m11 then
			local s = math.sqrt(1 - m00 + m11 - m22)
			local r = 0.5 / s
			return (m02 - m20) * r, Vector3.new((m10 + m01) * r, 0.5 * s, (m21 + m12) * r)
		elseif big == m22 then
			local s = math.sqrt(1 - m00 - m11 + m22)
			local r = 0.5 / s
			return (m10 - m01) * r, Vector3.new((m02 + m20) * r, (m21 + m12) * r, 0.5 * s)
		end
	end
end

return function(cf1, cf2, t)
	local p = cf1.p:Lerp(cf2.p, t)
	local q1 = Quaternion.new(QuaternionFromCFrame(cf1))
	local q2 = Quaternion.new(QuaternionFromCFrame(cf2))
	local sq = q1:Slerp(q2, t)
	return CFrame.new(p.x, p.y, p.z, sq.v.x, sq.v.y, sq.v.z, sq.w)
end
