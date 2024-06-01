local directories = require(".directories")

Netlog = {}

--@Netlog
function Netlog:create(path)
	local nl = {}
	setmetatable(nl, {
		__index = self
	})

	self.path = path or "netlog"
	self.handle = nil

	self.flush = false

	return nl
end

--@void
function Netlog:open()
	self.handle, err = io.open(self.path, "w+")
	if err then
		print("Error opening Netlog: '" .. err .. "'")
	end

	self.handle:write("======================\n")
	self.handle:write("NETLOG @ " .. os.date() .. "\n")
	self.handle:write("======================\n")
end

--@void
function Netlog:write(msg)
	assert(self.handle, "Can't write to closed file")

	self.handle:write("@ " .. os.date() .. " --> " .. msg .. "\n")
	self.handle:flush()
end

--@void
function Netlog:close()
	assert(self.handle, "File is already closed")

	self.handle:write("@ END @\n")
	self.handle:close()
	self.handle = nil
end

return Netlog

