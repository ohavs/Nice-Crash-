#!/usr/bin/env bash
# Copies the Kenney (CC0) models/sounds the game uses into assets/kenney/.
# Source: github.com/ETdoFresh/kenney.nl (mirror of the kenney.nl packs) and
# github.com/KenneyNL/Starter-Kit-3D-Platformer (skybox). kenney.nl itself is
# blocked from the cloud sandbox, GitHub is not.
# Usage: tools/fetch_assets.sh   (run from the repo root)
set -euo pipefail
ROOT=$(pwd)
SRC=${KENNEY_SRC:-/tmp/kenney-mirror}
if [ ! -d "$SRC/.git" ]; then
  git clone -q --filter=blob:none --no-checkout --depth 1 https://github.com/ETdoFresh/kenney.nl "$SRC"
fi
cd "$SRC"
git sparse-checkout set --no-cone \
  '/kenney_natureKit_2.1/Models/GLTF format/' '/foodKit_v1.2/Models/GLTF format/' \
  '/furniturekit_updated/Models/GLTF format/' '/kenney_piratekit_1.1/Models/glTF format/' \
  '/kenney_holidaypack/Models/GLTF format/' '/kenney_platformerkit/Models/GLTF format/' \
  '/fantasy-town-kit-1.0/Models/GLTF format/' '/minigolf-kit-2.0/Models/GLTF format/' \
  '/kenney_impactsounds/' '/kenney_digitalaudio/' '/kenney_rpgaudio/' '/kenney_voiceoverpack/' '/kenney_interfacesounds/'
git checkout -q

copy() { # copy <dest dir> <pack models dir> names...
  local dest="$ROOT/assets/kenney/$1" dir="$2"; shift 2
  mkdir -p "$dest"
  for n in "$@"; do
    if [ -f "$dir/$n.glb" ]; then cp "$dir/$n.glb" "$dest/"
    else cp "$dir/$n.gltf" "$dir/$n.bin" "$dest/"; fi
  done
}
copy food "foodKit_v1.2/Models/GLTF format" \
  egg eggHalf eggCooked eggCup bread loaf donutSprinkles cupcake burger tomato watermelon \
  pie fryingPan rollingPin cookingKnifeChopping meatTenderizer cuttingBoard plate pizza waffle \
  bottleKetchup cheese broccoli carrot eggplant pepper whisk croissant cookie sodaCan
copy furniture "furniturekit_updated/Models/GLTF format" \
  toaster kitchenFridgeLarge kitchenStove kitchenCabinet kitchenCabinetUpper kitchenSink \
  kitchenMicrowave kitchenCoffeeMachine kitchenBlender
copy nature "kenney_natureKit_2.1/Models/GLTF format" \
  tree_oak tree_default tree_detailed tree_fat tree_pineRoundA tree_pineRoundC tree_pineTallA \
  tree_palmTall tree_plateau rock_largeA rock_largeC rock_tallA rock_tallE cliff_block_rock \
  cliff_large_rock cliff_top_rock plant_bushLarge plant_bush flower_redA flower_yellowA \
  flower_purpleA mushroom_redGroup log stump_round tent_detailedOpen campfire_logs \
  fence_simple statue_obelisk grass_large
copy town "fantasy-town-kit-1.0/Models/GLTF format" windmill watermill stall stallRed treeHighRound rockLarge
copy pirate "kenney_piratekit_1.1/Models/glTF format" ship_light ship_dark cannon cannonBall tower palm_detailed_long formationLarge_rock chest
copy holiday "kenney_holidaypack/Models/GLTF format" present presentRound
copy platformer "kenney_platformerkit/Models/GLTF format" saw spikes blockHexagon crate barrel
mkdir -p "$ROOT/assets/kenney/sfx"
A=kenney_impactsounds/Audio
cp $A/impactPunch_heavy_000.ogg "$ROOT/assets/kenney/sfx/punch.ogg"
cp $A/impactPunch_medium_001.ogg "$ROOT/assets/kenney/sfx/punch2.ogg"
cp $A/impactGlass_light_002.ogg "$ROOT/assets/kenney/sfx/crack.ogg"
cp $A/impactGlass_medium_000.ogg "$ROOT/assets/kenney/sfx/crack_big.ogg"
cp $A/impactSoft_heavy_001.ogg "$ROOT/assets/kenney/sfx/splat.ogg"
cp $A/impactMetal_heavy_002.ogg "$ROOT/assets/kenney/sfx/clang.ogg"
cp $A/impactPlate_medium_000.ogg "$ROOT/assets/kenney/sfx/plate.ogg"
cp $A/impactWood_heavy_000.ogg "$ROOT/assets/kenney/sfx/bonk.ogg"
cp $A/impactBell_heavy_001.ogg "$ROOT/assets/kenney/sfx/ding.ogg"
cp kenney_rpgaudio/Audio/chop.ogg "$ROOT/assets/kenney/sfx/chop.ogg"
cp kenney_rpgaudio/Audio/metalPot1.ogg "$ROOT/assets/kenney/sfx/pot.ogg"
cp kenney_rpgaudio/Audio/creak1.ogg "$ROOT/assets/kenney/sfx/creak.ogg"
cp kenney_digitalaudio/Audio/laser4.ogg "$ROOT/assets/kenney/sfx/shoot.ogg"
cp kenney_digitalaudio/Audio/powerUp2.ogg "$ROOT/assets/kenney/sfx/powerup.ogg"
cp kenney_digitalaudio/Audio/phaseJump1.ogg "$ROOT/assets/kenney/sfx/boing.ogg"
cp kenney_digitalaudio/Audio/lowDown.ogg "$ROOT/assets/kenney/sfx/eliminated.ogg"
cp kenney_interfacesounds/Audio/pluck_001.ogg "$ROOT/assets/kenney/sfx/pop.ogg"
cp kenney_interfacesounds/Audio/drop_002.ogg "$ROOT/assets/kenney/sfx/throw.ogg"
V=kenney_voiceoverpack/Male
for v in ready set go congratulations you_win you_lose game_over final_round; do cp $V/$v.ogg "$ROOT/assets/kenney/sfx/vo_$v.ogg"; done
cp kenney_impactsounds/License.txt "$ROOT/assets/kenney/License.txt"
echo "done"
