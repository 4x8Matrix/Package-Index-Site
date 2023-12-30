local process = require("@lune/process")
local serde = require("@lune/serde")
local fs = require("@lune/fs")
local net = require("@lune/net")

local mappedLuauDataTypes = {
	-- generic Roblox datatypes
	[{ "boolean", "bool" }] = "https://create.roblox.com/docs/en-us/luau/booleans",
	[{ "nil" }] = "https://create.roblox.com/docs/en-us/luau/nil",
	[{ "number" }] = "https://create.roblox.com/docs/en-us/luau/numbers",
	[{ "string" }] = "https://create.roblox.com/docs/en-us/luau/strings",
	[{ "table" }] = "https://create.roblox.com/docs/en-us/luau/tables",
	[{ "tuple", "..." }] = "https://create.roblox.com/docs/en-us/luau/tuples",
	[{ "userdata", "proxy" }] = "https://create.roblox.com/docs/en-us/luau/userdata",

	-- common Roblox datatypes
	[{ "instance" }] = "https://create.roblox.com/docs/en-us/reference/engine/datatypes/Instance",
	[{ "player" }] = "https://create.roblox.com/docs/en-us/reference/engine/classes/Player",
	[{ "vector3", "vec3" }] = "https://create.roblox.com/docs/en-us/reference/engine/datatypes/Vector3",
	[{ "vector2", "vec2" }] = "https://create.roblox.com/docs/en-us/reference/engine/datatypes/Vector2",
	[{ "udim2" }] = "https://create.roblox.com/docs/en-us/reference/engine/datatypes/UDim2",
	[{ "udim" }] = "https://create.roblox.com/docs/en-us/reference/engine/datatypes/UDim",

	[{ "rbxscriptsignal", "signal" }] = "https://create.roblox.com/docs/en-us/reference/engine/datatypes/RBXScriptSignal",
	[{ "rbxscriptconnection", "connection" }] = "https://create.roblox.com/docs/en-us/reference/engine/datatypes/RBXScriptConnection",
}

type moonwavePropertyData = {
	name: string,
	desc: string,
	lua_type: string,
	source: {
		line: number,
		path: string,
	},
}

type moonwaveFunctionData = {
	name: string,
	desc: string,
	source: {
		path: string,
		line: number,
	},
	function_type: "method" | "static",
	returns: {
		{
			desc: string,
			lua_type: string,
		}
	},
	params: {
		{
			name: string,
			desc: string,
			lua_type: string,
		}?
	},
}

type moonwaveDataExportArray = {
	{
		name: string,
		functions: { moonwaveFunctionData? },
		source: {
			path: string,
			line: number,
		},
		properties: { moonwavePropertyData? },
		desc: string,
		types: unknown,
	}
}

local function getFunctionsOfFunctionType(inputArray, functionType)
	local resultArray = {}

	for _, functionObject in inputArray do
		if functionObject.function_type == functionType then
			table.insert(resultArray, functionObject)
		end
	end

	return resultArray
end

local function parseLuauType(luaType)
	local luaTypeCheck = string.gsub(string.lower(luaType), "%W", "")

	luaType = string.gsub(luaType, "{", "\\{")

	for queryTable, apiUrl in mappedLuauDataTypes do
		if table.find(queryTable, luaTypeCheck) then
			return `[{luaType}]({apiUrl})`
		end
	end

	return luaType
end

---------------------------------

local function writeClassHeaderToMdx(className, classDescription, mdxContent)
	mdxContent ..= `# {className}\n`
	mdxContent ..= `{classDescription}\n\n`

	return mdxContent
end

local function writeClassPropertiesToMdx(className, classProperties, mdxContent)
	mdxContent ..= `## Properties\n`

	local function parsePropertyHeader(property: moonwavePropertyData)
		return property.name
	end

	local function getPropertyType(property: moonwavePropertyData)
		if property.lua_type == "" then
			return parseLuauType("any")
		end

		return parseLuauType(property.lua_type)
	end

	for _, property: moonwavePropertyData in classProperties do
		mdxContent ..= `### {parsePropertyHeader(property)}\n`
		mdxContent ..= `> {className}.{property.name} \\<{getPropertyType(property)}>\n\n`
		mdxContent ..= `{property.desc}\n\n`
	end

	return mdxContent
end

local function writeClassMethodsToMdx(className, classMethods, mdxContent)
	mdxContent ..= `## Methods\n`

	local function parseMethodHeader(proto: moonwaveFunctionData)
		return `{proto.name}\n`
	end

	local function getReadableParamList(proto: moonwaveFunctionData)
		local readableList = " "

		if #proto.params == 0 then
			return ""
		end

		for index, paramObject in proto.params do
			readableList ..= `\`{paramObject.name}\` {parseLuauType(paramObject.lua_type)}` .. (index == #proto.params and ` ` or `, `)
		end

		return readableList
	end

	local function getReadableReturnsList(proto: moonwaveFunctionData)
		local readableList = " "

		if #proto.returns == 0 then
			return parseLuauType("nil")
		end

		for index, returnObject in proto.returns do
			readableList ..= `{parseLuauType(returnObject.lua_type)}` .. (index == #proto.returns and ` ` or `, `)
		end

		return readableList
	end

	for _, method: moonwaveFunctionData in classMethods do
		mdxContent ..= `### {parseMethodHeader(method)}\n`
		mdxContent ..= `> {className}:{method.name}({getReadableParamList(method)}) -> {getReadableReturnsList(method)}\n\n`
		mdxContent ..= `{method.desc}\n\n`
		mdxContent ..= `---\n`
	end

	return mdxContent
end

local function writeClassFunctionsToMdx(className, classFunctions, mdxContent)
	mdxContent ..= `## Functions\n`

	local function parseFunctionHeader(proto: moonwaveFunctionData)
		return `{proto.name}\n`
	end

	local function getReadableParamList(proto: moonwaveFunctionData)
		local readableList = " "

		if #proto.params == 0 then
			return ""
		end

		for index, paramObject in proto.params do
			readableList ..= `\`{paramObject.name}\` {parseLuauType(paramObject.lua_type)}` .. (index == #proto.params and ` ` or `, `)
		end

		return readableList
	end

	local function getReadableReturnsList(proto: moonwaveFunctionData)
		local readableList = " "

		if #proto.returns == 0 then
			return parseLuauType("nil")
		end

		for index, returnObject in proto.returns do
			readableList ..= `{parseLuauType(returnObject.lua_type)}` .. (index == #proto.returns and ` ` or `, `)
		end

		return readableList
	end

	for _, proto: moonwaveFunctionData in classFunctions do
		mdxContent ..= `### {parseFunctionHeader(proto)}\n`
		mdxContent ..= `> {className}.{proto.name}({getReadableParamList(proto)}) -> {getReadableReturnsList(proto)}\n\n`
		mdxContent ..= `{proto.desc}\n\n`
		mdxContent ..= `---\n`
	end

	return mdxContent
end

---------------------------------

local function createVirtualMDXs(moonwaveData: moonwaveDataExportArray)
	local virtualFileSystem = {}

	for _, moonwaveDataObject in moonwaveData do
		local className = moonwaveDataObject.name
		local classDescription = moonwaveDataObject.desc
		local classProperties = moonwaveDataObject.properties

		local classMethods = getFunctionsOfFunctionType(moonwaveDataObject.functions, "method")
		local classFunctions = getFunctionsOfFunctionType(moonwaveDataObject.functions, "static")

		print(`Building MDX for class '{className}'`)

		local classMdxContent = ""

		classMdxContent ..= "import { Callout } from 'nextra/components'\n\n"

		classMdxContent = writeClassHeaderToMdx(className, classDescription, classMdxContent)
		classMdxContent = writeClassPropertiesToMdx(className, classProperties, classMdxContent)
		classMdxContent = writeClassMethodsToMdx(className, classMethods, classMdxContent)
		classMdxContent = writeClassFunctionsToMdx(className, classFunctions, classMdxContent)

		table.insert(virtualFileSystem, {
			path = net.urlEncode(className),
			content = classMdxContent,
			name = className,
		})
	end

	print(`Built #{#virtualFileSystem} virtual MDXs`)

	return virtualFileSystem
end

local function main(moonwaveData: moonwaveDataExportArray)
	---------------------------------

	if fs.isDir("pages/Packages") then
		fs.removeDir("pages/Packages")
	end

	fs.writeDir("pages/Packages")

	---------------------------------

	local virtualTree = createVirtualMDXs(moonwaveData)
	local virtualTreeFileNames = {}

	print(`Writing #{#virtualTree} virtual MDXs`)

	for _, fileContents in virtualTree do
		fs.writeFile(`pages/Packages/{fileContents.path}.mdx`, fileContents.content)

		virtualTreeFileNames[fileContents.path] = fileContents.name
	end

	fs.writeFile(`pages/Packages/_meta.json`, serde.encode("json", virtualTreeFileNames))

	print(`Finished writing Virtual FS`)
end

main(serde.decode(
	"json",
	process.spawn("moonwave", {
		"extract",
		"-b",
		"package-index/Modules",
	}).stdout
))
