//=============================================================================
// Nightfall — Hero classes
//
// Every class has: a PASSIVE (always on), a SKILL (cooldown, WALK + SHOVE)
// and an ULTIMATE (charged by kills, WALK + USE).
//
// Hooks (all optional):
//   DealMult(p, st, victim, dt)    -> damage multiplier for damage p deals
//   TakeMult(p, st, attacker, dt)  -> damage multiplier for damage p takes (0 = negate)
//   OnKill(p, st, victim, kind)    -> kind: "common" | "special" | "witch" | "tank"
//   OnIncap(p, st)
//   Think(p, st)                   -> every 0.1s while alive
//   Skill(p, st) / Ult(p, st)      -> return true if the ability fired
//=============================================================================

::NF.ClassOrder <- ["vanguard", "bulwark", "hawkeye", "shade", "berserker", "weaver", "ronin", "gravecaller"];

::NF.Classes <- {

	//-------------------------------------------------------------------------
	vanguard = {
		title = "Vanguard"
		role = "All-rounder. Closes distance and breaks crowds."
		hp = 115
		speed = 1.0
		skillCD = 10.0
		passive = "Second Wind: once per night, rise on your own 3s after being downed."
		skill = "Grapple Lunge: hurl yourself at the point you aim at and crash down on it."
		ult = "Onslaught: a shockwave that flattens everything around you."

		OnIncap = function(p, st)
		{
			if (st.secondWindUsed) return;
			st.secondWindUsed = true;
			NF.Tell(p, "{o}Second Wind{d} — hold on...");
			NF.After(3.0, function() {
				if (NF.Alive(p) && p.IsIncapacitated() && !p.IsHangingFromLedge())
				{
					NF.Revive(p, null, 0.3);
					NF.Say(p.GetPlayerName() + " rises on a {o}Second Wind{d}!");
				}
			});
		}

		Skill = function(p, st)
		{
			local tr = NF.AimTrace(p, 900);
			local dest = tr.pos;
			local dir = dest - p.GetOrigin();
			local dist = dir.Length();
			if (dist < 64) return false;
			dir.Norm();
			NF.Invuln(p, 0.6);
			NF.Impulse(p, Vector(dir.x * 850, dir.y * 850, 260 + dir.z * 300));
			local tdelay = dist / 1100.0;
			if (tdelay > 0.8) tdelay = 0.8;
			NF.After(tdelay + 0.15, function() {
				if (NF.Alive(p)) NF.AoE(p, p.GetOrigin(), 170, 90, 60, true, NF.DMG.CLUB);
			});
			return true;
		}

		Ult = function(p, st)
		{
			local pos = p.GetOrigin();
			NF.Invuln(p, 1.0);
			local n = NF.AoE(p, pos, 360, 500, 300, true, NF.DMG.BLAST);
			NF.Say(p.GetPlayerName() + " unleashes {o}Onslaught{d}! (" + n + " struck)");
			return true;
		}
	}

	//-------------------------------------------------------------------------
	bulwark = {
		title = "Bulwark"
		role = "Shield-bearer. Soaks punishment and protects the party."
		hp = 150
		speed = 0.92
		skillCD = 12.0
		passive = "Steel Hide: take 15% less damage, 45% less while crouched."
		skill = "Whirlwind Guard: stagger specials around you and brace (80% DR) for 3s."
		ult = "Aegis Descent: nearby allies become invulnerable for 5s; downed allies are raised."

		TakeMult = function(p, st, attacker, dt)
		{
			local m = 0.85;
			if (p.GetButtonMask() & NF.BTN.DUCK) m = 0.55;
			if (NF.HasBuff(st, "brace")) m *= 0.2;
			return m;
		}

		Skill = function(p, st)
		{
			NF.AddBuff(st, "brace", 3.0);
			NF.AoE(p, p.GetOrigin(), 220, 40, 25, true, NF.DMG.CLUB);
			foreach (a in NF.AlliesInRadius(p.GetOrigin(), 250, true))
				if (a.IsIncapacitated()) NF.AddReviveProgress(a, 50, p);
			return true;
		}

		Ult = function(p, st)
		{
			local raised = 0;
			foreach (a in NF.AlliesInRadius(p.GetOrigin(), 550, true))
			{
				if (a.IsIncapacitated() && !a.IsHangingFromLedge())
				{
					NF.Revive(a, p, 0.4);
					raised++;
				}
				NF.Invuln(a, 5.0);
			}
			NF.Say(p.GetPlayerName() + " calls down the {o}Aegis{d}!" + (raised > 0 ? " (" + raised + " raised)" : ""));
			return true;
		}
	}

	//-------------------------------------------------------------------------
	hawkeye = {
		title = "Hawkeye"
		role = "Marksman. Spots threats and deletes them at range."
		hp = 90
		speed = 1.08
		skillCD = 8.0
		passive = "Keen Eye: +30% damage beyond 700 units; special infected glow for the whole party."
		skill = "Marking Shot: mark the enemy in your sights — it takes +50% damage from everyone for 10s."
		ult = "Volley: strike every special infected and witch you can see within 1400 units."

		DealMult = function(p, st, victim, dt)
		{
			if ((victim.GetOrigin() - p.GetOrigin()).Length() > 700) return 1.3;
			return 1.0;
		}

		Skill = function(p, st)
		{
			local tr = NF.AimTrace(p, 3000);
			if (!("enthit" in tr) || !NF.IsEnemy(tr.enthit))
			{
				// Fall back to the nearest enemy to the crosshair point
				local best = null;
				foreach (e in NF.EnemiesInRadius(tr.pos, 160)) { best = e; break; }
				if (best == null) { NF.Center(p, "No target in sight"); return false; }
				tr.enthit <- best;
			}
			local e = tr.enthit;
			NF.Marks[e.GetEntityIndex()] <- Time() + 10.0;
			NF.SetGlow(e, 255, 40, 40);
			NF.Tell(p, "Target {o}marked{d}.");
			return true;
		}

		Ult = function(p, st)
		{
			local eye = p.EyePosition();
			local n = 0;
			NF.AbilityDamageActive = true;
			foreach (e in NF.EnemiesInRadius(p.GetOrigin(), 1400))
			{
				local c = e.GetClassname();
				if (c == "infected") continue;
				if (!NF.HasLOS(eye, e, p)) continue;
				try { e.TakeDamage(c == "witch" ? 400.0 : 350.0, NF.DMG.BULLET, p); } catch (err) {}
				n++;
			}
			NF.AbilityDamageActive = false;
			NF.Say(p.GetPlayerName() + " looses a {o}Volley{d} (" + n + " targets)");
			return true;
		}
	}

	//-------------------------------------------------------------------------
	shade = {
		title = "Shade"
		role = "Assassin. Slips through danger and replays the party's violence."
		hp = 95
		speed = 1.12
		skillCD = 14.0
		passive = "Ghost Step: dodge recovers twice as fast with longer i-frames; kills grant a burst of speed."
		skill = "Restage: everything the party did to nearby enemies in the last 4s happens again (60%)."
		ult = "Veil: you and nearby allies fade from sight — 70% damage reduction for 6s."

		OnKill = function(p, st, victim, kind)
		{
			NF.AddBuff(st, "ghostrun", 1.5);
		}

		SpeedMult = function(p, st)
		{
			return NF.HasBuff(st, "ghostrun") ? 1.25 : 1.0;
		}

		Skill = function(p, st)
		{
			local now = Time();
			local pos = p.GetOrigin();
			local per = {};
			foreach (d in NF.DamageLog)
			{
				if (now - d.t > 4.0) continue;
				if (!NF.Alive(d.victim)) continue;
				if ((d.victim.GetOrigin() - pos).Length() > 700) continue;
				local idx = d.victim.GetEntityIndex();
				if (!(idx in per)) per[idx] <- { ent = d.victim, dmg = 0.0 };
				per[idx].dmg += d.dmg;
			}
			local n = 0;
			NF.AbilityDamageActive = true;
			foreach (idx, v in per)
			{
				local dmg = v.dmg * 0.6;
				if (dmg > 600) dmg = 600;
				if (dmg < 1) continue;
				try { v.ent.TakeDamage(dmg, NF.DMG.SLASH, p); } catch (err) {}
				n++;
			}
			NF.AbilityDamageActive = false;
			if (n == 0) { NF.Center(p, "Nothing to restage"); return false; }
			NF.Tell(p, "{o}Restage{d} echoes through " + n + " enemies.");
			return true;
		}

		Ult = function(p, st)
		{
			foreach (a in NF.AlliesInRadius(p.GetOrigin(), 500, false))
			{
				local ast = NF.State(a);
				NF.AddBuff(ast, "veil", 6.0);
				NF.SetAlpha(a, 70);
				NF.After(6.0, function() { if (NF.Valid(a)) NF.SetAlpha(a, 255); });
			}
			NF.Say(p.GetPlayerName() + " draws the {o}Veil{d}.");
			return true;
		}
	}

	//-------------------------------------------------------------------------
	berserker = {
		title = "Berserker"
		role = "Bruiser. Gets stronger the closer to death they are."
		hp = 135
		speed = 0.95
		skillCD = 9.0
		passive = "Bloodrush: up to +50% damage as your health drops; +25% melee damage."
		skill = "Earthshaker: smash the ground, wrecking everything in front of you."
		ult = "War Totem: plant a totem — allies near it deal +35% damage and regenerate for 12s."

		DealMult = function(p, st, victim, dt)
		{
			local mx = p.GetMaxHealth();
			local missing = 1.0 - (p.GetHealth() + p.GetHealthBuffer()) / mx.tofloat();
			if (missing < 0) missing = 0;
			local m = 1.0 + missing * 0.5;
			if (NF.IsMelee(dt)) m *= 1.25;
			return m;
		}

		Skill = function(p, st)
		{
			local fwd = p.EyeAngles().Forward();
			fwd.z = 0; fwd.Norm();
			local center = p.GetOrigin() + fwd * 140;
			NF.AoE(p, center, 230, 150, 90, true, NF.DMG.CLUB);
			NF.Impulse(p, Vector(0, 0, 180));
			return true;
		}

		Ult = function(p, st)
		{
			local pos = p.GetOrigin();
			local prop = null;
			try
			{
				local mdl = "models/props_junk/propanecanister001a.mdl";
				PrecacheModel(mdl);
				prop = SpawnEntityFromTable("prop_dynamic", { model = mdl, origin = pos, solid = 0, rendercolor = "255 60 40" });
				NF.SetGlow(prop, 255, 80, 20);
			}
			catch (e) { prop = null; }
			NF.Totems.append({ pos = pos, until = Time() + 12.0, ent = prop, owner = p });
			NF.Say(p.GetPlayerName() + " plants a {o}War Totem{d}!");
			return true;
		}
	}

	//-------------------------------------------------------------------------
	weaver = {
		title = "Weaver"
		role = "Spellcaster. Siphons life from the dead and calls down ruin."
		hp = 85
		speed = 1.05
		skillCD = 18.0
		passive = "Soul Siphon: kills heal you (1 HP per common, 5 per special) and charge your ultimate 50% faster."
		skill = "Mending Rite: heal nearby allies 20 HP and rouse downed allies."
		ult = "Cataclysm: a second after casting, the point you aim at erupts."

		UltGainMult = 1.5

		OnKill = function(p, st, victim, kind)
		{
			NF.Heal(p, kind == "common" ? 1 : 5);
		}

		Skill = function(p, st)
		{
			foreach (a in NF.AlliesInRadius(p.GetOrigin(), 450, true))
			{
				if (a.IsIncapacitated()) NF.AddReviveProgress(a, 35, p);
				else NF.Heal(a, 20);
			}
			NF.Tell(p, "{o}Mending Rite{d}.");
			return true;
		}

		Ult = function(p, st)
		{
			local tr = NF.AimTrace(p, 2000);
			local pos = tr.pos;
			NF.Say(p.GetPlayerName() + " weaves a {o}Cataclysm{d}...");
			NF.After(1.0, function() {
				NF.AoE(NF.Valid(p) ? p : null, pos, 400, 600, 450, true, NF.DMG.BLAST | NF.DMG.BURN);
			});
			return true;
		}
	}

	//-------------------------------------------------------------------------
	ronin = {
		title = "Ronin"
		role = "Duelist. Parries blows and becomes a whirlwind of steel."
		hp = 105
		speed = 1.05
		skillCD = 10.0
		passive = "Parry: shove within 0.35s of being hit to negate the blow and stagger the attacker."
		skill = "Iai Stance: for 4s, your melee hits deal double damage."
		ult = "Beast Unbound: for 10s — faster, +60% damage, 30% damage reduction, heal 3 HP per hit."

		TakeMult = function(p, st, attacker, dt)
		{
			if (Time() - st.lastShove <= 0.35 && NF.IsEnemy(attacker))
			{
				if (NF.IsSpecial(attacker)) { try { attacker.Stagger(p.GetOrigin()); } catch (e) {} }
				st.ult += 4;
				NF.Center(p, "PARRY");
				return 0.0;
			}
			return NF.HasBuff(st, "beast") ? 0.7 : 1.0;
		}

		DealMult = function(p, st, victim, dt)
		{
			local m = 1.0;
			if (NF.HasBuff(st, "iai") && NF.IsMelee(dt)) m *= 2.0;
			if (NF.HasBuff(st, "beast"))
			{
				m *= 1.6;
				NF.Heal(p, 3);
			}
			return m;
		}

		SpeedMult = function(p, st)
		{
			return NF.HasBuff(st, "beast") ? 1.3 : 1.0;
		}

		Skill = function(p, st)
		{
			NF.AddBuff(st, "iai", 4.0);
			NF.Tell(p, "{o}Iai Stance{d}.");
			return true;
		}

		Ult = function(p, st)
		{
			NF.AddBuff(st, "beast", 10.0);
			NF.Say(p.GetPlayerName() + " is {o}Unbound{d}!");
			return true;
		}
	}

	//-------------------------------------------------------------------------
	gravecaller = {
		title = "Gravecaller"
		role = "Summoner. A spectral familiar fights at their side."
		hp = 95
		speed = 1.0
		skillCD = 20.0
		passive = "Familiar: a spirit strikes the nearest enemy within 450 units every 0.8s."
		skill = "Requiem: instantly raise the nearest downed ally within 600 units; heal allies 10 HP."
		ult = "Danse Macabre: for 12s your familiar strikes three foes at once, much harder."

		Think = function(p, st)
		{
			local now = Time();
			if (now < st.familiarNext || p.IsIncapacitated()) return;
			st.familiarNext = now + 0.8;
			local empowered = NF.HasBuff(st, "danse");
			local maxTargets = empowered ? 3 : 1;
			local dmg = empowered ? 45.0 : 14.0;
			local eye = p.EyePosition();
			local cands = [];
			foreach (e in NF.EnemiesInRadius(p.GetOrigin(), 450))
			{
				local d = (e.GetOrigin() - p.GetOrigin()).Length();
				cands.append({ e = e, d = d });
			}
			cands.sort(function(a, b) { return a.d <=> b.d; });
			local hit = 0;
			NF.AbilityDamageActive = true;
			foreach (c in cands)
			{
				if (hit >= maxTargets) break;
				if (!NF.HasLOS(eye, c.e, p)) continue;
				try { c.e.TakeDamage(NF.IsTank(c.e) ? dmg * 2 : dmg, NF.DMG.SLASH, p); } catch (err) {}
				hit++;
			}
			NF.AbilityDamageActive = false;
		}

		Skill = function(p, st)
		{
			local best = null;
			local bestD = 99999.0;
			foreach (a in NF.Survivors())
			{
				if (a == p || !a.IsIncapacitated() || a.IsHangingFromLedge()) continue;
				local d = (a.GetOrigin() - p.GetOrigin()).Length();
				if (d < 600 && d < bestD) { best = a; bestD = d; }
			}
			foreach (a in NF.AlliesInRadius(p.GetOrigin(), 450, false)) NF.Heal(a, 10);
			if (best != null)
			{
				NF.Revive(best, p, 0.35);
				NF.Say(p.GetPlayerName() + " sings a {o}Requiem{d} — " + best.GetPlayerName() + " rises.");
			}
			return true;
		}

		Ult = function(p, st)
		{
			NF.AddBuff(st, "danse", 12.0);
			NF.Say(p.GetPlayerName() + " begins the {o}Danse Macabre{d}.");
			return true;
		}
	}
};

//-----------------------------------------------------------------------------
// Class helpers
//-----------------------------------------------------------------------------
::NF.IsMelee <- function(dt)
{
	if (("Weapon" in dt) && NF.Valid(dt.Weapon))
		return dt.Weapon.GetClassname() == "weapon_melee" || dt.Weapon.GetClassname() == "weapon_chainsaw";
	return (dt.DamageType & (NF.DMG.CLUB | NF.DMG.SLASH)) != 0;
}

::NF.ClassOf <- function(st)
{
	if (st.cls == null || !(st.cls in NF.Classes))
		return null;
	return NF.Classes[st.cls];
}

::NF.Hook <- function(cdef, name)
{
	return (cdef != null && (name in cdef)) ? cdef[name] : null;
}

::NF.FindClass <- function(text)
{
	text = text.tolower();
	foreach (id in NF.ClassOrder)
	{
		if (id == text || NF.Classes[id].title.tolower() == text)
			return id;
	}
	// prefix match
	foreach (id in NF.ClassOrder)
	{
		if (text.len() >= 2 && id.find(text) == 0)
			return id;
	}
	return null;
}

::NF.SetClass <- function(p, id, quiet)
{
	local st = NF.State(p);
	st.cls = id;
	st.ult = 0.0;
	st.skillReadyAt = 0.0;
	NF.ApplyStats(p, true);
	if (!quiet)
	{
		local c = NF.Classes[id];
		NF.Say(p.GetPlayerName() + " walks the path of the {o}" + c.title + "{d}.");
		NF.Tell(p, "{l}Passive{d} " + c.passive);
		NF.Tell(p, "{l}Skill{d} (WALK+SHOVE) " + c.skill);
		NF.Tell(p, "{l}Ultimate{d} (WALK+USE) " + c.ult);
	}
}

// Give bots (and humans who never picked) a class nobody else is using
::NF.AutoAssignClasses <- function()
{
	local taken = {};
	foreach (s in NF.AllSurvivors())
	{
		local st = NF.State(s);
		if (st.cls != null) taken[st.cls] <- true;
	}
	foreach (s in NF.AllSurvivors())
	{
		local st = NF.State(s);
		if (st.cls != null) continue;
		local pick = null;
		local pool = clone NF.ClassOrder;
		// shuffle a little so runs differ
		for (local i = pool.len() - 1; i > 0; i--)
		{
			local j = RandomInt(0, i);
			local tmp = pool[i]; pool[i] = pool[j]; pool[j] = tmp;
		}
		foreach (id in pool) { if (!(id in taken)) { pick = id; break; } }
		if (pick == null) pick = pool[0];
		taken[pick] <- true;
		NF.SetClass(s, pick, IsPlayerABot(s));
		if (!IsPlayerABot(s))
			NF.Tell(s, "You were given the {o}" + NF.Classes[pick].title + "{d}. Type {l}!class{d} at a Site of Grace to change.");
	}
}
