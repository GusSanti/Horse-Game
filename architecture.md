# Horse Game Architecture

## Purpose

This document is the source of truth for the current runtime architecture,
the organization refactor completed on 2026-08-04, and the remaining risks
that must guide the next refactoring milestones. All paths refer to the Rojo
repository; the connected Studio place remains necessary for world and UI
assets that are not yet represented in source.

## Current runtime

```text
ServerScriptService.ServerBootup
  -> Lifecycle.Init (all server components)
  -> Lifecycle.Start (deterministic order)
  -> ServerReady / ServerFailed

ReplicatedFirst.ClientBootup
  -> critical animation preload
  -> UIRuntime
  -> LegacyClientRuntime (explicit manifest order)
  -> ClientReady / ClientFailed
```

The server no longer starts independent scripts or clones compatibility
entrypoints. `ServerBootup.server.luau` is the only server composition root.
Every server domain is a strict lifecycle component and cleanup runs in reverse
dependency order.

The client has one composition root, but most gameplay controllers are still
legacy `LocalScript` templates. `LegacyClientRuntime` starts them in the exact
order declared by `RuntimeManifest.Client` and waits for each `RuntimeReady`
attribute. This is now deterministic, but it is intentionally a compatibility
boundary rather than the final client architecture.

## Server components

| Component | Responsibility |
| --- | --- |
| `NetworkRuntime` | Creates the complete code-owned remote contract before services start. |
| `DataRuntime` | Owns ProfileStore sessions, player profile attachment, play-time tasks, and release. |
| `PlayerLifecycle` | Is the sole owner of Roblox `PlayerAdded`, `PlayerRemoving`, and character lifecycle signals. |
| `AdminRuntime` | Applies access attributes and owns admin request handlers. |
| `HorseRuntime` | Owns starter-reveal acknowledgement and horse-tool requests. It does not yet replace the main horse services. |
| `GameplayRuntime` | Initializes existing gameplay services and queues player readiness until those services have started. |
| `CommerceRuntime` | Owns the catalog, gift handlers, receipt callback, and their cleanup. |
| `PlotRuntime` | Assigns plots and coordinates level changes, layout replacement, prompts, and teleport requests. |
| `CharacterFolderRuntime` | Parents characters under the managed workspace folder. |
| `NpcIdleRuntime` | Owns NPC animation tracks and per-NPC Troves. |

`PlotRuntime` is split into `Layout`, `Prompts`, and a lifecycle entry module.
`CommerceRuntime`, `AdminRuntime`, and `HorseRuntime` use the same folder-module
pattern. Every new server module remains below the 500-line limit in
`RULES.luau`.

## Code-owned events and networking

`Modules.Framework.RuntimeEvents` is the in-process event boundary. Managed
systems subscribe to player, character, server, client, and UI events instead
of independently rebinding the same Roblox lifecycle signals.

`Modules.Network` is the shared remote contract. Requiring it on the server
materializes every declared `RemoteEvent` and `RemoteFunction` under
`ReplicatedStorage.Net`. The former `GameplayRemotes`, `ToolRemotes`, and manual
remote creation paths were removed. `Net` remains the transport adapter so
existing systems can migrate call sites incrementally without changing the
wire names used by already-centralized remotes.

RemoteFunction response ownership now supports Trove cleanup. Commerce also
releases its ProfileStore message handler and only clears
`MarketplaceService.ProcessReceipt` when it still owns the callback.

See [docs/network-runtime.md](docs/network-runtime.md).

## UI runtime

`Modules.Client.Hud.UIRuntime` is the single owner of initial `PlayerGui`
discovery and descendant binding. It registers every direct child of
`MainUI.MainframeFR.Frames` with `UIRouter`.

`UIRouter` owns modal state and exclusivity. `HudAnim` remains the presentation
adapter for the existing open, close, blur, FOV, sound, and HUD-fade behavior.
Legacy code that still writes `Visible` directly is synchronized back into the
router, so migration can proceed screen by screen without a visual rewrite.

The connected Studio place currently registers 14 modal frames. A live test
opened Inventory, closed it, opened Settings, verified exclusivity and router
state, and restored the closed state.

See [docs/ui-runtime.md](docs/ui-runtime.md).

## Horse runtime migration

The horse refactor has started with the mount domain. The new
`ServerStorage.Modules.Horse.Mount` boundary contains strict modules for rig
resolution, minimal physics assembly, and mount transaction state. The legacy
`HorseMountService` still orchestrates mount gameplay, but now owns its remote,
heartbeat, and code-lifecycle subscriptions through a Trove and exposes an
idempotent `Destroy` method.

The runtime mount root no longer welds every visual part or replaces the
horse model's authored `PrimaryPart`. It connects to the authored root and
preserves existing Motor6Ds and constraints; only disconnected legacy pieces
receive compatibility welds. Mount and dismount are locked across the complete
`Preparing -> Mounting -> Mounted -> Dismounting` transaction.

Current assets still lack the semantic rider anchor required to follow the
animated back. This milestone deliberately retains the old rigid rider offset
until the assets receive that contract and presentation can be migrated
without binding character physics directly to a Bone.

Mounted locomotion now has a shared deterministic state machine under
`ReplicatedStorage.Modules.Game.Horse.Mount.Movement`. It ports the supplied
reference place's persistent speed, progressive gait changes, forward
double-tap, brake-before-reverse, horse-relative steering, rear, obstacle
response, terrain alignment, and camera motion while preserving each current
horse's effective stats and the existing constraint assembly. A cached probe
reduces terrain and obstacle work to seven raycasts at 20 Hz.

Mount input carries monotonic sequences. The server rejects replayed inputs,
continues to enforce observed speed, and acknowledges the latest processed
sequence with observed speed and gait. Client speed reconciliation is only
requested after an actual server rollback, so normal constraint lag does not
change the selected gait. Full fixed-step position simulation is not claimed;
network ownership remains a documented compatibility boundary.

See [docs/horse-runtime.md](docs/horse-runtime.md).

## Player join flow

1. All components bind their code-event subscriptions during `Init`.
2. `PlayerLifecycle.Start` emits `RuntimeEvents.PlayerAdded` for current
   players and later mirrors Roblox player/character signals.
3. `DataRuntime` opens and attaches the profile synchronously in the player
   event before downstream readiness work is scheduled.
4. `GameplayRuntime` queues the player until its service list has initialized,
   then synchronizes loadout, login, starter horse, status, farming, stable,
   quest, and race state.
5. `PlotRuntime`, admin access, and character ownership receive the same
   code-owned player events with their own scoped cleanup.
6. The client waits for `ServerReady`, then starts its ordered compatibility
   controllers and publishes `ClientReady`.

## Source and Studio ownership

Rojo owns scripts and mapped source containers. The connected place still owns
substantial authored data under `Workspace`, `StarterGui`, `StarterPack`, and
asset folders. These instances are runtime dependencies but are not fully
reproducible from the repository. Studio MCP is therefore used for read-only
tree inspection and playtests; repository scripts must not be edited through
Studio.

## Refactoring milestone changes

- Replaced independent server startup with one lifecycle composition root.
- Removed all ten legacy server entry scripts and the server compatibility
  runner/template folder.
- Added deterministic readiness and failure attributes for both execution
  boundaries.
- Centralized player and character lifecycle events.
- Added Trove ownership to new runtime components, profile tasks, network
  handlers, NPC animation tracks, UI discovery, plot prompts, and commerce
  callbacks.
- Centralized all remote creation and removed obsolete remote configuration.
- Split plots, commerce, admin operations, and the first horse boundary into
  domain folders with small lifecycle entry modules.
- Centralized modal UI state without changing the existing visual animator.
- Added unit tests for lifecycle, signals, manifests, network contracts, and
  UI routing, plus a server bootstrap integration test.
- Started the horse refactor with a validated rig adapter, minimal mount
  assembly, transition locking, lifecycle cleanup, and mount-domain tests.
- Ported reference-style mounted locomotion into a shared state machine,
  bounded probe, sequenced input protocol, server acknowledgements, and
  deterministic movement tests without changing horse data ownership.

## Upstream compatibility integration

The 2026-08-04 upstream mount-camera and UI-animation update was rebased onto
the centralized runtime rather than replacing it. The updated mount client,
camera adapter, configuration, and server service remain the active gameplay
implementation and still start through the explicit client manifest and
`GameplayRuntime` boundaries.

The upstream `HudAnim` presentation additions (`Fade`, `Stagger`, and `Punch`),
attribute-driven rotation/easing, and public animation helpers coexist with
the centralized `UIRouter` adapter. Modal ownership therefore remains in one
router while the intended upstream visual transitions remain in `HudAnim`.
The generated Rojo sourcemap was rebuilt from this combined tree.

## Validation evidence

- `rojo build default.project.json` succeeds after the migration.
- `git diff --check` reports no whitespace errors.
- Studio unit suite: 31 run, 31 passed, 0 failed.
- Studio bootstrap integration: `Success = true`.
- Studio readiness: server and client both ready with no failure attribute.
- Studio UI smoke test: 14 routes registered; Inventory and Settings open/close
  behavior and modal exclusivity passed.
- Studio output contains no new game/runtime error. The Animation Spoofer plugin
  emits its own play-mode notices and is outside repository ownership.

## Remaining highest risks

| Priority | Risk | Required direction |
| --- | --- | --- |
| P0 | The full profile is still exposed to the client through `DataUtilityGet`. Internal LiveOps and receipt state should never be part of the client cache. | Introduce explicit client projections and path-level authorization before expanding gameplay. |
| P0 | The place is not reproducible solely from Rojo source. | Export or declaratively generate canonical world, UI, and asset dependencies; add schema validation at boot. |
| P1 | Twenty-nine client controllers still auto-run through the compatibility runtime and many own raw Roblox events without lifecycle cleanup. | Migrate one client domain at a time to strict `Init/Start/Destroy` controllers with Trove. |
| P1 | Core horse, mount, inventory, farming, race, and UI modules remain god modules far above 500 lines. | Split by command, state, validation, world adapter, and presentation responsibility. |
| P1 | Existing gameplay services generally expose `Init` but not `Destroy`; `GameplayRuntime` can only clean services that implement it. | Add idempotent lifecycle methods and per-player scopes during each domain migration. |
| P1 | Network payloads are mostly untyped and have no shared rate-limit policy. | Add typed request/response definitions, boundary validation, and per-action throttles. |
| P1 | There is no CI typecheck, lint, format, or automated Studio runner. | Add repository quality gates after the runtime layout stabilizes. |
| P2 | `HudAnim` remains a 1,600-line compatibility module and several feature scripts alter its attributes directly. | Split visual transitions, HUD fading, button effects, and route adapters while retaining snapshots of current behavior. |
| P2 | Runtime instance paths and names remain an implicit world API. | Add typed world/asset adapters and startup schema tests. |

## Next milestones

1. Convert the remaining client templates into managed controllers, starting
   with low-coupling HUD and tool scripts; remove `LegacyClientRuntime` only
   when the manifest is empty.
2. Add a client-safe player-state projection and tests that prove server-only
   profile fields cannot replicate.
3. Add service `Destroy` coverage and rate limiting at network boundaries.
4. Continue the horse-system refactor with authored rider anchors, fixed-step
   movement authority, additional gait/rear animation assets, ownership/stable
   allocation, status decay, world visuals, care actions, and roaming as
   separate subdomains.

ProfileStore itself remains out of scope: its session-lock semantics are
valuable and the current problem is ownership around it, not the library.
