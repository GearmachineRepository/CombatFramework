--!strict

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

function InputController.Init()
	ControllerTrove = Trove.new()
end

function InputController.Start()
	KeyboardInput = ControllerTrove:Add(Input.Keyboard.new() :: any) :: Keyboard
	MouseInput = ControllerTrove:Add(Input.Mouse.new() :: any) :: Mouse
	GamepadInput = ControllerTrove:Add(Input.Gamepad.new() :: any) :: Gamepad
	TouchInput = ControllerTrove:Add(Input.Touch.new() :: any) :: Touch

	if not KeyboardInput or not MouseInput or not GamepadInput then
		return
	end

	ControllerTrove:Add(KeyboardInput.KeyDown:Connect(function(KeyCode: Enum.KeyCode, Processed: boolean)
		FireActionsForInput(KeyCode, Enum.UserInputState.Begin, Processed)
	end))

	ControllerTrove:Add(KeyboardInput.KeyUp:Connect(function(KeyCode: Enum.KeyCode, Processed: boolean)
		FireActionsForInput(KeyCode, Enum.UserInputState.End, Processed)
	end))

	ControllerTrove:Add(MouseInput.LeftDown:Connect(function(Processed: boolean)
		FireActionsForInput(Enum.UserInputType.MouseButton1, Enum.UserInputState.Begin, Processed)
	end))

	ControllerTrove:Add(MouseInput.LeftUp:Connect(function(Processed: boolean)
		FireActionsForInput(Enum.UserInputType.MouseButton1, Enum.UserInputState.End, Processed)
	end))

	ControllerTrove:Add(MouseInput.RightDown:Connect(function(Processed: boolean)
		FireActionsForInput(Enum.UserInputType.MouseButton2, Enum.UserInputState.Begin, Processed)
	end))

	ControllerTrove:Add(MouseInput.RightUp:Connect(function(Processed: boolean)
		FireActionsForInput(Enum.UserInputType.MouseButton2, Enum.UserInputState.End, Processed)
	end))

	ControllerTrove:Add(GamepadInput.ButtonDown:Connect(function(Button: Enum.KeyCode, Processed: boolean)
		FireActionsForInput(Button, Enum.UserInputState.Begin, Processed)
	end))

	ControllerTrove:Add(GamepadInput.ButtonUp:Connect(function(Button: Enum.KeyCode, Processed: boolean)
		FireActionsForInput(Button, Enum.UserInputState.End, Processed)
	end))
end

function InputController.Stop()
	ControllerTrove:Destroy()
	KeyboardInput = nil
	MouseInput = nil
	GamepadInput = nil
	TouchInput = nil
	table.clear(Actions)
	table.clear(InputToActions)
end

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

function InputController.UnbindAction(ActionName: string)
	UnregisterInputMapping(ActionName)
	Actions[ActionName] = nil
end

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

function InputController.SetEnabled(ActionName: string, Enabled: boolean)
	local Action = Actions[ActionName]
	if Action then
		Action.Enabled = Enabled
	end
end

function InputController.IsEnabled(ActionName: string): boolean
	local Action = Actions[ActionName]
	return if Action then Action.Enabled else false
end

function InputController.IsKeyDown(KeyCode: Enum.KeyCode): boolean
	if not KeyboardInput then
		return false
	end
	return KeyboardInput:IsKeyDown(KeyCode)
end

function InputController.IsButtonDown(Button: Enum.KeyCode): boolean
	if not GamepadInput then
		return false
	end
	return GamepadInput:IsButtonDown(Button)
end

function InputController.GetKeyboard(): Keyboard?
	return KeyboardInput
end

function InputController.GetMouse(): Mouse?
	return MouseInput
end

function InputController.GetGamepad(): Gamepad?
	return GamepadInput
end

function InputController.GetTouch(): Touch?
	return TouchInput
end

function InputController.IsTouchEnabled(): boolean
	if not TouchInput then
		return false
	end
	return TouchInput:IsTouchEnabled()
end

return InputController