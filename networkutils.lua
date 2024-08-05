--[[
			networkutils.lua

  Copyright (C) 2024 Rodrigo Monteiro Junior - All Rights Reserved
  You may use, distribute and modify this code under the
  terms of the MIT license.
 
  You should have received a copy of the MIT license with
  this file. If not, please write to: tsukigva@gmail.com

--]]

Debug = require("debug")

--@String
function get_utf8_ssid(ap)
	local ssid = ap:get_ssid()
	if not ssid then
		return ""
	end
	return NetworkManager.utils_ssid_to_utf8(ssid:get_data())
end

--@{ Mac -> table.pack( SSID, BAND ) }
function wifi_scan(device)
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
	for _, ap in ipairs(device:get_access_points()) do
		local ssid = get_utf8_ssid(ap)
		local mac = ap:get_bssid()

		local bandwidth = 0000

		--@libnm >= 1.46
		if NetworkManager.AccessPoint.get_bandwidth ~= nil then
			bandwidth = ap:get_bandwidth()
		end

		table.insert(networks, table.pack(mac, ssid, bandwidth))
	end

	-- bw = bandwidth
	table.sort(networks, function(net_a, net_b)
		local _, _, bw1 = table.unpack(net_a)
		local _, _, bw2 = table.unpack(net_b)
		return bw1 > bw2 -- reversed
	end)

	return networks
end

--[[
	This function takes a dummy connection object and
	adds appropriate ethernet settings to it

	this function will probably remain unused for now
--]]
function configure_ethernet(conn, ip)
	conn:add_setting(NetworkManager.SettingWired.new())

	local setting_ipv4 = NetworkManager.SettingIP4Config.new()

	--fuck ipv6
	--local setting_ipv6 = NetworkManager.SettingIP6Config.new()
	--setting_ipv6[NetworkManager.SETTING_IP_CONFIG_METHOD] = NetworkManager.SETTING_IP6_CONFIG_METHOD_DISABLED

	Debug.writeln("\27[36;1m================SETTING ETHERNET IP================")
	Debug.writeln(string.format("IP ADDR -> %s", ip or "AUTO"))
	Debug.writeln("===================================================\27[0m")

	if ip then
		setting_ipv4[NetworkManager.SETTING_IP_CONFIG_METHOD] = NetworkManager.SETTING_IP4_CONFIG_METHOD_MANUAL

		-- AF_INET = 2
		local ipv4 = NetworkManager.IPAddress.new(2, self.ip, 8)
		setting_ipv4:add_address(ipv4)
	end

	conn:add_setting(setting_ipv4)
	--conn:add_setting(setting_ipv6)

	return conn
end

function setup_wifi_scan(network_name, device)
	local networks = wifi_scan(device)

	local match = nil

	for _, access_point in ipairs(networks) do
		mac, ssid, band = table.unpack(access_point)

		local ssid_rtrim = ssid:match("(.-)%s*$")

		Debug.writeln(string.format("found: %s %s %d", mac, ssid_rtrim, band))

		-- daily reminder that some ssids have a trailing space.
		-- have a good day :)
		if ssid_rtrim == network_name then
			-- correct an accidental mismatch
			local c_ssid = GLib.Bytes(ssid)

			match = table.pack(c_ssid, mac)

			Debug.writeln(string.format("Found match for %s, connecting to %s", network_name, mac))
			break
		end
	end

	return match
end

function make_wifi_setting(do_scan, network_name, device)
	local setting_wireless = NetworkManager.SettingWireless.new()
	local setting_wireless_security = NetworkManager.SettingWirelessSecurity.new()

	setting_wireless[NetworkManager.SETTING_WIRELESS_SSID] = GLib.Bytes(network_name)

	-- setting_wireless[NetworkManager.SETTING_WIRELESS_MODE] = "auto"

	setting_wireless_security[NetworkManager.SETTING_WIRELESS_SECURITY_KEY_MGMT] = "wpa-psk"

	if do_scan then
		setting_wireless_security[NetworkManager.SETTING_WIRELESS_SECURITY_AUTH_ALG] = "open"

		local net = setup_wifi_scan(network_name, device)

		if net == nil then
			Debug.writeln("Couldn't find network")

			return setting_wireless, setting_wireless_security
		end

		ssid, mac = table.unpack(net)

		setting_wireless[NetworkManager.SETTING_WIRELESS_SSID] = ssid
		setting_wireless[NetworkManager.SETTING_WIRELESS_BSSID] = mac
	end

	setting_wireless_security[NetworkManager.SETTING_WIRELESS_SECURITY_PSK] = password

	return setting_wireless, setting_wireless_security
end

function configure_wifi(conn, network_name, device)
	general, security = make_wifi_setting(conn, true, network_name, device)

	conn:add_setting(security)
	conn:add_setting(general)

	return conn
end

function configure_ap(conn)
	-- setting_wireless[NetworkManager.SETTING_WIRELESS_MODE_ADHOC] = GLib.Bytes("adhoc")

	-- don't do wifi scan
	general, security = make_wifi_setting(conn, false)

	local setting_ipv4 = NetworkManager.SettingIP4Config.new()
	setting_ipv4[NetworkManager.SETTING_IP_CONFIG_METHOD] = NetworkManager.SETTING_IP4_CONFIG_METHOD_SHARED

	security:add_proto("rsn")
	security:add_group("ccmp")
	security:add_pairwise("ccmp")

	-- setting_wireless_security[NetworkManager.SETTING_WIRELESS_SECURITY_GROUP] = "CCMP"
	-- setting_wireless_security[NetworkManager.SETTING_WIRELESS_SECURITY_PAIRWISE] = "CCMP"
	-- setting_ipv4:add_dns_search("127.0.0.1")

	general[NetworkManager.SETTING_WIRELESS_MODE] = "ap"

	conn:add_setting(setting_ipv4)

	conn:add_setting(setting_wireless_security)
	conn:add_setting(setting_wireless)

	return conn
end

function basic_connection(name, devname, uuid, type)
	local conn = NetworkManager.SimpleConnection.new()
	local setting_conn = NetworkManager.SettingConnection.new()

	setting_conn[NetworkManager.SETTING_CONNECTION_INTERFACE_NAME] = devname
	setting_conn[NetworkManager.SETTING_CONNECTION_UUID] = uuid

	setting_conn[NetworkManager.SETTING_CONNECTION_TYPE] = type
	setting_conn[NetworkManager.SETTING_CONNECTION_ID] = name

	conn:add_setting(setting_conn)

	return conn
end

Nutils = {
	basic_connection = basic_connection,

	configure_ethernet = configure_ethernet,
	configure_wifi = configure_wifi,
	configure_ap = configure_ap,
}

return Nutils
