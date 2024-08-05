math.randomseed(os.time())
math.random()
math.random()
math.random()

--@uuid
function gen_uuid()
	local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
	local uuid = string.gsub(template, "[xy]", function(c)
		local v = (c == "x") and math.random(0, 0xf) or math.random(8, 0xb)
		return string.format("%x", v)
	end)

	return uuid
end

return gen_uuid
