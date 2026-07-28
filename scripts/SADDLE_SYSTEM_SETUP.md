# Saddle System

## Gameplay

Saddles are reusable `Tack` items sold by `TackShop`.

| Saddle | Price | Bonuses |
| --- | ---: | --- |
| Starter Saddle | 8 | Sprint Speed +0.75 |
| Western Saddle | 40 | Canter +0.75, Sprint +1.5, Acceleration +0.02 |
| English Saddle | 75 | Canter +1, Sprint +2.5, Acceleration +0.05, Race Affinity +0.03 |

Equip flow:

1. Hold a saddle Tool and approach an owned horse.
2. Use the `Equip` prompt.
3. The saddle leaves `Inventory.Tack` and is stored in
   `horse.Equipment.SaddleItemId`.
4. If another saddle was equipped, it is returned to `Inventory.Tack`.
5. No model is attached to the horse. The equipped saddle only changes movement
   stats.

`HorseEquipmentUtility.GetEffectiveMovement` applies the same values to local mount
prediction, authoritative mounted movement, and race summaries.

## Studio setup

1. Sync the Rojo project.
2. Paste all of `scripts/GenerateSaddleAssets.commandbar.lua` into the Studio
   Command Bar while not playing.
3. Check the editable models in `Workspace.SaddleAssetPreview`.
4. Runtime tools are installed in `ReplicatedStorage.Assets.Items.Tack`.
5. Ensure the tack seller model is named `Workspace.Npcs.TackShop`; the server adds
   its shop prompt automatically.
