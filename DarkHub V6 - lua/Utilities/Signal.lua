--[[ Signal
	Batched yield-safe Signal (GoodSignal / Quenty-style).
	Passes tables by reference (unlike BindableEvent).

	Works with Maid: connections and signals expose Destroy.

	Usage:
		local Signal = loadstring(readfile("Utilities/Signal.lua"))()
		local signal = Signal.new()

		local connection = signal:Connect(function(value)
			print(value)
		end)

		signal:Fire("hello")
		connection:Disconnect()

		-- One-shot / wait
		signal:Once(function() end)
		local a, b = signal:Wait()
]]

local freeRunnerThread = nil

local function acquireRunnerThreadAndCallEventHandler(fn, ...)
	local acquiredRunnerThread = freeRunnerThread
	freeRunnerThread = nil
	fn(...)
	freeRunnerThread = acquiredRunnerThread
end

local function runEventHandlerInFreeThread()
	while true do
		acquireRunnerThreadAndCallEventHandler(coroutine.yield())
	end
end

--[[ Connection ]]

local Connection = {}
Connection.ClassName = "Connection"
Connection.__index = Connection

function Connection.new(signal, fn)
	return setmetatable({
		_connected = true,
		_signal = signal,
		_fn = fn,
		_next = false,
	}, Connection)
end

function Connection:IsConnected()
	return self._connected == true and self._signal ~= nil
end

function Connection:Disconnect()
	if not self._connected then
		return
	end

	self._connected = false

	local signal = self._signal
	if not signal then
		return
	end

	if signal._handlerListHead == self then
		signal._handlerListHead = self._next
	else
		local prev = signal._handlerListHead
		while prev and prev._next ~= self do
			prev = prev._next
		end
		if prev then
			prev._next = self._next
		end
	end

	-- Clear members so Maids holding a connection don't keep the signal alive
	self._signal = nil
	self._fn = nil
end

Connection.Destroy = Connection.Disconnect

setmetatable(Connection, {
	__index = function(_, key)
		error(("Attempt to get Connection::%s (not a valid member)"):format(tostring(key)), 2)
	end,
	__newindex = function(_, key)
		error(("Attempt to set Connection::%s (not a valid member)"):format(tostring(key)), 2)
	end,
})

--[[ Signal ]]

local Signal = {}
Signal.ClassName = "Signal"
Signal.__index = Signal

function Signal.new()
	return setmetatable({
		_handlerListHead = false,
	}, Signal)
end

function Signal.isSignal(value)
	return type(value) == "table" and getmetatable(value) == Signal
end

function Signal:Connect(fn)
	local connection = Connection.new(self, fn)
	if self._handlerListHead then
		connection._next = self._handlerListHead
		self._handlerListHead = connection
	else
		self._handlerListHead = connection
	end
	return connection
end

function Signal:GetConnectionCount()
	local n = 0
	local prev = self._handlerListHead
	while prev do
		n += 1
		prev = prev._next
	end
	return n
end

function Signal:DisconnectAll()
	local head = self._handlerListHead
	while head do
		local nextNode = head._next
		head._connected = false
		head._signal = nil
		head._fn = nil
		head._next = false
		head = nextNode
	end
	self._handlerListHead = false
end

function Signal:Fire(...)
	local item = self._handlerListHead
	while item do
		local nextItem = item._next
		if item._connected then
			if not freeRunnerThread then
				freeRunnerThread = coroutine.create(runEventHandlerInFreeThread)
				coroutine.resume(freeRunnerThread)
			end
			task.spawn(freeRunnerThread, item._fn, ...)
		end
		item = nextItem
	end
end

function Signal:Wait()
	local waitingCoroutine = coroutine.running()
	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		task.spawn(waitingCoroutine, ...)
	end)
	return coroutine.yield()
end

function Signal:Once(fn)
	local connection
	connection = self:Connect(function(...)
		if connection._connected then
			connection:Disconnect()
		end
		fn(...)
	end)
	return connection
end

Signal.Destroy = Signal.DisconnectAll

setmetatable(Signal, {
	__index = function(_, key)
		error(("Attempt to get Signal::%s (not a valid member)"):format(tostring(key)), 2)
	end,
	__newindex = function(_, key)
		error(("Attempt to set Signal::%s (not a valid member)"):format(tostring(key)), 2)
	end,
})

return Signal
