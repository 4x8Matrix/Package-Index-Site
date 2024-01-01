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

type compiledFileNode = {
	nodeType: "FILE",
	nodeName: string,
	nodeClassName: string,
	nodeFullName: string,
	nodeMdx: string,
}

type compiledFolderNode = {
	nodeType: "FOLDER",
	nodeName: string,
	nodeChildren: { compiledFileNode | compiledFolderNode },
}

type compiledFileTree = {
	nodeChildren: { compiledFileNode | compiledFolderNode },
	mdxCount: number,
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
	local virtualFileSystem = {
		nodeChildren = {},
		mdxCount = 0,
	}

	for _, moonwaveDataObject in moonwaveData do
		local classSourceFile = string.split(moonwaveDataObject.source.path, "package-index/Modules/")[2]
		local classFileSystem = string.split(classSourceFile, "/")

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

		virtualFileSystem.mdxCount += 1

		table.remove(classFileSystem, 2)

		local headNode = virtualFileSystem

		for index, fileIndex in classFileSystem do
			if index == #classFileSystem then
				headNode.nodeChildren[fileIndex] = {
					nodeType = "FILE",
					nodeName = fileIndex,
					nodeClassName = className,
					nodeFullName = table.concat(classFileSystem, "/"),
					nodeMdx = classMdxContent,
				}
			else
				if not headNode.nodeChildren[fileIndex] then
					headNode.nodeChildren[fileIndex] = {
						nodeType = "FOLDER",
						nodeName = fileIndex,
						nodeChildren = {},
					}
				end

				headNode = headNode.nodeChildren[fileIndex]
			end
		end
	end

	print(`Built #{virtualFileSystem.mdxCount} virtual MDXs`)

	return virtualFileSystem
end

local function writeFoldersToFileSystem(fileTree: compiledFileTree, path: string)
	for _, fileOrFolderNode in fileTree.nodeChildren do
		if fileOrFolderNode.nodeType == "FOLDER" then
			local folderNode: compiledFolderNode = fileOrFolderNode
			local folderPath = `{path}/{fileOrFolderNode.nodeName}`

			fs.writeDir(folderPath)

			writeFoldersToFileSystem({
				nodeChildren = folderNode.nodeChildren,
				mdxCount = -1,
			}, folderPath)
		end
	end
end

local function writeFilesToFileSystem(fileTree: compiledFileTree, path: string, metaFilePaths)
	for _, fileOrFolderNode in fileTree.nodeChildren do
		if fileOrFolderNode.nodeType == "FILE" then
			local fileNode: compiledFileNode = fileOrFolderNode
			local filePath = `{path}/{fileOrFolderNode.nodeName}`
			local fileName = string.match(fileOrFolderNode.nodeName, "(%S+)%.")

			filePath = string.split(filePath, "/")
			table.remove(filePath, #filePath)
			filePath = table.concat(filePath, "/")

			if fileName == "init" then
				filePath = string.split(filePath, "/")
				local newFileName = table.remove(filePath, #filePath)
				filePath = table.concat(filePath, "/")

				fileName = newFileName
			end

			if not metaFilePaths[filePath] then
				metaFilePaths[filePath] = {}
			end

			metaFilePaths[filePath][net.urlEncode(fileName)] = fileNode.nodeClassName

			fs.writeFile(`{filePath}/{net.urlEncode(fileName)}.mdx`, fileNode.nodeMdx)
		else
			local folderNode: compiledFolderNode = fileOrFolderNode
			local folderPath = `{path}/{fileOrFolderNode.nodeName}`

			writeFilesToFileSystem({
				nodeChildren = folderNode.nodeChildren,
				mdxCount = -1,
			}, folderPath, metaFilePaths)
		end
	end
end

local function main(moonwaveData: moonwaveDataExportArray)
	---------------------------------

	if fs.isDir("pages/Packages") then
		fs.removeDir("pages/Packages")
	end

	fs.writeDir("pages/Packages")

	---------------------------------

	local virtualTree = createVirtualMDXs(moonwaveData)
	local metaFilePaths = {}

	print(`Writing #{virtualTree.mdxCount} virtual MDXs`)

	writeFoldersToFileSystem(virtualTree, "pages/Packages")
	writeFilesToFileSystem(virtualTree, "pages/Packages", metaFilePaths)

	for filePath, jsonContent in metaFilePaths do
		fs.writeFile(`{filePath}/_meta.json`, net.jsonEncode(jsonContent, true))
	end

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
