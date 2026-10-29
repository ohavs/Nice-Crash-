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
  bottleKetchup cheese broccoli carrot eggplant pepper whisk croissant cookie sodaCan banana bowl
copy furniture "furniturekit_updated/Models/GLTF format" \
  toaster kitchenFridgeLarge kitchenStove kitchenCabinet kitchenCabinetUpper kitchenSink \
  kitchenMicrowave kitchenCoffeeMachine kitchenBlender
copy nature "kenney_natureKit_2.1/Models/GLTF format" \
  tree_oak tree_default tree_detailed tree_fat tree_pineRoundA tree_pineRoundC tree_pineTallA \
  tree_palmTall tree_plateau rock_largeA rock_largeC rock_tallA rock_tallE cliff_block_rock \
  cliff_large_rock cliff_top_rock plant_bushLarge plant_bush flower_redA flower_yellowA \
  flower_purpleA mushroom_redGroup log stump_round tent_detailedOpen campfire_logs \
  fence_simple statue_obelisk grass_large mushroom_redTall mushroom_tanTall mushroom_red log_large \
  stump_roundDetailed tree_oak_fall tree_default_fall tree_pineRoundB tree_pineDefaultA lily_large \
  canoe cliff_block_stone tree_palm crop_pumpkin rock_tallB plant_bushDetailed flower_redB
copy town "fantasy-town-kit-1.0/Models/GLTF format" windmill watermill stall stallRed treeHighRound rockLarge \
  fountainRound cart wheel lantern stallGreen
copy pirate "kenney_piratekit_1.1/Models/glTF format" ship_light ship_dark cannon cannonBall tower palm_detailed_long formationLarge_rock chest
copy holiday "kenney_holidaypack/Models/GLTF format" present presentRound treePineSnow treePineSnowRound \
  snowman snowmanFancy snowFort rockFormationLarge rockFormationMedium candyCane candyCaneMint \
  trainLocomotive trainWagon sled lightpost snowPatch
copy platformer "kenney_platformerkit/Models/GLTF format" saw spikes blockHexagon crate barrel \
  block blockLarge blockSnow blockSnowLarge blockCliff blockMoving bridge platform fence tree treeSnow \
  mushrooms coinGold jewel heart sign spikesLarge flowers button
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

# 2D: Kenney game icons (white), particle textures, HUD hearts
git sparse-checkout add '/gameicons/PNG/White/2x/' '/gameicons-expansion/PNG/White/2x/' \
  '/particlePack_1.1/PNG (Transparent)/' '/platformer-pack-redux-360-assets/PNG/HUD/'
git checkout -q
mkdir -p "$ROOT/assets/kenney/icons" "$ROOT/assets/kenney/particles"
I=gameicons/PNG/White/2x
for n in cross exclamation gear home import locked minus plus pause right left return star trophy \
    multiplayer massiveMultiplayer singleplayer target arrowUp fastForward leaderboardsComplex signal3 \
    exitLeft checkmark warning medal1 power; do cp $I/$n.png "$ROOT/assets/kenney/icons/"; done
for n in fightFist coin flag userRobot pointer key diamond; do cp gameicons-expansion/PNG/White/2x/$n.png "$ROOT/assets/kenney/icons/"; done
cp platformer-pack-redux-360-assets/PNG/HUD/hudHeart_full.png platformer-pack-redux-360-assets/PNG/HUD/hudHeart_empty.png "$ROOT/assets/kenney/icons/"
P="particlePack_1.1/PNG (Transparent)"
for n in scratch_01 star_07 star_06 light_02 smoke_04 circle_05 slash_02 magic_03 dirt_02; do cp "$P/$n.png" "$ROOT/assets/kenney/particles/"; done

# ---------------------------------------------------------------- KayKit + Quaternius (CC0)
# KayKit (Kay Lousberg): github.com/KayKit-Game-Assets. Quaternius: the Stylized
# Nature MegaKit (textures slimmed by tools/prep_assets.py), mirrored at github.com/tilakpatell/tilakverse-assets.
WORK=${PACKS_SRC:-/tmp/model-packs}
mkdir -p "$WORK"
pack() { # pack <git url> <dir> <sparse paths>...
  local url=$1 dir=$2; shift 2
  [ -d "$WORK/$dir/.git" ] || git clone -q --filter=blob:none --no-checkout --depth 1 "$url" "$WORK/$dir"
  (cd "$WORK/$dir" && git sparse-checkout set --no-cone "$@" && git checkout -q)
}
grab() { # grab <dest> <src dir> names...   (gltf+bin, or glb; plus the folder's textures)
  local dest="$ROOT/assets/$1" dir="$2"; shift 2
  mkdir -p "$dest"
  for n in "$@"; do
    if [ -f "$dir/$n.gltf" ]; then cp "$dir/$n.gltf" "$dir/$n.bin" "$dest/"
    elif [ -f "$dir/$n.gltf.glb" ]; then cp "$dir/$n.gltf.glb" "$dest/$n.glb"
    else cp "$dir/$n.glb" "$dest/"; fi
  done
  cp "$dir"/*.png "$dest/" 2>/dev/null || true
}
KK=https://github.com/KayKit-Game-Assets
pack $KK/KayKit-Medieval-Hexagon-Pack-1.0 hex '/addons/kaykit_medieval_hexagon_pack/Assets/gltf/buildings/' '/addons/kaykit_medieval_hexagon_pack/Assets/gltf/decoration/' '/LICENSE.txt'
H=$WORK/hex/addons/kaykit_medieval_hexagon_pack/Assets/gltf
mkdir -p "$ROOT/assets/kaykit/medieval"
for d in buildings/blue buildings/red buildings/neutral decoration/nature decoration/props; do cp "$H/$d"/*.gltf "$H/$d"/*.bin "$H/$d"/*.png "$ROOT/assets/kaykit/medieval/"; done
cp "$WORK/hex/LICENSE.txt" "$ROOT/assets/kaykit/LICENSE.txt"

pack $KK/KayKit-Halloween-Bits-1.0 halloween '/addons/kaykit_halloween_bits/Assets/gltf/'
mkdir -p "$ROOT/assets/kaykit/halloween"
cp "$WORK/halloween/addons/kaykit_halloween_bits/Assets/gltf"/* "$ROOT/assets/kaykit/halloween/"

pack $KK/KayKit-Dungeon-Remastered-1.0 dungeon '/addons/kaykit_dungeon_remastered/Assets/gltf/'
grab kaykit/dungeon "$WORK/dungeon/addons/kaykit_dungeon_remastered/Assets/gltf" \
  floor_tile_big_spikes chest chest_gold torch_lit barrel_large box_large crates_stacked column pillar \
  rubble_large stairs wall wall_broken wall_arched sword_shield coin coin_stack_large key banner_red \
  banner_patternA_red keg trunk_large_A floor_tile_large floor_tile_big_grate table_long_decorated_A

pack $KK/KayKit-Character-Pack-Skeletons-1.0 skeletons '/addons/kaykit_character_pack_skeletons/Assets/gltf/' \
  '/addons/kaykit_character_pack_skeletons/Characters/gltf/'
S=$WORK/skeletons/addons/kaykit_character_pack_skeletons
mkdir -p "$ROOT/assets/kaykit/skeletons"
for c in Minion Warrior Rogue Mage; do
  python3 -I "$ROOT/tools/prep_assets.py" trim-glb "$S/Characters/gltf/Skeleton_$c.glb" "$ROOT/assets/kaykit/skeletons/Skeleton_$c.glb" \
    Idle Walking_D_Skeletons Running_C 1H_Melee_Attack_Chop 2H_Melee_Attack_Spin Spellcast_Shoot \
    1H_Ranged_Shoot Hit_A Death_C_Skeletons Skeletons_Awaken_Standing Taunt Cheer
done
grab kaykit/skeletons "$S/Assets/gltf" Skeleton_Blade Skeleton_Axe Skeleton_Staff Skeleton_Crossbow Skeleton_Shield_Small_A Skeleton_Arrow

pack https://github.com/tilakpatell/tilakverse-assets quaternius '/quaternius/stylized-nature-megakit/glTF/'
grab quaternius/nature "$WORK/quaternius/quaternius/stylized-nature-megakit/glTF" \
  CommonTree_1 CommonTree_2 CommonTree_3 CommonTree_4 CommonTree_5 Pine_1 Pine_2 Pine_3 Pine_5 \
  Birch_1 Birch_3 GiantPine_1 GiantPine_3 DeadTree_1 DeadTree_2 DeadTree_3 TwistedTree_1 TwistedTree_3 \
  CherryBlossom_1 CherryBlossom_2 TallThick_1 Bush_Common Bush_Common_Flowers Bush_Large Bush_Long_1 \
  Fern_1 Fern_2 Flower_1_Group Flower_3_Group Flower_4_Group Flower_7_Group Grass_Common_Short \
  Grass_Common_Tall Grass_Wispy_Tall Grass_Wheat Clover_1 Mushroom_Common Mushroom_RedCap Mushroom_Laetiporus \
  Plant_1_Big Plant_7_Big Rock_Big_1 Rock_Big_2 Rock_Medium_1 Rock_Medium_2 Rock_Medium_3 \
  RockPath_Round_Wide RockPath_Square_Wide RockPath_Round_Small_1 Pebble_Round_1 Pebble_Round_3
python3 -I "$ROOT/tools/prep_assets.py" slim-gltf "$ROOT/assets/quaternius/nature"
python3 -I -c "from PIL import Image; im=Image.open('$WORK/quaternius/quaternius/stylized-nature-megakit/glTF/Noise_Perlin.png'); im.thumbnail((512,512)); im.save('$ROOT/assets/quaternius/noise_perlin.png')"
echo "done"
