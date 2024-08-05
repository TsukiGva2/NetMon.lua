--[[
			netmon2.lua

  Copyright (C) 2024 Rodrigo Monteiro Junior - All Rights Reserved
  You may use, distribute and modify this code under the
  terms of the MIT license.
 
  You should have received a copy of the MIT license with
  this file. If not, please write to: tsukigva@gmail.com

--]]

local NetworkManager = lgi.require("NM") -- include NetworkManager from lgi
local directories = require("directories")
local gen_uuid = require("uuid")
local Nutils = require("networkutils")
local Netlog = require("netlog")
local Debug = require("debug")
local Itool = require("itool")

local lgi = require("lgi")
local GLib = lgi.require("GLib")
-- needed for AF_INET (why doesn't NetworkManager define this?)
-- local socket = require("socket")

--@Shared variables
Netmon = {
	nmcli = NetworkManager.Client.new(),
	logger = {},
	--monitored = {}, -- devices monitored by Netmon
	Loop = GLib.MainLoop(nil, false),
}

function Netmon:attach_debugger(dbg)
	self.debugger = dbg
end

function Netmon:print_debug(msg)
	self.debugger.writeln(msg)
end

function Netmon:print_box(msg, title, color)
	self:print_debug(string.format("\n\27[3%d;1m=====================%s==========================", color, title))
	self:print_debug(msg)
	self:print_debug("============================================\27[0m")
end

--@NetworkManagerConnection <name> <type> [network_name] [password]
function Netmon:create_conn(name, devtype, network_name, password)
	local correct_type = "802-11-wireless"
	if devtype == "wired" or devtype == "ethernet" then
		correct_type = "802-3-ethernet"
	end

	local conn = Nutils.basic_connection(name, self.device_name, self.uuid, correct_type)

	if devtype == "wired" or devtype == "ethernet" then
		return Nutils.configure_ethernet(conn, self.ip)
	end

	if devtype == "hotspot" then
		return Nutils.configure_ap(conn)
	end

	return Nutils.configure_wifi(conn, network_name, self.device)
end

--@device list
function Netmon:detect_devices()
	devices = self.nmcli:get_devices()

	return devices
end

--@void @callback
function Netmon:generic_conn_callback(_, result, data)
	local conn, err, code = self.nmcli:add_and_activate_connection_finish(result)

	-- self.connecting = false

	if conn then
		local dev = conn:get_connection():get_interface_name()

		self:print_debug("\n\27[32;1m==================================")
		self.debugger.pp({ "CALLBACK FROM " .. dev, string.format("%s, %s", conn:get_id(), conn:get_uuid()) })
		self.debugger.pp("CALLBACK FROM " .. dev .. "| " .. self.uuid)
		self.debugger.pp({ "CONN CALLBACK", string.format("%s: (%s)", conn:get_path(), conn:get_state()) })
		self:print_debug("==================================\27[0m\n")
	else
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

	--netmon.connecting = false
	netmon.device_name = device

	netmon.devtype = devtype or "wifi" -- defaults to wifi

	-- netmon.config_path = config_file or directories.MyTempo .. "main/config_shell.txt"
	netmon.config_path = config_file or directories.Home .. "MyTempo/conf/" .. devtype .. ".conf"
	if config_file == "no_config" then
		netmon.config_path = nil
	end

	for i, dev in ipairs(self:detect_devices()) do
		if dev:get_iface() == netmon.device_name then
			netmon.device = dev
		end
	end

	netmon.uuid = gen_uuid()

	return netmon
end

--@Name, Password
function Netmon:read_config()
	assert(self.config_path, "Can't read from nil file")

	f, err = io.open(self.config_path)
	if err then
		self:print_debug(string.format("READ CONFIG| Couldn't open config file: %s", err))
		return nil, nil
	end

	local config = f:read("*a")

	-- field:"value"
	local config_iterator = config:gmatch('[a-zA-Z0-9]:"([^\n]*)"')

	return Itool.iter_unpack(config_iterator)
end

function Netmon:activateconn()
	local conn = self.nmcli:get_connection_by_uuid(self.uuid)

	if not conn then
		self:connect_once()
		return
	end

	-- self.connecting = true

	self.nmcli:activate_connection_async(conn, self.device, nil, nil, self.generic_conn_callback, nil)
end

--@bool
function Netmon:connect_once()
	assert(self.device, "No device specified!")

	if not self.network_name then
		self.network_name, self.password, self.ip = self:read_config()

		if self.network_name == nil then
			self:print_debug("\27[31;1mcouldn't read configuration\27[0m")
			return
		end
	end

	-- self.connecting = true

	self.conn = self:create_conn(self.network_name, self.devtype, self.network_name, self.password)

	self:print_debug(string.format("\27[36;1m"))
	self.debugger.pp(self.conn)
	self.debugger.pp(self.password)
	self.debugger.pp(self.network_name)
	self:print_debug(string.format("%s\27[0m", self.ip))

	self.nmcli:add_and_activate_connection_async(self.conn, self.device, nil, nil, self.generic_conn_callback, nil)

	-- self.conn_wait_loop:run()
end

function Netmon:did_network_name_change()
	if not self.config_path then
		return false
	end

	local network_name, pass, ip = self:read_config()

	if network_name ~= self.network_name or pass ~= self.password then
		self.uuid = gen_uuid()

		self.network_name = network_name
		self.password = pass
		self.ip = ip

		return true
	end

	return false
end

CHECK_UP_CONNECT_ONCE = 1
CHECK_UP_REACTIVATE = 2
CHECK_UP_OK = 3
function Netmon:check_up()
	local dev_state = self.device:get_state()

	local msg = string.format("- DEVICE STATE: (%s)", dev_state)
	msg ..= string.format("- DEVICE CONFIGURATION: (Network name: %s, Password: %s)", self.network_name, self.password)
	msg ..= string.format("network: %s", self.network_name or "NIL")

	self:print_box(msg, "CHECKING_UP " .. self.device_name, 3)

	if self:did_network_name_change() then
		local active = self.device:get_active_connection()

		-- delete active connection if configuration file changes
		if active then
			active:get_connection():delete()
		end

		self:print_debug(string.format("network: %s", self.network_name or "NIL"))
		self.conn = nil

		return CHECK_UP_CONNECT_ONCE
	end

	local conn = self.device:get_active_connection()
	if not conn then -- XXX: what?
		if not self.conn then
			return CHECK_UP_CONNECT_ONCE
		end

		return CHECK_UP_REACTIVATE
	end

	self:print_debug(string.format("- ACTIVE CONNECTION: (%s)", conn))

	local conn_uuid = conn:get_uuid()
	self:print_debug(string.format("\t| .. FOUND UUID: (%s) - (SELF UUID: (%s))", conn_uuid, self.uuid))

	if conn_uuid ~= self.uuid then
		self:LOG(
			string.format("checking_up %s", self.device_name),
			"Device connected to another network, reconnecting..."
		)

		self:print_debug("- UNKNOWN NETWORK ... DELETING")
		conn:get_connection():delete()

		return CHECK_UP_CONNECT_ONCE
	end

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

	GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 8, self.mon)
end

--@void ((__INF_LOOP__))
function Netmon.run()
	Netmon.Loop:run()
end

Netmon:attach_debugger(Debug)
Netmon:delete_all()
Netmon.run()
