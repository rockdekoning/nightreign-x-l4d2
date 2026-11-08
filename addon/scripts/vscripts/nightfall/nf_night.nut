//=============================================================================
// Nightfall — The Night: the closing Tide, Omens, raids, field bosses and
//             the Nightlord.
//
// Nightreign's shrinking storm circle becomes "the Tide": a wall of night
// that advances along the map's flow from the saferoom toward the exit.
// Anyone caught behind it burns. Linear campaigns, same pressure.
//=============================================================================

::NF.Tide <- {
	active = false
	paused = false
	disabled = false
	startTime = 0.0
	pct = -15.0
	lastTick = 0.0
	warned = {}
}

::NF.Raids <- { r1 = false, r2 = false, boss = false }

// Each night rolls one Omen
::NF.Omens <- [
	{
		id = "clear", name = "Starlit Night"
		desc = "A rare calm. Runes +25%."
		runes = 1.25
	},
	{
		id = "bloodmoon", name = "Blood Moon"
		desc = "Tanks have +50% health. Special infected hit 20% harder."
		tankHP = 1.5, specialDmg = 1.2
	},
	{
		id = "horde", name = "Ashen Horde"
		desc = "The dead come in far greater numbers. Runes +15%."
		runes = 1.15
		options = { CommonLimit = 45, MobSpawnSize = 35, MobMaxSize = 45 }
	},
	{
		id = "stalkers", name = "Night of Stalkers"
		desc = "Special infected return faster and in larger packs."
		options = { MaxSpecials = 6, SpecialRespawnInterval = 12, DominatorLimit = 4 }
	},
	{
		id = "gloom", name = "Gloom"
		desc = "Flasks heal 30% less, but runes are worth 50% more."
		flask = 0.7, runes = 1.5
	},
	{
		id = "swift", name = "Swift Tide"
		desc = "The Tide advances a third faster, but you move 8% faster."
		tideSpeed = 1.33, speed = 1.08
	}
];

::NF.NightlordNames <- [
	"Gravemaw, Hunger of the Dusk",
	"The Hollow Sovereign",
	"Vessel of the Long Night",
	"Ashveil, Who Swallows Light",
	"The Twice-Drowned King"
];

::NF.FieldBossNames <- [
	"Ruin-Hulk of the Old Road",
	"Bellwether of Rot",
	"The Weeping Colossus",
	"Cindergut",
	"Marrow Tyrant"
];

//-----------------------------------------------------------------------------
// Omens
//-----------------------------------------------------------------------------
::NF.RollOmen <- function()
{
	local o = NF.Omens[RandomInt(0, NF.Omens.len() - 1)];
	if (NF.Day == 1 && o.id == "bloodmoon") o = NF.Omens[0]; // be gentle on night one
	NF.Omen = o;
	if ("options" in o)
	{
		foreach (k, v in o.options)
			SessionOptions[k] <- v;
	}
}

//-----------------------------------------------------------------------------
// Tide
//-----------------------------------------------------------------------------
::NF.TideRate <- function()
{
	// percent of map flow per second
	local mins = NF.Config.TideMinutes;
	local r = 115.0 / (mins * 60.0);
	if (NF.Omen != null && ("tideSpeed" in NF.Omen)) r *= NF.Omen.tideSpeed;
	return r;
}

::NF.SurvivorFlow <- function(p)
{
	return GetFlowPercentForPosition(p.GetOrigin(), false);
}

::NF.UpdateTide <- function()
{
	local T = NF.Tide;
	if (T.disabled) return;
	if (!T.active)
	{
		if (Director.HasAnySurvivorLeftSafeArea())
		{
			T.active = true;
			T.startTime = Time();
			T.lastTick = Time();
			NF.Say("The \x05Tide\x01 begins to rise behind you. Keep moving.");
		}
		return;
	}
	if (T.paused) return;

	local now = Time();
	local dt = now - T.lastTick;
	if (dt < 1.0) return;
	T.lastTick = now;

	T.pct += NF.TideRate() * dt;
	if (T.pct > 100.0) T.pct = 100.0;

	foreach (s in NF.Survivors())
	{
		local st = NF.State(s);
		local flow = NF.SurvivorFlow(s);
		local gap = flow - T.pct;
		if (gap < 0)
		{
			if (st.behindSince == 0.0) st.behindSince = now;
			if (s.IsIncapacitated()) continue;
			local secs = now - st.behindSince;
			local dmg = 2 + (secs / 4).tointeger();
			if (dmg > 10) dmg = 10;
			NF.TideDamageActive = true;
			try { s.TakeDamage(dmg.tofloat(), NF.DMG.GENERIC, NF.World); } catch (e) {}
			NF.TideDamageActive = false;
			NF.Center(s, "The Tide consumes you! Move forward!");
		}
		else
		{
			st.behindSince = 0.0;
			if (gap < 8 && !s.IsIncapacitated())
				NF.Center(s, "The Tide is close behind...");
		}
	}
}

//-----------------------------------------------------------------------------
// Raids and field bosses, triggered by the party's progress
//-----------------------------------------------------------------------------
::NF.LeadFlow <- function()
{
	local best = 0.0;
	foreach (s in NF.Survivors())
	{
		local f = NF.SurvivorFlow(s);
		if (f > best) best = f;
	}
	return best;
}

::NF.SpawnElite <- function()
{
	local t = RandomInt(1, 6);
	NF.PendingElites++;
	try { ZSpawn({ type = t }); } catch (e) { NF.PendingElites--; }
}

::NF.CheckRaids <- function()
{
	if (!NF.Tide.active || NF.Tide.paused) return;
	local lead = NF.LeadFlow();
	if (!NF.Raids.r1 && lead >= 33)
	{
		NF.Raids.r1 = true;
		NF.Say("\x05Night Raid!\x01 An elite hunts the party — slay it for a bounty.");
		NF.SpawnElite();
		try { Director.ForcePanicEvent(); } catch (e) {}
	}
	if (!NF.Raids.boss && lead >= 55)
	{
		NF.Raids.boss = true;
		local chance = 40 + NF.Day * 10;
		if (RandomInt(1, 100) <= chance && !NF.AnyTankAlive())
		{
			NF.PendingBoss = { kind = "field", name = NF.FieldBossNames[RandomInt(0, NF.FieldBossNames.len() - 1)] };
			try { ZSpawn({ type = 8 }); } catch (e) { NF.PendingBoss = null; }
		}
	}
	if (!NF.Raids.r2 && lead >= 70)
	{
		NF.Raids.r2 = true;
		NF.Say("\x05Night Raid!\x01 Two elites close in.");
		NF.SpawnElite();
		NF.SpawnElite();
	}
}

::NF.AnyTankAlive <- function()
{
	foreach (s in NF.Specials())
		if (s.GetZombieType() == 8) return true;
	return false;
}

//-----------------------------------------------------------------------------
// Spawns: elites, field bosses, Nightlord
//-----------------------------------------------------------------------------
::NF.OnInfectedSpawn <- function(p)
{
	local zt = p.GetZombieType();
	if (zt == 8) return; // handled by tank_spawn
	if (NF.PendingElites > 0)
	{
		NF.PendingElites--;
		NF.After(0.2, function() {
			if (!NF.Alive(p)) return;
			local hp = p.GetMaxHealth() * (3 + NF.Day);
			p.SetMaxHealth(hp);
			p.SetHealth(hp);
			NF.SetGlow(p, 255, 200, 40);
			NF.Bosses[p.GetEntityIndex()] <- { kind = "elite", name = "Elite", phase = 1 };
		});
	}
}

::NF.OnTankSpawn <- function(p)
{
	local survivors = NF.Survivors().len();
	if (survivors < 1) survivors = 1;
	local kind = "tank";
	local name = "Tank";
	local mult = 1.0 + 0.15 * (NF.Day - 1);

	if (NF.NightlordPending)
	{
		NF.NightlordPending = false;
		kind = "nightlord";
		name = NF.NightlordNames[RandomInt(0, NF.NightlordNames.len() - 1)];
		mult = 1.6 + 0.25 * survivors + 0.1 * NF.Day;
	}
	else if (NF.PendingBoss != null)
	{
		kind = "field";
		name = NF.PendingBoss.name;
		NF.PendingBoss = null;
		mult *= 1.4;
	}
	if (NF.Omen != null && ("tankHP" in NF.Omen)) mult *= NF.Omen.tankHP;

	NF.After(0.25, function() {
		if (!NF.Alive(p)) return;
		local hp = (p.GetMaxHealth() * mult).tointeger();
		p.SetMaxHealth(hp);
		p.SetHealth(hp);
		NF.Bosses[p.GetEntityIndex()] <- { kind = kind, name = name, phase = 1, maxhp = hp };
		if (kind == "nightlord")
		{
			NF.SetGlow(p, 170, 60, 255);
			NF.CenterAll("NIGHTLORD: " + name.toupper());
			NF.Say("\x04" + name + "\x01 descends. End the night.");
		}
		else if (kind == "field")
		{
			NF.SetGlow(p, 255, 120, 0);
			NF.Say("Field Boss: \x05" + name + "\x01 blocks the road. Bounty for the whole party.");
		}
	});
}

::NF.UpdateBosses <- function()
{
	local dead = [];
	foreach (idx, b in NF.Bosses)
	{
		local e = EntIndexToHScript(idx);
		if (!NF.Alive(e)) { dead.append(idx); continue; }
		if (b.kind == "nightlord" && b.phase == 1 && e.GetHealth() < b.maxhp / 2)
		{
			b.phase = 2;
			NetProps.SetPropFloat(e, "m_flLaggedMovementValue", 1.2);
			NF.CenterAll(b.name.toupper() + " IS ENRAGED");
			NF.Say("\x04" + b.name + "\x01 enters its second phase! The night itself answers its call.");
			try { Director.ForcePanicEvent(); } catch (err) {}
			NF.SpawnElite();
		}
	}
	foreach (idx in dead) delete NF.Bosses[idx];
}

::NF.OnFinaleStart <- function()
{
	NF.Tide.paused = true;
	NF.NightlordPending = true;
	NF.Say("The Tide stills. Something vast stirs in the dark... \x04the Nightlord comes\x01.");
}

//-----------------------------------------------------------------------------
// Kills
//-----------------------------------------------------------------------------
::NF.UltGain <- function(p, amount)
{
	local st = NF.State(p);
	local c = NF.ClassOf(st);
	if (c != null && ("UltGainMult" in c)) amount *= c.UltGainMult;
	st.ult += amount;
	if (st.ult > 100) st.ult = 100.0;
}

::NF.OnKill <- function(killer, victim, kind)
{
	if (!NF.IsSurvivor(killer)) return;
	local st = NF.State(killer);
	local c = NF.ClassOf(st);
	switch (kind)
	{
		case "common":  NF.GiveRunes(killer, NF.RuneValues.common);  NF.UltGain(killer, 1.5); break;
		case "special": NF.GiveRunes(killer, NF.RuneValues.special); NF.UltGain(killer, 8); break;
		case "witch":   NF.GiveRunes(killer, NF.RuneValues.witch);   NF.UltGain(killer, 25); break;
		case "tank":    NF.UltGain(killer, 30); break;
	}
	local hook = NF.Hook(c, "OnKill");
	if (hook != null) hook(killer, st, victim, kind);
}

::NF.OnBossDeath <- function(victim, killer)
{
	local idx = victim.GetEntityIndex();
	if (!(idx in NF.Bosses))
	{
		if (NF.IsTank(victim))
		{
			NF.GiveRunesAll(NF.RuneValues.tank);
			NF.Say("Tank slain. \x05+" + NF.RuneValues.tank + " runes\x01 to every survivor.");
		}
		return;
	}
	local b = NF.Bosses[idx];
	delete NF.Bosses[idx];
	switch (b.kind)
	{
		case "elite":
			if (NF.IsSurvivor(killer)) NF.GiveRunes(killer, NF.RuneValues.elite);
			NF.Say("Elite slain! \x05+" + NF.RuneValues.elite + " runes\x01" + (NF.IsSurvivor(killer) ? " to " + killer.GetPlayerName() : "") + ".");
			break;
		case "field":
			NF.GiveRunesAll(NF.RuneValues.fieldboss);
			NF.Say("\x05" + b.name + "\x01 falls. \x05+" + NF.RuneValues.fieldboss + " runes\x01 to every survivor.");
			break;
		case "nightlord":
			NF.CenterAll("NIGHTLORD VANQUISHED");
			NF.Say("\x04" + b.name + "\x01 is vanquished. Dawn is within reach — reach the rescue!");
			break;
		default:
			NF.GiveRunesAll(NF.RuneValues.tank);
			NF.Say("Tank slain. \x05+" + NF.RuneValues.tank + " runes\x01 to every survivor.");
	}
}
