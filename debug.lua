-- Ignore debug things if CHECKNET_DEBUG not set
function ignore_index(...)
	local empty_function = function(...) end
	return empty_function
end

local Debug = {}
setmetatable(Debug, { __index = ignore_index })
if os.getenv("CHECKNET_DEBUG") then
	Debug = { dbg = require("debugger/debugger") }
	setmetatable(Debug, { __index = Debug.dbg })
end

return Debug
