//=============================================================================
// Nightfall — Core loop: init, input, damage pipeline, chat, events, bot AI
//=============================================================================

// Safe to call more than once: it only (re)starts when the think entity is gone,
// which is what happens after a round restart wipes the map's entities.
::NF.Init <- function()
{
	if (NF.Initialized && NF.Valid(NF.ThinkEnt)) return;
	NF.ResetState();
	NF.Initialized = true;

	NF.World = Entities.FindByClassname(null, "worldspawn");
	NF.LoadRun();
	NF.RollOmen();

	// Hold-to-revive still exists, but it is slow: striking your allies is the way.
	try { Convars.SetValue("survivor_revive_duration", 8); } catch (e) {}

	// A HUD problem must never stop the rest of the mod from starting
	try { NF.SetupHUD(); }
	catch (e) { printl("[Nightfall] HUD setup failed: " + e); }
	NF.StartThink();

	NF.After(1.0, function() {
		NF.AutoAssignClasses();
		foreach (s in NF.AllSurvivors())
		{
			NF.PrecacheSounds(s);
			local st = NF.State(s);
			st.flask = NF.MaxFlasks(st);
			st.downs = 0;
			st.secondWindUsed = false;
			if (IsPlayerABot(s)) NF.LevelUp(s);
			NF.ApplyStats(s, true);
			NF.RollInventory(s);
		}
		// Checkpoint: a wipe restarts the map with the state you entered it with
		NF.SaveRun(NF.Day);
	});

	NF.After(3.0, function() {
		NF.Say("Nightfall v" + NF.Version + " — {o}Night " + NF.Day + "{d}. Omen: {o}" + NF.Omen.name + "{d} — " + NF.Omen.desc);
		NF.Say("Type {l}!nfhelp{d} for controls. Spend runes with {l}!levelup{d} before leaving the saferoom.");
	});
}

::NF.ResetState <- function()
{
	// "<-" creates the slot if it does not exist yet; plain "=" would be an error.
	NF.Players <- {};
	NF.Timers <- [];
	NF.DamageLog <- [];
	NF.Marks <- {};
	NF.Totems <- [];
	NF.Stains <- [];
	NF.Bosses <- {};
	NF.PendingElites <- 0;
	NF.PendingElitesUntil <- 0.0;
	NF.PendingBoss <- null;
	NF.NightlordPending <- false;
	NF.TideDamageActive <- false;
	NF.AbilityDamageActive <- false;
	NF.LastSlowTick <- 0.0;
	NF.LastBotTick <- 0.0;
	NF.WeaponRarity <- {};
	NF.SeenCommons <- {};
	NF.Tide <- { active = false, paused = false, disabled = false, startTime = 0.0, pct = -15.0, lastTick = 0.0 };
	NF.Raids <- { r1 = false, r2 = false, boss = false };
}

::NF.StartThink <- function()
{
	local ent = SpawnEntityFromTable("info_target", { targetname = "nightfall_think" });
	NF.ThinkEnt = ent;
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
		// The HUD text doesn't need 10 updates a second; twice is plenty and much cheaper
		NF.UpdateHUD();
	}
	NF.UpdateTide();
}

// Every second
::NF.SlowThink <- function()
{
	local now = Time();

	// passive ultimate charge
	foreach (s in NF.Survivors())
		if (!s.IsIncapacitated()) NF.UltGain(s, 0.4);

	NF.UpdateThirdPerson();
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
		NF.PlayTo(p, "denied");
		return;
	}
	if (c.Skill(p, st))
	{
		st.skillReadyAt = now + c.skillCD;
		NF.OnSkillUsed(p, c);
	}
}

::NF.TryUlt <- function(p, st)
{
	local c = NF.ClassOf(st);
	if (c == null) return;
	if (st.ult < 100)
	{
		NF.Center(p, "Ultimate " + st.ult.tointeger() + "%");
		NF.PlayTo(p, "denied");
		return;
	}
	if (c.Ult(p, st))
	{
		st.ult = 0.0;
		NF.OnUltUsed(p, c);
	}
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
	NF.PlayTo(p, "dodge");
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
			if (victim.IsIncapacitated() && !(dt.DamageType & NF.DMG.BURN))
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
			NF.Tell(speaker, "{l}WALK+SHOVE{d} skill | {l}WALK+USE{d} ultimate | {l}WALK+RELOAD{d} flask | {l}double-tap CROUCH{d} dodge");
			NF.Tell(speaker, "{l}Shove / hit a downed ally{d} to rouse them. Outrun the {o}Tide{d}. Kill to earn runes.");
			NF.Tell(speaker, "Commands: !class [name], !classes, !levelup, !stats, !skill, !ult, !flask, !3p, !1p");
			NF.Tell(speaker, "Own keys: in the console type {l}bind q \"scripted_user_func skill\"{d} (also: ult, flask, dodge, camera)");
			return false;

		case "classes":
			foreach (id in NF.ClassOrder)
				NF.Tell(speaker, "{o}" + NF.Classes[id].title + "{d} — " + NF.Classes[id].role);
			return false;

		case "class":
			if (args.len() < 2)
			{
				local c = NF.ClassOf(st);
				if (c != null)
				{
					NF.Tell(speaker, "You are the {o}" + c.title + "{d}. " + c.role);
					NF.Tell(speaker, "{l}Passive{d} " + c.passive);
					NF.Tell(speaker, "{l}Skill{d} " + c.skill);
					NF.Tell(speaker, "{l}Ultimate{d} " + c.ult);
				}
				NF.Tell(speaker, "Change with {l}!class <name>{d} at a Site of Grace. See {l}!classes{d}.");
				return false;
			}
			if (!NF.AtGrace())
			{
				NF.Tell(speaker, "You can only change class at a {o}Site of Grace{d}.");
				return false;
			}
			{
				local id = NF.FindClass(args[1]);
				if (id == null) { NF.Tell(speaker, "Unknown class. See {l}!classes{d}."); return false; }
				NF.SetClass(speaker, id, false);
			}
			return false;

		case "levelup":
		case "lvl":
			NF.LevelUp(speaker);
			return false;

		case "stats":
			{
				local next = st.level < NF.MAX_LEVEL ? NF.LevelCosts[st.level].tostring() : "max";
				NF.Tell(speaker, "Level {o}" + st.level + "{d} | Runes {o}" + st.runes + "{d} (next: " + next + ") | Damage +" + ((st.level - 1) * 4) + "% | Flasks " + st.flask + "/" + NF.MaxFlasks(st));
			}
			return false;

		case "skill": NF.TrySkill(speaker, st); return false;
		case "ult":   NF.TryUlt(speaker, st); return false;
		case "flask": NF.DrinkFlask(speaker); return false;

		case "3p":
		case "third":
		case "thirdperson":
			NF.SetThirdPerson(speaker, true);
			NF.Tell(speaker, "Third-person camera {o}on{d}. Type {l}!1p{d} for first person.");
			return false;

		case "1p":
		case "first":
		case "firstperson":
			NF.SetThirdPerson(speaker, false);
			NF.Tell(speaker, "First-person camera {o}on{d}. Type {l}!3p{d} for third person.");
			return false;

		case "tide":
			if (args.len() >= 2 && (args[1] == "off" || args[1] == "on"))
			{
				NF.Tide.disabled = args[1] == "off";
				NF.Say("The Tide has been turned {o}" + args[1] + "{d} by " + speaker.GetPlayerName() + ".");
			}
			else NF.Tell(speaker, "Tide: " + (NF.Tide.disabled ? "off" : (NF.Tide.pct < 0 ? 0 : NF.Tide.pct.tointeger()) + "%") + ". Use !tide on|off.");
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
			if (c.Ult(s, st)) { st.ult = 0.0; NF.OnUltUsed(s, c); }
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
		NF.Say(killer.GetPlayerName() + " slays a Witch. {o}+" + NF.RuneValues.witch + " runes{d}.");
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
	if (!NF.Tide.paused) NF.OnFinaleStart();
}

::NF.Ev_map_transition <- function(params)
{
	NF.SaveRun(NF.Day + 1);
}

::NF.Ev_finale_vehicle_leaving <- function(params)
{
	NF.Say("{g}Dawn breaks.{d} The expedition survives the Long Night.");
}

::NF.Ev_witch_spawn <- function(params)
{
	local w = ("witchid" in params) ? EntIndexToHScript(params.witchid) : null;
	if (NF.Valid(w)) NF.After(0.1, function() { if (NF.Valid(w)) NF.ApplyWitchModel(w); });
}

// Give every piece of run state a value as soon as the scripts load, so callbacks that
// fire before Init (early spawns, chat) never touch a missing slot.
::NF.ResetState();
