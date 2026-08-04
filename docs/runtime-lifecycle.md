# Runtime Lifecycle

## Contract

Server and client composition roots use the same lifecycle contract:

```luau
type Component = {
    Name: string?,
    Init: ((self: Component) -> ())?,
    Start: ((self: Component) -> ())?,
    Destroy: ((self: Component) -> ())?,
}
```

Every component finishes `Init` before any component enters `Start`.
`Destroy` is idempotent and runs in reverse order, allowing consumers to clean
their work while providers are still available. A phase error includes the
runtime, component, and phase name and prevents readiness from being reported.

Resources created by a managed component must belong to its Trove or to a
nested player/entity Trove. This includes connections, tasks, callbacks,
temporary instances, and animation tracks.

## Server composition

`ServerScriptService.ServerBootup` is the only server entrypoint. Its component
order is:

1. `NetworkRuntime`
2. `DataRuntime`
3. `PlayerLifecycle`
4. `AdminRuntime`
5. `HorseRuntime`
6. `GameplayRuntime`
7. `CommerceRuntime`
8. `PlotRuntime`
9. `CharacterFolderRuntime`
10. `NpcIdleRuntime`

There is no legacy server manifest, clone runner, or entrypoint template
folder. `RuntimeManifest.Server` is intentionally empty and protected by a
unit test.

`PlayerLifecycle` is the only component that connects directly to Roblox
player and character lifecycle signals. Because every subscription is bound in
`Init`, its `Start` method can safely emit current-player events before other
components start. `GameplayRuntime` queues those players until its existing
service modules are initialized.

## Client composition

`ReplicatedFirst.ClientBootup` owns:

1. critical mount-animation preload;
2. `UIRuntime` initialization and `PlayerGui` observation;
3. `LegacyClientRuntime` startup.

The client waits for server readiness before starting compatibility scripts.
The client manifest is explicit, so filesystem/instance enumeration cannot
change controller order. Each legacy template reports `RuntimeReady` after its
initial bindings are installed.

This compatibility layer contains 29 controllers. New client work should be a
strict lifecycle module registered directly in `ClientBootup`; migrated
controllers must be removed from the manifest and template folder.

## Runtime events

`Modules.Framework.RuntimeEvents` owns in-process signals for:

- player added/removing;
- character added/removing;
- server and client started/stopping;
- UI screen registration/open/close.

These signals decouple domain components from the composition root. Roblox
signals are still valid inside the system that owns the corresponding engine
boundary, but the same global lifecycle signal must not be rebound across
independent domains.

## Readiness attributes

`ReplicatedStorage.Modules.Framework` exposes:

| Attribute | Owner | Meaning |
| --- | --- | --- |
| `ServerReady` | server | all server components initialized and started |
| `ServerFailed` | server | server lifecycle failed before readiness |
| `ServerError` | server | causal lifecycle diagnostic |
| `ClientReady` | client | UI and all ordered compatibility controllers started |
| `ClientFailed` | client | client lifecycle failed before readiness |
| `ClientError` | client | causal lifecycle diagnostic |

These attributes are diagnostic gates, not replicated gameplay state.

## Migration checklist

1. Extract the entry script into a domain folder with a small `init.luau`.
2. Move Roblox signal bindings into `Init` or `Start` and attach them to Trove.
3. Subscribe to `RuntimeEvents` for global player/character lifecycle.
4. Provide idempotent `Destroy`, including nested player/entity scopes.
5. Register the component in the composition root at its dependency position.
6. Remove the compatibility manifest entry and old script only after tests
   cover observable behavior and cleanup.
