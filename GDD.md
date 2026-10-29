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

### Mode 1: WORLD (open world, `adventure.gd`, `Adventure.LEVELS`) - the main mode
- World map (`world_map.gd`): every zone is an island in the sea dressed like its place, linked by stepping stones;
  your character hops between them. 2 stars in a zone open the next; best stars per zone are saved.
- Before PLAY: 0-4 bot buddies (they tag along, smash skeletons near you, catch up if left behind).
- Zones are big open valleys (~140 m across, `terrain.gd`: rolling height grid, vertex-coloured grass / dirt paths /
  sand / rock / snow, `ground.gdshader` with Quaternius' Perlin noise), ringed by mountains (or the sea, Cannon Cove).
  Rivers and lakes are hazards (fall in = lose a heart, back to the last camp). Dressed with the Quaternius Stylized
  Nature MegaKit (trees, bushes, grass, flowers, rocks: batched per 40 m chunk in MultiMeshes with visibility ranges),
  KayKit buildings / ruins / graveyard bits, Kenney extras.
- Health: 5 hearts. Skeleton swings, bolts and skulls, saws, hammers, spike traps (KayKit floor spikes), cannonballs,
  rolling barrels and water each cost a heart (team mates' shoves don't); 1.3 s of blinking invulnerability after.
  0 hearts = knocked out: back at the last camp healed. Camps (campfires) are checkpoints that heal; hearts to pick up.
- Enemies (`enemy.gd`): KayKit skeletons (animated: idle/walk/run/attack/hit/death/awaken): minion (blade), knight
  (axe + shield), archer (crossbow bolts, keeps its distance), mage (flying skulls), the Bone Chief (big, spin attack).
  They guard a home spot, some lie dormant in graves and get up when you come close. HIT (shove) = 1 damage, rolling
  pin 2, items 1-3, thrown friends 2 ("bowling"). Health bar over the head once hurt, bone burst when smashed.
- Three missions per zone = three stars, shown top left with progress; a compass under the HUD points at the nearest
  thing still to do; light beams mark them in the world:
  1. Green Valley - 6 golden eggs (pan bounce, lake island, behind ruins...), smash the skeleton camp, climb Lookout Hill
     (rolling barrels, a hammer).
  2. Mushroom Woods - light 4 lost lanterns (mushroom trampolines up a ledge, archers' den), defeat the Bone Chief,
     5 golden eggs (on giant mushrooms).
  3. Spooky Hollow (dusk) - light 5 jack-o'-lanterns, smash 10 skeletons rising from their graves, open the crypt
     (spike traps, mages).
  4. Cannon Cove (island) - jam 3 cannons, beat the skeleton crew, 5 golden eggs (end of the dock...).
  5. Frosty Peaks - climb to the summit (barrels), 5 golden eggs (frozen slippery lake), smash the skeleton outpost; toy trains.
- Camera: follows where you run (swings behind you, never when you run at it), drag the top half to turn it.

### Mode 2: PARTY - everyone vs everyone minigames (`party.gd`, `Party.GAMES`), 1-4 bots
- Waffle Drop (survival): two layers of tiles that drop when touched.
- Pizza Sumo (survival): a spinning pizza that keeps speeding up.
- Rolling Pin Jump (survival): two pins sweep a round island, faster and faster.
- Cannon Chaos (survival): four cannons fire at everyone on a sandy island.
- King of the Cheese (60 s): score while standing on the hill.
- Tomato Brawl (60 s): most bonks wins, presents everywhere.
- Rounds: 1 = a single game; more = a show of random games (no repeats of the last 3) with a leaderboard:
  10/8/6/5/4/3/2/1 points by place each round, the champion after the last.

### Mode 3: WITH FRIENDS (`lobby.gd`, `net.gd`)
- HOST / JOIN online (4-letter room code, through the relay in `server/`, address in Settings -> ONLINE SERVER or
  `Game.DEFAULT_RELAY`) or on the same Wi-Fi (the host's phone runs the relay; games are announced by UDP broadcast,
  or join by the host's IP). Up to 8 in a room; your name and character in the lobby, everyone on a little stage.
- The host picks PARTY (rounds + bots) or WORLD (a zone they've unlocked + buddies) and STARTs.
- Netcode: every phone simulates its own player and streams it 15x/s; the others are kinematic puppets (gliding to
  the latest state). Hits are judged by the attacker for shoves and by the target's owner for projectiles, and sent
  to the owner. The host runs bots, skeletons (streamed 10x/s), cannons and rollers (shots copied to everyone),
  scores, eliminations, round ends and missions; pickups / lanterns / goals are shared events.

- GRAB only shows on screen while there's something to grab (another player within 3.5 m, a crate).
- Crash juice: slow-mo (offline), shake, vibration, popup score; BONK popups when you knock someone over.

## Next
1. More zones (candy land...), more party games (tail-tag, team games), Quaternius monsters.
2. Monetization: rewarded ad (continue / double coins), skin shop, remove ads.
3. Clip saving of best crash (share to TikTok).
4. Matchmaking (quick play with strangers), rejoining a game in progress.
5. Funny weapons (plunger, fish cannon), vehicles.

## Art rules
- Real models only, no primitive shapes for world/props: Kenney kits (CC0) under `assets/kenney/<kit>/`
  (food, furniture, nature, pirate, town, holiday, platformer, models = 3D platformer starter kit), Kenney skybox, Kenney sounds,
  Kenney Game Icons + HUD hearts (`assets/kenney/icons`), Kenney particle textures (`assets/kenney/particles`);
  KayKit (CC0) under `assets/kaykit/` (skeletons, medieval buildings, halloween, dungeon); Quaternius Stylized Nature
  MegaKit (CC0) under `assets/quaternius/nature` (normal maps dropped, textures <= 1024 px by `tools/prep_assets.py`).
  `tools/fetch_assets.sh` copies them all from GitHub (kenney.nl / quaternius.com are blocked from the cloud sandbox).
- `Props` (`scripts/props.gd`) loads a model by id ("food/egg", "kaykit/halloween/crypt", "quaternius/nature/Pine_1"),
  re-centres it and gives it the candy look (saturation lift, teal foliage pushed to green, toon shading; Quaternius gets
  soft wrapped light instead). `Props.multi` batches copies into MultiMeshes (optional shadows / visibility range).
- Primitives are fine only for character faces/limbs and the water shader.
- Look: not too bright - filmic tonemap at exposure 0.8, soft (not neon) greens in `Props.candy_mat`, MSAA 4x, soft shadows.
  Character bodies get smooth normals (`Props.smooth`). Menus render their 3D through `UI.world_view` at the screen's real
  resolution (a SubViewportContainer would render at the 720x1280 design size and look pixelated on phones).
- UI: "candy" buttons/panels drawn by `ChunkyStyle` (ink outline, bottom lip, two-tone body, gloss), palette + helpers in `scripts/ui.gd`, icons are Kenney Game Icons (white PNG, mapped by name in `UI.ICONS`; inked on white buttons).
- Backdrop (`scripts/scenery.gd`): Kenney skybox + themes built from models: meadow (river valley, cliffs, forests, tents, ships),
  kitchen (giant counters, appliances and food around a sea of tomato soup), pirate (rock islands, palms, ships, towers).
