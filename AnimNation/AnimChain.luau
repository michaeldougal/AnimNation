local Spring = require(script.Parent:WaitForChild("Spring"))

type Spring = Spring.Spring

export type AnimChain = {
	-- Metatable members

	__index: AnimChain,

	-- Public members

	new: (animators: { Spring | Tween }?) -> AnimChain,
	AndThen: (AnimChain, callback: () -> ()) -> AnimChain,
	Await: (AnimChain) -> AnimChain,
	Resume: (AnimChain) -> AnimChain,
	Pause: (AnimChain) -> AnimChain,
	Destroy: (AnimChain) -> (),

	-- Private members

	_addAnimator: (AnimChain, animator: Spring | Tween) -> (),
	_processCallbackQueue: (AnimChain) -> (),
	_waitForAnimationsCompleted: (AnimChain) -> (),

	-- Constructed private members

	_animators: { Spring | Tween },
	_callbackQueue: { () -> () },
	_processingQueue: boolean,
	_destroyed: boolean,
}

--[=[
	@class AnimChain

	An object that can be used to link functionality to the end of an
	animation. `:AndThen()` can be used to link a callback, and `:Await()` can
	be used to wait for the animation to complete. These links are processed
	in the order they are called in.
]=]
local AnimChain = {}
AnimChain.__index = AnimChain

function AnimChain:_addAnimator(animator: Spring | Tween)
	table.insert(self._animators, animator)
end

function AnimChain:_processCallbackQueue()
	if not self._processingQueue then
		self._processingQueue = true

		while self._callbackQueue[1] do
			(table.remove(self._callbackQueue, 1) :: () -> ())()
		end

		self._processingQueue = false
	end
end

function AnimChain:_waitForAnimationsCompleted()
	if self._destroyed then
		return
	end

	for _, animator: Spring | Tween in ipairs(self._animators) do
		if typeof(animator) == "table" then -- Spring
			while animator:IsAnimating(0.01) and not self._destroyed do
				task.wait()
			end
		elseif typeof(animator) == "Instance" and animator:IsA("Tween") then -- Tween
			while
				animator.PlaybackState ~= Enum.PlaybackState.Completed
				and animator.PlaybackState ~= Enum.PlaybackState.Cancelled
				and not self._destroyed
			do
				animator:GetPropertyChangedSignal("PlaybackState"):Wait()
			end
		end
	end
end

--[=[
	Links a callback to be executed after all animations in the chain have
	completed.

	@param callback () -> () -- The callback to execute
	@return AnimChain -- The current AnimChain object
]=]
function AnimChain:AndThen(callback: () -> ()): AnimChain
	if self._destroyed then
		return self
	end

	task.spawn(function()
		table.insert(self._callbackQueue, callback)

		self:_waitForAnimationsCompleted()

		if self._destroyed then
			return
		end

		self:_processCallbackQueue()
	end)

	return self :: AnimChain
end

--[=[
	Yields the current thread until all animations in the chain have completed,
	then returns the current AnimChain object.

	@return AnimChain -- The current AnimChain object
]=]
function AnimChain:Await(): AnimChain
	local locked = true
	local unlock = function()
		locked = false
	end

	table.insert(self._callbackQueue, unlock)

	self:_waitForAnimationsCompleted()

	if self._destroyed then
		return self
	end

	task.spawn(self._processCallbackQueue, self)

	while locked do
		task.wait()
	end

	return self :: AnimChain
end

--[=[
	Pauses all animators.

	@return AnimChain -- The current AnimChain object.
]=]
function AnimChain:Pause(): AnimChain
	for _, animator in ipairs(self._animators) do
		animator:Pause()
	end

	return self :: AnimChain
end

--[=[
	Resumes all animators.

	@return AnimChain -- The current AnimChain object
]=]
function AnimChain:Resume(): AnimChain
	for _, animator in ipairs(self._animators) do
		if typeof(animator) == "Instance" and animator:IsA("Tween") then
			animator:Play()
		elseif typeof(animator) == "table" then
			animator:Resume()
		end
	end

	return self :: AnimChain
end

--[=[
	Destroys the AnimChain object.
]=]
function AnimChain:Destroy()
	if self._destroyed then
		return
	end

	self._destroyed = true

	for _, animator in ipairs(self._animators) do
		if typeof(animator) == "Instance" and animator:IsA("Tween") then
			animator:Destroy()
		elseif typeof(animator) == "table" then
			animator:Pause()
			animator:Destroy()
		end
	end

	table.clear(self._animators)
	table.clear(self._callbackQueue)

	for k in pairs(self) do
		self[k] = nil
	end
end

--[=[
	Constructs a new AnimChain object.

	@param animators { Spring | Tween }? -- A list of animators to add to the chain
	@return AnimChain -- The constructed AnimChain object
]=]
function AnimChain.new(animators: { Spring | Tween }?): AnimChain
	local self = setmetatable({}, AnimChain)

	self._animators = animators or {}
	self._callbackQueue = {}
	self._processingQueue = false

	return self
end

return AnimChain
