local unpack = table.unpack or unpack
local pcall = pcall
local type = type
local tableinsert = table.insert

local Promise
Promise = class("Promise", {
	isDone = function(self)
		return self.resolved or self.rejected
	end,
	new = function(self, resolver)
		self.resolved = false
		self.rejected = false
		self.thens = {}
		local succ, err = pcall(
			resolver,
			function(...)--resolve
				if self:isDone() then
					return
				end
				self.resolved = true
				self.resolveData = {...}
				for idx, thenable in next, self.thens do
					if thenable.resolved then
						thenable.resolved(...)
					end
				end
			end,
			function(...)--reject
				if self:isDone() then
					return
				end
				self.rejected = true
				self.resolveData = {...}
				for idx, thenable in next, self.thens do
					if thenable.rejected then
						thenable.rejected(...)
					end
				end
			end
		)
		if self:isDone() then
			return
		end
		if not succ then
			self.rejected = true
			self.resolveData = {err}
			for idx, thenable in next, self.thens do
				if thenable.errored then
					thenable.errored({err})
				end
			end
		end
	end,
	next = function(self, resolve, reject)
		return Promise(function(resolveInternal, rejectInternal)
			if self.resolved and resolve then
				resolveInternal(resolve(unpack(self.resolveData)))
			elseif self.rejected then
				if reject then
					rejectInternal(reject(unpack(self.resolveData)))
				else
					rejectInternal(unpack(self.resolveData))
				end
			else
				tableinsert(self.thens, {
					resolved = function()
						resolveInternal(resolve(unpack(self.resolveData)))
					end,
					rejected = function()
						rejectInternal(reject(unpack(self.resolveData)))
					end
				})
			end
		end)
	end,
	error = function(self, callback)
		return Promise(function(resolveInternal, rejectInternal)
			if self.resolved then
				resolveInternal(unpack(self.resolveData))--original value ?
			elseif self.rejected then
				resolveInternal(callback(unpack(self.resolveData)))
			else
				tableinsert(self.thens, {
					resolved = function()
						resolveInternal(unpack(self.resolveData))--original value ?
					end,
					rejected = function()
						resolveInternal(callback(unpack(self.resolveData)))--original value ?
					end
				})
			end
		end)
	end
}, {
	resolve = function(object)
		if type(object) == "table" and object.next then
			return Promise(function(resolve, reject)
				object:next(resolve, reject)
			end)
		end
		return Promise(function(resolve, reject) resolve(object) end)
	end,
	reject = function(object)
		return Promise(function(resolve, reject) reject(object) end)
	end,
	any = function(promises)
		return Promise(function(resolve, reject)
			for index, promise in next, promises do
				promise:next(function(result)
					resolve(result)
				end, function(result)
					reject(result)
				end)
			end
		end)
	end,
	all = function(promises)
		return Promise(function(resolve, reject)
			local needed = #promises
			local has = 0
			local ret = {}
			for index, promise in next, promises do
				promise:next(function(result)
					has = has + 1
					ret[has] = result
					if has == needed then
						resolve(ret)
					end
				end, function(result)
					reject(result)
				end)
			end
		end)		
	end
})

return Promise