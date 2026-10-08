--!strict
--!optimize 2
--!native

local FixedSlotPoolTypes =
	require(script.Parent.Parent.Parent.Parent.types.components.fixedSlotPool.shared.fixedSlotPool)

type FixedSlotPool<T> = FixedSlotPoolTypes.FixedSlotPool<T>
type FixedSlotPoolImpl<T> = FixedSlotPoolTypes.FixedSlotPoolImpl<T>
type FixedSlotPoolOptions<T> = FixedSlotPoolTypes.FixedSlotPoolOptions<T>
type FixedSlotPoolModule = {
	read new: <T>(capacity: number, options: FixedSlotPoolOptions<T>) -> FixedSlotPool<T>,
}

local ACQUIRED = -1
local MAX_GENERATION = 9007199254740991

local function validateIndex(index: number, capacity: number): ()
	assert(
		index >= 1 and index <= capacity and index % 1 == 0,
		"slot index must be an integer within capacity"
	)
end

local function validateGeneration(generation: number): ()
	assert(
		generation >= 1 and generation <= MAX_GENERATION and generation % 1 == 0,
		"generation must be a positive safe integer"
	)
end

-- An explicit result preserves pcall's failure-result slot in the pinned analyzer.
-- This shared helper avoids a closure allocation for each reset.
local function invokeReset<T>(reset: (T) -> (), value: T): unknown
	reset(value)
	return nil
end

local FixedSlotPool = {}
FixedSlotPool.__index = FixedSlotPool

function FixedSlotPool.new<T>(capacity: number, options: FixedSlotPoolOptions<T>): FixedSlotPool<T>
	assert(
		capacity >= 1 and capacity < math.huge and capacity % 1 == 0,
		"capacity must be a positive finite integer"
	)
	assert(type(options.create) == "function", "create must be a function")
	assert(options.reset == nil or type(options.reset) == "function", "reset must be a function or nil")
	local values: { T } = table.create(capacity)
	local nextFree: { number } = table.create(capacity, 0)
	local generations: { number } = table.create(capacity, 0)
	for index = 1, capacity do
		local value = options.create(index)
		assert(value ~= nil, "create must return a non-nil payload")
		values[index] = value
		nextFree[index] = if index < capacity then index + 1 else 0
	end
	local self: FixedSlotPoolImpl<T> = setmetatable({
		values = table.freeze(values),
		capacity = capacity,
		_nextFree = nextFree,
		_generations = generations,
		_freeHead = 1,
		_activeCount = 0,
		_reset = options.reset,
		_resetting = false,
	}, FixedSlotPool) :: FixedSlotPoolImpl<T>
	return self
end

function FixedSlotPool.tryAcquire<T>(self: FixedSlotPoolImpl<T>): (number?, number?, T?)
	assert(not self._resetting, "cannot mutate a pool from its reset callback")
	local index = self._freeHead
	if index == 0 then
		return nil, nil, nil
	end
	local generation = self._generations[index]
	assert(generation < MAX_GENERATION, "slot generation exhausted; construct a new pool")
	generation += 1
	self._freeHead = self._nextFree[index]
	self._nextFree[index] = ACQUIRED
	self._generations[index] = generation
	self._activeCount += 1
	return index, generation, self.values[index]
end

function FixedSlotPool.release<T>(self: FixedSlotPoolImpl<T>, index: number, generation: number): boolean
	assert(not self._resetting, "cannot mutate a pool from its reset callback")
	validateIndex(index, self.capacity)
	validateGeneration(generation)
	if self._nextFree[index] ~= ACQUIRED or self._generations[index] ~= generation then
		return false
	end
	local reset = self._reset
	if reset then
		self._resetting = true
		local ok, failure = pcall(invokeReset, reset, self.values[index])
		self._resetting = false
		if not ok then
			error(failure, 0)
		end
	end
	self._nextFree[index] = self._freeHead
	self._freeHead = index
	self._activeCount -= 1
	return true
end

function FixedSlotPool.isAcquired<T>(self: FixedSlotPoolImpl<T>, index: number, generation: number?): boolean
	validateIndex(index, self.capacity)
	if generation ~= nil then
		validateGeneration(generation)
	end
	return self._nextFree[index] == ACQUIRED and (generation == nil or self._generations[index] == generation)
end

function FixedSlotPool.count<T>(self: FixedSlotPoolImpl<T>): number
	return self._activeCount
end

function FixedSlotPool.clear<T>(self: FixedSlotPoolImpl<T>): ()
	assert(not self._resetting, "cannot mutate a pool from its reset callback")
	for index = 1, self.capacity do
		if self._nextFree[index] == ACQUIRED then
			self:release(index, self._generations[index])
		end
	end
end

table.freeze(FixedSlotPool)
local module: FixedSlotPoolModule = FixedSlotPool
return module
