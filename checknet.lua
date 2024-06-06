local Netmon = require("netmon")
local Netlog = require("netlog")

-- Ignore debug things if CHECKNET_DEBUG not set
function ignore_index(...)
	local empty_function = (function(...)end)
	return empty_function
end

local Debug = {}
setmetatable(Debug, {__index=ignore_index})
if os.getenv("CHECKNET_DEBUG") then
	Debug = {dbg = require("debugger/debugger")}
	setmetatable(Debug, {__index=Debug.dbg})
end
-- end debug stuff

local log = Netlog:create()
log.flush = true
log:open()


local devices = Netmon:detect_devices()

local monitored = {}

-- add monitored devices
for _, dev in ipairs(devices) do
	local desc = dev:get_description()

	local devtype = string.lower(dev:get_device_type())
	
	Debug.writeln("\27[36;1m" .. devtype .. "\27[0m")

	-- local config_dir = "test_config"

	if devtype == "wifi" then
		local rtl_spec = desc:match("RTL[0-9]+")

		if rtl_spec == "RTL8192" then -- we use an rtl8192 device for the hotspot
			devtype = "hotspot"
			Debug.writeln("hotspot detected")
		end

		if not rtl_spec then -- if not a realtek device then use as wifi iface
			devtype = "wifi"
		end
	end

	-- exclude lo, p2p etc
	if devtype == "ethernet" or devtype == "hotspot" or devtype == "wifi" then
	--if devtype == "hotspot" or devtype == "wifi" then
	--if devtype == "hotspot" then
	--if devtype == "ethernet" then
		local monitored_device = Netmon:create(dev:get_iface(), log, devtype)

		monitored_device:monitor()
		table.insert(monitored, monitored_device)
	end
end

-- Debug.pp(monitored)

Netmon:attach_debugger(Debug)
Netmon:delete_all()
Netmon.run()

