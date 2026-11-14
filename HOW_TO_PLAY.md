# How to install and play Nightfall (the simple version)

You need **Left 4 Dead 2 on Steam** and a Windows PC. That's it.
You do **not** need Nightreign, Python, Blender or anything else for this guide.

---

## Part 1: Install (2 minutes)

1. **Download the mod.** On the GitHub page, click the green **Code** button, then
   **Download ZIP**.
2. **Unzip it.** Find the ZIP in your Downloads folder, right-click it and choose
   **Extract All**, then click **Extract**.
   Don't just double-click into the ZIP. It has to be extracted or nothing will work.
3. **Open the extracted folder** and keep opening folders until you see a file called
   **`INSTALL_MOD.bat`**.
4. **Double-click `INSTALL_MOD.bat`.**
   - If Windows shows a blue "Windows protected your PC" box, click **More info**, then
     **Run anyway**.
   - If it says it can't find Left 4 Dead 2: open Steam, right-click **Left 4 Dead 2**,
     choose **Manage → Browse local files**, copy the address from the top of the window that
     opens, paste it into the black window and press Enter.
5. Wait until it says **DONE**.

## Part 2: Turn on the console (one time only)

1. Start Left 4 Dead 2.
2. Go to **Options → Keyboard/Mouse**.
3. Set **Allow Developer Console** to **Enabled**.
4. Press the **`~`** key (top-left of the keyboard, under Esc). A grey box appears. That's the
   console.

## Part 3: Start the game

In the console, type this and press Enter:

```
map c1m1_hotel nightfall
```

The map loads and the mod is running. You'll see green **[Nightfall]** messages in the chat.

Want a different campaign? Swap the map name:

| Campaign | Type this |
|---|---|
| Dead Center | `map c1m1_hotel nightfall` |
| Dark Carnival | `map c2m1_highway nightfall` |
| Swamp Fever | `map c3m1_plankcountry nightfall` |
| Hard Rain | `map c4m1_milltown_a nightfall` |
| The Parish | `map c5m1_waterfront nightfall` |
| No Mercy | `map c8m1_apartment nightfall` |

## Part 4: Play with friends

1. **Everyone** installs the mod (Part 1).
2. **One person** (the host) starts the game with the console command in Part 3.
3. The host presses **Shift + Tab**, right-clicks each friend and chooses **Invite to Game**.

---

## Controls

| What | Keys |
|---|---|
| Use your skill | **Shift + Right Mouse** |
| Use your ultimate (when it says `Ult OK`) | **Shift + E** |
| Heal (you have no medkits, you have flasks) | **Shift + R** |
| Dodge | **tap Ctrl twice** |
| Revive a downed friend | **Shove or hit them** (yes, really) |

The camera is **third person** by default. Type `!1p` in chat for first person and `!3p` to go
back.

When an ability works you'll know: its name appears in the middle of the screen, the screen
flashes and a sound plays. If you only see "Skill ready in 5s" or "Ultimate 40%", it isn't ready.

**Want your own keys?** Open the console (`~`) and type any of these once. Change `q`, `f`, `h`,
`c` to whatever keys you like:

```
bind q "scripted_user_func skill"
bind f "scripted_user_func ult"
bind h "scripted_user_func flask"
bind c "scripted_user_func dodge"
bind v "scripted_user_func camera"
```

Type these in chat (press **Y**):

| Type | What it does |
|---|---|
| `!nfhelp` | shows the controls |
| `!classes` | lists the 8 classes |
| `!class ronin` | picks a class (only in the saferoom, before anyone leaves) |
| `!levelup` | spends your runes on levels (only in the saferoom) |
| `!stats` | shows your level and runes |
| `!tide off` | turns off the Tide if it's too hard |
| `!3p` / `!1p` | third-person / first-person camera |

**The one rule:** keep moving forward. The **Tide** follows you through the map and hurts
anyone it catches.

---

## It's not working

| Problem | Fix |
|---|---|
| Nothing happens when I press `~` | Do Part 2 again. On some keyboards the key is `` ` `` or `ö`/`ñ`. Still nothing? In Steam, right-click L4D2 → **Properties** → in **Launch Options** type `-console`. |
| "map not found" or nothing loads | Check the spelling. It's `c1m1_hotel` (letter c, number 1, letter m, number 1). |
| The map loads but it's normal L4D2 (no green [Nightfall] messages) | The mod isn't installed. Close the game, run `INSTALL_MOD.bat` again, and make sure it says DONE. Then restart the game. |
| `INSTALL_MOD.bat` says it can't find the "addon" folder | You ran it from inside the ZIP. Extract the ZIP first (Part 1, step 2). |
| The Shift keys don't do anything | Your walk key isn't Shift. Set your own keys with the `bind` lines above, or use the chat: `!skill`, `!ult`, `!flask`. |
| It's hard to aim in third person | Type `!1p` in chat. |
| Red error text in the console | Take a screenshot of it and send it to whoever gave you the mod. |

To uninstall, delete `nightfall.vpk` from
`Steam\steamapps\common\Left 4 Dead 2\left4dead2\addons`.
