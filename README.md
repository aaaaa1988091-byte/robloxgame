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
