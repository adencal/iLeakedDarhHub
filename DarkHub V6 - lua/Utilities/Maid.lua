--[[ Maid
	Manages cleanup of events, instances, threads, and other resources.
	Based on Quenty / NevermoreEngine Maid:
	https://quenty.github.io/NevermoreEngine/docs/architecture/patterns#maid

	Usage:
		local Maid = loadstring(readfile("Utilities/Maid.lua"))()
		local maid = Maid.new()

		maid:GiveTask(workspace.ChildAdded:Connect(print))
		maid:GiveTask(function()
			print("Cleaning up")
		end)

		-- Named tasks: assigning replaces (and cleans) the previous value
		maid._part = Instance.new("Part")
		maid._part = nil

		maid:DoCleaning()
]]

local Maid = {}
Maid.ClassName = "Maid"

function Maid.new()
	return setmetatable({
		_tasks = {},
	}, Maid)
end

function Maid.isMaid(value)
	return type(value) == "table" and value.ClassName == "Maid"
end

function Maid:__index(index)
	if Maid[index] then
		return Maid[index]
	end
	return self._tasks[index]
end

function Maid:__newindex(index, newTask)
	if Maid[index] ~= nil then
		error(("Cannot use '%s' as a Maid key"):format(tostring(index)), 2)
	end

	local tasks = self._tasks
	local job = tasks[index]

	if job == newTask then
		return
	end

	tasks[index] = newTask

	if job then
		Maid._cleanupTask(job)
	end
end

function Maid._cleanupTask(job)
	local ty = typeof(job)
	if ty == "function" then
		job()
	elseif ty == "table" then
		if type(job.Destroy) == "function" then
			job:Destroy()
		end
	elseif ty == "Instance" then
		job:Destroy()
	elseif ty == "thread" then
		local cancelled = false
		if coroutine.running() ~= job then
			cancelled = pcall(task.cancel, job)
		end
		if not cancelled then
			local toCancel = job
			task.defer(function()
				task.cancel(toCancel)
			end)
		end
	elseif ty == "RBXScriptConnection" then
		job:Disconnect()
	end
end

--[[ Gives a task and returns it (handy for chaining). ]]
function Maid:Add(job)
	if not job then
		error("Task cannot be false or nil", 2)
	end

	self[#self._tasks + 1] = job

	if type(job) == "table" and not job.Destroy then
		warn("[Maid.Add] - Gave table task without .Destroy\n\n" .. debug.traceback())
	end

	return job
end

--[[ Gives a task; returns a numeric task id. ]]
function Maid:GiveTask(job)
	if not job then
		error("Task cannot be false or nil", 2)
	end

	local taskId = #self._tasks + 1
	self[taskId] = job

	if type(job) == "table" and not job.Destroy then
		warn("[Maid.GiveTask] - Gave table task without .Destroy\n\n" .. debug.traceback())
	end

	return taskId
end

--[[
	Gives a pending promise. Cancelled on maid cleanup.
	Expects a promise with IsPending / resolved / Finally (e.g. Nevermore Promise).
]]
function Maid:GivePromise(promise)
	if not promise:IsPending() then
		return promise
	end

	local newPromise = promise.resolved(promise)
	local id = self:GiveTask(newPromise)

	newPromise:Finally(function()
		self[id] = nil
	end)

	return newPromise
end

--[[
	Cleans all tasks. Connections are disconnected first.
	Safe to call recursively; each task runs at most once.
]]
function Maid:DoCleaning()
	local tasks = self._tasks

	for index, job in tasks do
		if typeof(job) == "RBXScriptConnection" then
			tasks[index] = nil
			job:Disconnect()
		end
	end

	local index, job = next(tasks)
	while job ~= nil do
		tasks[index] = nil
		Maid._cleanupTask(job)
		index, job = next(tasks)
	end
end

Maid.Destroy = Maid.DoCleaning

return Maid
