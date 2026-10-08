--!strict
--!optimize 2

local FixedSlotPool = require("../src")

type Record = { amount: number, target: string? }
local pool: FixedSlotPool.FixedSlotPool<Record> = FixedSlotPool.new(4, {
	create = function(index: number): Record
		return { amount = index, target = nil }
	end,
	reset = function(record: Record)
		record.target = nil
	end,
})

pool.values[1].amount = 5
local record, generation = pool:tryAcquire()
if record ~= nil and generation ~= nil then
	record.target = "example"
	assert(pool:isAcquired(record, generation), "expected pool:isAcquired(record, generation)")
	assert(pool:release(record, generation), "expected pool:release(record, generation)")
end
local numberPool: FixedSlotPool.FixedSlotPool<number> = FixedSlotPool.new(2, {
	create = function(slotIndex: number): number
		return slotIndex
	end,
})
assert(
	numberPool.capacity == 2 and numberPool:count() == 0,
	"expected numberPool.capacity == 2 and numberPool:count() == 0"
)
pool:clear()
return pool
