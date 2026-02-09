--!strict

--[=[
	@class ObjectPool

	A generic object pool for reusing instances (or other destroyable objects) to reduce allocations
	and improve runtime performance.

	This pool tracks "active" (checked out) objects to protect against
	double-return, returning foreign objects (not created by this pool),
	and delayed returns after Clear().

	Behavioral notes:
	- MaxSize caps the number of *available (idle)* objects retained, not total objects created.
	- Get() errors if the pool has been destroyed.
	- Clear() destroys both available and active objects, and resets tracking.
	- Return() behavior for objects not currently active (foreign, double-return, delayed return after Clear()):
		- If DestroyUntrackedReturns is true (default), the object is destroyed deterministically.
		- If DestroyUntrackedReturns is false, the return is a no-op.
	- Returning an object after Destroy() destroys that object deterministically.
	- Reset errors are handled according to ResetErrorMode. On reset failure, the object is destroyed and not retained.

	```lua
	local ObjectPool = require(path.to.ObjectPool)

	local Pool = ObjectPool.new({
		Create = function()
			local Part = Instance.new("Part")
			Part.Anchored = true
			Part.CanCollide = false
			return Part
		end,
		Reset = function(Object)
			Object.Parent = nil
			Object.CFrame = CFrame.new()
		end,
		InitialSize = 50,
		MaxSize = 200,
		DestroyUntrackedReturns = true,
		ResetErrorMode = "Warn",
	})

	local Part = Pool:Get()
	Part.Parent = workspace

	Pool:Return(Part)
	```
]=]

export type ResetErrorMode = "Warn" | "Error" | "Silent"

export type PoolConfig<T> = {
	Create: () -> T,
	Reset: (Object: T) -> (),

	InitialSize: number?,
	MaxSize: number?,

	DestroyUntrackedReturns: boolean?,
	ResetErrorMode: ResetErrorMode?,
}

export type ObjectPool<T> = {
	Get: (Self: ObjectPool<T>) -> T,
	Return: (Self: ObjectPool<T>, Object: T) -> (),
	Warm: (Self: ObjectPool<T>, Count: number) -> (),
	GetAvailableCount: (Self: ObjectPool<T>) -> number,
	GetActiveCount: (Self: ObjectPool<T>) -> number,
	Clear: (Self: ObjectPool<T>) -> (),
	Destroy: (Self: ObjectPool<T>) -> (),
}

local DEFAULT_INITIAL_SIZE = 10
local DEFAULT_MAX_SIZE = 100
local DEFAULT_DESTROY_UNTRACKED_RETURNS = true
local DEFAULT_RESET_ERROR_MODE: ResetErrorMode = "Warn"

--[=[
	Destroys or disconnects common Roblox resources.

	Supported cleanup targets:
	- Instance:Destroy()
	- RBXScriptConnection:Disconnect()
	- Table with a Destroy function field: Destroy(CleanupValue)

	If CleanupValue is none of the above, this is a no-op.

	@param CleanupValue unknown -- The resource to clean up
]=]
local function Cleanup(CleanupValue: unknown)
	if CleanupValue == nil then
		return
	end

	local CleanupType = typeof(CleanupValue)

	if CleanupType == "Instance" then
		(CleanupValue :: Instance):Destroy()
		return
	end

	if CleanupType == "RBXScriptConnection" then
		(CleanupValue :: RBXScriptConnection):Disconnect()
		return
	end

	if CleanupType == "table" then
		local CleanupTable = CleanupValue :: { [any]: any }
		local DestroyFunction = CleanupTable.Destroy
		if typeof(DestroyFunction) == "function" then
			(DestroyFunction :: (any) -> ())(CleanupValue)
		end
	end
end

type PoolInternal<T> = {
	Available: { T },
	Active: { [T]: boolean },

	CreateFunction: () -> T,
	ResetFunction: (Object: T) -> (),

	MaxSize: number,
	DestroyUntrackedReturns: boolean,
	ResetErrorMode: ResetErrorMode,

	IsDestroyed: boolean,

	Get: (Self: PoolInternal<T>) -> T,
	Return: (Self: PoolInternal<T>, Object: T) -> (),
	Warm: (Self: PoolInternal<T>, Count: number) -> (),
	GetAvailableCount: (Self: PoolInternal<T>) -> number,
	GetActiveCount: (Self: PoolInternal<T>) -> number,
	Clear: (Self: PoolInternal<T>) -> (),
	Destroy: (Self: PoolInternal<T>) -> (),
}

local PoolMetatable = {}
PoolMetatable.__index = PoolMetatable

local function DestroyObject<T>(Object: T)
	Cleanup(Object :: any)
end

local function HandleResetFailure<T>(Self: PoolInternal<T>, Object: T, ResetErrorMessage: string)
	DestroyObject(Object)

	if Self.ResetErrorMode == "Silent" then
		return
	end

	if Self.ResetErrorMode == "Warn" then
		warn(ResetErrorMessage)
		return
	end

	error(ResetErrorMessage, 3)
end

local function TryReset<T>(Self: PoolInternal<T>, Object: T): boolean
	local Ok, ResetError = pcall(function()
		Self.ResetFunction(Object)
		return true
	end)

	if Ok then
		return true
	end

	local ResetErrorMessage = ("ObjectPool Reset failed; object destroyed. Error: %s"):format(tostring(ResetError))
	HandleResetFailure(Self, Object, ResetErrorMessage)
	return false
end

--[=[
	Checks out an object from the pool.

	If an idle object is available, it is reused. Otherwise, a new object is created.
	Errors if the pool has been destroyed.

	@return T -- The checked-out object
]=]
function PoolMetatable.Get<T>(Self: PoolInternal<T>): T
	if Self.IsDestroyed then
		error("ObjectPool is destroyed", 2)
	end

	local Object: T
	if #Self.Available > 0 then
		Object = table.remove(Self.Available, #Self.Available) :: T
	else
		Object = Self.CreateFunction()
	end

	Self.Active[Object] = true
	return Object
end

--[=[
	Returns an object to the pool.

	If the pool has been destroyed, the object is destroyed deterministically.
	If the object is not currently tracked as active (foreign, double-return, delayed return after Clear()),
	it is either destroyed or ignored based on DestroyUntrackedReturns.

	On a successful return, ResetFunction is invoked. If ResetFunction fails, the object
	is destroyed and not retained. If the available pool is at capacity, the object is destroyed.

	@param Object T -- The object to return
]=]
function PoolMetatable.Return<T>(Self: PoolInternal<T>, Object: T)
	if Self.IsDestroyed then
		DestroyObject(Object)
		return
	end

	if Self.Active[Object] ~= true then
		if Self.DestroyUntrackedReturns then
			DestroyObject(Object)
		end
		return
	end

	Self.Active[Object] = nil

	local ResetSucceeded = TryReset(Self, Object)
	if not ResetSucceeded then
		return
	end

	if #Self.Available < Self.MaxSize then
		table.insert(Self.Available, Object)
	else
		DestroyObject(Object)
	end
end

--[=[
	Pre-allocates objects into the available pool.

	Count is capped to MaxSize. Objects are created and reset before becoming available.
	If Reset fails for an object, it is destroyed and creation continues.
	No-op if the pool has been destroyed.

	@param Count number -- The target number of idle objects
]=]
function PoolMetatable.Warm<T>(Self: PoolInternal<T>, Count: number)
	if Self.IsDestroyed then
		return
	end

	local Target = math.min(Count, Self.MaxSize)
	local ToCreate = Target - #Self.Available
	if ToCreate <= 0 then
		return
	end

	local CreatedCount = 0
	while CreatedCount < ToCreate do
		local Object = Self.CreateFunction()

		local ResetSucceeded = TryReset(Self, Object)
		if ResetSucceeded then
			table.insert(Self.Available, Object)
			CreatedCount += 1
		end
	end
end

--[=[
	Returns the number of idle objects currently available in the pool.

	@return number -- The available count
]=]
function PoolMetatable.GetAvailableCount<T>(Self: PoolInternal<T>): number
	return #Self.Available
end

--[=[
	Returns the number of objects currently checked out (active).

	@return number -- The active count
]=]
function PoolMetatable.GetActiveCount<T>(Self: PoolInternal<T>): number
	local Count = 0
	for _ in pairs(Self.Active) do
		Count += 1
	end
	return Count
end

--[=[
	Destroys all objects in the pool (both active and available) and resets tracking.

	After Clear(), any later Return() calls for previously active objects are treated as untracked.
	No-op if the pool has been destroyed.
]=]
function PoolMetatable.Clear<T>(Self: PoolInternal<T>)
	if Self.IsDestroyed then
		return
	end

	for Object in pairs(Self.Active) do
		DestroyObject(Object)
	end
	table.clear(Self.Active)

	for Index = #Self.Available, 1, -1 do
		local Object = Self.Available[Index]
		DestroyObject(Object)
		Self.Available[Index] = nil
	end
end

--[=[
	Destroys the pool permanently.

	Clears all objects (active and available) and marks the pool as destroyed.
	After destruction, Get() errors and Return() destroys the provided object.
]=]
function PoolMetatable.Destroy<T>(Self: PoolInternal<T>)
	if Self.IsDestroyed then
		return
	end

	Self:Clear()
	Self.IsDestroyed = true
end

local function CreatePool<T>(Config: PoolConfig<T>): ObjectPool<T>
	local InitialSize = Config.InitialSize or DEFAULT_INITIAL_SIZE
	local MaxSize = Config.MaxSize or DEFAULT_MAX_SIZE

	if MaxSize <= 0 then
		error("MaxSize must be > 0", 2)
	end

	if InitialSize < 0 then
		error("InitialSize must be >= 0", 2)
	end

	local DestroyUntrackedReturns = if Config.DestroyUntrackedReturns ~= nil
		then Config.DestroyUntrackedReturns
		else DEFAULT_DESTROY_UNTRACKED_RETURNS

	local ResetErrorMode: ResetErrorMode
	if Config.ResetErrorMode ~= nil then
		ResetErrorMode = Config.ResetErrorMode
	else
		ResetErrorMode = DEFAULT_RESET_ERROR_MODE
	end

	local PoolInternalObject: PoolInternal<T> = {
		Available = {},
		Active = {},

		CreateFunction = Config.Create,
		ResetFunction = Config.Reset,

		MaxSize = MaxSize,
		DestroyUntrackedReturns = DestroyUntrackedReturns,
		ResetErrorMode = ResetErrorMode,

		IsDestroyed = false,

		Get = PoolMetatable.Get,
		Return = PoolMetatable.Return,
		Warm = PoolMetatable.Warm,
		GetAvailableCount = PoolMetatable.GetAvailableCount,
		GetActiveCount = PoolMetatable.GetActiveCount,
		Clear = PoolMetatable.Clear,
		Destroy = PoolMetatable.Destroy,
	}

	local PoolObject = (setmetatable(PoolInternalObject, PoolMetatable) :: any) :: ObjectPool<T>
	PoolObject:Warm(math.min(InitialSize, MaxSize))

	return PoolObject
end

--[=[
	Creates a new ObjectPool with the given configuration.

	@param Config PoolConfig<T> -- Pool configuration with Create and Reset functions
	@return ObjectPool<T> -- The new pool instance
]=]
local function New<T>(Config: PoolConfig<T>): ObjectPool<T>
	return CreatePool(Config)
end

return {
	new = New,
}