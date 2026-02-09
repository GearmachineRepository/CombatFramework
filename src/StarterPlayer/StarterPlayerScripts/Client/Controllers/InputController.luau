--!strict

--[=[
	@class InputController

	Keyboard, mouse, gamepad, and touch input management.

	Provides an action-binding system where named actions map to input keys.
	Actions can be bound, unbound, rebound, and toggled. Fires `ActionTriggered`
	whenever a bound action activates, and wraps the Input package for typed
	device access.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = require(Shared.Packages)

local Trove = Packages.Trove
local Signal = Packages.Signal
local Input = Packages.Input

type Connection = {
	Disconnect: (self: Connection) -> (),
	Connected: boolean,
}

type InputSignal<T...> = {
	Connect: (self: InputSignal<T...>, Callback: (T...) -> ()) -> Connection,
}

type Keyboard = {
	KeyDown: InputSignal<Enum.KeyCode, boolean>,
	KeyUp: InputSignal<Enum.KeyCode, boolean>,
	IsKeyDown: (self: Keyboard, KeyCode: Enum.KeyCode) -> boolean,
	Destroy: (self: Keyboard) -> (),
}

type Mouse = {
	LeftDown: InputSignal<boolean>,
	LeftUp: InputSignal<boolean>,
	RightDown: InputSignal<boolean>,
	RightUp: InputSignal<boolean>,
	MiddleDown: InputSignal<boolean>,
	MiddleUp: InputSignal<boolean>,
	Moved: InputSignal<Vector2, boolean>,
	Scrolled: InputSignal<number, boolean>,
	IsLeftDown: (self: Mouse) -> boolean,
	IsRightDown: (self: Mouse) -> boolean,
	GetPosition: (self: Mouse) -> Vector2,
	Destroy: (self: Mouse) -> (),
}

type Gamepad = {
	ButtonDown: InputSignal<Enum.KeyCode, boolean>,
	ButtonUp: InputSignal<Enum.KeyCode, boolean>,
	IsButtonDown: (self: Gamepad, Button: Enum.KeyCode) -> boolean,
	IsConnected: (self: Gamepad) -> boolean,
	Destroy: (self: Gamepad) -> (),
}

type Touch = {
	TouchTap: InputSignal<{ Vector2 }, boolean>,
	TouchTapInWorld: InputSignal<Vector2, boolean>,
	TouchMoved: InputSignal<InputObject, boolean>,
	TouchLongPress: InputSignal<{ Vector2 }, Enum.UserInputState, boolean>,
	TouchStarted: InputSignal<InputObject, boolean>,
	TouchEnded: InputSignal<InputObject, boolean>,
	IsTouchEnabled: (self: Touch) -> boolean,
	Destroy: (self: Touch) -> (),
}

type ActionData = {
	Callback: (Enum.UserInputState) -> (),
	Enabled: boolean,
	Inputs: { Enum.KeyCode | Enum.UserInputType },
}

local InputController = {}

local ControllerTrove: typeof(Trove.new()) = nil :: any
local KeyboardInput: Keyboard? = nil
local MouseInput: Mouse? = nil
local GamepadInput: Gamepad? = nil
local TouchInput: Touch? = nil

local Actions: { [string]: ActionData } = {}
local InputToActions: { [Enum.KeyCode | Enum.UserInputType]: { string } } = {}

InputController.ActionTriggered = Signal.new()

local function RegisterInputMapping(ActionName: string, InputType: Enum.KeyCode | Enum.UserInputType)
	if not InputToActions[InputType] then
		InputToActions[InputType] = {}
	end
	table.insert(InputToActions[InputType], ActionName)
end

local function UnregisterInputMapping(ActionName: string)
	for InputType, ActionNames in InputToActions do
		local Index = table.find(ActionNames, ActionName)
		if Index then
			table.remove(ActionNames, Index)
			if #ActionNames == 0 then
				InputToActions[InputType] = nil
			end
		end
	end
end

local function FireActionsForInput(InputType: Enum.KeyCode | Enum.UserInputType, State: Enum.UserInputState, Processed: boolean)
	if Processed then
		return
	end

	local ActionNames = InputToActions[InputType]
	if not ActionNames then
		return
	end

	for _, ActionName in ActionNames do
		local Action = Actions[ActionName]
		if Action and Action.Enabled then
			Action.Callback(State)
			InputController.ActionTriggered:Fire(ActionName, State)
		end
	end
end

--[=[
	Creates the controller Trove for connection cleanup.
]=]
function InputController.Init()
	ControllerTrove = Trove.new()
end

--[=[
	Initializes input devices and connects their signals to the action dispatch system.
]=]
function InputController.Start()
	KeyboardInput = ControllerTrove:Add(Input.Keyboard.new() :: any) :: Keyboard
	MouseInput = ControllerTrove:Add(Input.Mouse.new() :: any) :: Mouse
	GamepadInput = ControllerTrove:Add(Input.Gamepad.new() :: any) :: Gamepad
	TouchInput = ControllerTrove:Add(Input.Touch.new() :: any) :: Touch

	if not KeyboardInput or not MouseInput or not GamepadInput then
		return
	end

	ControllerTrove:Connect(KeyboardInput.KeyDown :: any, function(KeyCode: Enum.KeyCode, Processed: boolean)
		FireActionsForInput(KeyCode, Enum.UserInputState.Begin, Processed)
	end)

	ControllerTrove:Connect(KeyboardInput.KeyUp :: any, function(KeyCode: Enum.KeyCode, Processed: boolean)
		FireActionsForInput(KeyCode, Enum.UserInputState.End, Processed)
	end)

	ControllerTrove:Connect(MouseInput.LeftDown :: any, function(Processed: boolean)
		FireActionsForInput(Enum.UserInputType.MouseButton1, Enum.UserInputState.Begin, Processed)
	end)

	ControllerTrove:Connect(MouseInput.LeftUp :: any, function(Processed: boolean)
		FireActionsForInput(Enum.UserInputType.MouseButton1, Enum.UserInputState.End, Processed)
	end)

	ControllerTrove:Connect(MouseInput.RightDown :: any, function(Processed: boolean)
		FireActionsForInput(Enum.UserInputType.MouseButton2, Enum.UserInputState.Begin, Processed)
	end)

	ControllerTrove:Connect(MouseInput.RightUp :: any, function(Processed: boolean)
		FireActionsForInput(Enum.UserInputType.MouseButton2, Enum.UserInputState.End, Processed)
	end)

	ControllerTrove:Connect(GamepadInput.ButtonDown :: any, function(Button: Enum.KeyCode, Processed: boolean)
		FireActionsForInput(Button, Enum.UserInputState.Begin, Processed)
	end)

	ControllerTrove:Connect(GamepadInput.ButtonUp :: any, function(Button: Enum.KeyCode, Processed: boolean)
		FireActionsForInput(Button, Enum.UserInputState.End, Processed)
	end)
end

--[=[
	Destroys the controller Trove, releases input devices, and clears all action bindings.
]=]
function InputController.Stop()
	ControllerTrove:Destroy()
	KeyboardInput = nil
	MouseInput = nil
	GamepadInput = nil
	TouchInput = nil
	table.clear(Actions)
	table.clear(InputToActions)
end

--[=[
	Binds a named action to one or more input keys. If an action with the
	same name already exists, it is unbound first.

	@param ActionName string -- Unique name for the action
	@param Callback (Enum.UserInputState) -> () -- Handler called on input state changes
	@param ... Enum.KeyCode | Enum.UserInputType -- One or more inputs to bind
]=]
function InputController.BindAction(
	ActionName: string,
	Callback: (Enum.UserInputState) -> (),
	...: Enum.KeyCode | Enum.UserInputType
)
	if Actions[ActionName] then
		InputController.UnbindAction(ActionName)
	end

	local Inputs = { ... }

	Actions[ActionName] = {
		Callback = Callback,
		Enabled = true,
		Inputs = Inputs,
	}

	for _, InputType in Inputs do
		RegisterInputMapping(ActionName, InputType)
	end
end

--[=[
	Removes an action binding entirely.

	@param ActionName string -- The action to unbind
]=]
function InputController.UnbindAction(ActionName: string)
	UnregisterInputMapping(ActionName)
	Actions[ActionName] = nil
end

--[=[
	Replaces the input keys for an existing action without changing its callback.

	@param ActionName string -- The action to rebind
	@param ... Enum.KeyCode | Enum.UserInputType -- New inputs
]=]
function InputController.RebindAction(ActionName: string, ...: Enum.KeyCode | Enum.UserInputType)
	local Action = Actions[ActionName]
	if not Action then
		return
	end

	UnregisterInputMapping(ActionName)

	local Inputs = { ... }
	Action.Inputs = Inputs

	for _, InputType in Inputs do
		RegisterInputMapping(ActionName, InputType)
	end
end

--[=[
	Enables or disables an action without removing it.

	@param ActionName string -- The action to toggle
	@param Enabled boolean -- Whether the action should fire
]=]
function InputController.SetEnabled(ActionName: string, Enabled: boolean)
	local Action = Actions[ActionName]
	if Action then
		Action.Enabled = Enabled
	end
end

--[=[
	Returns whether the given action is currently enabled.

	@param ActionName string -- The action to check
	@return boolean -- True if the action exists and is enabled
]=]
function InputController.IsEnabled(ActionName: string): boolean
	local Action = Actions[ActionName]
	return if Action then Action.Enabled else false
end

--[=[
	Returns whether a keyboard key is currently held down.

	@param KeyCode Enum.KeyCode -- The key to check
	@return boolean -- True if the key is down
]=]
function InputController.IsKeyDown(KeyCode: Enum.KeyCode): boolean
	if not KeyboardInput then
		return false
	end
	return KeyboardInput:IsKeyDown(KeyCode)
end

--[=[
	Returns whether a gamepad button is currently held down.

	@param Button Enum.KeyCode -- The button to check
	@return boolean -- True if the button is down
]=]
function InputController.IsButtonDown(Button: Enum.KeyCode): boolean
	if not GamepadInput then
		return false
	end
	return GamepadInput:IsButtonDown(Button)
end

--[=[
	Returns the Keyboard input device, or nil if not initialized.

	@return Keyboard? -- The keyboard device
]=]
function InputController.GetKeyboard(): Keyboard?
	return KeyboardInput
end

--[=[
	Returns the Mouse input device, or nil if not initialized.

	@return Mouse? -- The mouse device
]=]
function InputController.GetMouse(): Mouse?
	return MouseInput
end

--[=[
	Returns the Gamepad input device, or nil if not initialized.

	@return Gamepad? -- The gamepad device
]=]
function InputController.GetGamepad(): Gamepad?
	return GamepadInput
end

--[=[
	Returns the Touch input device, or nil if not initialized.

	@return Touch? -- The touch device
]=]
function InputController.GetTouch(): Touch?
	return TouchInput
end

--[=[
	Returns whether the current device supports touch input.

	@return boolean -- True if touch is available
]=]
function InputController.IsTouchEnabled(): boolean
	if not TouchInput then
		return false
	end
	return TouchInput:IsTouchEnabled()
end

return InputController