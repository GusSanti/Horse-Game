# Obstacle jump service

## World contract

Tag a `BasePart` or `Model` with the exact CollectionService tag `obstacle`.
The service automatically handles tags that exist at startup and tags added or
removed at runtime. No prompt, touch transmitter, or remote needs to be placed
inside the obstacle.

The shortest horizontal bounding-box dimension is treated as the direction of
travel through the obstacle. For unusual geometry, set the tagged instance's
`ObstacleAxis` attribute to `X` or `Z`. A tagged model should have a meaningful
`PrimaryPart` so its oriented bounding box follows the authored rotation.

## Rating model

The server starts an attempt when the existing authoritative mount service
accepts a jump and keeps looking for a nearby obstacle during the airborne
window. This handles early takeoff and a mount velocity that settles one or two
samples after the jump begins. Crossing the obstacle center plane completes the
clear; landing-state replication has a short grace window so a valid jump is
not dropped at the boundary.
The result combines:

- jump-apex timing over the obstacle: 35%;
- straightness through the obstacle: 30%;
- clearance from the obstacle's lateral edge: 15%;
- approach-to-landing speed retention: 20%.

Scores of 82 or higher are `Perfect`, scores from 55 through 81 are `Good`, and
lower scores are `Bad`. Tune detection distances in
`ReplicatedStorage.Modules.GameData.Horse.ObstacleConfig` and rating weights or
thresholds in `ReplicatedStorage.Modules.Game.Horse.Obstacle.Scoring`.

Only the server calculates the result. The client receives a rating and a
bounded numeric score, validates both, and displays a lazily-created, reused UI
indicator. Its Fredoka One type, brown rounded strokes, warm cream panel, and
pop/fade motion follow the inspected `MainUI` visual language.

## References

- [Roblox CollectionService](https://create.roblox.com/docs/reference/engine/classes/CollectionService)
- [Roblox Model bounding boxes](https://create.roblox.com/docs/reference/engine/classes/Model)
- [Roblox RunService](https://create.roblox.com/docs/reference/engine/classes/RunService)
- [Roblox UI animation](https://create.roblox.com/docs/ui/animation)
- [University of Georgia: Evaluating Common Equine Performance Classes](https://secure.caes.uga.edu/extension/publications/files/pdf/B%201401_2.PDF)
