//=============================================================================
// Nightfall — Runes, levels, flasks, weapon rarity, rousing the downed,
//             and persistence between maps.
//=============================================================================

::NF.MAX_LEVEL <- 15;
// Cost to go from level i to i+1 (index = current level)
::NF.LevelCosts <- [0, 120, 260, 420, 600, 820, 1060, 1340, 1650, 2000, 2400, 2850, 3350, 3900, 4500];

::NF.HP_PER_LEVEL <- 7;
::NF.DMG_PER_LEVEL <- 0.04;

::NF.RuneValues <- {
	common = 8
	special = 50
	elite = 300
	witch = 250
	tank = 800
	fieldboss = 1500
}

//-----------------------------------------------------------------------------
// Stats
//-----------------------------------------------------------------------------
::NF.MaxFlasks <- function(st)
{
	return 3 + (st.level >= 6 ? 1 : 0) + (st.level >= 11 ? 1 : 0);
}

::NF.ApplyStats <- function(p, refill)
{
	if (!NF.Valid(p)) return;
	local st = NF.State(p);
	local c = NF.ClassOf(st);
	local base = c != null ? c.hp : 100;
	local mx = base + (st.level - 1) * NF.HP_PER_LEVEL;
	local oldMax = p.GetMaxHealth();
	p.SetMaxHealth(mx);
	if (!p.IsDead() && !p.IsIncapacitated())
	{
		local hp = p.GetHealth();
		if (refill) hp = mx;
		else if (mx > oldMax) hp += (mx - oldMax);
		if (hp > mx) hp = mx;
		if (hp < 1) hp = 1;
		p.SetHealth(hp);
	}
	st.lastSpeed = -1.0;
	NF.ApplyHeroModel(p);
}

::NF.UpdateSpeed <- function(p, st)
{
	local c = NF.ClassOf(st);
	local spd = c != null ? c.speed : 1.0;
	local hook = NF.Hook(c, "SpeedMult");
	if (hook != null) spd *= hook(p, st);
	if (NF.Omen != null && ("speed" in NF.Omen)) spd *= NF.Omen.speed;
	if (spd != st.lastSpeed)
	{
		NetProps.SetPropFloat(p, "m_flLaggedMovementValue", spd);
		st.lastSpeed = spd;
	}
}

//-----------------------------------------------------------------------------
// Runes & levels
//-----------------------------------------------------------------------------
::NF.GiveRunes <- function(p, amount)
{
	if (!NF.IsSurvivor(p)) return;
	local mult = 1.0;
	if (NF.Omen != null && ("runes" in NF.Omen)) mult = NF.Omen.runes;
	amount = (amount * mult).tointeger();
	local st = NF.State(p);
	st.runes += amount;
	// The party shares a quarter of every bounty
	local share = (amount / 4).tointeger();
	if (share > 0)
	{
		foreach (s in NF.AllSurvivors())
			if (s != p) NF.State(s).runes += share;
	}
}

::NF.GiveRunesAll <- function(amount)
{
	local mult = 1.0;
	if (NF.Omen != null && ("runes" in NF.Omen)) mult = NF.Omen.runes;
	foreach (s in NF.AllSurvivors())
		NF.State(s).runes += (amount * mult).tointeger();
}

::NF.AtGrace <- function()
{
	return !Director.HasAnySurvivorLeftSafeArea();
}

::NF.LevelUp <- function(p)
{
	local st = NF.State(p);
	if (!NF.AtGrace())
	{
		NF.Tell(p, "You can only level up at a {o}Site of Grace{d} (the saferoom, before the party leaves).");
		return;
	}
	local gained = 0;
	while (st.level < NF.MAX_LEVEL && st.runes >= NF.LevelCosts[st.level])
	{
		st.runes -= NF.LevelCosts[st.level];
		st.level++;
		gained++;
	}
	if (gained == 0)
	{
		if (st.level >= NF.MAX_LEVEL) NF.Tell(p, "You are at the maximum level.");
		else NF.Tell(p, "Not enough runes. Next level costs {o}" + NF.LevelCosts[st.level] + "{d} (you have " + st.runes + ").");
		return;
	}
	NF.ApplyStats(p, true);
	st.flask = NF.MaxFlasks(st);
	NF.Say(p.GetPlayerName() + " rests at Grace and reaches {o}level " + st.level + "{d}.");
}

//-----------------------------------------------------------------------------
// Flask of tears (replaces medkits / pills / adrenaline)
//-----------------------------------------------------------------------------
::NF.DrinkFlask <- function(p)
{
	local st = NF.State(p);
	if (p.IsIncapacitated()) return;
	if (NF.HasBuff(st, "flaskcd")) return;
	if (st.flask <= 0) { NF.Center(p, "Flask empty"); return; }
	local mx = p.GetMaxHealth();
	if (p.GetHealth() >= mx) { NF.Center(p, "Already at full health"); return; }
	st.flask--;
	NF.AddBuff(st, "flaskcd", 1.5);
	local pct = 0.45;
	if (NF.Omen != null && ("flask" in NF.Omen)) pct *= NF.Omen.flask;
	NF.Heal(p, (mx * pct).tointeger());
	// Drinking cleanses the bleed-out "temporary health" state
	try { NetProps.SetPropInt(p, "m_isGoingToDie", 0); } catch (e) {}
	NF.Center(p, "Flask: " + st.flask + " left");
}

//-----------------------------------------------------------------------------
// Rousing downed allies: hit them (shove, melee, bullets) to fill their gauge
//-----------------------------------------------------------------------------
::NF.AddReviveProgress <- function(victim, amount, reviver)
{
	if (!NF.Alive(victim) || !victim.IsIncapacitated() || victim.IsHangingFromLedge())
		return;
	local st = NF.State(victim);
	local mult = 1.0;
	if (NF.IsSurvivor(reviver))
	{
		local rst = NF.State(reviver);
		if (rst.cls == "gravecaller") mult = 2.0;
	}
	st.reviveProgress += amount * mult;
	st.lastReviveHit = Time();
	local pct = (st.reviveProgress * 100 / st.reviveNeeded).tointeger();
	if (pct > 100) pct = 100;
	if (NF.IsSurvivor(reviver))
		NF.Center(reviver, "Rousing " + victim.GetPlayerName() + ": " + pct + "%");
	NF.Center(victim, "Being roused: " + pct + "%");
	if (st.reviveProgress >= st.reviveNeeded)
		NF.Revive(victim, reviver, 0.35);
}

::NF.Revive <- function(p, reviver, hpPct)
{
	if (!NF.Alive(p) || !p.IsIncapacitated()) return;
	local st = NF.State(p);
	p.ReviveFromIncap();
	// Our gauge replaces black-and-white: the cost of going down is a bigger gauge next time
	try
	{
		NetProps.SetPropInt(p, "m_currentReviveCount", 0);
		NetProps.SetPropInt(p, "m_isGoingToDie", 0);
	}
	catch (e) {}
	local mx = p.GetMaxHealth();
	local hp = (mx * hpPct).tointeger();
	if (hp < 1) hp = 1;
	p.SetHealth(hp);
	p.SetHealthBuffer(0.0);
	st.reviveProgress = 0.0;
	NF.Invuln(p, 1.5);
	if (NF.IsSurvivor(reviver) && reviver != p)
	{
		NF.State(reviver).ult += 5;
		NF.Tell(reviver, "You roused " + p.GetPlayerName() + ".");
	}
}

::NF.OnIncapped <- function(p)
{
	local st = NF.State(p);
	st.reviveNeeded = 100.0 * (1.0 + 0.5 * st.downs);
	st.reviveProgress = 0.0;
	st.downs++;
	local c = NF.ClassOf(st);
	local hook = NF.Hook(c, "OnIncap");
	if (hook != null) hook(p, st);
	NF.Say(p.GetPlayerName() + " has fallen! {l}Strike them{d} (shove / melee / shoot) to rouse them.");
}

// Shoving a downed ally counts as a rousing blow
::NF.TryShoveRouse <- function(p)
{
	local eye = p.EyePosition();
	local fwd = p.EyeAngles().Forward();
	foreach (a in NF.Survivors())
	{
		if (a == p || !a.IsIncapacitated() || a.IsHangingFromLedge()) continue;
		local to = a.GetCenter() - eye;
		local d = to.Length();
		if (d > 130) continue;
		to.Norm();
		if (to.Dot(fwd) < 0.55) continue;
		NF.AddReviveProgress(a, 25, p);
		return true;
	}
	return false;
}

::NF.DecayRevive <- function()
{
	local now = Time();
	foreach (s in NF.Survivors())
	{
		if (!s.IsIncapacitated()) continue;
		local st = NF.State(s);
		if (st.reviveProgress > 0 && now - st.lastReviveHit > 3.0)
		{
			st.reviveProgress -= 4.0; // per second
			if (st.reviveProgress < 0) st.reviveProgress = 0.0;
		}
	}
}

//-----------------------------------------------------------------------------
// Death: lose a level, drop your runes where you fell
//-----------------------------------------------------------------------------
::NF.OnSurvivorDeath <- function(p)
{
	local st = NF.State(p);
	local lost = st.runes;
	if (lost > 0)
	{
		NF.Stains.append({ pos = p.GetOrigin(), amount = lost, key = NF.Key(p) });
		st.runes = 0;
	}
	if (st.level > 1) st.level--;
	NF.Say(p.GetPlayerName() + " has perished. They lose a level" + (lost > 0 ? " and drop {o}" + lost + " runes{d} where they fell." : "."));
}

::NF.CheckStains <- function()
{
	if (NF.Stains.len() == 0) return;
	local keep = [];
	foreach (s in NF.Stains)
	{
		local claimed = false;
		foreach (p in NF.Survivors())
		{
			if (NF.Key(p) != s.key || p.IsIncapacitated()) continue;
			if ((p.GetOrigin() - s.pos).Length() < 90)
			{
				NF.State(p).runes += s.amount;
				NF.Say(p.GetPlayerName() + " reclaims {o}" + s.amount + " runes{d}.");
				claimed = true;
				break;
			}
		}
		if (!claimed) keep.append(s);
	}
	NF.Stains = keep;
}

//-----------------------------------------------------------------------------
// Weapon rarity
//-----------------------------------------------------------------------------
::NF.Rarities <- [
	{ name = "Worn",        mult = 1.00, color = "{d}" },
	{ name = "Tempered",    mult = 1.10, color = "{l}" },
	{ name = "Runed",       mult = 1.22, color = "{o}" },
	{ name = "Nightforged", mult = 1.36, color = "{g}" },
	{ name = "Dusk-Blessed", mult = 1.55, color = "{g}" }
];

::NF.WeaponRarity <- {}   // entindex -> { r = rarity index, cls = weapon classname }

::NF.RollableWeapons <- {
	weapon_smg = 1, weapon_smg_silenced = 1, weapon_smg_mp5 = 1,
	weapon_pumpshotgun = 1, weapon_shotgun_chrome = 1, weapon_autoshotgun = 1, weapon_shotgun_spas = 1,
	weapon_rifle = 1, weapon_rifle_ak47 = 1, weapon_rifle_desert = 1, weapon_rifle_sg552 = 1, weapon_rifle_m60 = 1,
	weapon_hunting_rifle = 1, weapon_sniper_military = 1, weapon_sniper_awp = 1, weapon_sniper_scout = 1,
	weapon_pistol_magnum = 1, weapon_grenade_launcher = 1, weapon_melee = 1, weapon_chainsaw = 1
}

::NF.RollRarity <- function()
{
	// Later nights tilt the odds upward
	local d = NF.Day - 1;
	local w = [55 - d * 6, 27, 12 + d * 3, 5 + d * 2, 1 + d];
	if (w[0] < 15) w[0] = 15;
	local total = 0;
	foreach (x in w) total += x;
	local r = RandomInt(1, total);
	for (local i = 0; i < w.len(); i++)
	{
		r -= w[i];
		if (r <= 0) return i;
	}
	return 0;
}

::NF.PrettyWeapon <- function(cls)
{
	local s = cls;
	if (s.find("weapon_") == 0) s = s.slice(7);
	local parts = split(s, "_");
	local out = "";
	foreach (pt in parts)
	{
		if (out.len() > 0) out += " ";
		out += pt.slice(0, 1).toupper() + pt.slice(1);
	}
	return out;
}

::NF.RollInventory <- function(p)
{
	for (local i = 0; i < 48; i++)
	{
		local w = null;
		try { w = NetProps.GetPropEntityArray(p, "m_hMyWeapons", i); } catch (e) { break; }
		if (!NF.Valid(w)) continue;
		local cls = w.GetClassname();
		if (!(cls in NF.RollableWeapons)) continue;
		local idx = w.GetEntityIndex();
		// entity slots get reused: only trust an entry made for the same kind of weapon
		if ((idx in NF.WeaponRarity) && NF.WeaponRarity[idx].cls == cls) continue;
		local r = NF.RollRarity();
		NF.WeaponRarity[idx] <- { r = r, cls = cls };
		local rr = NF.Rarities[r];
		if (r >= 2)
			NF.Tell(p, "Picked up a " + rr.color + rr.name + " " + NF.PrettyWeapon(cls) + "{d} (+" + ((rr.mult - 1.0) * 100).tointeger() + "% damage)");
	}
}

::NF.RarityMult <- function(dt, attacker)
{
	local w = null;
	if (("Weapon" in dt) && NF.Valid(dt.Weapon)) w = dt.Weapon;
	else { try { w = attacker.GetActiveWeapon(); } catch (e) {} }
	if (!NF.Valid(w)) return 1.0;
	local idx = w.GetEntityIndex();
	if ((idx in NF.WeaponRarity) && NF.WeaponRarity[idx].cls == w.GetClassname())
		return NF.Rarities[NF.WeaponRarity[idx].r].mult;
	return 1.0;
}

//-----------------------------------------------------------------------------
// Persistence between maps (and to the start of a map after a wipe)
//-----------------------------------------------------------------------------
::NF.SaveRun <- function(nextDay)
{
	local t = { day = nextDay };
	foreach (k, st in NF.Players)
	{
		t["c" + k + "_cls"] <- st.cls == null ? "" : st.cls;
		t["c" + k + "_level"] <- st.level;
		t["c" + k + "_runes"] <- st.runes;
	}
	SaveTable("nightfall_run", t);
}

::NF.LoadRun <- function()
{
	// Cache what we restored: Init can run more than once per map load, and the saved
	// table may only be readable once.
	local root = getroottable();
	if (!("NF_RunCache" in root))
	{
		local loaded = {};
		RestoreTable("nightfall_run", loaded);
		root.NF_RunCache <- loaded;
	}
	local t = root.NF_RunCache;
	if (Director.IsFirstMapInScenario() || !("day" in t))
	{
		NF.Day = 1;
		return;
	}
	NF.Day = t.day;
	for (local k = 0; k < 8; k++)
	{
		if (!(("c" + k + "_level") in t)) continue;
		local st = NF.NewState();
		local cls = t["c" + k + "_cls"];
		st.cls = (cls == "" || !(cls in NF.Classes)) ? null : cls;
		st.level = t["c" + k + "_level"];
		st.runes = t["c" + k + "_runes"];
		st.flask = NF.MaxFlasks(st);
		NF.Players[k] <- st;
	}
}
