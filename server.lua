#!/usr/bin/env luajit
local fennel = require("fennel")
local http_request = require("http.request")
local cjson = require("cjson")
local url = require("socket.url")

io.stdout:setvbuf 'no' -- make sure we can print debugging 🙄

-- where the fish lives
local runtime_env = os.getenv("AWS_LAMBDA_RUNTIME_API")
local runtime_uri = "http://" .. runtime_env .. "/2018-06-01/runtime"
local next_uri = runtime_uri .. "/invocation/next"
local timeout = 900

function pointer_get(str) -- turn a pointer into a value
	local uri = url.parse(str)
	if uri.scheme == "str" then
		return uri.path
	elseif uri.scheme == "int" then
		return tonumber(uri.path)
	elseif uri.scheme == "float" then
		return tonumber(uri.path)
	elseif uri.scheme == "bool" then
		if uri.path == "True" then
			return true
		else
			return false
		end
	elseif uri.scheme == "none" then
		return nil
	elseif uri.scheme == "json" then
		local code = url.unescape(uri.path)
		return cjson.decode(code)
	elseif uri.scheme == "fennel" then
		local code = url.unescape(uri.path)
		code = fennel.compileString(code, {compilerEnv=_G})
		return assert(loadstring(code))()
	elseif uri.scheme == "lua" then
		local code = url.unescape(uri.path)
		return assert(loadstring(code))()
	else
		error("unsupported scheme: " .. uri.scheme)
	end
end


function pointer_put(value) -- turn a value into a pointer
	local tipe = type(value)
	if tipe == "string" then
		return "str:" .. url.escape(value)
	elseif tipe == "nil" then
		return "none:"
	elseif tipe == "none" then
		return "none:"
	elseif tipe == "boolean" then
		if value then
			return "bool:True"
		else
			return "bool:False"
		end
	elseif tipe == "number" then
		str = tostring(value)
		if string.find(str, "\\.") then
			return "float:" .. str
		else
			return "int:" .. str
		end
	elseif tipe == "table" then
		local code = cjson.encode(value)
		return "json:" .. url.escape(code)
	else
		error("unsupported type: " .. tipe)
	end
end


function shallow_map(operator, value) -- for applied get/put across structure
	local tipe = type(value)
	local result
	if tipe == "table" then
		result = {}
		for k, v in pairs(value) do
			result[k] = operator(v)
		end
	else
		result = operator(value)
	end
	return result
end


function shallow_get(value) -- get preserving structure
	return shallow_map(pointer_get, value)
end


function shallow_put(value) -- put preserving structure
	return shallow_map(pointer_put, value)
end


function dump_headers(headers) -- for debugging responses
	print("-- headers...")
	for name, value, never_index in headers:each() do
		print(name, value)
	end
end


function run_payload(payload) -- turn incoming payload into outgoing payload
	-- load the input
	local result = {}
	for k, v in pairs(payload) do
		result[k] = shallow_get(v)
	end
	-- run the program
	result = result["def"](unpack(result["args"]))
	-- store the output
	result = shallow_put(result)
	return result
end


function handler(input) -- consume json, produce json
	local input = cjson.decode(input)  -- json to input
	input = run_payload(input)         -- input to output
	input = cjson.encode(input)        -- output to json
	return input
end


while true do
	local headers, stream = assert(http_request.new_from_uri(next_uri):go(timeout))
	local body = assert(stream:get_body_as_string())
	if headers:get ":status" ~= "200" then
		error(body)
	else
		-- get a request from lambda
		local request_id = headers:get_comma_separated "lambda-runtime-aws-request-id"
		local reply_to = runtime_uri
			.. "/invocation/"
			.. request_id
			.. "/response"
		-- turn the request into a response
		body = handler(body)
		-- send the response to lambda
		local reply = http_request.new_from_uri(reply_to)
		reply.headers:upsert(":method", "POST")
		reply.headers:upsert("content-type", "application/json")
		reply:set_body(body)
		headers, stream = assert(reply:go())
		if headers:get ":status" ~= "202" then
			error(stream:get_body_as_string())
		end
	end
end
