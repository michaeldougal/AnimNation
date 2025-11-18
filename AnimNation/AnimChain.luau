local Spring = require(script.Parent:WaitForChild("Spring"))

type Spring = Spring.Spring

export type AnimChainImpl = {
	-- Metatable members

	__index: AnimChain,

	-- Public members

	new: (animators: { Spring | Tween }?) -> AnimChain,
	AndThen: (AnimChain, callback: () -> ()) -> AnimChain,
	Await: (AnimChain) -> AnimChain,

	-- Private members

	_addAnimator: (AnimChain, animator: Spring | Tween) -> (),
	_processCallbackQueue: (AnimChain) -> (),
	_waitForAnimationsCompleted: (AnimChain) -> (),
}
export type AnimChain = typeof(setmetatable(
	{} :: {
		-- Constructed public members

		-- Constructed private members
		_animators: { Spring | Tween },
		_callbackQueue: { () -> () },
		_processingQueue: boolean,
	},
	{} :: AnimChainImpl
))

--[=[
	@class AnimChain

	An object that can be used to link functionality to the end of an
	animation. `:AndThen()` can be used to link a callback, and `:Await()` can
	be used to wait for the animation to complete. These links are processed
	in the order they are called in.
]=]
local AnimChain: AnimChainImpl = {} :: AnimChainImpl
AnimChain.__index = AnimChain

function AnimChain:_addAnimator(animator: Spring | Tween)
	table.insert(self._animators, animator)
end

function AnimChain:_processCallbackQueue()
	if not self._processingQueue then
		self._processingQueue = true

		while self._callbackQueue[1] do
			table.remove(self._callbackQueue, 1)()
		end

		self._processingQueue = false
	end
end

function AnimChain:_waitForAnimationsCompleted()
	for _, animator: Spring | Tween in ipairs(self._animators) do
		if typeof(animator) == "table" then -- Spring
			while animator:IsAnimating(0.01) do
				task.wait()
			end
		elseif typeof(animator) == "Instance" then -- Tween
			while
				animator.PlaybackState ~= Enum.PlaybackState.Completed
				and animator.PlaybackState ~= Enum.PlaybackState.Cancelled
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
	task.spawn(function()
		table.insert(self._callbackQueue, callback)

		self:_waitForAnimationsCompleted()

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

	task.spawn(self._processCallbackQueue, self)

	while locked do
		task.wait()
	end

	return self :: AnimChain
end

--[=[
	Constructs a new AnimChain object.

	@param animators { Spring | Tween }? -- A list of animators to add to the chain
	@return AnimChain -- The constructed AnimChain object
]=]
function AnimChain.new(animators: { Spring | Tween }?)
	local self = setmetatable({}, AnimChain)

	self._animators = animators or {}
	self._callbackQueue = {}
	self._processingQueue = false

	return self
end

AnimChain.andThen = AnimChain.AndThen
AnimChain.await = AnimChain.Await

return AnimChain
