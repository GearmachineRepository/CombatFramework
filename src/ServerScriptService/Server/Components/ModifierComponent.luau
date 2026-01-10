--!strict

local ModifierComponent = {}

ModifierComponent.ComponentName = "Modifiers"
ModifierComponent.Dependencies = {}

type ModifierFunction = (BaseValue: number, Data: { [string]: any }?) -> number

type Modifier = {
	Priority: number,
	Func: ModifierFunction,
}

type ModifierInstance = {
	Register: (Type: string, Priority: number, Func: ModifierFunction) -> () -> (),
	Unregister: (Type: string, Func: ModifierFunction) -> (),
	Apply: (Type: string, BaseValue: number, Data: { [string]: any }?) -> number,
	GetCount: (Type: string) -> number,
	Clear: (Type: string?) -> (),
	Destroy: () -> (),
}

function ModifierComponent.From(Entity: any): Type?
	return Entity:GetComponent("Modifiers")
end

function ModifierComponent.Create(_Entity: any, _Context: any): ModifierInstance
	local ModifiersByType: { [string]: { Modifier } } = {}

	local function Register(Type: string, Priority: number, Func: ModifierFunction): () -> ()
		local Modifiers = ModifiersByType[Type]
		if not Modifiers then
			Modifiers = {}
			ModifiersByType[Type] = Modifiers
		end

		local NewModifier: Modifier = {
			Priority = Priority,
			Func = Func,
		}

		table.insert(Modifiers, NewModifier)

		table.sort(Modifiers :: {Modifier}, function(FirstModifier: Modifier, SecondModifier: Modifier): boolean
			return FirstModifier.Priority < SecondModifier.Priority
		end)

		return function()
			local CurrentModifiers = ModifiersByType[Type]
			if not CurrentModifiers then
				return
			end

			for Index, Modifier in CurrentModifiers do
				if Modifier.Func == Func then
					table.remove(CurrentModifiers, Index)
					break
				end
			end
		end
	end

	local function Unregister(Type: string, Func: ModifierFunction)
		local Modifiers = ModifiersByType[Type]
		if not Modifiers then
			return
		end

		for Index, Modifier in Modifiers do
			if Modifier.Func == Func then
				table.remove(Modifiers, Index)
				break
			end
		end
	end

	local function Apply(Type: string, BaseValue: number, Data: { [string]: any }?): number
		local Modifiers = ModifiersByType[Type]
		if not Modifiers or #Modifiers == 0 then
			return BaseValue
		end

		local CurrentValue = BaseValue

		for _, Modifier in Modifiers do
			CurrentValue = Modifier.Func(CurrentValue, Data)
		end

		return CurrentValue
	end

	local function GetCount(Type: string): number
		local Modifiers = ModifiersByType[Type]
		return if Modifiers then #Modifiers else 0
	end

	local function Clear(Type: string?)
		if Type then
			ModifiersByType[Type] = nil
		else
			table.clear(ModifiersByType)
		end
	end

	local function Destroy()
		table.clear(ModifiersByType)
	end

	return {
		Register = Register,
		Unregister = Unregister,
		Apply = Apply,
		GetCount = GetCount,
		Clear = Clear,
		Destroy = Destroy,
	}
end

export type Type = typeof(ModifierComponent.Create(nil :: any, nil :: any))

return ModifierComponent