--!strict
--!optimize 2

local FixedSlotPool = require("../src")

local pool = FixedSlotPool.new(2, {
	create = function(): { amount: number }
		return { amount = 0 }
	end,
})

pool.values[1].amount = 5
pool.values[1] = { amount = 3 } -- EXPECT_ERROR
pool.values = {} -- EXPECT_ERROR
pool.capacity = 100 -- EXPECT_ERROR
pool:release(pool.values[1]) -- EXPECT_ERROR
pool:release(pool.values[1], "old") -- EXPECT_ERROR
pool.values[1].amount = "wrong" -- EXPECT_ERROR
pool:release(1, 1) -- EXPECT_ERROR
pool:isAcquired(1) -- EXPECT_ERROR
return pool
