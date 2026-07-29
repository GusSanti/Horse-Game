# Saddle System

## Gameplay

Saddles are reusable `Tack` items sold by `Noob`. Old tack remains in `TackShop`.

| Saddle | Price | Bonuses |
| --- | ---: | --- |
| Starter Saddle | 8 | Sprint Speed +0.75 |
| Trail Saddle | 25 | Trot +0.5, Turn +0.04, Stamina +6 |
| Western Saddle | 40 | Canter +0.75, Sprint +1.5, Acceleration +0.02 |
| Endurance Saddle | 60 | Canter +0.75, Acceleration +0.04, Turn +0.04, Stamina +12 |
| English Saddle | 75 | Canter +1, Sprint +2.5, Acceleration +0.05, Race Affinity +0.03 |
| Racing Saddle | 110 | Canter +1.25, Sprint +3.5, Acceleration +0.08, Race Affinity +0.06 |
| Royal Saddle | 180 | Premium all-around movement, stamina, and race bonuses |

Equip flow:

1. Hold a saddle Tool and approach an owned horse.
2. Use the `Equip` prompt.
3. The saddle leaves `Inventory.Tack` and is stored in
   `horse.Equipment.SaddleItemId`.
4. If another saddle was equipped, it is returned to `Inventory.Tack`.
5. The matching 3D model is attached to the stable horse and moves with it while
   mounted.

`HorseEquipmentUtility.GetEffectiveMovement` applies the same values to local mount
prediction, authoritative mounted movement, and race summaries.

## Studio setup

The server now guarantees all runtime saddle Tools and mounted models before
inventory/shop services start. This prevents the colored-cube placeholder even
when the editable Studio assets have not been generated yet.

1. Sync the Rojo project and restart the Play session.
2. To keep editable assets in the place file, paste all of
   `scripts/GenerateSaddleAssets.commandbar.lua` into the Studio
   Command Bar while not playing.
3. Check the editable models in `Workspace.SaddleAssetPreview`.
4. Runtime tools are installed in `ReplicatedStorage.Assets.Items.Tack`.
5. Mounted saddle models are installed in
   `ReplicatedStorage.Assets.HorseEquipment.Saddles`.
6. For a custom horse-specific fit, add an Attachment named `SaddleAttachment`
   to the horse. Without one, the server calculates a position from its bounding
   box.
7. Ensure the new seller model is named `Workspace.Npcs.Noob`; the server adds
   its shop prompt automatically.
