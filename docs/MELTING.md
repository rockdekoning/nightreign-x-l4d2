# Melting Nightreign assets into L4D2

This is the "bring your own game" half of the mashup. The repo contains **no Nightreign files**.
`MELT.bat` reads models from **your own copy** of Nightreign, converts them into L4D2 models on
your PC, and installs them as a second addon (`nightfall_assets.vpk`). When the Nightfall mod
loads, it finds that addon automatically:

- survivors wear the hero of their class
- the finale Tank becomes the real Nightlord model
- elites, specials, Witches and commons take on Nightreign enemy models

Roles you haven't converted keep their normal L4D2 model, so you can convert a single character
and still have a working game.

> **Nightreign never needs to be running.** The converter only *reads* files from your unpacked
> game folder and never touches the game itself or its anti-cheat. Don't share the generated
> `nightfall_assets.vpk`: it contains converted copyrighted assets and is meant for your PC only.

---

## 1. Install the tools (one time)

| Tool | Why | Where |
|---|---|---|
| Python 3.10+ | runs the converter | python.org (tick "Add to PATH") |
| Pillow + NumPy *(optional)* | rebuilds normal maps properly | `pip install pillow numpy` |
| **An unpacker that supports Nightreign** | extracts the game's encrypted archives | e.g. UXM Selective Unpack or Smithbox. Use a build that supports your game version |
| **WitchyBND** | unpacks `.dcx` / `.bnd` / `.tpf` files | GitHub. Copy `oo2core_9_win64.dll` from your Nightreign folder next to `WitchyBND.exe` |
| **Blender** + **Blender Source Tools** | fits the model onto the L4D2 skeleton, exports SMD | blender.org + the Blender Source Tools add-on |
| **A FLVER importer add-on for Blender** | reads FromSoftware models | e.g. the Soulstruct Blender add-on. Put its import operator name in `flver_import_operator` |
| **texconv** | converts textures | Microsoft DirectXTex releases |
| **VTFEdit** (VTFCmd.exe) | makes Source textures | Nem's Tools |
| **Left 4 Dead 2 Authoring Tools** | `studiomdl.exe` compiles models | Steam → Library → Tools |
| **Crowbar** | decompiles the vanilla L4D2 models used as skeleton references | GitHub (ZeqMacaw) |

If you can't get a FLVER importer working, export the model to `.fbx` with Smithbox or a FLVER
editor and put the `.fbx` path in `assets.json` instead. The rest of the pipeline is the same.

## 2. Unpack Nightreign

Run your unpacker on the Nightreign install and point it at an output folder, for example
`C:\Games\NightreignUnpacked`. When it finishes, that folder should contain `chr\` and `parts\`.

## 3. Decompile the reference models

Converted models borrow each vanilla model's skeleton, animations, hitboxes and physics, which is
why they move and take damage properly in L4D2. In Crowbar, decompile the models named under
`reference` in `tools/assets.json` from your L4D2 VPKs (`left4dead2\pak01_dir.vpk`). Mirror the
model path under `tools\work\reference\`:

```
tools\work\reference\survivors\survivor_gambler\survivor_gambler.qc  (+ its .smd files)
tools\work\reference\infected\hulk\hulk.qc
...
```

You only need the references for roles you're actually converting.

## 4. Pick the models

```bash
python tools/melt.py scan
```

This lists every character archive. Open them in Smithbox's model viewer to see which ID is
which hero, boss or enemy. Then fill in the `source` lists in `tools/assets.json`:

```json
"hero_vanguard": { "source": ["chr/cXXXX.chrbnd.dcx"], "reference": "survivors/survivor_gambler.mdl", "rig": "humanoid", "scale": 1.0 },
"nightlord":     { "source": ["chr/cYYYY.chrbnd.dcx"], "reference": "infected/hulk.mdl", "rig": "humanoid", "scale": 1.2 }
```

A hero built from several part files (head, body, arms, legs) takes all of them in one list, and
they get merged into one model. Each file under `commons` becomes a separate common-infected
variant.

## 5. Melt

Double-click **`MELT.bat`**. The first run creates `tools\melt_config.json` and auto-detects
L4D2 and Blender. Fill in the remaining paths and run it again. It checks every tool, converts
each role, packs both addons and installs them into `left4dead2\addons\`. Then, in L4D2:

```
map c1m1_hotel nightfall
```

To rebuild only some roles, run `python tools/melt.py build hero_vanguard nightlord`. All tool
output goes to `tools\work\melt.log`.

---

## What converts well and what doesn't

The pipeline is automatic, but porting models between engines is never perfect:

- **Human-shaped characters** (the heroes, human enemies) convert best. The Blender stage scales
  the model to the L4D2 character's height, rotates each limb to line up with the L4D2 skeleton,
  bakes that pose in and moves the skin weights onto the matching bones. Expect small problems
  at the shoulders, hips and fingers. Fix those by hand in Blender if they bother you.
- **Non-human bosses** (most Nightlords) have skeletons with no L4D2 equivalent. With `"rig":
  "humanoid"` you get whatever bones match, and anything unrecognised falls back to `"rigid"`,
  where the model slides around stiffly as a statue. For good results, write a `bone_map` in
  `assets.json` (Nightreign bone name → L4D2 bone name) and set `"rig": "bone_map"`, or rig it
  onto the Tank skeleton by hand.
- **First-person arms** stay vanilla, because the viewmodel uses a separate model.
- **Textures:** albedo and normal maps convert. FromSoftware's metallic/roughness maps have no
  direct Source equivalent and are skipped. Materials with hair, fur or veils get alpha-testing.
  If the lighting looks inside-out, set `"flip_normal_green": true` in `melt_config.json`.
- **Common infected** use a complex skeleton with gore bodygroups. Swapped commons won't show
  dismemberment, and a badly converted model here is the most likely thing to cause visual
  glitches. Leave `commons` empty if you see problems.
- **Sounds and music** aren't converted yet.
