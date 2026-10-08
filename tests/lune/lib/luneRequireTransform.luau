--!strict
--!optimize 2

local requireAny = require :: any
local fs = requireAny("@lune/fs")
local process = requireAny("@lune/process")

export type TransformOptions = {
	packageRoot: string,
}

export type TransformHandle = {
	requireModule: (relativePath: string) -> any,
}

local LuneRequireTransform = {}

local function normalizePath(path: string): string
	return (path:gsub("\\", "/"))
end

local function joinPath(left: string, right: string): string
	if left:sub(-1) == "/" or left:sub(-1) == "\\" then
		return left .. right
	end
	return left .. "/" .. right
end

local function resolveFromCwd(path: string): string
	local normalized = normalizePath(path)
	if normalized:match("^%a:/") or normalized:sub(1, 1) == "/" then
		return normalized
	end
	return joinPath(process.cwd, normalized)
end

local function dirname(path: string): string
	return normalizePath(path):match("^(.*)/[^/]+$") or ""
end

-- Adapted from VoxelMMO's Lune 0.10 host adapter; runtime sources remain script-relative.
local modulePath = debug.info(1, "s"):gsub("^@", "")
local function requirePath(sourceFile: string, targetFile: string): string
	local sourceParts = string.split(dirname(resolveFromCwd(sourceFile):gsub("/init%.luau$", "")), "/")
	local targetParts = string.split(normalizePath(targetFile):gsub("%.luau$", ""):gsub("/init$", ""), "/")
	local common = 0
	for index = 1, math.min(#sourceParts, #targetParts) do
		if sourceParts[index]:lower() ~= targetParts[index]:lower() then
			break
		end
		common = index
	end
	assert(common > 0, "Lune fixture modules must share a filesystem root")
	local result = {}
	for _ = common + 1, #sourceParts do
		table.insert(result, "..")
	end
	for index = common + 1, #targetParts do
		table.insert(result, targetParts[index])
	end
	return "./" .. table.concat(result, "/")
end

local function discoverPackageFiles(packageRoot: string): { string }
	local discovered: { string } = {}

	local function visit(directoryPath: string, directoryRel: string)
		for _, entry in fs.readDir(directoryPath) do
			local entryPath = joinPath(directoryPath, entry)
			local entryRel = if directoryRel == "" then entry else directoryRel .. "/" .. entry
			if fs.isDir(entryPath) then
				visit(entryPath, entryRel)
			elseif fs.isFile(entryPath) and entry:sub(-5) == ".luau" then
				table.insert(discovered, entryRel)
			end
		end
	end

	visit(packageRoot, "")
	table.sort(discovered)
	return discovered
end

local function moduleSegments(sourceRel: string): { string }
	local withoutExtension = normalizePath(sourceRel):gsub("%.luau$", "")
	local segments: { string } = {}
	for part in withoutExtension:gmatch("[^/]+") do
		table.insert(segments, part)
	end
	if segments[#segments] == "init" then
		table.remove(segments)
	end
	return segments
end

local function relFromSegments(segments: { string }, sourceFileSet: { [string]: true }): string
	local base = table.concat(segments, "/")
	local initRel = if base == "" then "init.luau" else base .. "/init.luau"
	if sourceFileSet[initRel] then
		return initRel
	end
	return base .. ".luau"
end

local function resolveScriptRequire(
	sourceRel: string,
	expression: string,
	tempRoot: string,
	sourceFileSet: { [string]: true }
): string
	local segments = moduleSegments(sourceRel)
	local first = true
	for token in expression:gmatch("[A-Za-z_][A-Za-z0-9_]*") do
		if first then
			first = false
		elseif token == "Parent" then
			table.remove(segments)
		else
			table.insert(segments, token)
		end
	end
	return joinPath(tempRoot, relFromSegments(segments, sourceFileSet))
end

function LuneRequireTransform.write(options: TransformOptions): TransformHandle
	local packageRoot = resolveFromCwd(options.packageRoot)
	local runtimePath = process.env.FIXED_SLOT_POOL_LUNE_RUNTIME
	assert(
		runtimePath ~= nil and runtimePath ~= "",
		"use scripts/verify/tests.ps1 to own the generated runtime"
	)
	local tempRoot = resolveFromCwd(runtimePath)
	assert(not fs.isDir(tempRoot), "each run may transform its package only once")
	fs.writeDir(tempRoot)
	local packageFiles = discoverPackageFiles(packageRoot)
	local sourceFileSet: { [string]: true } = {}

	for _, relativePath in packageFiles do
		sourceFileSet[relativePath] = true
	end

	for _, relativePath in packageFiles do
		local source = fs.readFile(joinPath(packageRoot, relativePath))
		local transformed = source:gsub("require%(%s*(script[^%)]*)%)", function(expression)
			return "require([["
				.. requirePath(
					joinPath(tempRoot, relativePath),
					resolveScriptRequire(relativePath, expression, tempRoot, sourceFileSet)
				)
				.. "]])"
		end)

		local targetPath = joinPath(tempRoot, relativePath)
		local targetDir = dirname(targetPath)
		if targetDir ~= "" then
			fs.writeDir(targetDir)
		end
		fs.writeFile(targetPath, transformed)
	end

	return {
		requireModule = function(relativePath: string): any
			return requireAny(requirePath(modulePath, joinPath(tempRoot, relativePath)))
		end,
	}
end

return LuneRequireTransform
