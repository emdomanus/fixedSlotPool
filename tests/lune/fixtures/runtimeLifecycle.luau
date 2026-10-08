--!strict
--!optimize 2
local requireAny = require :: any
local process = requireAny("@lune/process")
local task = requireAny("@lune/task")
local fs = requireAny("@lune/fs")
local transform = requireAny("../lib/luneRequireTransform")
local mode = process.env.FIXED_SLOT_POOL_HARNESS_CASE
local package = transform.write({
	packageRoot = if mode == "setup-failure" then "missing-fixed-slot-pool-fixture" else "src",
})
local tempo = package.requireModule("init.luau")
assert(tempo.new ~= nil, "transformed package must export its constructor")
if mode == "test-failure" then
	error("intentional harness fixture failure")
elseif mode == "concurrent" then
	print("RUNTIME=" .. process.env.FIXED_SLOT_POOL_LUNE_RUNTIME)
	task.wait(1)
	assert(fs.isDir(process.env.FIXED_SLOT_POOL_LUNE_RUNTIME), "another run must not remove this runtime")
	assert(package.requireModule("init.luau") == tempo, "concurrent runtime must remain readable")
end
