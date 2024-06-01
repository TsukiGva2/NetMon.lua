Itool = {}

function Itool.test_insert(dest, iterator)
	status, elem = pcall(iterator)
	if not status or not elem then
		return false
	end

	table.insert(dest, elem)
	return true
end

function Itool.iter_unpack(iterator)
	status, elem = pcall(iterator)
	if not status then
		return nil
	end

	local elements = {elem}
	repeat
	until not Itool.test_insert(elements, iterator)
	
	return table.unpack(elements)
end

return Itool

