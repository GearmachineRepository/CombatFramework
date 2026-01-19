--!strict

local Handlers = {}

local LoadedHandlers: { [string]: any } = {}

local HANDLER_MAP: { [string]: string } = {
	Wait = "WaitHandler",
	WaitForMarker = "WaitForMarkerHandler",
	Animation = "AnimationHandler",
	Sound = "SoundHandler",
	Velocity = "VelocityHandler",
	Hitbox = "HitboxHandler",
	HitCancel = "HitCancelHandler",
	Chase = "ChaseHandler",
	Grab = "GrabHandler",
	Action = "ActionHandler",
	AddHealth = "AddHealthHandler",
	AddEvasive = "AddEvasiveHandler",
}

function Handlers.Get(BlockType: string): any?
	if LoadedHandlers[BlockType] then
		return LoadedHandlers[BlockType]
	end

	local HandlerName = HANDLER_MAP[BlockType]
	if not HandlerName then
		return nil
	end

	local HandlerModule = script:FindFirstChild(HandlerName)
	if not HandlerModule or not HandlerModule:IsA("ModuleScript") then
		return nil
	end

	local Success, Handler = pcall(require, HandlerModule)
	if not Success then
		warn(string.format("[Handlers] Failed to load %s: %s", HandlerName, tostring(Handler)))
		return nil
	end

	LoadedHandlers[BlockType] = Handler
	return Handler
end

function Handlers.Has(BlockType: string): boolean
	return HANDLER_MAP[BlockType] ~= nil
end

function Handlers.GetAll(): { [string]: any }
	local All: { [string]: any } = {}

	for BlockType in HANDLER_MAP do
		local Handler = Handlers.Get(BlockType)
		if Handler then
			All[BlockType] = Handler
		end
	end

	return All
end

function Handlers.Preload()
	for BlockType in HANDLER_MAP do
		Handlers.Get(BlockType)
	end
end

return Handlers