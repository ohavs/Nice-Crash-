# Nice Crash! — GDD (short)

**Pitch:** Wobbly food-object characters (egg, toast, marshmallow) run obstacle courses. Crashing is the fun: slow-mo, "NICE CRASH! +score", shareable fails.

## Core
- Engine: Godot 4.6, Jolt physics, Mobile renderer, portrait. Android first; Google Play Games on PC later.
- View: top-back follow camera. Controls: floating joystick (right), JUMP + GRAB (left) by default; every control can be dragged anywhere and resized (70-140%) in Settings → Controls layout (saved to `user://settings.cfg`). The joystick base only slides ~30% of its radius towards the thumb.
- Pace: 1.5x gravity, with jump / fling / knock speeds scaled by sqrt(1.5): same arcs, ~20% quicker. Run 6.8 m/s, quick recovery after a crash.
- Character: RigidBody kept upright by a PD controller; hard impact (dv > threshold) or hazard hit → **crash** (full ragdoll, floppy limbs on pin joints) → auto-recover.
- GRAB: pin joint to whatever is in front (ledges, crates, later other players).

## Now
- 6 food skins: Eggbert (egg), Toasty (bread slice), Donny (donut), Nana (banana), Burgz, Cuppy. Egg, donut and banana are smooth
  hand-built meshes (`scripts/food_mesh.gd`: the kit's versions are 6-8 sided gems up close); the rest are Kenney Food Kit models.
  - Faces: googly eyes whose pupils slosh with every bump, blinking, brows + mouth by mood (happy / angry when grabbing or
    shoving / scared when flying / dizzy spinning pupils when crashed), blush.
  - Banana drops a peel when it crashes (60%): the next one to step on it slips and goes flying ("SLIP!"). Pops out of a fruit bowl.
  - Egg cracks on every crash (overlay textures), the 3rd crack bursts it: shell halves fly, a fried egg lands, a fresh egg pops out of an egg cup.
  - Toast pops out of a toaster (with a ding) on every (re)spawn and gets darker with each crash.
  - Everyone else pops off a plate.
- Countdown READY/SET/GO with everyone waiting in their spawner.
- Combat / friendly fire: ACT button = PUSH (shove), or use the held item; grab someone + ACT = YEET them.
  Throws wind up (lean back, item / victim hoisted overhead) then snap forward with a swoosh; hits pop comic words (POW!, YEET!, SPLAT!).
  Aim assist: holding something throwable, the nearest player within ~20 deg in front gets a lock-on marker (ring + arrow); the lock
  is sticky (holds to ~35 deg) and throws go to the target, items on a solved arc.
  Items from present boxes: tomatoes (throw x3), cookie blaster (shoot x5), watermelon (heavy throw), rolling pin (melee x3).
- Enemies: veggie brawlers (broccoli / eggplant / carrot / snowman) guard areas and bonk players; pirate cannons aim at the nearest player; rolling giant tomatoes / barrels; toy trains.
- Camera follows the level's route as it turns; drag the top half of the screen to look around (eases back while you run).

### Mode 1: ADVENTURE (the main mode) - a world of levels
- World map (`world_map.gd`): every level is an island in the sea dressed like its place, linked by stepping stones;
  your character hops between them. Levels unlock in order; best stars per level are saved.
- Before PLAY: 0-4 bots, WITH YOU (team: they never pick on you, wait up if ahead) or AGAINST YOU (race, place counts).
- Levels (`adventure.gd`, `Adventure.LEVELS`), each in a different place and bigger/harder than the last. Wide open
  ground (big land slabs, side islands, alternative routes: stepping stones vs bridge, ramp vs bounce pan, raft vs saw plank),
  the route turns 1-3 times. Coins to collect, checkpoints, a flag + chest goal.
  1. Sunny Meadow - rolling-pin sweepers, river stones / bridge, loaf pushers, ramp or frying-pan bounce, hammers.
  2. Mushroom Woods - weave between trunks, broccoli bully, saw log or raft, mushroom trampolines, rolling logs, crumbling planks, hammer bridge.
  3. Windmill Village - fountain square, market street (loaf pushers + rolling barrels), brawler plaza, the windmill wheel, crumbling planks, bounce climb.
  4. Kitchen Chaos - pizza turntable, toaster launchers, cleaver field, tomato avalanche, whisk, falling waffles, pan to the plate.
  5. Cannon Cove - plank bridges under cannon fire, raft or saw plank, brawler deck, barrel ramp, barrel-top hops, saw alley.
  6. Frosty Peaks - sweeper on ice (slippery), toy-train crossings, snowmen, snowy barrel slope, switchback climb, hammer bridge, summit jump.
- Stars: 1 = finish, 2 = 70% of the coins, 3 = 1st place (vs bots) or beat the par time (solo / team).

### Mode 2: PARTY - everyone vs everyone minigames (`party.gd`, `Party.GAMES`), 1-4 bots
- Waffle Drop (survival): two layers of tiles that drop when touched.
- Pizza Sumo (survival): a spinning pizza that keeps speeding up.
- Rolling Pin Jump (survival): two pins sweep a round island, faster and faster.
- Cannon Chaos (survival): four cannons fire at everyone on a sandy island.
- King of the Cheese (60 s): score while standing on the hill.
- Tomato Brawl (60 s): most bonks wins, presents everywhere.
- Results: standings with scores.

- Crash juice: slow-mo, shake, vibration, popup score; BONK popups when you knock someone over.

## Next
1. More world levels (graveyard, candy land...), more party games (tail-tag, team games), a multi-round party "show".
2. Monetization: rewarded ad (continue / double coins), skin shop, remove ads.
3. Clip saving of best crash (share to TikTok).
4. Async "ghost" races with friends via party code (Firebase). Real-time later.
5. Funny weapons (plunger, fish cannon), vehicles.

## Art rules
- Real models only, no primitive shapes for world/props: Kenney kits (CC0) under `assets/kenney/<kit>/`
  (food, furniture, nature, pirate, town, holiday, platformer, models = 3D platformer starter kit), Kenney skybox, Kenney sounds.
  `tools/fetch_assets.sh` copies them from the GitHub mirror (kenney.nl is blocked from the cloud sandbox).
- `Props` (`scripts/props.gd`) loads a model by id ("food/egg"), re-centres it and gives it the candy look
  (saturation lift, teal foliage pushed to green, toon shading). `Props.multi` batches backdrop copies into MultiMeshes.
- Primitives are fine only for character faces/limbs and the water shader.
- Look: not too bright - filmic tonemap at exposure 0.8, soft (not neon) greens in `Props.candy_mat`, MSAA 4x, soft shadows.
  Character bodies get smooth normals (`Props.smooth`). Menus render their 3D through `UI.world_view` at the screen's real
  resolution (a SubViewportContainer would render at the 720x1280 design size and look pixelated on phones).
- UI: "candy" buttons/panels drawn by `ChunkyStyle` (ink outline, bottom lip, two-tone body, gloss), palette + helpers in `scripts/ui.gd`, icons are SVGs in `assets/ui/` generated by `tools/gen_icons.py`.
- Backdrop (`scripts/scenery.gd`): Kenney skybox + themes built from models: meadow (river valley, cliffs, forests, tents, ships),
  kitchen (giant counters, appliances and food around a sea of tomato soup), pirate (rock islands, palms, ships, towers).
