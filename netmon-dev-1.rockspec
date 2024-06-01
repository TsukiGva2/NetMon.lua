package = "netmon"
version = "dev-1"
source = {
   url = "git+https://github.com/TsukiGva2/NetMon.lua"
   license = "MIT"
}
description = {
   homepage = "https://github.com/TsukiGva2/NetMon.lua",
}
build = {
   type = "builtin",
   modules = {
      checknet = "checknet.lua",
      directories = "directories.lua",
      ["include.debugger.debugger"] = "include/debugger/debugger.lua",
      ["include.debugger.embed.debugger_lua.c"] = "include/debugger/embed/debugger_lua.c.lua",
      ["include.debugger.test.test"] = "include/debugger/test/test.lua",
      ["include.debugger.test.test_util"] = "include/debugger/test/test_util.lua",
      ["include.debugger.tutorial"] = "include/debugger/tutorial.lua",
      itool = "itool.lua",
      monitor = "monitor.lua",
      netlog = "netlog.lua",
      netmon = "netmon.lua"
   },
   install = {
	bin = {
		["netmon"] = "checknet.lua"
	}
   }
}
