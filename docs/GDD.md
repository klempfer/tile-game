# Tile-Capture Shooter — Game Design Document

> Authoritative spec for development. Engine: **Godot 4.7 stable**. Platform: **Windows PC**.
> Status: pre-implementation. Numbers marked *(TBD)* are intentionally open — see
> **§19 Open Questions**.

## 1. Vision & Pillars
A 1v1 (later 2v2) third-person shooter where maps are a capturable tile grid. Territory control —
not raw aim — is the main win pressure. Combat feels like a fighting game: cornering, knockdown,
wakeup, escaping pressure. Snowballing is intentional but **recoverable** via respawns, round
resets, and comeback mechanics.

- **Territory creates advantage.** More tiles = more movement, more build sites, easier corners.
- **Close-range combat.** Long range only harasses/zones; it doesn't secure easy kills.
- **Information warfare.** Detection limits what players see, making stealth viable.
- **Recoverable snowball.** Losing space constrains you, but death is a setback, not a reset.
- **Simple movement.** No movement tech should dominate fights.
- **Deterministic.** All randomness is seeded for future online play + replays.

## 2. Platform & Tech
- Godot 4.7 stable; Windows PC build.
- Keyboard + mouse default; **controller support required**.
- Renderer selectable in Config: Vulkan, Direct3D 12, Compatibility (OpenGL), Mobile.
- **Determinism is a hard requirement** (§18). No use of unseeded global RNG.
- Architected to add authoritative-server multiplayer + replays later without a rewrite
  (input/simulation separation).

## 3. Modes
- **1v1** at launch. **2v2** later.
- Multiplayer or single-player vs bots. **Initial target: single-player with bots** for testing.

## 4. Arena & Tile System
- Arena is a grid of equal squares ("tiles"), **5m × 5m**, each with a visible ground outline.
- **1v1 map: 45m × 100m = 9 tiles × 20 tiles**, perfectly packed.
- **Tile states:** Neutral, Captured by Team 1, Captured by Team 2 — each a distinct outline color.
- **Capture:** stand on a neutral tile for **5s** to capture it for your team. Stand on an
  enemy-captured tile for **5s** to revert it to neutral (then it can be recaptured by either team).
- **Contested:** if two opposing players stand on the same tile, capture progress **pauses** until
  one remains.
- **Death clears presence:** a dead player is immediately no longer "on" their tile.
- **Adjacency:** a tile sharing any of its 4 edges with a team's captured tile is "Adjacent to
  Team X". A tile can be adjacent to both teams at once.
- **Movement restriction:** a player may only enter tiles their team has **captured** or that are
  **adjacent** to their team's captured tiles. They are blocked from all other tiles.
- **Spawn tiles:** each player spawns in the **center of their single starting tile** (the middle
  tile of the 9 on their end). Starting tiles are pre-captured by that player's team and **cannot
  be captured or neutralized** by the opponent.
- **Comeback:** a player with **fewer than 5 captured tiles** captures tiles **twice as fast** (2.5s).

## 5. Character & Camera
- Player controls a humanoid in a 3D arena.
- Third-person camera starts **over the right shoulder** (Fortnite-style default).
- **Aiming (ADS)** zooms the camera in closer to the shoulder (Fortnite-style).

## 6. Movement
- WASD-style directional movement (forward/back/left/right).
- **Jump** and **Crouch**.
- **Sprint** (costs energy).
- **Dodge roll:** Dodge key + a direction; usable in the air too (costs energy).
- **Ledge climb:** after jumping, hold Jump to climb ledges.
- Movement is deliberately simple — no advanced movement tech should dominate.

## 7. Combat
- Weapons include **shotguns** and **revolvers**. Both **hitscan** and **projectile** weapons exist.
- **Fire** with the Fire key; firing consumes ammo for ammo-using weapons.
- **ADS:** two separately bindable inputs — **Toggle ADS** and **Hold ADS**.
- **Spread:** **none while aimed**; present while hip-firing. Modeled as a 3D cone from the muzzle;
  each shot lands at a random point on the cone's end face.
- **Recoil:** mild. Hip-fire spread is fairly low and **effective at close range (≤10m)**.
- **Damage falloff** over distance to encourage close range.
- **Modest headshot multiplier**, varying by weapon.
- **TTK ≈ 3s** for most weapons.
- Long range is for harassment/zoning, not easy kills.

## 8. Defense
- **Directional shield** (Shield key): blocks **all** damage coming from the direction the shield
  faces. Costs energy.

## 9. Health, Death, Respawn
- Players have **HP**; at 0 HP they die.
- After death, players **respawn after a delay** from their **unique per-player spawn point**.
- On respawn: **5s of invincibility**, which is **interrupted if the player fires**.

## 10. Energy
- Start with **200 energy**. Used by: sprint, dodge roll, shield, build.
- Running out of energy → **stunned for 2s**.

## 11. Detection (information mechanic)
- Enemies are **not rendered** on your screen until **detected**.
- Detection is **distance-based**, measured **center-of-body to center-of-body**, **not** dependent
  on line of sight.
- **Default detection range: 20m.** Entering an enemy's detection range detects you.
- **Firing** raises your detection range to **50m for 1s**.
- Detection is **shared team-wide**: if one teammate detects an enemy, the whole team sees them.
- **Lingering:** once you escape detection, you remain visible for **3s**; if uninterrupted, you
  become invisible to the enemy team again.
- **UI:** an element must show the player whether they are currently detected.
- **Outlines/health bars:** detected hostiles have a **red outline unaffected by shadows** + an
  overhead HP bar. Friendlies always show a **blue outline** + overhead HP bar.

## 12. Cards & Decks
- Players **build a deck** from the main menu out of a fixed set of programmed cards with varied
  effects.
- During a match, cards are **drawn randomly** from the deck as the match progresses.
- **Hand:** up to **5 cards**, **visible to both players** (yours and the opponent's).
- **Selection:** the first card is selected by default; **Swap Card** cycles to the next (wrapping
  from last back to first); **Use Card** plays the selected card.
- Example effects: "Buff gun damage by 10% for the rest of the round"; "Reduce detection range by
  50% for 20 seconds".

## 13. Structures
- Built via the **Build key**, which opens a **radial menu** to pick a structure.
- Buildable **only on tiles your team has captured** (not neutral, not enemy).
- Costs **energy** scaling with power; have **build times** scaling with power.
  - **Wall:** built instantly; blocks incoming fire / must be climbed over; energy **50**.
  - **Turret:** auto-fires at enemies entering range; build time **10s**.
  - **Lookout post:** climbable; while a player stands on top, all players' detection range becomes
    **50m**; energy **199**.
- **One structure per tile.** Building a new one on an occupied tile **destroys the old one** and
  starts the new build.
- Structures **do not block capture.** Enemies can still neutralize then capture a tile under your
  structure. **Structures persist** through neutralization/capture changes.
- Structures on **neutral** tiles are **inactive**; a structure **functions for the team that owns
  the tile**.

## 14. Scoring & Match Flow
- **Kills score points.** Reach **3 points** to win the **round**.
- Kills do not end the match; respawns make death a temporary setback/positional loss.
- After a round: **reset all tiles** to default and **reset players** to spawn as at match start;
  round winner goes **+1 round**.
- **First to 2 rounds wins the match.**
- Pacing target: match **5–15 min**, round **~5 min**.

## 15. HUD / UI
- **Bottom-left:** HP, with **energy** below it.
- **Bottom-right:** **ammo** for the selected weapon; **your hand** displayed above the ammo counter.
- **Top-left:** opponents' current hands (one player's hand below another's).
- **Lower-middle:** **capture progress bar** for the tile you're standing on.
- **Top-middle:** current kill score + round scores.
- **Detection indicator** (§11).

## 16. Menus
- **Main menu:** Play, Config, Exit.
- **Play:** choose mode (1v1 or 2v2); only **1v1 available** for now.
- **Config:**
  - Keybinds for **all** player actions.
  - Mouse sensitivity slider.
  - Zoom (ADS) sensitivity **multiplier** slider.
  - FOV slider.
  - **FPS cap slider (max 144, default 60).**
  - Show-FPS toggle.
  - Renderer select: Vulkan / D3D12 / Compatibility (OpenGL) / Mobile.

## 17. Default Keybinds
- Move: **WASD**
- Jump: **Space**
- Crouch: **Left Ctrl**
- Sprint: **Left Shift**
- ADS Toggle: **Right Mouse**
- ADS Hold: **unbound by default**
- Fire: **Left Mouse**
- Build: **B**
- Dodge roll: **X**
- Use card: **Q**
- Swap selected card: **E**

## 18. Determinism & Future-Proofing
- **All random elements must be deterministic** (seeded RNG) to enable future online play + replays.
- Separate **player input** from **simulation** so authoritative-server netcode can be layered in.
- **Ranked play with ELO** is a later-stage goal.

## 19. Open Questions (resolve with the user before/while building)
Numbers and systems the spec leaves unspecified. The first session should ask about these:
- **Combat tuning:** base HP value; per-weapon damage, fire rate, ammo capacity, reload behavior
  (is there reloading?); falloff curves (start/end distances, min damage); headshot multipliers per
  weapon; exact hip-fire cone angle; recoil pattern specifics.
- **Weapons & loadout:** how many weapons at launch; can players carry/switch multiple weapons
  ("selected weapon" implies more than one)? Is there weapon switching, and on what key?
- **Energy economy:** exact costs (sprint per second? dodge per use? shield per second? build per
  structure); **energy regeneration** rate/conditions (not specified).
- **Respawn:** exact respawn delay duration.
- **Cards:** draw cadence/trigger (timer? on event?); starting hand size; deck size limits; the full
  card list and each effect's exact numbers; what happens to unused cards / hand at round reset.
- **Detection:** UI form of the detection indicator; behavior when both ADS and lookout post modify
  detection; how outlines render when not detected.
- **Bots:** difficulty levels; behavior model (how do bots capture, fight, build, use cards?).
- **Structures:** full launch list beyond wall/turret/lookout; turret range/damage/fire rate;
  wall HP / can it be destroyed; lookout climb mechanic specifics.
- **Map:** exact spawn-tile row/column indexing for the 9×20 grid; any cover/obstacles or flat arena.
- **Controller:** default controller bindings and aim-assist policy.
- **Audio/visuals:** placeholder vs. real assets timeline (initial = placeholders).
- **Seed source:** where the deterministic seed comes from (per-match seed, exposed for replays?).
