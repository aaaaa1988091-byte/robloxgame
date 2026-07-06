# Element Weavers: Chain Reaction

Roblox combat prototype scaffold for the **Aether Core** mode. The project is data-driven: element behavior is declared in `src/ReplicatedStorage/ElementDatabase.lua`, server scripts validate every gameplay request, and map interaction is expected to use `CollectionService` tags plus instance attributes.

## Project Layout

- `src/ReplicatedStorage/ElementDatabase.lua` — authoritative material, modifier, and combination database.
- `src/ReplicatedStorage/NetworkBootstrap.lua` — creates required remotes and prefab folders if missing.
- `src/ServerScriptService/SecuritySanitizer.server.lua` — validates absorb requests server-side.
- `src/ServerScriptService/WeaveManager.server.lua` — resolves weave casts, prefabs, and fizzle fallback.
- `src/ServerScriptService/MatchManager.server.lua` — runs 300-second Aether Core scoring and carrier debuffs.
- `src/StarterGui/HUD_ScreenGui.client.lua` — scale-based HUD scaffold for match state and current weave.

## Roblox Studio Setup

1. Sync or copy the `src` tree into a Roblox place.
2. Ensure absorbable map parts are tagged `Absorbable` and have an `ElementType` attribute like `Iron`, `Water`, or `Magma`.
3. Ensure the match core model/part is tagged `MatchCore`; optionally add `CarrierUserId` and `CarrierTeam` attributes at runtime from pickup code.
4. Add projectile prefabs under `ReplicatedStorage.Projectiles_Prefab` with names matching `ElementDatabase.Combinations[*].Prefab` for custom visuals.

## Deployment Guide

Use this checklist to move the prototype from this repository into a playable Roblox experience.

### 1. Create or open a Roblox place

- Open Roblox Studio and create a new place, or open the existing experience that will host Element Weavers.
- Save a local backup before importing scripts if the place already contains production content.
- Keep **Team Create** enabled only after the first import is verified, so collaborators do not overwrite the scaffold while it is being wired.

### 2. Import the source tree

You can deploy manually or through a sync tool.

#### Manual import

1. In Roblox Studio, create these containers if they do not already exist:
   - `ReplicatedStorage`
   - `ServerScriptService`
   - `StarterGui`
2. Create ModuleScript/Script/LocalScript instances that mirror the files in `src`:
   - `src/ReplicatedStorage/ElementDatabase.lua` → `ReplicatedStorage.ElementDatabase` as a **ModuleScript**.
   - `src/ReplicatedStorage/NetworkBootstrap.lua` → `ReplicatedStorage.NetworkBootstrap` as a **ModuleScript**.
   - `src/ServerScriptService/SecuritySanitizer.server.lua` → `ServerScriptService.SecuritySanitizer` as a **Script**.
   - `src/ServerScriptService/WeaveManager.server.lua` → `ServerScriptService.WeaveManager` as a **Script**.
   - `src/ServerScriptService/MatchManager.server.lua` → `ServerScriptService.MatchManager` as a **Script**.
   - `src/StarterGui/HUD_ScreenGui.client.lua` → `StarterGui.HUD_ScreenGui` as a **LocalScript**.
3. Copy each file's Lua source into the matching Roblox instance.
4. Press **Play** once. `NetworkBootstrap` should ensure `ReplicatedStorage.Network_Events` and `ReplicatedStorage.Projectiles_Prefab` exist at runtime.

#### Recommended Rojo workflow

This repository does not currently include a Rojo project file, but the `src` layout is compatible with one. If your team uses Rojo:

1. Add a `default.project.json` that maps `src/ReplicatedStorage`, `src/ServerScriptService`, and `src/StarterGui` to the same Roblox services.
2. Run `rojo serve` from this repository.
3. Connect Roblox Studio with the Rojo plugin.
4. Verify that the Studio Explorer tree matches the manual mapping above.

### 3. Configure the map

- Tag every absorbable map object with `CollectionService` tag `Absorbable`.
- Add an `ElementType` attribute to each absorbable part. The value must match a key in `ElementDatabase.Materials`, such as `Iron`, `Water`, `Magma`, or `Shadow`.
- Tag the match objective part/model with `CollectionService` tag `MatchCore`.
- Ensure the core is a `BasePart` or a `Model` with a `PrimaryPart`, because `MatchManager` reads and broadcasts the core position.
- Avoid generating the map from scripts at runtime; build the map in Studio and use tags/attributes for interaction data.

### 4. Add projectile prefabs and effects

- Put custom projectile models or parts in `ReplicatedStorage.Projectiles_Prefab`.
- Name each prefab exactly as referenced by `ElementDatabase.Combinations[*].Prefab`.
- Make each prefab a `BasePart` or a `Model` with a valid `PrimaryPart` so `WeaveManager` can position and launch it.
- Replace the placeholder fizzle sound ID in `WeaveManager.server.lua` with an approved Roblox audio asset before public release.

### 5. Test before publishing

Run these checks in Roblox Studio before publishing:

1. **Server/client boot:** press **Play** and confirm there are no red errors in Output.
2. **Absorb validation:** stand within 20 studs of a tagged part and call/trigger absorb; then repeat from farther away to confirm the server rejects it.
3. **Known combination:** set or acquire a valid left-hand element and right-hand modifier, then fire a weave and confirm the expected prefab or fallback projectile appears.
4. **Invalid combination:** fire an unsupported combination and confirm the fizzle effect appears instead of a damaging spell.
5. **Match scoring:** set the `CarrierUserId` and `CarrierTeam` attributes on the tagged core and confirm the matching team score increases by 1% per second.
6. **Mobile layout:** use Studio device emulation to verify the HUD remains readable because it uses scale-based sizing.

### 6. Publish to Roblox

1. In Studio, choose **File → Publish to Roblox** for a new experience, or **File → Publish to Roblox As...** if replacing an existing place.
2. Configure experience name, description, icon, thumbnails, age guidelines, and device support in Creator Hub.
3. Keep the first release private or friends-only until the validation checklist passes with multiple players.
4. Use **Test → Start** with at least two local clients to check server-authoritative behavior before opening the experience publicly.
5. After launch, watch the Developer Console and Creator Dashboard analytics for script errors, server memory, and player retention signals.

## Release Readiness Notes

- This is still a gameplay scaffold, not a finished live-service release.
- Pickup UX, BP flow, marketplace trading, battle pass rewards, monetization products, and polished projectile assets still need production implementation.
- Any Robux monetization must be configured through Roblox Creator Hub and reviewed against current Roblox policy before going live.
