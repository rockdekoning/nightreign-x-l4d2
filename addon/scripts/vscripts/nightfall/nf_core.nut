//=============================================================================
// Nightfall — Core loop: init, input, damage pipeline, chat, events, bot AI
//=============================================================================

::NF.Init <- function()
{
	if (NF.Initialized) return;
	NF.Initialized = true;

	NF.World = Entities.FindByClassname(null, "worldspawn");
	NF.LoadRun();
	NF.RollOmen();

	// Hold-to-revive still exists, but it is slow: striking your allies is the way.
	try { Convars.SetValue("survivor_revive_duration", 8); } catch (e) {}

	NF.SetupHUD();
	NF.StartThink();

	NF.After(1.0, function() {
		NF.AutoAssignClasses();
		foreach (s in NF.AllSurvivors())
		{
			local st = NF.State(s);
			st.flask = NF.MaxFlasks(st);
			st.downs = 0;
			st.secondWindUsed = false;
			NF.ApplyStats(s, true);
			NF.RollInventory(s);
		}
		// Checkpoint: a wipe restarts the map with the state you entered it with
		NF.SaveRun(NF.Day);
	});

	NF.After(3.0, function() {
		NF.Say("Nightfall v" + NF.Version + " — \x05Night " + NF.Day + "\x01. Omen: \x05" + NF.Omen.name + "\x01 — " + NF.Omen.desc);
		NF.Say("Type \x03!nfhelp\x01 for controls. Spend runes with \x03!levelup\x01 before leaving the saferoom.");
	});
}

::NF.StartThink <- function()
{
	local ent = SpawnEntityFromTable("info_target", { targetname = "nightfall_think" });
	ent.ValidateScriptScope();
	local scope = ent.GetScriptScope();
	scope.NFThink <- function()
	{
		try { ::NF.Think(); }
		catch (e) { printl("[Nightfall] think error: " + e); }
		return 0.1;
	}
	AddThinkToEnt(ent, "NFThink");
}

//-----------------------------------------------------------------------------
// Main think — every 0.1s
//-----------------------------------------------------------------------------
::NF.Think <- function()
{
	local now = Time();
	NF.RunTimers();

	foreach (s in NF.Survivors())
	{
		local st = NF.State(s);
		NF.HandleInput(s, st);
		NF.UpdateSpeed(s, st);
		local c = NF.ClassOf(st);
		local hook = NF.Hook(c, "Think");
		if (hook != null && !s.IsIncapacitated()) hook(s, st);
	}

	if (now - NF.LastSlowTick >= 1.0)
	{
		NF.LastSlowTick = now;
		NF.SlowThink();
	}
	if (now - NF.LastBotTick >= 0.5)
	{
		NF.LastBotTick = now;
		NF.BotThink();
		NF.UpdateCommonModels();
	}
	NF.UpdateTide();
	NF.UpdateHUD();
}

// Every second
::NF.SlowThink <- function()
{
	local now = Time();

	// passive ultimate charge
	foreach (s in NF.Survivors())
		if (!s.IsIncapacitated()) NF.UltGain(s, 0.4);

	NF.DecayRevive();
	NF.CheckStains();
	NF.CheckRaids();
	NF.UpdateBosses();

	// prune the Restage log
	local keep = [];
	foreach (d in NF.DamageLog) if (now - d.t <= 4.0) keep.append(d);
	NF.DamageLog = keep;

	// expire Hawkeye marks
	local expired = [];
	foreach (idx, t in NF.Marks) if (t <= now) expired.append(idx);
	foreach (idx in expired)
	{
		delete NF.Marks[idx];
		local e = EntIndexToHScript(idx);
		if (NF.Valid(e) && !(idx in NF.Bosses)) NF.ClearGlow(e);
	}

	// War Totems: regen + expiry
	local live = [];
	foreach (t in NF.Totems)
	{
		if (t.until <= now)
		{
			if (NF.Valid(t.ent)) t.ent.Kill();
			continue;
		}
		foreach (a in NF.AlliesInRadius(t.pos, 300, false)) NF.Heal(a, 2);
		live.append(t);
	}
	NF.Totems = live;

	// Keen Eye: a living Hawkeye lights up every special for the party
	local hawk = false;
	foreach (s in NF.Survivors()) if (NF.State(s).cls == "hawkeye" && !s.IsIncapacitated()) { hawk = true; break; }
	if (hawk)
	{
		foreach (sp in NF.Specials())
		{
			local idx = sp.GetEntityIndex();
			if ((idx in NF.Bosses) || (idx in NF.Marks)) continue;
			NF.SetGlow(sp, 120, 200, 255);
		}
	}
}

//-----------------------------------------------------------------------------
// Input
//   Skill     WALK + SHOVE
//   Ultimate  WALK + USE
//   Flask     WALK + RELOAD
//   Dodge     double-tap CROUCH
//   Rouse     SHOVE a downed ally (or hit them with anything)
//-----------------------------------------------------------------------------
::NF.HandleInput <- function(p, st)
{
	local b = p.GetButtonMask();
	local pressed = b & ~st.prevButtons;
	st.prevButtons = b;
	if (pressed == 0 || IsPlayerABot(p)) return;
	if (p.IsIncapacitated()) return;

	local walk = (b & NF.BTN.WALK) != 0;
	local now = Time();

	if (pressed & NF.BTN.ATTACK2)
	{
		st.lastShove = now;
		if (walk) NF.TrySkill(p, st);
		else NF.TryShoveRouse(p);
	}
	if (walk && (pressed & NF.BTN.USE)) NF.TryUlt(p, st);
	if (walk && (pressed & NF.BTN.RELOAD)) NF.DrinkFlask(p);

	if (pressed & NF.BTN.DUCK)
	{
		if (now - st.lastDuck < 0.3) NF.TryDodge(p, st);
		st.lastDuck = now;
	}
}

::NF.TrySkill <- function(p, st)
{
	local c = NF.ClassOf(st);
	if (c == null) return;
	local now = Time();
	if (now < st.skillReadyAt)
	{
		NF.Center(p, "Skill ready in " + ((st.skillReadyAt - now).tointeger() + 1) + "s");
		return;
	}
	if (c.Skill(p, st)) st.skillReadyAt = now + c.skillCD;
}

::NF.TryUlt <- function(p, st)
{
	local c = NF.ClassOf(st);
	if (c == null) return;
	if (st.ult < 100)
	{
		NF.Center(p, "Ultimate " + st.ult.tointeger() + "%");
		return;
	}
	if (c.Ult(p, st)) st.ult = 0.0;
}

::NF.TryDodge <- function(p, st)
{
	local now = Time();
	if (now < st.dodgeReadyAt) return;
	local shade = st.cls == "shade";
	local v = p.GetVelocity();
	v.z = 0;
	local dir = null;
	if (v.Length() > 60) { dir = v; dir.Norm(); }
	else { dir = p.EyeAngles().Forward() * -1; dir.z = 0; dir.Norm(); }
	NF.Impulse(p, Vector(dir.x * 480, dir.y * 480, 170));
	NF.Invuln(p, shade ? 0.7 : 0.4);
	st.dodgeReadyAt = now + (shade ? 0.7 : 1.4);
}

//-----------------------------------------------------------------------------
// Damage pipeline (called from AllowTakeDamage)
//-----------------------------------------------------------------------------
::NF.OnTakeDamage <- function(dt)
{
	local victim = ("Victim" in dt) ? dt.Victim : null;
	local attacker = ("Attacker" in dt) ? dt.Attacker : null;
	if (!NF.Valid(victim)) return true;

	// --- Damage to survivors ---
	if (NF.IsSurvivor(victim))
	{
		if (NF.TideDamageActive) return true;

		// Striking a downed ally rouses them instead of hurting them
		if (NF.IsSurvivor(attacker) && attacker != victim)
		{
			if (victim.IsIncapacitated())
			{
				local amt = dt.DamageDone * 2.0;
				if (amt < 10) amt = 10;
				if (amt > 40) amt = 40;
				NF.AddReviveProgress(victim, amt, attacker);
				return false;
			}
			return true; // ordinary friendly fire
		}

		local st = NF.State(victim);
		if (Time() < st.invulnUntil) return false;

		local mult = 1.0;
		local c = NF.ClassOf(st);
		local hook = NF.Hook(c, "TakeMult");
		if (hook != null) mult *= hook(victim, st, attacker, dt);
		if (NF.HasBuff(st, "veil")) mult *= 0.3;
		if (NF.Omen != null && ("specialDmg" in NF.Omen) && NF.IsSpecial(attacker)) mult *= NF.Omen.specialDmg;

		if (mult <= 0) return false;
		if (mult != 1.0) dt.DamageDone = dt.DamageDone * mult;
		return true;
	}

	// --- Damage dealt by survivors to the infected ---
	if (NF.IsSurvivor(attacker) && NF.IsEnemy(victim))
	{
		local st = NF.State(attacker);
		local mult = 1.0 + (st.level - 1) * NF.DMG_PER_LEVEL;
		if (!NF.AbilityDamageActive) mult *= NF.RarityMult(dt, attacker);

		local c = NF.ClassOf(st);
		local hook = NF.Hook(c, "DealMult");
		if (hook != null) mult *= hook(attacker, st, victim, dt);

		local vidx = victim.GetEntityIndex();
		if ((vidx in NF.Marks) && NF.Marks[vidx] > Time()) mult *= 1.5;

		foreach (t in NF.Totems)
			if (t.until > Time() && (attacker.GetOrigin() - t.pos).Length() <= 300) { mult *= 1.35; break; }

		dt.DamageDone = dt.DamageDone * mult;
		if (!NF.AbilityDamageActive)
			NF.DamageLog.append({ t = Time(), victim = victim, dmg = dt.DamageDone });
		return true;
	}
	return true;
}

//-----------------------------------------------------------------------------
// Chat commands
//-----------------------------------------------------------------------------
::NF.OnChat <- function(msg, speaker)
{
	if (!NF.IsSurvivor(speaker)) return true;
	// L4D2 passes "Name: text"
	local idx = msg.find(": ");
	local text = idx != null ? msg.slice(idx + 2) : msg;
	text = strip(text);
	if (text.len() < 2 || (text[0] != '!' && text[0] != '/')) return true;
	local args = split(text.slice(1).tolower(), " ");
	if (args.len() == 0) return true;
	local cmd = args[0];
	local st = NF.State(speaker);

	switch (cmd)
	{
		case "nfhelp":
		case "help":
			NF.Tell(speaker, "\x03WALK+SHOVE\x01 skill | \x03WALK+USE\x01 ultimate | \x03WALK+RELOAD\x01 flask | \x03double-tap CROUCH\x01 dodge");
			NF.Tell(speaker, "\x03Shove / hit a downed ally\x01 to rouse them. Outrun the \x05Tide\x01. Kill to earn runes.");
			NF.Tell(speaker, "Commands: !class [name], !classes, !levelup, !stats, !skill, !ult, !flask");
			return false;

		case "classes":
			foreach (id in NF.ClassOrder)
				NF.Tell(speaker, "\x05" + NF.Classes[id].title + "\x01 — " + NF.Classes[id].role);
			return false;

		case "class":
			if (args.len() < 2)
			{
				local c = NF.ClassOf(st);
				if (c != null)
				{
					NF.Tell(speaker, "You are the \x05" + c.title + "\x01. " + c.role);
					NF.Tell(speaker, "\x03Passive\x01 " + c.passive);
					NF.Tell(speaker, "\x03Skill\x01 " + c.skill);
					NF.Tell(speaker, "\x03Ultimate\x01 " + c.ult);
				}
				NF.Tell(speaker, "Change with \x03!class <name>\x01 at a Site of Grace. See \x03!classes\x01.");
				return false;
			}
			if (!NF.AtGrace())
			{
				NF.Tell(speaker, "You can only change class at a \x05Site of Grace\x01.");
				return false;
			}
			local id = NF.FindClass(args[1]);
			if (id == null) { NF.Tell(speaker, "Unknown class. See \x03!classes\x01."); return false; }
			NF.SetClass(speaker, id, false);
			return false;

		case "levelup":
		case "lvl":
			NF.LevelUp(speaker);
			return false;

		case "stats":
			local next = st.level < NF.MAX_LEVEL ? NF.LevelCosts[st.level].tostring() : "max";
			NF.Tell(speaker, "Level \x05" + st.level + "\x01 | Runes \x05" + st.runes + "\x01 (next: " + next + ") | Damage +" + ((st.level - 1) * 4) + "% | Flasks " + st.flask + "/" + NF.MaxFlasks(st));
			return false;

		case "skill": NF.TrySkill(speaker, st); return false;
		case "ult":   NF.TryUlt(speaker, st); return false;
		case "flask": NF.DrinkFlask(speaker); return false;

		case "tide":
			if (args.len() >= 2 && (args[1] == "off" || args[1] == "on"))
			{
				NF.Tide.disabled = args[1] == "off";
				NF.Say("The Tide has been turned \x05" + args[1] + "\x01 by " + speaker.GetPlayerName() + ".");
			}
			else NF.Tell(speaker, "Tide: " + (NF.Tide.disabled ? "off" : NF.Tide.pct.tointeger() + "%") + ". Use !tide on|off.");
			return false;
	}
	return true;
}

//-----------------------------------------------------------------------------
// Bot AI: use abilities when it makes sense
//-----------------------------------------------------------------------------
::NF.BotThink <- function()
{
	local now = Time();
	foreach (s in NF.Survivors())
	{
		if (!IsPlayerABot(s) || s.IsIncapacitated()) continue;
		local st = NF.State(s);
		local c = NF.ClassOf(st);
		if (c == null) continue;

		local near = NF.EnemiesInRadius(s.GetOrigin(), 350);
		local tankNear = false;
		foreach (e in near) if (NF.IsTank(e)) { tankNear = true; break; }

		local downedNear = false;
		foreach (a in NF.AlliesInRadius(s.GetOrigin(), 500, true))
			if (a.IsIncapacitated() && !a.IsHangingFromLedge()) { downedNear = true; break; }

		// Bots rouse downed allies by "striking" them
		foreach (a in NF.AlliesInRadius(s.GetOrigin(), 120, true))
			if (a != s && a.IsIncapacitated() && !a.IsHangingFromLedge()) NF.AddReviveProgress(a, 12, s);

		if (now >= st.skillReadyAt)
		{
			local want = near.len() >= 4 || tankNear;
			if (st.cls == "weaver" || st.cls == "gravecaller" || st.cls == "bulwark") want = want || downedNear;
			if (st.cls == "hawkeye") want = tankNear;
			if (want && c.Skill(s, st)) st.skillReadyAt = now + c.skillCD;
		}
		if (st.ult >= 100 && (near.len() >= 10 || tankNear || (downedNear && st.cls == "bulwark")))
		{
			if (c.Ult(s, st)) st.ult = 0.0;
		}
		if (s.GetHealth() < s.GetMaxHealth() * 0.35) NF.DrinkFlask(s);
	}
}

//-----------------------------------------------------------------------------
// Game events (wired up in nightfall.nut)
//-----------------------------------------------------------------------------
::NF.Ev_player_death <- function(params)
{
	local victim = (("userid" in params) && params.userid != 0) ? GetPlayerFromUserID(params.userid) : null;
	local killer = (("attacker" in params) && params.attacker != 0) ? GetPlayerFromUserID(params.attacker) : null;
	if (!NF.Valid(victim)) return; // commons are handled by infected_death

	if (victim.IsSurvivor())
	{
		NF.OnSurvivorDeath(victim);
		return;
	}
	local zt = victim.GetZombieType();
	if (zt == 8) NF.OnKill(killer, victim, "tank");
	else NF.OnKill(killer, victim, "special");
	if (zt == 8 || (victim.GetEntityIndex() in NF.Bosses))
		NF.OnBossDeath(victim, killer);
	NF.ClearGlow(victim);
}

::NF.Ev_infected_death <- function(params)
{
	local killer = (("attacker" in params) && params.attacker != 0) ? GetPlayerFromUserID(params.attacker) : null;
	NF.OnKill(killer, null, "common");
}

::NF.Ev_witch_killed <- function(params)
{
	local killer = (("userid" in params) && params.userid != 0) ? GetPlayerFromUserID(params.userid) : null;
	NF.OnKill(killer, null, "witch");
	if (NF.IsSurvivor(killer))
		NF.Say(killer.GetPlayerName() + " slays a Witch. \x05+" + NF.RuneValues.witch + " runes\x01.");
}

::NF.Ev_player_incapacitated <- function(params)
{
	local p = GetPlayerFromUserID(params.userid);
	if (NF.IsSurvivor(p)) NF.OnIncapped(p);
}

::NF.Ev_revive_success <- function(params)
{
	local p = ("subject" in params) ? GetPlayerFromUserID(params.subject) : null;
	if (!NF.IsSurvivor(p)) return;
	try
	{
		NetProps.SetPropInt(p, "m_currentReviveCount", 0);
		NetProps.SetPropInt(p, "m_isGoingToDie", 0);
	}
	catch (e) {}
	NF.State(p).reviveProgress = 0.0;
}

::NF.Ev_player_spawn <- function(params)
{
	local p = GetPlayerFromUserID(params.userid);
	if (!NF.Valid(p)) return;
	if (p.IsSurvivor())
	{
		NF.After(0.5, function() {
			if (!NF.Valid(p)) return;
			local st = NF.State(p);
			if (st.cls == null) NF.AutoAssignClasses();
			NF.ApplyStats(p, false);
		});
	}
	else NF.OnInfectedSpawn(p);
}

::NF.Ev_tank_spawn <- function(params)
{
	local p = GetPlayerFromUserID(params.userid);
	if (NF.Valid(p)) NF.OnTankSpawn(p);
}

::NF.Ev_item_pickup <- function(params)
{
	local p = GetPlayerFromUserID(params.userid);
	if (NF.IsSurvivor(p)) NF.After(0.1, function() { if (NF.Valid(p)) NF.RollInventory(p); });
}

::NF.Ev_finale_start <- function(params)
{
	NF.OnFinaleStart();
}

::NF.Ev_map_transition <- function(params)
{
	NF.SaveRun(NF.Day + 1);
}

::NF.Ev_finale_vehicle_leaving <- function(params)
{
	NF.Say("\x04Dawn breaks.\x01 The expedition survives the Long Night.");
}

::NF.Ev_witch_spawn <- function(params)
{
	local w = ("witchid" in params) ? EntIndexToHScript(params.witchid) : null;
	if (NF.Valid(w)) NF.After(0.1, function() { if (NF.Valid(w)) NF.ApplyWitchModel(w); });
}
