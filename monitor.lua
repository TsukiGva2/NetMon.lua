lfs = require("lfs")
home = os.getenv("HOME")

mytempo_main = home .. "MyTempo/"
mytempo_src  = mytempo_main .. "src/mytempo-api-linux/"

log = mytempo_src .. "log"

log_file = io.open(log, "w+")
log_file:write("LOG @ " .. os.date())

function write_log(str)
	log_file:write("@ " .. os.date() .. " --> " .. str)
end

function make_database()
	write_log("REMAKING DATABASE...")
	
	lfs.mkdir(mytempo_src .. "database")
	lfs.chdir(mytempo_src)

	local handle = io.popen("python3 intern.py migrate 2>&1")
	write_log(handle:read("*a"))
	handle:close()
end

