# Horse Runtime

## Scope

This document tracks the incremental migration of the horse domain from the
legacy services under `ServerStorage.Modules.Horse` into small, explicit
subdomains. The mount migration now covers rig assembly, transactions, the
shared locomotion model, bounded terrain probes, and sequenced movement input.

## Mount domain

`ServerStorage.Modules.Horse.Mount` is the composition boundary for the first
extracted modules:

| Module | Responsibility |
| --- | --- |
| `RigAdapter` | Resolves the authored root, base parts, optional rider anchor, and compatibility diagnostics. |
| `Assembly` | Creates the runtime physics root, seat, driver constraints, and minimal rig welds. |
| `TransactionRegistry` | Enforces stale-safe `Preparing`, `Mounting`, `Mounted`, and `Dismounting` transitions. |
| `Bindings` | Owns remote and code-lifecycle subscriptions through one Trove. |
| `InputState` | Validates and applies mount input fields at the transport boundary. |

All new modules are strict, individually remain below 500 lines, and expose no
Roblox event ownership. `HorseMountService` remains the legacy orchestrator for
now, but its connections and remote ownership are scoped to a Trove and use
`Framework.RuntimeEvents` for player and character lifecycle changes.

## Movement domain

`ReplicatedStorage.Modules.Game.Horse.Mount.Movement` is shared by the client,
server, and unit tests:

| Module | Responsibility |
| --- | --- |
| `StateMachine` | Deterministic speed, gait, double-tap, braking, reverse, rear, obstacle limiting, and speed reconciliation. |
| `GroundProbe` | Cached terrain and obstacle raycasts at a bounded frequency. |

The movement behavior is ported from the supplied medieval-combat place, but
is normalized to each owned horse's effective movement stats. A horse keeps
its catalog, nature, and saddle-derived speed, acceleration, turn, and jump
values; the reference place's literal `60` speed is not copied into game
balance.

Current controls are:

| Input | Behavior |
| --- | --- |
| `W` / forward stick | Accelerates continuously through gait, trot, and gallop. |
| Release forward | Keeps the selected speed instead of applying automatic braking. |
| Double-tap forward | Immediately enters the horse's gallop band. |
| `S` / backward stick | Brakes to zero, then engages reverse. |
| `A` / `D` / horizontal stick | Turns around the horse axis; reverse steering is inverted naturally. |
| `Shift` / `L3` | Applies the existing optional acceleration boost. |
| `Space` / jump action | Jumps while moving; requests the existing backend dismount while stopped. |
| `J` / gamepad `Y` | Rears while stopped, with a cooldown. |

The physical driver still uses the existing `LinearVelocity` and
`AlignOrientation`. Terrain pitch, turn lean, rear pose, jump velocity, and
camera bob are layered onto that modern constraint assembly. Locomotion maps
to the existing horse animation assets: gait, trot, and reverse use the walk
track with speed scaling; gallop uses the run track. This avoids inventing
missing animation assets during the behavior port.

`GroundProbe` reuses one `RaycastParams` object per mounted client and samples
five ground rays plus two obstacle rays every `0.05` seconds. The old hot path
created five `RaycastParams` objects and ran ground work every rendered frame.

## Movement networking

Every mount input now includes a monotonically increasing sequence. The server
rejects missing, duplicate, and stale sequences, clamps input axes, validates
gait names, and remains responsible for jump cooldown and speed enforcement.
At `0.1` second intervals it acknowledges the latest processed input with the
observed signed assembly speed and server-classified gait. The client retains
up to 64 unacknowledged inputs. A speed correction is applied only when the
server actually rolls the assembly back after a validated speed violation;
ordinary constraint lag cannot silently change the rider's selected gait.

This is an incremental authoritative boundary rather than the final fixed-step
server simulation. Roblox network ownership remains on the rider for responsive
constraint physics, while the server observes speed, rolls back violations,
and can force a dismount. Position replay and full server simulation remain a
later hardening milestone.

## Rig contract

A mountable visual currently requires:

- one or more `BasePart` descendants;
- a `Model.PrimaryPart`, preferably the authored `RootPart`;
- authored joints or constraints connecting animated visual parts to that
  root;
- in the target contract, a semantic `RiderAnchor`, `RiderAttachment`, or
  `SaddleAttachment` tied to the animated back pose.

The rider anchor is optional only during the compatibility period. Missing
anchors emit the `MissingRiderAnchor` diagnostic and the existing rigid seat
offset remains active. The six current horse assets do not yet contain this
anchor, so the rider still follows the stable physics root rather than the
animated back in this milestone.

The adapter can resolve a named `HorseRoot` or `RootPart` when a legacy model
has no `PrimaryPart`, but records this fallback. New assets must provide a
`PrimaryPart` explicitly.

## Physics assembly

The old mount implementation welded the artificial root directly to every
horse `BasePart`, while existing `Motor6D` joints also connected those parts.
That produced closed rigid paths through the animated rig.

The current assembly has this ownership:

```text
HorseMountRoot
  -> HorseMountSeat
  -> authored horse RootPart
       -> authored Motor6Ds and constraints
```

Only a genuinely disconnected legacy part receives a compatibility weld to
the authored root. `Model.PrimaryPart` is no longer replaced by
`HorseMountRoot`, so model pivot semantics remain asset-owned through mount and
dismount.

## Transaction lifecycle

Every player can own at most one mount transaction:

```text
Preparing -> Mounting -> Mounted -> Dismounting -> finished
```

Each transaction has an identity token. A delayed task can only transition or
finish the entry when its token is still current, preventing stale mount and
dismount tasks from clearing a newer operation. Character replacement, player
removal, service destruction, and failed preparation cancel the relevant
transaction and restore acquired state.

An immediate mount request during a transition returns `MountBusy` with the
active phase. Repeated requests no longer create a second assembly during the
mount animation or while the previous horse is still being released.

## Validation

- Rojo build succeeds.
- Studio unit suite: 31 passed, 0 failed, including five mount-domain, seven
  deterministic movement-state, and two probe integration tests.
- Bootstrap integration succeeds.
- Live mount assembly retains the authored `RootPart` as `PrimaryPart`.
- Live `HorseMountRoot` contains only the seat and authored-root welds.
- Immediate remount during dismount is rejected, and remount succeeds after
  cleanup.
- Final dismount leaves no `HorseMountRoot` in the world.

## Remaining mount milestones

1. Author and validate an animated rider anchor for every horse asset, then
   drive rider and saddle presentation from that anchor without attaching
   gameplay physics directly to a `Bone`.
2. Replace observed-speed reconciliation with fixed-step server simulation and
   position snapshots if playtests show the remaining network-owner model is
   insufficient under hostile clients or high latency.
3. Establish one animation authority for horse and rider tracks.
4. Extract geometry, transition presentation, input protocol, and movement
   state from `HorseMountService` until the legacy orchestrator is removed.
5. Add integration coverage for every horse asset, avatar scale, death,
   disconnect, streaming, and network-latency case.
