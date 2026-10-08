--!strict
--!optimize 2

local LuneRequireTransform = require("./lib/luneRequireTransform")
local package = LuneRequireTransform.write({ packageRoot = "src" })
local FixedSlotPool = package.requireModule("init.luau")
local passed = 0

local function test(name, callback)
	callback()
	passed += 1
	print("PASS " .. name)
end

local function rejects(callback)
	assert(not pcall(callback), "expected a contract violation")
end

test("preallocates distinct stable payloads and freezes only the values array", function()
	local created = 0
	local pool = FixedSlotPool.new(64, {
		create = function(index)
			created += 1
			return { amount = index }
		end,
	})
	assert(
		created == 64 and pool.capacity == 64 and pool:count() == 0,
		"expected created == 64 and pool.capacity == 64 and pool:count() == 0"
	)
	assert(
		table.isfrozen(pool.values) and not table.isfrozen(pool.values[1]),
		"expected table.isfrozen(pool.values) and not table.isfrozen(pool.values[1])"
	)
	assert(pool.values[1] ~= pool.values[2], "expected pool.values[1] ~= pool.values[2]")
	pool.values[1].amount = 7
	rejects(function()
		pool.values[1] = { amount = 8 }
	end)
	local record, generation = pool:tryAcquire()
	assert(
		generation == 1 and record == pool.values[1] and record.amount == 7,
		"expected generation == 1 and record == pool.values[1] and record.amount == 7"
	)
	assert(pool:release(record, generation), "expected pool:release(record, generation)")
	assert(created == 64, "expected created == 64")
end)

test("full capacity returns nil without resizing or stealing", function()
	local created = 0
	local pool = FixedSlotPool.new(3, {
		create = function(index)
			created += 1
			return index
		end,
	})
	for expected = 1, 3 do
		local value, generation = pool:tryAcquire()
		assert(generation == 1 and value == expected, "expected generation == 1 and value == expected")
	end
	for _ = 1, 20 do
		local value, generation = pool:tryAcquire()
		assert(generation == nil and value == nil, "expected generation == nil and value == nil")
	end
	assert(
		created == 3 and #pool.values == 3 and pool:count() == 3,
		"expected created == 3 and #pool.values == 3 and pool:count() == 3"
	)
	for index = 1, 3 do
		assert(pool:isAcquired(index, 1), "expected pool:isAcquired(index, 1)")
	end
end)

test("arbitrary release uses a LIFO free stack and rejects stale/double release", function()
	local resets = 0
	local pool = FixedSlotPool.new(3, {
		create = function()
			return { amount = 0 }
		end,
		reset = function(record)
			resets += 1
			record.amount = 0
		end,
	})
	for _ = 1, 3 do
		pool:tryAcquire()
	end
	assert(
		pool:release(pool.values[2], 1) and pool:release(pool.values[1], 1),
		"expected pool:release(pool.values[2], 1) and pool:release(pool.values[1], 1)"
	)
	assert(
		not pool:release(pool.values[1], 1) and resets == 2,
		"expected not pool:release(pool.values[1], 1) and resets == 2"
	)
	local first, firstGeneration = pool:tryAcquire()
	local second, secondGeneration = pool:tryAcquire()
	assert(
		first == pool.values[1]
			and second == pool.values[2]
			and firstGeneration == 2
			and secondGeneration == 2,
		"expected first == pool.values[1] and second == pool.values[2] and firstGeneration == 2 and secondGeneration == 2"
	)
	assert(
		not pool:release(first, 1) and not pool:isAcquired(first, 1),
		"expected not pool:release(first, 1) and not pool:isAcquired(first, 1)"
	)
	assert(
		pool:isAcquired(first, firstGeneration) and pool:count() == 3 and resets == 2,
		"expected pool:isAcquired(first, firstGeneration) and pool:count() == 3 and resets == 2"
	)
end)

test("reset clears references once and acquisition preserves the same record", function()
	local original = { target = {}, amount = 5 }
	local resets = 0
	local pool = FixedSlotPool.new(1, {
		create = function()
			return original
		end,
		reset = function(record)
			resets += 1
			record.target = nil
			record.amount = 0
		end,
	})
	assert(resets == 0, "expected resets == 0")
	local record, generation = pool:tryAcquire()
	assert(
		record.target ~= nil and record.amount == 5,
		"expected record.target ~= nil and record.amount == 5"
	)
	assert(pool:release(record, generation), "expected pool:release(record, generation)")
	assert(
		resets == 1 and record.target == nil and record.amount == 0,
		"expected resets == 1 and record.target == nil and record.amount == 0"
	)
	local nextRecord, nextGeneration = pool:tryAcquire()
	assert(
		nextGeneration ~= generation and nextRecord == record,
		"expected nextGeneration ~= generation and nextRecord == record"
	)
end)

test("without reset payloads retain their contents; false is a valid payload", function()
	local pool = FixedSlotPool.new(1, {
		create = function()
			return { amount = 5 }
		end,
	})
	local record, generation = pool:tryAcquire()
	record.amount = 9
	assert(pool:release(record, generation), "expected pool:release(record, generation)")
	local reused = pool:tryAcquire()
	assert(reused.amount == 9, "expected reused.amount == 9")
	local booleanPool = FixedSlotPool.new(1, {
		create = function()
			return false
		end,
	})
	local value, booleanGeneration = booleanPool:tryAcquire()
	assert(booleanGeneration == 1 and value == false, "expected booleanGeneration == 1 and value == false")
end)

test("clear resets active slots only and old leases cannot release replacements", function()
	local resets = 0
	local pool = FixedSlotPool.new(4, {
		create = function(index)
			return index
		end,
		reset = function()
			resets += 1
		end,
	})
	for _ = 1, 3 do
		pool:tryAcquire()
	end
	pool:clear()
	pool:clear()
	assert(pool:count() == 0 and resets == 3, "expected pool:count() == 0 and resets == 3")
	for _ = 1, 4 do
		local record, generation = pool:tryAcquire()
		assert(record ~= nil, "expected record ~= nil")
		if record <= 3 then
			assert(
				generation == 2 and not pool:release(record, 1),
				"expected generation == 2 and not pool:release(record, 1)"
			)
		end
	end
	assert(pool:count() == 4, "expected pool:count() == 4")
end)

test("reset errors preserve the lease and restore operation availability", function()
	local fail = true
	local failure = {}
	local pool = FixedSlotPool.new(1, {
		create = function()
			return { amount = 1 }
		end,
		reset = function(record)
			record.amount = 0
			if fail then
				error(failure)
			end
		end,
	})
	local record, generation = pool:tryAcquire()
	local ok, actualFailure = pcall(pool.release, pool, record, generation)
	assert(not ok and actualFailure == failure, "expected not ok and actualFailure == failure")
	assert(
		pool:count() == 1 and pool:isAcquired(record, generation),
		"expected pool:count() == 1 and pool:isAcquired(record, generation)"
	)
	assert(pool:tryAcquire() == nil, "expected pool:tryAcquire() == nil")
	fail = false
	assert(
		pool:release(record, generation) and pool:count() == 0,
		"expected pool:release(record, generation) and pool:count() == 0"
	)
end)

test("reset callbacks can observe but cannot mutate pool allocation state", function()
	local pool
	local checks = 0
	pool = FixedSlotPool.new(1, {
		create = function()
			return 1
		end,
		reset = function()
			assert(
				pool:count() == 1 and pool:isAcquired(1, 1),
				"expected pool:count() == 1 and pool:isAcquired(1, 1)"
			)
			rejects(function()
				pool:tryAcquire()
			end)
			rejects(function()
				pool:release(1, 1)
			end)
			rejects(function()
				pool:clear()
			end)
			checks += 1
		end,
	})
	pool:tryAcquire()
	assert(
		pool:release(1, 1) and checks == 1 and pool:count() == 0,
		"expected pool:release(1, 1) and checks == 1 and pool:count() == 0"
	)
end)

test("clear failure is partial and remaining acquired slots can be retried", function()
	local fail = true
	local pool = FixedSlotPool.new(3, {
		create = function(index)
			return index
		end,
		reset = function(value)
			if value == 2 and fail then
				error("reset failed")
			end
		end,
	})
	for _ = 1, 3 do
		pool:tryAcquire()
	end
	rejects(function()
		pool:clear()
	end)
	assert(
		pool:count() == 2 and not pool:isAcquired(1) and pool:isAcquired(2) and pool:isAcquired(3),
		"expected pool:count() == 2 and not pool:isAcquired(1) and pool:isAcquired(2) and pool:isAcquired(3)"
	)
	fail = false
	pool:clear()
	assert(pool:count() == 0, "expected pool:count() == 0")
end)

test("invalid boundaries fail before changing allocation state", function()
	for _, capacity in { 0, -1, 0.5, math.huge, 0 / 0 } do
		rejects(function()
			FixedSlotPool.new(capacity, {
				create = function()
					return 1
				end,
			})
		end)
	end
	rejects(function()
		FixedSlotPool.new(1, {
			create = function()
				return nil
			end,
		})
	end)
	local pool = FixedSlotPool.new(2, {
		create = function(index)
			return index
		end,
	})
	pool:tryAcquire()
	for _, value in { 0, 3, 0.5, math.huge, 0 / 0 } do
		assert(not pool:release(value, 1), "foreign values cannot release slots")
		assert(not pool:isAcquired(value), "foreign values are not acquired")
	end
	for _, generation in { 0, -1, 0.5, math.huge, 0 / 0, 9007199254740992 } do
		rejects(function()
			pool:release(1, generation)
		end)
	end
	assert(
		pool:count() == 1 and pool:isAcquired(1, 1),
		"expected pool:count() == 1 and pool:isAcquired(1, 1)"
	)
end)

test("generation exhaustion fails before mutation instead of wrapping", function()
	local pool = FixedSlotPool.new(1, {
		create = function()
			return 1
		end,
	})
	-- Private setup reaches the otherwise impractical numeric boundary.
	pool._generations[1] = 9007199254740991
	rejects(function()
		pool:tryAcquire()
	end)
	assert(
		pool:count() == 0 and not pool:isAcquired(1),
		"expected pool:count() == 0 and not pool:isAcquired(1)"
	)
end)

test("50,000 mixed operations match an independent occupied-slot model", function()
	local created = 0
	local pool = FixedSlotPool.new(64, {
		create = function(index)
			created += 1
			return { index = index }
		end,
	})
	local leases = {}
	local oldGenerations = {}
	local count = 0
	local seed = 9127
	for step = 1, 50000 do
		seed = (seed * 48271) % 2147483647
		local index = seed % 64 + 1
		if seed % 3 == 0 then
			local old = oldGenerations[index]
			if old then
				assert(
					not pool:release(pool.values[index], old),
					"expected not pool:release(pool.values[index], old)"
				)
			end
			local generation = leases[index]
			if generation then
				assert(
					pool:release(pool.values[index], generation),
					"expected pool:release(pool.values[index], generation)"
				)
				oldGenerations[index] = generation
				leases[index] = nil
				count -= 1
			end
		else
			local record, generation = pool:tryAcquire()
			if count == 64 then
				assert(record == nil and generation == nil, "expected exhaustion")
			else
				assert(record ~= nil, "expected acquired record")
				local acquiredIndex = record.index
				assert(
					acquiredIndex ~= nil and leases[acquiredIndex] == nil,
					"expected acquiredIndex ~= nil and leases[acquiredIndex] == nil"
				)
				assert(
					record == pool.values[acquiredIndex] and record.index == acquiredIndex,
					"expected record == pool.values[acquiredIndex] and record.index == acquiredIndex"
				)
				leases[acquiredIndex] = generation
				count += 1
			end
		end
		assert(pool:count() == count and created == 64, "expected pool:count() == count and created == 64")
		if step % 100 == 0 then
			for slot = 1, 64 do
				assert(
					pool:isAcquired(pool.values[slot]) == (leases[slot] ~= nil),
					"expected pool:isAcquired(pool.values[slot]) == (leases[slot] ~= nil)"
				)
			end
		end
	end
	pool:clear()
	assert(pool:count() == 0 and created == 64, "expected pool:count() == 0 and created == 64")
end)

test("record identity is private and generation survives reuse without wrappers", function()
	local resets = 0
	local pool = FixedSlotPool.new(1, {
		create = function()
			return { amount = 0 }
		end,
		reset = function()
			resets += 1
		end,
	})
	local record, generation = pool:tryAcquire()
	local foreign = { amount = 0 }
	assert(not pool:isAcquired(foreign), "foreign record is not owned")
	assert(not pool:release(foreign, generation), "foreign release must fail")
	assert(resets == 0, "foreign release must not invoke reset")
	assert(pool:release(record, generation), "first lease releases")
	local replacement, replacementGeneration = pool:tryAcquire()
	assert(rawequal(record, replacement), "acquisition returns the preallocated table itself")
	assert(not pool:release(record, generation), "old scalar token cannot release replacement")
	assert(pool:isAcquired(replacement, replacementGeneration), "replacement remains live")
	local keys = 0
	for key in record do
		assert(key == "amount", "pool metadata must not be injected into payload")
		keys += 1
	end
	assert(keys == 1 and resets == 1, "payload shape and reset count remain unchanged")
end)

test("constructor rejects ambiguous duplicate values and NaN", function()
	local same = {}
	for _, value in { same, false, 7, "same" } do
		rejects(function()
			FixedSlotPool.new(2, {
				create = function()
					return value
				end,
			})
		end)
	end
	rejects(function()
		FixedSlotPool.new(1, {
			create = function()
				return 0 / 0
			end,
		})
	end)
	local frozen = table.freeze({ amount = 1 })
	local pool = FixedSlotPool.new(1, {
		create = function()
			return frozen
		end,
	})
	local record, generation = pool:tryAcquire()
	assert(record == frozen and pool:release(record, generation), "frozen payloads need no metadata writes")
end)

print(tostring(passed) .. " fixed-slot pool test groups passed")
