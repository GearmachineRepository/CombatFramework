--!strict

local Combat = {}

Combat.ActionExecutor = require(script.ActionExecutor)
Combat.ExecutionContext = require(script.ExecutionContext)
Combat.ActionRegistry = require(script.ActionRegistry)
Combat.ActionValidator = require(script.ActionValidator)
Combat.Handlers = require(script.Handlers)

return Combat