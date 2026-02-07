# Strand Game Framework

A lightweight Roblox game framework with full IntelliSense support, inspired by Sleitnick's post-Knit philosophy: just use ModuleScripts as singletons, require directly, and add a lifecycle loader.

## Philosophy

- **ModuleScripts are singletons** — No magic, no string lookups
- **Require at the top** — IntelliSense works everywhere
- **Lifecycle prevents race conditions** — Init, Start, Stop
- **Not everything is a service** — Use the right tool for the job
- **Ensemble bridges players and entities** — Unified component architecture for players and NPCs

## Folder Structure

```
Server/
├── Services/           -- Global server systems
├── Components/         -- Entity behaviors (Ensemble ECS)
├── Hooks/              -- Temporary entity modifiers
├── HookUtil/           -- Hook loader
├── Ensemble/           -- ECS engine (don't modify)
│   ├── Core/           -- Entity, EntityBuilder, ComponentLoader
│   ├── Systems/        -- UpdateSystem
│   └── Types.luau      -- Re-exports from Shared/Types/EnsembleTypes
└── Scripts/
    └── Bootstrap.server.luau

Client/
├── Controllers/        -- Global client systems
└── Scripts/
    └── Bootstrap.client.luau

Shared/
├── Packages.luau       -- Package exports
├── Enums/              -- StatEnums, StateEnums, EntityEnums
├── Network/
│   └── Packets.luau    -- Network definitions with FireNearby, FireExcept, FireList
├── Types/              -- SettingsTypes, AudioTypes, EnsembleTypes
├── Config/             -- StatConfig, StateConfig
├── Utils/              -- ServiceLoader, EventBus, ObjectPool
└── Data/               -- PlayerDataTemplate
```

## Quick Start

### Adding a Service (Server)

```lua
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = require(Shared.Packages)

local Trove = Packages.Trove
local Signal = Packages.Signal

local OtherService = require(script.Parent.OtherService)

local MyService = {}

MyService.Dependencies = { "OtherService" }

MyService.SomethingHappened = Signal.new()

local ServiceTrove: typeof(Trove.new()) = nil :: any

function MyService.Init()
    ServiceTrove = Trove.new()
end

function MyService.Start()
    ServiceTrove:Connect(Players.PlayerAdded, function(Player)
    end)
end

function MyService.Stop()
    ServiceTrove:Destroy()
end

function MyService.DoSomething()
end

return MyService
```

### Adding a Controller (Client)

Same pattern as services, in `Client/Controllers/`.

```lua
--!strict

local MyController = {}

MyController.Dependencies = { "SettingsController" }

local ControllerTrove: typeof(Trove.new()) = nil :: any

function MyController.Init()
    ControllerTrove = Trove.new()
end

function MyController.Start()
end

function MyController.Stop()
    ControllerTrove:Destroy()
end

return MyController
```

### Adding a Component (Entity Behavior)

Components define per-entity behavior managed by Ensemble. They use a factory pattern with `Create` returning an instance table.

```lua
--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local Server = ServerScriptService:WaitForChild("Server")
local Types = require(Server.Ensemble.Types)

type Entity = Types.Entity
type EntityContext = Types.EntityContext

local MyComponent = {}

MyComponent.ComponentName = "MyComponent"
MyComponent.Dependencies = {}

type MyComponentInstance = {
    DoThing: () -> (),
    Destroy: () -> (),
}

function MyComponent.From(EntityInstance: Entity): MyComponentInstance?
    return EntityInstance:GetComponent("MyComponent")
end

function MyComponent.Create(EntityInstance: Entity, Context: EntityContext): MyComponentInstance
    local function DoThing()
    end

    local function Destroy()
    end

    return {
        DoThing = DoThing,
        Destroy = Destroy,
    }
end

export type Type = typeof(MyComponent.Create(nil :: any, nil :: any))

return MyComponent
```

Register it in Bootstrap by adding it to an archetype:

```lua
Ensemble.Init({
    Components = Server.Components,
    Archetypes = {
        Player = { "Stats", "States", "Modifiers", "MyComponent" },
        Enemy = { "Stats", "States", "Modifiers" },
    },
})
```

### Adding a Hook (Temporary Entity Modifier)

Hooks are toggleable modifiers for buffs, debuffs, status effects, passives, and talents. Return a cleanup function from `OnActivate` to undo the effect.

```lua
--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local EnsembleTypes = require(ServerScriptService.Server.Ensemble.Types)

type Entity = EnsembleTypes.Entity

local BOOST_MULTIPLIER = 1.5

local SpeedBoostHook = {}

SpeedBoostHook.HookName = "SpeedBoost"

function SpeedBoostHook.OnActivate(Entity: Entity): (() -> ())?
    local Humanoid = Entity.Humanoid
    if not Humanoid then
        return nil
    end

    local OriginalSpeed = Humanoid.WalkSpeed
    Humanoid.WalkSpeed = OriginalSpeed * BOOST_MULTIPLIER

    return function()
        if Humanoid and Humanoid.Parent then
            Humanoid.WalkSpeed = OriginalSpeed
        end
    end
end

return SpeedBoostHook
```

Usage:

```lua
local HookComponent = Entity:GetComponent("Hooks")
HookComponent.Register("SpeedBoost")
HookComponent.Unregister("SpeedBoost")
```

### Adding Network Packets

```lua
return {
    MyPacket = Packet(
        "MyPacket",
        Packet.String,
        Packet.NumberF32,
        Packet.Any
    ),
}
```

Server:

```lua
Packets.MyPacket:FireClient(Player, "hello", 42, { Data = true })
Packets.FireNearby(Packets.MyPacket, Position, 100, "hello", 42, nil)
Packets.FireExcept(Packets.MyPacket, ExcludedPlayer, "hello", 42, nil)
```

Client:

```lua
Packets.MyPacket.OnClientEvent:Connect(function(Str, Num, Data)
end)
```

## Lifecycle

```
Bootstrap
    │
    ├── HookLoader.Configure(Server.Hooks)
    │
    ├── Ensemble.Init({ Components, Archetypes })
    │
    ├── ServiceLoader.LoadServices(Folder)  -- Require all modules
    │
    ├── ServiceLoader.InitAll()             -- Init() in dependency order (synchronous)
    │
    └── ServiceLoader.StartAll()            -- Start() in dependency order (async per service)
```

## Current Inventory

### Services (Server)

| Service | Purpose |
|---------|---------|
| `PlayerService` | Character lifecycle, entity creation via archetypes |
| `EntityService` | Thin wrapper over Ensemble for entity CRUD |
| `PlayerDataService` | ProfileStore session management |
| `DataBridgeService` | Rate-limited client data requests |
| `SettingsService` | Server-side settings validation and persistence |

### Controllers (Client)

| Controller | Purpose |
|------------|---------|
| `SettingsController` | Client settings cache and sync |
| `AudioController` | SFX and music playback |
| `EffectsController` | VFX spawning with quality scaling and pooling |
| `CameraController` | Camera shake |
| `EntityController` | Client-side entity state tracking |
| `InputController` | Keyboard, mouse, and gamepad input |

### Components (Ensemble)

| Component | Purpose |
|-----------|---------|
| `Stats` | Numeric stats with base/current values, clamping, replication |
| `States` | Boolean states with conflicts, timed durations, replication |
| `Modifiers` | Priority-ordered modifier functions per stat type |
| `Hooks` | Toggleable hook registration and cleanup |

### Archetypes

Defined in Bootstrap:

```lua
Archetypes = {
    Player = { "Stats", "States", "Modifiers" },
    Enemy = { "Stats", "States", "Modifiers" },
}
```

### Utils

| Utility | Purpose |
|---------|---------|
| `ServiceLoader` | Lifecycle manager with topological dependency sort |
| `EventBus` | Decoupled pub/sub messaging |
| `ObjectPool` | Generic object pooling with reset, tracking, and error handling |

### Packages (via Packages.luau)

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
| `Loader` | Module loading |

## When to Use What

| Need | Solution |
|------|----------|
| Global system (audio, input, data) | Service / Controller |
| Per-entity behavior (health, states) | Component |
| Temporary entity modifier (buff, debuff) | Hook |
| Pure helper function | Module in Utils/ |
| Data definitions (items, templates) | Module in Data/ |
| Type definitions | Module in Types/ |
| Configuration tables | Module in Config/ |

## Anti-Patterns

```lua
-- BAD: Require inside a function
function MyService.Init()
    local Other = require(script.Parent.OtherService)
end

-- BAD: Typing a dependency as any
local SomeService: any = nil

-- BAD: Connections without cleanup
function MyController.Start()
    Players.PlayerAdded:Connect(Handler)
end

-- BAD: Over-servicing
CoinService, CoinController, CoinManager, CoinHandler...

-- GOOD: Just a data module
local Coins = require(Shared.Data.Coins)
```

## Tips

1. **Require at the top** — Never require inside functions
2. **Use Trove:Connect()** — Cleaner than `Trove:Add(Signal:Connect())`
3. **Declare Dependencies** — Ensures correct initialization order
4. **Always implement Stop()** — Clean shutdown matters
5. **Keep services thin** — Heavy logic belongs in Components or Utils
6. **Use From() for typed component access** — `StatComponent.From(Entity)` gives IntelliSense