# UI Runtime

## Responsibilities

`Modules.Client.Hud.UIRuntime` owns UI discovery and lifecycle. It connects to
`PlayerGui.DescendantAdded` before scanning existing children, preventing a
replication race between the initial scan and event binding. Its Trove owns the
connection, and `Destroy` unbinds all `HudAnim` state before destroying the
router.

`UIRouter` owns state; `HudAnim` owns presentation:

```text
HUD button / feature request
  -> UIRouter.Open or Close
  -> close exclusive modal sibling without animation
  -> HudAnim adapter preserves the target's configured transition
  -> RuntimeEvents.ScreenOpened or ScreenClosed
```

All direct `GuiObject` children of `MainUI.MainframeFR.Frames` are registered in
the `Modal` layer. Modal routes are exclusive by default. Non-exclusive layers
are supported for later notifications and overlays.

## Compatibility behavior

- Existing button-to-frame naming (`InventoryBT` -> `Inventory`) is unchanged.
- `TargetFrame` and `CloseTarget` attributes remain supported.
- `UIOpen`, `open_anim`, blur, FOV, sounds, and HUD exclusions remain owned by
  `HudAnim` and retain their previous values.
- The upstream fade, stagger, punch, rotation, and easing presentation options
  remain available. They do not bypass `UIRouter` modal ownership.
- A legacy direct write to `Frame.Visible` calls `UIRouter.Sync`, so the router
  closes an exclusive sibling and reflects the externally caused state.
- Internal visibility changes during close/open animation are ignored by the
  sync listener to prevent feedback loops.
- Re-registering a replaced frame invalidates stale cleanup callbacks, so an
  old instance cannot unregister its replacement.

## Diagnostics

The `UIRouter` ModuleScript exposes local client attributes:

| Attribute | Meaning |
| --- | --- |
| `Initialized` | the real client UI runtime initialized the router |
| `RegisteredCount` | number of active routes |
| `OpenScreen` | currently open registered screen, or absent when all are closed |

The Studio execution tool uses a separate Luau VM and therefore a separate
`require` cache. Tests of the actual LocalScript runtime must inspect these
instance attributes or drive real input instead of requiring the router from
the executor and reading its private table.

## Tests

Unit tests cover modal exclusivity, non-exclusive layers, legacy visibility
synchronization, and stale cleanup. The connected-place smoke test registered
14 frames, opened and closed Inventory, opened and closed Settings, verified
only one modal was visible, and restored the initial closed state.

## Remaining work

`HudAnim` is still a compatibility module above the 500-line limit. It should
be split into route adapters, modal transitions, HUD fading, button effects,
and sound/blur helpers after representative visual snapshots are available.
Individual feature scripts also need lifecycle migration so they no longer
own untracked input, descendant, and render connections.
