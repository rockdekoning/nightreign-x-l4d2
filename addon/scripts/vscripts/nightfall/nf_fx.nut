//=============================================================================
// Nightfall — Feel: third-person camera, ability feedback (sound, screen
//             flash, shake, blast visuals) and key-bindable commands.
//=============================================================================

::NF.Sounds <- {
	skill   = "ui/pickup_secret01.wav"
	ult     = "ui/critical_event_1.wav"
	flask   = "ui/littlereward.wav"
	levelup = "ui/bigreward.wav"
	revive  = "ui/littlereward.wav"
	dodge   = "ui/beep07.wav"
	denied  = "ui/beep_error01.wav"
}

::NF.PrecacheSounds <- function(ent)
{
	foreach (k, snd in NF.Sounds)
	{
		try { ent.PrecacheScriptSound(snd); } catch (e) {}
		try { PrecacheSound(snd); } catch (e) {}
	}
}

// Play a sound for one player only (their own feedback)
::NF.PlayTo <- function(p, key)
{
	if (!NF.Valid(p) || IsPlayerABot(p) || !(key in NF.Sounds)) return;
	try { EmitSoundOnClient(NF.Sounds[key], p); } catch (e) {}
}

// Play a sound in the world at an entity (everyone nearby hears it)
::NF.PlayAt <- function(ent, key)
{
	if (!NF.Valid(ent) || !(key in NF.Sounds)) return;
	try { EmitSoundOn(NF.Sounds[key], ent); } catch (e) {}
}

// Brief coloured flash on one player's screen
::NF.Flash <- function(p, r, g, b, alpha, dur)
{
	if (!NF.Valid(p) || IsPlayerABot(p)) return;
	try { ScreenFade(p, r, g, b, alpha, dur, 0.05, 1); } catch (e) {}
}

::NF.Shake <- function(pos, amplitude, dur, radius)
{
	try { ScreenShake(pos, amplitude.tofloat(), 40.0, dur.tofloat(), radius.tofloat(), 0, true); } catch (e) {}
}

// A harmless explosion: fireball, smoke and sound, no damage of its own
::NF.BlastFX <- function(pos)
{
	try
	{
		local ex = SpawnEntityFromTable("env_explosion", {
			origin = pos
			iMagnitude = 1
			iRadiusOverride = 1
			spawnflags = 1      // no damage
			rendermode = 5
		});
		if (!NF.Valid(ex)) return;
		DoEntFireByInstanceHandle(ex, "Explode", "", 0.0, null, null);
		DoEntFireByInstanceHandle(ex, "Kill", "", 1.0, null, null);
	}
	catch (e) {}
}

// "Grapple Lunge: hurl yourself..." -> "Grapple Lunge"
::NF.AbilityName <- function(desc)
{
	local i = desc.find(":");
	return i == null ? desc : desc.slice(0, i);
}

::NF.OnSkillUsed <- function(p, c)
{
	NF.Center(p, NF.AbilityName(c.skill).toupper());
	NF.PlayTo(p, "skill");
	NF.Flash(p, 120, 180, 255, 60, 0.35);
}

::NF.OnUltUsed <- function(p, c)
{
	NF.CenterAll(p.GetPlayerName() + ": " + NF.AbilityName(c.ult).toupper());
	NF.PlayAt(p, "ult");
	NF.Flash(p, 255, 220, 120, 110, 0.6);
	NF.Shake(p.GetOrigin(), 8, 0.8, 600);
}

//-----------------------------------------------------------------------------
// Third-person camera
// L4D2 has a built-in "external view" used for stumbles and getting up. Holding
// that timer open gives a proper over-the-shoulder camera with no client setup.
//-----------------------------------------------------------------------------
::NF.SetThirdPerson <- function(p, on)
{
	if (!NF.Valid(p) || IsPlayerABot(p)) return;
	local st = NF.State(p);
	st.thirdPerson = on;
	try { NetProps.SetPropFloat(p, "m_TimeForceExternalView", on ? Time() + 3.0 : 0.0); }
	catch (e) { printl("[Nightfall] third person not available: " + e); }
}

// Called every second: keep the camera out for everyone who wants it
::NF.UpdateThirdPerson <- function()
{
	foreach (s in NF.Survivors())
	{
		if (IsPlayerABot(s)) continue;
		local st = NF.State(s);
		if (st.thirdPerson == null) st.thirdPerson = NF.Config.ThirdPerson;
		if (!st.thirdPerson) continue;
		try { NetProps.SetPropFloat(s, "m_TimeForceExternalView", Time() + 3.0); } catch (e) {}
	}
}

//-----------------------------------------------------------------------------
// Bindable commands:  bind q "scripted_user_func skill"
// L4D2 routes scripted_user_func to UserConsoleCommand in the mode script.
//-----------------------------------------------------------------------------
::NF.OnUserCommand <- function(p, arg)
{
	if (!NF.IsSurvivor(p) || p.IsDead()) return;
	local st = NF.State(p);
	local parts = split(arg.tolower(), ",");
	if (parts.len() == 0) return;
	switch (strip(parts[0]))
	{
		case "skill": if (!p.IsIncapacitated()) NF.TrySkill(p, st); break;
		case "ult":   if (!p.IsIncapacitated()) NF.TryUlt(p, st); break;
		case "flask": NF.DrinkFlask(p); break;
		case "dodge": if (!p.IsIncapacitated()) NF.TryDodge(p, st); break;
		case "camera": NF.SetThirdPerson(p, !st.thirdPerson); break;
	}
}
