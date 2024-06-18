local directories = require("directories")
local Itool = require("itool")

local lgi = require("lgi")
local NetworkManager = lgi.require("NM") -- include NetworkManager from lgi
local GLib = lgi.require("GLib")

local Netlog = require("netlog")

-- needed for AF_INET (why doesn't NetworkManager define this?)
local socket = require("socket")

--[[ workaround
function sleep(sec)
socket.select(nil, nil, sec)
end
]]
--

--@Shared variables
Netmon = {
	nmcli = NetworkManager.Client.new(),
	logger = {},
	--monitored = {}, -- devices monitored by Netmon
	Loop = GLib.MainLoop(nil, false),
}

--@void ((__DEBUG__))
function Netmon:attach_debugger(dbg)
	self.debugger = dbg
end

function Netmon:delete_all()
	self.debugger.writeln("Deleting all connections...")

	for _, conn in ipairs(self.nmcli:get_connections()) do
		conn:delete()
	end

	self.debugger.writeln("Done!")
end

math.randomseed(os.time())
math.random()
math.random()
math.random()

--@uuid
function Netmon.gen_uuid()
	local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
	local uuid = string.gsub(template, "[xy]", function(c)
		local v = (c == "x") and math.random(0, 0xf) or math.random(8, 0xb)
		return string.format("%x", v)
	end)

	return uuid
end

--@String
function Netmon.get_utf8_ssid(ap)
	local ssid = ap:get_ssid()
	if not ssid then
		return ""
	end
	return NetworkManager.utils_ssid_to_utf8(ssid:get_data())
end

--@{ Mac -> table.pack( SSID, BAND ) }
function Netmon:_wifi_scan()
	--[[
	This function is only enabled on wifi capable interfaces.

	Returns a list containing the SSID and MAC address of
	all the available networks for said interface.

	this is used once atm, because of shit dual band routers
	configured to not separate 2ghz and 5ghz, so we have to
	get the mac addrs and choose. Of course, 5GHz is preferred.
	(this is customizable) (TODO*)

	WARNING: 2G and 5G checking may only be properly
	implemented when using the latest version of Libnm
	(I think it runs fine on arch)
	--]]

	local networks = {}
	for _, ap in ipairs(self.device:get_access_points()) do
		local ssid = self.get_utf8_ssid(ap)
		local mac = ap:get_bssid()

		local bandwidth = 0000

		--@libnm >= 1.46
		if NetworkManager.AccessPoint.get_bandwidth ~= nil then
			bandwidth = ap:get_bandwidth()
		end

		table.insert(table.pack(mac, ssid, bandwidth))
	end

	table.sort(networks, function(net_a, net_b)
		local _, _, bw1 = table.unpack(net_a)
		local _, _, bw2 = table.unpack(net_b)
		return bw1 < bw2
	end)

	return networks
end

--@NetworkManagerConnection <name> <type> [network_name] [password]
function Netmon:_create_conn(name, devtype, network_name, password)
	self._tmp_conn = NetworkManager.SimpleConnection.new()

	local setting_conn = NetworkManager.SettingConnection.new()

	setting_conn[NetworkManager.SETTING_CONNECTION_INTERFACE_NAME] = self.device_name
	setting_conn[NetworkManager.SETTING_CONNECTION_UUID] = self.uuid

	local correct_type = "802-11-wireless"
	if devtype == "wired" or devtype == "ethernet" then
		correct_type = "802-3-ethernet"
	end

	setting_conn[NetworkManager.SETTING_CONNECTION_TYPE] = correct_type
	setting_conn[NetworkManager.SETTING_CONNECTION_ID] = name

	self._tmp_conn:add_setting(setting_conn)

	if devtype == "wired" or devtype == "ethernet" then
		self._tmp_conn:add_setting(NetworkManager.SettingWired.new())

		local setting_ipv4 = NetworkManager.SettingIP4Config.new()
		--local setting_ipv6 = NetworkManager.SettingIP6Config.new()

		self.debugger.writeln("\27[36;1m================SETTING ETHERNET IP================")
		self.debugger.writeln(string.format("IP ADDR -> %s", self.ip))
		self.debugger.writeln("===================================================\27[0m")

		--setting_ipv6[NetworkManager.SETTING_IP_CONFIG_METHOD] = NetworkManager.SETTING_IP6_CONFIG_METHOD_DISABLED

		if self.ip then
			setting_ipv4[NetworkManager.SETTING_IP_CONFIG_METHOD] = NetworkManager.SETTING_IP4_CONFIG_METHOD_MANUAL

			-- 2 IS AF_INET WHT IS GETTING AF_INET SO ANNOYING
			local ipv4 = NetworkManager.IPAddress.new(2, self.ip, 8)
			setting_ipv4:add_address(ipv4)
		end

		self._tmp_conn:add_setting(setting_ipv4)

		--self._tmp_conn:add_setting(setting_ipv6)

		return self._tmp_conn
	end

	local setting_wireless = NetworkManager.SettingWireless.new()
	local setting_wireless_security = NetworkManager.SettingWirelessSecurity.new()

	setting_wireless[NetworkManager.SETTING_WIRELESS_SSID] = GLib.Bytes(network_name)

	-- setting_wireless[NetworkManager.SETTING_WIRELESS_MODE] = "auto"

	setting_wireless_security[NetworkManager.SETTING_WIRELESS_SECURITY_KEY_MGMT] = "wpa-psk"
	if devtype ~= "hotspot" then
		setting_wireless_security[NetworkManager.SETTING_WIRELESS_SECURITY_AUTH_ALG] = "open"

		if self.wifi_scan ~= nil then
			self.debugger.writeln("\27[32;1mDevice capable of wifi scan, scanning...\27[0m")

			local networks = self:wifi_scan()
			for _, access_point in networks do
				mac, ssid, band = table.unpack(access_point)
				if ssid == network_name then
					setting_wireless[NetworkManager.SETTING_WIRELESS_MAC_ADDRESS] = mac
					break
				end
			end
		end
	end

	setting_wireless_security[NetworkManager.SETTING_WIRELESS_SECURITY_PSK] = password

	if devtype == "hotspot" then
		-- setting_wireless[NetworkManager.SETTING_WIRELESS_MODE_ADHOC] = GLib.Bytes("adhoc")

		local setting_ipv4 = NetworkManager.SettingIP4Config.new()
		setting_ipv4[NetworkManager.SETTING_IP_CONFIG_METHOD] = NetworkManager.SETTING_IP4_CONFIG_METHOD_SHARED

		setting_wireless_security:add_proto("rsn")
		setting_wireless_security:add_group("ccmp")
		setting_wireless_security:add_pairwise("ccmp")

		-- setting_wireless_security[NetworkManager.SETTING_WIRELESS_SECURITY_GROUP] = "CCMP"
		-- setting_wireless_security[NetworkManager.SETTING_WIRELESS_SECURITY_PAIRWISE] = "CCMP"
		-- setting_ipv4:add_dns_search("127.0.0.1")

		setting_wireless[NetworkManager.SETTING_WIRELESS_MODE] = "ap"

		self._tmp_conn:add_setting(setting_ipv4)
	end

	self._tmp_conn:add_setting(setting_wireless_security)
	self._tmp_conn:add_setting(setting_wireless)

	return self._tmp_conn
end

--@device list
function Netmon:detect_devices()
	devices = self.nmcli:get_devices()
	return devices
end

--@void ((__callback__))
function Netmon:_generic_conn_callback(_, result, data)
	local conn, err, code = self.nmcli:add_and_activate_connection_finish(result)

	self.connecting = false

	if conn then
		local dev = conn:get_connection():get_interface_name()

		self:LOG("CALLBACK FROM " .. dev, "starting")
		self:LOG("CALLBACK FROM " .. dev, "The connection profile has been successfully added to NetworkManager:")
		self:LOG("CALLBACK FROM " .. dev, "%s, %s", conn:get_id(), conn:get_uuid())

		self.debugger.writeln("\n\27[32;1m==================================")
		self.debugger.pp({ "CALLBACK FROM " .. dev, string.format("%s, %s", conn:get_id(), conn:get_uuid()) })
		self.debugger.pp("CALLBACK FROM " .. dev .. "| " .. self.uuid)
		self.debugger.pp({ "CONN CALLBACK", string.format("%s: (%s)", conn:get_path(), conn:get_state()) })
		self.debugger.writeln("==================================\27[0m\n")

		self:LOG("CONN CALLBACK", "%s: (%s)", conn:get_path(), conn:get_state(), self.uuid)
	else
		self:LOG("CONN CALLBACK", "Error: (%d) %s", code or -1, err)
		self.debugger.pp("CALLBACK FROM " .. self.device_name .. "| " .. self.uuid)
	end

	-- self.conn_wait_loop:quit() -- exit now
end

--@Netmon Instance
function Netmon:create(device, log, devtype, config_file)
	local netmon = {}
	setmetatable(netmon, {
		__index = self,
	})

	assert(device, "Please specify a device")

	if log then
		self.logger = log
		self.logger:write("logger attached succesfully")
	end

	netmon.connecting = false
	netmon.device_name = device
	netmon.device = nil

	netmon.devtype = devtype or "wifi" -- defaults to wifi

	-- netmon.config_path = config_file or directories.MyTempo .. "main/config_shell.txt"
	netmon.config_path = config_file or directories.Home .. "MyTempo/conf/" .. devtype .. ".conf"
	if config_file == "no_config" then
		netmon.config_path = nil
	end

	self.generic_conn_callback = function(...)
		netmon:_generic_conn_callback(...)
	end

	for i, dev in ipairs(self:detect_devices()) do
		if dev:get_iface() == netmon.device_name then
			netmon.device = dev

			if netmon.device:get_device_type() == "WIFI" then
				netmon.wifi_scan = self._wifi_scan -- implement the wifi scan fn
			end
		end
	end

	netmon.uuid = Netmon.gen_uuid()

	return netmon
end

--@Name, Password
function Netmon:read_config()
	assert(self.config_path, "Can't read from nil file")

	f, err = io.open(self.config_path)
	if err and self.logger then
		self.logger:write(string.format("READ CONFIG| Couldn't open config file: %s", err))
		return nil, nil
	end

	local config = f:read("*a")
	local config_iterator = config:gmatch('[a-zA-Z0-9]:"([^\n]*)"')

	return Itool.iter_unpack(config_iterator)
end

function Netmon:activateconn()
	local conn = self.nmcli:get_connection_by_uuid(self.uuid)
	if not conn then
		self:connect_once()
		return
	end

	self.connecting = true

	self.nmcli:activate_connection_async(conn, self.device, nil, nil, self.generic_conn_callback, nil)
end

--@bool
function Netmon:connect_once()
	assert(self.device, "No device specified!")

	if not self.network_name then
		self.network_name, self.password, self.ip = self:read_config()

		if self.network_name == nil then
			error("couldn't read configuration")
		end
	end

	self.connecting = true

	self.conn = self:_create_conn(self.network_name, self.devtype, self.network_name, self.password)

	self.debugger.writeln(string.format("\27[36;1m"))
	self.debugger.pp(self.conn)
	self.debugger.pp(self.password)
	self.debugger.pp(self.network_name)
	self.debugger.writeln(string.format("%s\27[0m", self.ip))

	self.nmcli:add_and_activate_connection_async(self.conn, self.device, nil, nil, self.generic_conn_callback, nil)

	-- self.conn_wait_loop:run()
end

function Netmon:LOG(fn, fmt, ...)
	if self.logger then
		self.logger:write(string.format("IN %s| " .. fmt or "", fn:upper(), ...))
	end
end

function Netmon:did_network_name_change()
	if not self.config_path then
		return false
	end

	local network_name, pass, ip = self:read_config()
	if network_name ~= self.network_name or pass ~= self.password then
		self.network_name = network_name
		self.password = pass
		self.ip = ip
		self.uuid = self.gen_uuid()

		return true
	end

	return false
end

CHECK_UP_CONNECT_ONCE = 1
CHECK_UP_REACTIVATE = 2
CHECK_UP_OK = 3
function Netmon:check_up()
	local dev_state = self.device:get_state()

	self.debugger.writeln(
		"\n\27[33;1m=====================CHECKING UP" .. self.device_name .. "============================="
	)
	self.debugger.writeln(string.format("- DEVICE STATE: (%s)", dev_state))
	self.debugger.writeln(
		string.format("- DEVICE CONFIGURATION: (Network name: %s, Password: %s)", self.network_name, self.password)
	)

	self:LOG(string.format("checking up %s", self.device_name), "Dev state: %s", dev_state)

	self.debugger.writeln(string.format("network: %s", self.network_name or "127"))
	if self:did_network_name_change() then
		local active = self.device:get_active_connection()
		if active then
			active:get_connection():delete()
		end

		self.debugger.writeln(string.format("network: %s", self.network_name or "127"))
		self.conn = nil

		return CHECK_UP_CONNECT_ONCE
	end

	if dev_state ~= "ACTIVATED" and dev_state ~= "IP_CONFIG" and dev_state ~= "CONFIG" then --XXX: the IP_CONFIG thing is a workaround, testing
		self.debugger.writeln("- DEVICE NOT ACTIVATED, RECONNECTING ...")
		self.debugger.writeln("===========================================\27[0m\n")

		if self.conn then
			return CHECK_UP_REACTIVATE
		end

		return CHECK_UP_CONNECT_ONCE
	end

	local conn = self.device:get_active_connection()
	if not conn then -- XXX: what?
		if not self.conn then
			return CHECK_UP_CONNECT_ONCE
		end

		return CHECK_UP_REACTIVATE
	end

	self.debugger.writeln(string.format("- ACTIVE CONNECTION: (%s)", conn))

	local conn_uuid = conn:get_uuid()
	self.debugger.writeln(string.format("\t| .. FOUND UUID: (%s) - (SELF UUID: (%s))", conn_uuid, self.uuid))

	if conn_uuid ~= self.uuid then
		self:LOG(
			string.format("checking_up %s", self.device_name),
			"Device connected to another network, reconnecting..."
		)

		self.debugger.writeln("- UNKNOWN NETWORK ... DELETING")
		conn:get_connection():delete()

		self.debugger.writeln("===========================================\27[0m\n")

		return CHECK_UP_CONNECT_ONCE
	end

	self.debugger.writeln("===========================================\27[0m\n")

	return CHECK_UP_OK
end

--@void
function Netmon:create_monitor()
	self.mon = coroutine.create(
		--@void __coroutine__
		function()
			while true do
				local result = self:check_up()

				if result == CHECK_UP_CONNECT_ONCE then
					self:connect_once()
				end

				if result == CHECK_UP_REACTIVATE then
					self:activateconn()
				end

				coroutine.yield(true) -- return true to make glib run this again
			end
		end
	)
end

function Netmon:monitor()
	assert(self.device, "How can you monitor an empty device?")

	if not self.mon then
		self:create_monitor()
	end
	--table.insert(Netmon.monitored, self.mon)
	GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 8, self.mon)
end

--[[@void
function Netmon.check_all()
for _, mon_routine in ipairs(Netmon.monitored) do
coroutine.resume(mon_routine)
end
end
]]
--

--@void ((__INF_LOOP__))
function Netmon.run()
	--[[while true do
	if Netmon.logger then
	Netmon.logger:write("NETMON.RUN| Checking all networks")
	end

	Netmon.check_all()

	sleep(4)
	end
	]]
	--
	--GLib.idle_add(
	Netmon.Loop:run()
end

return Netmon
