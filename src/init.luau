--!strict
--!optimize 2

local FixedSlotPool = require(script.fixedSlotPool.components.fixedSlotPool.shared.fixedSlotPool)
local FixedSlotPoolTypes = require(script.fixedSlotPool.types.components.fixedSlotPool.shared.fixedSlotPool)

export type FixedSlotPool<T> = FixedSlotPoolTypes.FixedSlotPool<T>
export type FixedSlotPoolOptions<T> = FixedSlotPoolTypes.FixedSlotPoolOptions<T>

return FixedSlotPool
