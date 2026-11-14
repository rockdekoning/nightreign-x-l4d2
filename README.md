# Nightfall — Nightreign × Left 4 Dead 2

A "melty merge" of **Elden Ring Nightreign** and **Left 4 Dead 2**. You still play the L4D2
campaigns you know, with the same maps, saferooms, crescendos and finales, but the run plays like a
Nightreign expedition. You get hero classes with a passive, a skill and an ultimate. Kills earn
runes, and you level up at a Site of Grace. A Tide swallows the map behind you. You rouse
downed allies by hitting them, and a **Nightlord** waits at every finale.

The mashup has two halves:

1. **The mod** (`addon/`) carries all the gameplay. It's a VScript mutation that runs on every
   official campaign and most custom ones, and it works on its own with vanilla L4D2 models.
2. **The melt** (`MELT.bat` + `tools/`) is a Melty-style "bring your own game" converter. It reads
   character and enemy models from **your own Nightreign install**, converts them into L4D2
   models on your PC, and installs them as a second addon. When the mod loads, it detects that
   addon automatically: survivors wear their class's hero, the finale Tank becomes the Nightlord,
   and enemies take on Nightreign models. **No Nightreign files are stored in this repo**, and
   Nightreign never has to be running. See **[docs/MELTING.md](docs/MELTING.md)**.

---

## Install & play

**New here? Follow [HOW_TO_PLAY.md](HOW_TO_PLAY.md).** It's the step-by-step guide.

**Just the mod (vanilla L4D2 models):** download the repo as a ZIP, extract it, and
double-click **`INSTALL_MOD.bat`**. It finds Left 4 Dead 2, packs the mod and installs it. No
other tools are needed.

**With Nightreign models:** set up the tools in [docs/MELTING.md](docs/MELTING.md), then run
`MELT.bat`. It converts your Nightreign assets and installs both addons.

**By hand:**

1. Drag the `addon` folder onto `Left 4 Dead 2/bin/vpk.exe`. Rename the `addon.vpk` it creates
   to `nightfall.vpk` and move it into `Left 4 Dead 2/left4dead2/addons/`. (L4D2 only loads
   packed `.vpk` addons, so copying the loose folder into `addons` doesn't work.)
2. Launch L4D2 with the developer console enabled, then run:

   ```
   map c1m1_hotel nightfall
   ```

   Any campaign map works (`c2m1_highway`, `c8m1_apartment`, …). You can also run
   `mp_gamemode nightfall` before starting a lobby.

## Controls

| Action | Input | Chat fallback |
|---|---|---|
| Skill (cooldown) | **WALK + SHOVE** (Shift + Mouse 2) | `!skill` |
| Ultimate (charged by kills) | **WALK + USE** (Shift + E) | `!ult` |
| Flask of Tears (heal) | **WALK + RELOAD** (Shift + R) | `!flask` |
| Dodge roll (i-frames) | **double-tap CROUCH** | — |
| Rouse a downed ally | **Shove / melee / shoot them** | — |

Chat commands: `!nfhelp`, `!classes`, `!class <name>`, `!levelup`, `!stats`, `!tide on|off`, `!3p`, `!1p`.

The camera starts in third person (`NF.Config.ThirdPerson` in `nightfall.nut`). To use your own
keys, bind them in the console, for example `bind q "scripted_user_func skill"`. The same works
for `ult`, `flask`, `dodge` and `camera`.

---

## How the two games merge

| Nightreign | In Nightfall (L4D2) |
|---|---|
| Choose a Nightfarer | Choose one of **8 hero classes**. Each has HP, speed, a passive, a skill and an ultimate. Bots get classes too and use their abilities. |
| Runes & levelling at Sites of Grace | Kills give **runes** (the party gets a 25% share of each kill). Spend them with `!levelup` in the **saferoom before anyone leaves**. Each level adds +7 max HP and +4% damage, and you get extra flasks at levels 6 and 11. Max level is 15. |
| Day 1 → Day 2 → Night 3 Nightlord | Each map is a **Night**. Your progress carries across the campaign. The **finale's first Tank is the Nightlord**: it has a huge health pool, a boss bar, and a second phase at 50% HP that summons a horde and an elite. |
| The Night's rain / closing circle | **The Tide** moves along the map's flow, from just behind the saferoom toward the exit, over about 10 minutes. If you fall behind it, you take damage that grows the longer you stay. It stops when the finale starts. |
| Field bosses & evergaols | **Night Raids** start at 33% and 70% progress. Each one sends gold-glowing **elites** (special infected with several times their normal HP) with a bounty. At 55% progress there is a chance of an orange **Field Boss** Tank, and its bounty goes to the whole party. |
| Shifting Earth / night modifiers | Each Night rolls an **Omen**: Blood Moon, Ashen Horde, Night of Stalkers, Gloom, Swift Tide, or a calm Starlit Night. |
| Revive by striking downed allies | Downed survivors have a **rousing gauge** that you fill by shoving, slashing or shooting them. Friendly fire on a downed ally heals instead of hurting. The gauge gets bigger each time you go down in a Night, and it **replaces black-and-white death**. Hold-E revive still works but takes 8 seconds. |
| Death costs a level, runes drop | If you die, you **lose a level** and drop your runes where you fell. Get back to that spot after a rescue closet or defib to pick them up again. |
| Flask of Crimson Tears | **Medkits, pills and adrenaline are removed.** Everyone carries 3 or more flask charges. Each charge heals 45% of max HP, and the flasks refill every Night and on level-up. |
| Weapon rarity | Weapons and melees roll a **rarity** when you pick them up: Worn, Tempered, Runed, Nightforged or Dusk-Blessed, up to +55% damage. Better rarities get more common on later Nights. |
| Dodge roll | Double-tap crouch to dash and get brief invulnerability. |

### Hero classes

Every class is built to fill one of the Nightreign roles. The names are original, and so are some
of the exact kits.

| Class | Role | Passive | Skill (WALK+SHOVE) | Ultimate (WALK+USE) |
|---|---|---|---|---|
| **Vanguard** | All-rounder | *Second Wind*: gets up on their own once per Night | *Grapple Lunge*: leaps to the aimed point and smashes it | *Onslaught*: huge shockwave around you |
| **Bulwark** | Shield tank | *Steel Hide*: 15% damage reduction, 45% while crouched | *Whirlwind Guard*: staggers nearby enemies and gives 80% damage reduction for 3s | *Aegis Descent*: raises downed allies, and nearby allies are invulnerable for 5s |
| **Hawkeye** | Marksman | *Keen Eye*: +30% damage at range, and specials glow for the whole team | *Marking Shot*: marked target takes +50% damage | *Volley*: hits every special and witch in line of sight |
| **Shade** | Assassin | *Ghost Step*: faster dodges, and kills give a speed burst | *Restage*: repeats the last 4s of team damage | *Veil*: allies fade from view and take 70% less damage |
| **Berserker** | Bruiser | *Bloodrush*: up to +50% damage at low HP, and +25% melee damage | *Earthshaker*: frontal ground slam | *War Totem*: damage + regen aura for 12s |
| **Weaver** | Caster | *Soul Siphon*: kills heal you, and your ultimate charges faster | *Mending Rite*: heals nearby allies and rouses downed ones | *Cataclysm*: delayed blast at the aimed point |
| **Ronin** | Duelist | *Parry*: shoving just before a hit cancels it | *Iai Stance*: double melee damage for 4s | *Beast Unbound*: speed, damage, damage reduction and lifesteal for 10s |
| **Gravecaller** | Summoner | *Familiar*: a spirit keeps striking nearby enemies | *Requiem*: instantly raises a downed ally | *Danse Macabre*: the familiar hits 3 targets, much harder |

### Enemies

Without custom models, the L4D2 infected play Nightreign's enemy roles:

- **Commons** are the field mobs, worth a few runes each.
- **Special infected** are the roaming named enemies. **Elites** glow gold.
- **Witches** are the optional high-risk targets with a big bounty.
- **Tanks** are the field bosses (orange glow, party bounty). The finale Tank becomes the
  **Nightlord** (purple glow, boss bar, enrages in phase 2).

---

## Code layout

```
addon/
├── addoninfo.txt
├── modes/nightfall.txt                    # mutation definition (base: coop)
└── scripts/vscripts/
    ├── nightfall.nut                      # mode script: director options, callbacks, events, config
    └── nightfall/
        ├── nf_util.nut                    # shared state, helpers, timers
        ├── nf_classes.nut                 # the 8 hero classes (data-driven; easy to add more)
        ├── nf_progression.nut             # runes, levels, flasks, rarity, rousing, persistence
        ├── nf_night.nut                   # Tide, Omens, raids, elites, field bosses, Nightlord
        ├── nf_hud.nut                     # party/Tide/boss HUD
        ├── nf_assets.nut                  # detects the melted asset pack and swaps models
        ├── nf_fx.nut                      # third-person camera, ability feedback, key binds
        └── nf_core.nut                    # think loop, input, damage pipeline, chat, bot AI

INSTALL_MOD.bat                            # one-click: install just the mod
HOW_TO_PLAY.md                             # simple install and play guide
MELT.bat                                   # one-click: check tools, convert, install
docs/MELTING.md                            # setup guide for the asset converter
tools/
├── melt.py                                # converter: unpack -> Blender -> textures -> studiomdl -> VPK
├── blender/flver_to_smd.py                # fits Nightreign meshes onto L4D2 skeletons
├── assets.json                            # which Nightreign model becomes which L4D2 role
└── melt_config.example.json               # tool paths (copy to melt_config.json)
```

Tuning: `NF.Config.TideMinutes` and `TideMaxPercent` in `nightfall.nut`. Class numbers live in each class table in
`nf_classes.nut`. Rune values and level costs are at the top of `nf_progression.nut`.

## Status / known caveats

- **The asset converter hasn't been run against real game files yet.** It was written without
  access to Windows, Nightreign or the Source SDK tools. The repo-side logic is unit-tested, but
  the Blender, WitchyBND and studiomdl stages will need a shakedown on a real PC. Check
  `tools/work/melt.log` when a role fails.
- **Not playtested in-game yet.** It was written against the documented L4D2 VScript API, but I
  had no way to run L4D2 while building it. If something breaks, open the console and look for
  lines starting with `[Nightfall]`. Script errors also show up there.
- The Tide uses the map's flow percentage. On maps with odd nav flow, or long crescendo holdouts,
  it can feel harsh. Use `!tide off` or raise `TideMinutes`.
- The HUD is shared by all players (that is a limit of vanilla VScript). Your personal feedback,
  such as cooldowns, rousing progress and parries, shows up as center-screen text.
- Movement abilities use velocity impulses, so how they feel can depend on the map and on server
  tickrate.
