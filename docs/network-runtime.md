# Network Runtime

## Contract and transport

`Modules.Network` is the single shared inventory of remote APIs.
`Modules.Libraries.Net` remains the transport adapter and owns the physical
instances under:

```text
ReplicatedStorage.Net
  Events
  Functions
```

On the server, requiring the contract materializes every declared remote.
`NetworkRuntime.Init` does this before any domain service starts. Client access
is lazy and waits only when a wrapper is first used.

The contract exposes a complete `Events`/`Functions` inventory and domain
aliases such as `Network.Admin` and `Network.Horse`. New code must use a domain
alias or add a clearly named contract entry; it must not instantiate remotes or
introduce another remote folder.

## Removed compatibility paths

The manually created `GameplayRemotes`, `ToolRemotes`, Admin, Horse Reveal, and
Stable Cleaning paths were removed. Their repository clients and handlers now
use the central contract. Obsolete remote-name fields and `NetworkConfig` were
removed after a repository-wide reference check.

Remote wire names already using `Net` were preserved. Existing call sites can
therefore move to `Modules.Network` incrementally without changing behavior.

## Ownership and cleanup

- Event listeners accept a Trove owner.
- `RemoteFunction:Respond` now accepts a Trove and only clears the callback if
  the same owner still holds it.
- Admin, horse request, commerce, and reveal handlers are lifecycle-owned.
- Commerce removes its ProfileStore message handler and receipt callback on
  destroy.

## Validation

The network unit test verifies that every declared event/function is created
with the expected Roblox class and that domain aliases resolve to the same
wrapper. A repository scan verifies there is no first-party manual
`RemoteEvent` or `RemoteFunction` construction outside the transport adapter.

## Remaining work

The transport does not yet enforce payload schemas, request sequencing, or
rate limits. Each gameplay boundary must gain explicit input validation and a
per-action throttle as its domain is migrated. Client-safe state projection is
the highest-priority network change because `DataUtilityGet` still exposes the
full profile.
