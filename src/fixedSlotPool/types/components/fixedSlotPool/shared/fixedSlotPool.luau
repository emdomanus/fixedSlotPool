--!strict
--!optimize 2

export type FixedSlotPoolOptions<T> = {
	read create: (index: number) -> T,
	read reset: ((value: T) -> ())?,
}

export type FixedSlotPool<T> = {
	read values: { read [number]: T },
	read capacity: number,
	read tryAcquire: (self: FixedSlotPool<T>) -> (T?, number?),
	read release: (self: FixedSlotPool<T>, value: T, generation: number) -> boolean,
	read isAcquired: (self: FixedSlotPool<T>, value: T, generation: number?) -> boolean,
	read count: (self: FixedSlotPool<T>) -> number,
	read clear: (self: FixedSlotPool<T>) -> (),
}

export type FixedSlotPoolImpl<T> = FixedSlotPool<T> & {
	_indices: { [T]: number },
	_nextFree: { number },
	_generations: { number },
	_freeHead: number,
	_activeCount: number,
	_reset: ((value: T) -> ())?,
	_resetting: boolean,
}

return table.freeze({})
