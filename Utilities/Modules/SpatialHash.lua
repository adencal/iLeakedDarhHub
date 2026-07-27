--[[ SpatialHash
	3D spatial hash grid for fast radius / nearest queries.
	Rebuild with Clear + Insert each tick (cheap); query with Nearest / Best / ForEach.

	Usage:
		local SpatialHash = loadstring(readfile("Utilities/SpatialHash.lua"))()
		local hash = SpatialHash.new(64)

		hash:Clear()
		hash:Insert(part.Position, part)

		local nearest = hash:Nearest(origin, 100)
		local best = hash:Best(origin, 100, function(obj, dist, pos)
			return obj.Score
		end)

		hash:ForEach(origin, 100, function(obj, dist, pos)
			print(obj, dist)
		end)
]]

-- Large primes for cell key hashing (avoids string allocs)
local HASH_X = 73856093
local HASH_Y = 19349663
local HASH_Z = 83492791

local SpatialHash = {}
SpatialHash.ClassName = "SpatialHash"
SpatialHash.__index = SpatialHash

function SpatialHash.new(cellSize)
	return setmetatable({
		cellSize = cellSize or 64,
		cells = {},
		_count = 0,
	}, SpatialHash)
end

function SpatialHash.isSpatialHash(value)
	return type(value) == "table" and value.ClassName == "SpatialHash"
end

local function cellKey(cx, cy, cz)
	return cx * HASH_X + cy * HASH_Y + cz * HASH_Z
end

local function cellCoords(pos, cellSize)
	return math.floor(pos.X / cellSize), math.floor(pos.Y / cellSize), math.floor(pos.Z / cellSize)
end

function SpatialHash:Clear()
	table.clear(self.cells)
	self._count = 0
end

function SpatialHash:GetCount()
	return self._count
end

--[[ Insert an object at a world position. ]]
function SpatialHash:Insert(pos, obj)
	local s = self.cellSize
	local cx, cy, cz = cellCoords(pos, s)
	local key = cellKey(cx, cy, cz)
	local bucket = self.cells[key]
	if not bucket then
		bucket = {}
		self.cells[key] = bucket
	end
	bucket[#bucket + 1] = { pos = pos, obj = obj }
	self._count = self._count + 1
end

--[[
	Iterate cells covering a sphere. Calls fn(bucket) for each non-empty cell.
	Stops early if fn returns true.
]]
function SpatialHash:_forEachBucket(pos, radius, fn)
	local s = self.cellSize
	local cx, cy, cz = cellCoords(pos, s)
	local span = math.ceil(radius / s)
	local cells = self.cells

	for x = cx - span, cx + span do
		for y = cy - span, cy + span do
			for z = cz - span, cz + span do
				local bucket = cells[cellKey(x, y, z)]
				if bucket and fn(bucket) then
					return
				end
			end
		end
	end
end

--[[
	Nearest object within radius.
	Optional pred(obj) -> boolean filter.
	Returns obj or nil.
]]
function SpatialHash:Nearest(pos, radius, pred)
	local r2 = radius * radius
	local best, bestd2 = nil, r2

	self:_forEachBucket(pos, radius, function(bucket)
		for i = 1, #bucket do
			local entry = bucket[i]
			if not pred or pred(entry.obj) then
				local d = entry.pos - pos
				local d2 = d.X * d.X + d.Y * d.Y + d.Z * d.Z
				if d2 <= bestd2 then
					best, bestd2 = entry.obj, d2
				end
			end
		end
	end)

	return best
end

--[[
	Highest-scoring object within radius.
	scorefn(obj, dist, pos) -> number | nil  (nil skips)
	Returns obj or nil.
]]
function SpatialHash:Best(pos, radius, scorefn)
	local best, bestscore = nil, -math.huge

	self:_forEachBucket(pos, radius, function(bucket)
		for i = 1, #bucket do
			local entry = bucket[i]
			local d = (entry.pos - pos).Magnitude
			if d <= radius then
				local score = scorefn(entry.obj, d, entry.pos)
				if score ~= nil and score > bestscore then
					best, bestscore = entry.obj, score
				end
			end
		end
	end)

	return best
end

--[[
	Call fn(obj, dist, pos) for every object within radius.
	Stops early if fn returns true.
]]
function SpatialHash:ForEach(pos, radius, fn)
	self:_forEachBucket(pos, radius, function(bucket)
		for i = 1, #bucket do
			local entry = bucket[i]
			local d = (entry.pos - pos).Magnitude
			if d <= radius then
				if fn(entry.obj, d, entry.pos) then
					return true
				end
			end
		end
	end)
end

--[[
	All objects within radius as { obj, dist, pos } entries.
]]
function SpatialHash:Query(pos, radius, pred)
	local results = {}
	self:_forEachBucket(pos, radius, function(bucket)
		for i = 1, #bucket do
			local entry = bucket[i]
			if not pred or pred(entry.obj) then
				local d = (entry.pos - pos).Magnitude
				if d <= radius then
					results[#results + 1] = {
						obj = entry.obj,
						dist = d,
						pos = entry.pos,
					}
				end
			end
		end
	end)
	return results
end

function SpatialHash:Destroy()
	self:Clear()
end

return SpatialHash
