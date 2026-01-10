# Game Framework Template

A lightweight Roblox game framework with full IntelliSense support.

## Philosophy

- **ModuleScripts are singletons** - No magic, no string lookups
- **Require at the top** - IntelliSense works everywhere
- **Lifecycle prevents race conditions** - Init → Start → Stop
- **Not everything is a service** - Use the right tool for the job
- **Utilities people!** - There may be a utility for your usecase. Consider making utilities to help in the future too.

## Folder Structure

```
Server/
├── Services/           -- Global server systems
├── Components/         -- Entity behaviors (Ensemble ECS)
├── Hooks/              -- Temporary entity modifiers
├── Ensemble/           -- ECS engine (don't modify)
└── Scripts/
    └── Bootstrap.server.lua

Client/
├── Controllers/        -- Global client systems
└── Scripts/
    └── Bootstrap.client.lua

Shared/
├── ServiceLoader.lua   -- Lifecycle manager
├── Packages.lua        -- Package exports
├── Network/
│   └── Packets.lua     -- Network definitions
├── Types/              -- Type definitions
├── Utils/              -- Pure helper functions
├── Data/               -- Configs, templates, definitions
└── Enums.lua
```

## Quick Start

### Adding a Service (Server)

```lua
--!strict
-- Server/Services/MyService.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = require(Shared.Packages)

local Trove = Packages.Trove
local Signal = Packages.Signal

-- Require dependencies at the TOP (IntelliSense works!)
local OtherService = require(script.Parent.OtherService)

local MyService = {}

-- Optional: Declare dependencies for load ordering
MyService.Dependencies = { "OtherService" }

-- Optional: Public signals
MyService.SomethingHappened = Signal.new()

local ServiceTrove: typeof(Trove.new()) = nil :: any

function MyService.Init()
    -- Create troves, set up state
    -- All modules loaded, safe to reference other services
    ServiceTrove = Trove.new()
end

function MyService.Start()
    -- Connect events, start loops
    -- All Init() calls complete
    ServiceTrove:Connect(Players.PlayerAdded, function(Player)
        -- Handle player
    end)
end

function MyService.Stop()
    -- Cleanup (optional but recommended)
    ServiceTrove:Destroy()
end

function MyService.DoSomething()
    -- Public API
end

return MyService
```

### Adding a Controller (Client)

Same pattern as services, just in `Client/Controllers/`.

```lua
--!strict
-- Client/Controllers/MyController.lua

local MyController = {}

MyController.Dependencies = { "InputController" }

function MyController.Init()
end

function MyController.Start()
end

function MyController.Stop()
end

return MyController
```

### Adding a Component (Entity Behavior)

Components define entity behavior. They're managed by Ensemble.

```lua
--!strict
-- Server/Components/HealthComponent.lua

local ServerScriptService = game:GetService("ServerScriptService")
local Types = require(ServerScriptService.Server.Ensemble.Types)

type Entity = Types.Entity
type EntityContext = Types.EntityContext

local HealthComponent = {}

HealthComponent.ComponentName = "Health"
HealthComponent.Dependencies = { "Stats" }  -- Other components this needs
-- HealthComponent.UpdateRate = 1  -- Optional: runs Update() every N seconds

type HealthInstance = {
    TakeDamage: (Amount: number) -> (),
    Heal: (Amount: number) -> (),
    GetHealth: () -> number,
    Destroy: () -> (),
}

-- Helper to get this component from an entity with proper typing
function HealthComponent.From(Entity: Entity): HealthInstance?
    return Entity:GetComponent("Health")
end

function HealthComponent.Create(Entity: Entity, Context: EntityContext): HealthInstance
    local Humanoid = Entity.Humanoid
    local MaxHealth = 100

    local function TakeDamage(Amount: number)
        Humanoid.Health = math.max(0, Humanoid.Health - Amount)
    end

    local function Heal(Amount: number)
        Humanoid.Health = math.min(MaxHealth, Humanoid.Health + Amount)
    end

    local function GetHealth(): number
        return Humanoid.Health
    end

    local function Destroy()
        -- Cleanup connections, etc.
    end

    return {
        TakeDamage = TakeDamage,
        Heal = Heal,
        GetHealth = GetHealth,
        Destroy = Destroy,
    }
end

export type Type = HealthInstance

return HealthComponent
```

### Adding a Hook (Temporary Modifier)

Hooks are toggleable entity modifiers - perfect for buffs/debuffs.

```lua
--!strict
-- Server/Hooks/SpeedBoostHook.lua

local ServerScriptService = game:GetService("ServerScriptService")
local EnsembleTypes = require(ServerScriptService.Server.Ensemble.Types)

type Entity = EnsembleTypes.Entity

local SpeedBoostHook = {}

SpeedBoostHook.HookName = "SpeedBoost"

function SpeedBoostHook.OnActivate(Entity: Entity): (() -> ())?
    local Humanoid = Entity.Humanoid
    local OriginalSpeed = Humanoid.WalkSpeed
    Humanoid.WalkSpeed = OriginalSpeed * 2

    -- Return cleanup function (runs when hook is unregistered)
    return function()
        Humanoid.WalkSpeed = OriginalSpeed
    end
end

function SpeedBoostHook.OnDeactivate(Entity: Entity)
    -- Additional cleanup if needed
end

return SpeedBoostHook
```

**Using hooks:**
```lua
local HookComponent = Entity:GetComponent("Hooks")
HookComponent.Register("SpeedBoost")   -- Activate
HookComponent.Unregister("SpeedBoost") -- Deactivate
```

### Adding Network Packets

```lua
-- Shared/Network/Packets.lua

return {
    -- Existing packets...

    MyPacket = Packet(
        "MyPacket",
        Packet.String,      -- First argument type
        Packet.NumberF32,   -- Second argument type
        Packet.Any          -- Third argument (flexible)
    ),
}
```

**Server:**
```lua
Packets.MyPacket:FireClient(Player, "hello", 42, { data = true })
Packets.MyPacket:Fire("broadcast", 0, nil)  -- All clients
```

**Client:**
```lua
Packets.MyPacket.OnClientEvent:Connect(function(Str, Num, Data)
    print(Str, Num, Data)
end)

Packets.MyPacket:Fire("to server", 10, nil)  -- To server
```

## Lifecycle

```
Bootstrap
    │
    ├── ServiceLoader.LoadServices(Folder)  -- Require all modules
    │
    ├── ServiceLoader.InitAll()             -- Call Init() in dependency order
    │                                        -- (synchronous, safe to reference others)
    │
    └── ServiceLoader.StartAll()            -- Call Start() in dependency order
                                             -- (can be async, all Init complete)
```

## When to Use What

| Need | Solution |
|------|----------|
| Global system (audio, input, data) | Service / Controller |
| Entity behavior (health, combat) | Component |
| Temporary entity modifier (buff, debuff) | Hook |
| Pure helper function | ModuleScript in Utils/ |
| Data definitions (items, abilities) | ModuleScript in Data/ |
| Type definitions | ModuleScript in Types/ |

## Archetypes

Archetypes are component presets. Define them in Bootstrap:

```lua
Ensemble.Init({
    Components = Server.Components,
    Archetypes = {
        Player = { "Stats", "States", "Modifiers", "Combat", "Inventory" },
        Enemy = { "Stats", "States", "Modifiers", "Combat" },
        NPC = { "Stats", "States" },
    },
})
```

**Usage:**
```lua
EntityService.CreateEntityWithArchetype(Character, "Player", { Player = Player })
EntityService.CreateEntityWithArchetype(EnemyModel, "Enemy", {})
```

## Packages Available

From `Packages.lua`:

| Package | Use For |
|---------|---------|
| `Trove` | Cleanup management |
| `Signal` | Custom events |
| `Input` | Keyboard/Mouse/Gamepad |
| `Shake` | Camera shake |
| `Spring` | Smooth animations |
| `Timer` | Interval loops |
| `TableUtil` | Table operations |
| `Log` | Structured logging |
| `Packet` | Network definitions |

## Tips

1. **Require at the top** - Never require inside functions
2. **Use Trove:Connect()** - Cleaner than `Trove:Add(Signal:Connect())`
3. **Declare Dependencies** - Ensures correct initialization order
4. **Keep services thin** - Heavy logic belongs in Components or Utils
5. **Don't over-service** - Not everything needs to be a service

## Anti-Patterns

```lua
-- BAD: Require inside function (breaks IntelliSense)
function MyService.Start()
    local Other = require(script.Parent.OtherService)
end

-- BAD: Using any type
local SomeService: any = nil

-- BAD: Missing cleanup
function MyController.Start()
    Players.PlayerAdded:Connect(handler)  -- Never disconnected!
end

-- BAD: Everything is a service
CoinService, CoinController, CoinManager, CoinHandler...

-- GOOD: Just a data module
local Coins = require(Shared.Data.Coins)
```