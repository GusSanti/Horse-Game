# Stable Cleaning

## Gameplay

Each horse assigned to a stall receives persistent dirt records over time. Dirt is
rendered around that horse's `HorsePosition`, and every active record increases the
decay rate of specific horse needs.

| Dirt | Tool | Active penalty |
| --- | --- | --- |
| Loose Hay | Stable Broom | Happiness x1.15, Cleanliness x1.10 |
| Mud Patch | Cleaning Bucket | Cleanliness x1.30, Health x1.08 |
| Manure | Muck Fork | Cleanliness x1.35, Health x1.15 |

Bonuses and limits:

- A horse can have at most five dirt spots.
- Each cleaned spot restores 2 Cleanliness.
- Cleaning the final spot gives 5 Happiness.
- Every spot counts toward `Stats.TotalCleanActions`, so the existing stable-cleaning
  daily quest works without a separate quest.
- Tools are reusable and sold by the `Cowboy` shop.

## Studio setup

1. Sync the Rojo project so the new modules exist in Studio.
2. Open `scripts/GenerateStableCleaningAssets.commandbar.lua`.
3. Paste the entire file into the Studio Command Bar while not playing.
4. Confirm the preview under `Workspace.StableCleaningAssetPreview`.
5. Start Play mode and equip the matching tool near a dirt spot.

The command installs runtime tools under `ReplicatedStorage.Assets.Items.Misc` and
dirt templates under `ReplicatedStorage.Assets.StableCleaning.Dirt`.

Studio uses a 2-second initial delay and an 18-second spawn interval for fast tests.
Published servers use a 60-second initial delay and roughly six minutes between
spawns. All balancing and text live in
`ReplicatedStorage.Modules.GameData.StableCleaningConfig`.
