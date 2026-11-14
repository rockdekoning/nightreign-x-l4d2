//=============================================================================
// Nightfall — shared state, constants and helpers
//=============================================================================

::NF <- {
	Version = "0.1.0"
	Initialized = false

	// Per-survivor state, keyed by survivor character index (survives bot/human swaps)
	Players = {}

	// Run state
	Day = 1
	Omen = null
	Timers = []
	DamageLog = []      // [{t, victim, dmg}] used by the Shade's Restage
	Marks = {}          // entindex -> expire time (Hawkeye marks)
	Totems = []         // Berserker War Totems
	Stains = []         // dropped runes on death
	Bosses = {}         // entindex -> {kind, name, phase}
	PendingElites = 0
	PendingBoss = null
	NightlordPending = false
	TideDamageActive = false
	AbilityDamageActive = false
	LastSlowTick = 0.0
	LastBotTick = 0.0
	World = null
	ThinkEnt = null
}

::NF.BTN <- {
	ATTACK  = 1
	JUMP    = 2
	DUCK    = 4
	USE     = 32
	ATTACK2 = 2048      // shove
	RELOAD  = 8192
	WALK    = 131072    // IN_SPEED (shift / walk in L4D2)
}

::NF.DMG <- {
	GENERIC = 0
	BULLET  = 2
	SLASH   = 4
	BURN    = 8
	BLAST   = 64
	CLUB    = 128
}

::NF.MASK_SHOT <- 1174421515

// Chat colours are written as tokens ({d} default, {l} light green, {g} green, {o} olive)
// and swapped for the real control characters when a message is sent. Writing the raw
// "\x04"-style escapes inline is unsafe: Squirrel reads up to four hex digits, so an
// escape followed by a letter A-F would be misread.
::NF.ColorTokens <- {
	d = (1).tochar()
	l = (3).tochar()
	g = (4).tochar()
	o = (5).tochar()
}

::NF.Colorize <- function(msg)
{
	local out = "";
	local i = 0;
	while (true)
	{
		local j = msg.find("{", i);
		if (j == null || j + 2 >= msg.len()) break;
		local key = msg.slice(j + 1, j + 2);
		if (msg[j + 2] == '}' && (key in NF.ColorTokens))
		{
			out += msg.slice(i, j) + NF.ColorTokens[key];
			i = j + 3;
		}
		else
		{
			out += msg.slice(i, j + 1);
			i = j + 1;
		}
	}
	return out + msg.slice(i);
}

//-----------------------------------------------------------------------------
// Messaging
//-----------------------------------------------------------------------------
::NF.Say <- function(msg)
{
	ClientPrint(null, 3, NF.Colorize("{g}[Nightfall]{d} " + msg));
}

::NF.Tell <- function(p, msg)
{
	if (p && p.IsValid() && !IsPlayerABot(p))
		ClientPrint(p, 3, NF.Colorize("{g}[Nightfall]{d} " + msg));
}

::NF.Center <- function(p, msg)
{
	if (p && p.IsValid() && !IsPlayerABot(p))
		ClientPrint(p, 4, msg);
}

::NF.CenterAll <- function(msg)
{
	ClientPrint(null, 4, msg);
}

//-----------------------------------------------------------------------------
// Timers (driven by NF.Think)
//-----------------------------------------------------------------------------
::NF.After <- function(delay, fn)
{
	NF.Timers.append({ at = Time() + delay, fn = fn });
}

::NF.RunTimers <- function()
{
	if (NF.Timers.len() == 0)
		return;
	local now = Time();
	local due = [];
	local keep = [];
	foreach (t in NF.Timers)
	{
		if (t.at <= now) due.append(t);
		else keep.append(t);
	}
	NF.Timers = keep;
	foreach (t in due)
	{
		try { t.fn(); }
		catch (e) { printl("[Nightfall] timer error: " + e); }
	}
}

//-----------------------------------------------------------------------------
// Entity helpers
//-----------------------------------------------------------------------------
::NF.Valid <- function(ent)
{
	return ent != null && ent.IsValid();
}

::NF.IsSurvivor <- function(ent)
{
	return NF.Valid(ent) && ent.GetClassname() == "player" && ent.IsSurvivor();
}

::NF.IsEnemy <- function(ent)
{
	if (!NF.Valid(ent))
		return false;
	local cls = ent.GetClassname();
	if (cls == "infected" || cls == "witch")
		return true;
	if (cls == "player")
		return !ent.IsSurvivor();
	return false;
}

::NF.IsSpecial <- function(ent)
{
	return NF.Valid(ent) && ent.GetClassname() == "player" && !ent.IsSurvivor();
}

::NF.IsTank <- function(ent)
{
	return NF.IsSpecial(ent) && ent.GetZombieType() == 8;
}

::NF.Alive <- function(ent)
{
	if (!NF.Valid(ent))
		return false;
	if (ent.GetClassname() == "player")
		return !ent.IsDead();
	return ent.GetHealth() > 0;
}

::NF.Key <- function(p)
{
	return NetProps.GetPropInt(p, "m_survivorCharacter");
}

::NF.Survivors <- function()
{
	local list = [];
	local ent = null;
	while (ent = Entities.FindByClassname(ent, "player"))
	{
		if (ent.IsSurvivor() && !ent.IsDead())
			list.append(ent);
	}
	return list;
}

::NF.AllSurvivors <- function()
{
	local list = [];
	local ent = null;
	while (ent = Entities.FindByClassname(ent, "player"))
	{
		if (ent.IsSurvivor())
			list.append(ent);
	}
	return list;
}

::NF.Specials <- function()
{
	local list = [];
	local ent = null;
	while (ent = Entities.FindByClassname(ent, "player"))
	{
		if (!ent.IsSurvivor() && !ent.IsDead())
			list.append(ent);
	}
	return list;
}

::NF.EnemiesInRadius <- function(pos, radius)
{
	local out = [];
	local ent = null;
	while (ent = Entities.FindByClassnameWithin(ent, "infected", pos, radius))
		if (ent.GetHealth() > 0) out.append(ent);
	ent = null;
	while (ent = Entities.FindByClassnameWithin(ent, "witch", pos, radius))
		if (ent.GetHealth() > 0) out.append(ent);
	ent = null;
	while (ent = Entities.FindByClassnameWithin(ent, "player", pos, radius))
		if (!ent.IsSurvivor() && !ent.IsDead()) out.append(ent);
	return out;
}

::NF.AlliesInRadius <- function(pos, radius, includeIncapped)
{
	local out = [];
	foreach (s in NF.Survivors())
	{
		if (!includeIncapped && s.IsIncapacitated())
			continue;
		if ((s.GetOrigin() - pos).Length() <= radius)
			out.append(s);
	}
	return out;
}

::NF.AimTrace <- function(p, dist)
{
	local start = p.EyePosition();
	local fwd = p.EyeAngles().Forward();
	local t = { start = start, end = start + fwd * dist, ignore = p, mask = NF.MASK_SHOT };
	TraceLine(t);
	if (!("pos" in t))
		t.pos <- t.end;
	return t;
}

::NF.HasLOS <- function(fromPos, toEnt, ignore)
{
	local t = { start = fromPos, end = toEnt.GetCenter(), ignore = ignore, mask = NF.MASK_SHOT };
	TraceLine(t);
	if (!t.hit) return true;
	return ("enthit" in t) && t.enthit == toEnt;
}

::NF.SetGlow <- function(ent, r, g, b)
{
	try
	{
		NetProps.SetPropInt(ent, "m_Glow.m_iGlowType", 3);
		NetProps.SetPropInt(ent, "m_Glow.m_glowColorOverride", r + g * 256 + b * 65536);
	}
	catch (e) {}
}

::NF.ClearGlow <- function(ent)
{
	try { NetProps.SetPropInt(ent, "m_Glow.m_iGlowType", 0); } catch (e) {}
}

::NF.SetAlpha <- function(p, alpha)
{
	try
	{
		NetProps.SetPropInt(p, "m_nRenderMode", alpha < 255 ? 1 : 0);
		NetProps.SetPropInt(p, "m_clrRender", 255 + 255 * 256 + 255 * 65536 + alpha * 16777216);
	}
	catch (e) {}
}

//-----------------------------------------------------------------------------
// Combat helpers
//-----------------------------------------------------------------------------

// Damage everything hostile in a sphere. Staggers special infected if asked.
::NF.AoE <- function(attacker, pos, radius, dmgCommon, dmgSpecial, stagger, dmgType)
{
	local hits = 0;
	if (radius >= 150)
	{
		NF.BlastFX(pos + Vector(0, 0, 16));
		NF.Shake(pos, 10, 0.6, radius * 2);
	}
	NF.AbilityDamageActive = true;
	foreach (e in NF.EnemiesInRadius(pos, radius))
	{
		local isPlayer = e.GetClassname() == "player";
		local dmg = isPlayer ? dmgSpecial : dmgCommon;
		if (e.GetClassname() == "witch") dmg = dmgSpecial;
		try { e.TakeDamage(dmg.tofloat(), dmgType, attacker); } catch (err) {}
		if (stagger && isPlayer && !e.IsDead())
		{
			try { e.Stagger(pos); } catch (err) {}
		}
		hits++;
	}
	NF.AbilityDamageActive = false;
	return hits;
}

::NF.Heal <- function(p, amount)
{
	if (!NF.Alive(p) || p.IsIncapacitated())
		return;
	local hp = p.GetHealth();
	local mx = p.GetMaxHealth();
	local buf = p.GetHealthBuffer();
	local nhp = hp + amount.tointeger();
	if (nhp > mx) nhp = mx;
	p.SetHealth(nhp);
	// Temporary health may not push the total above max
	if (nhp + buf > mx)
		p.SetHealthBuffer((mx - nhp).tofloat());
}

::NF.Impulse <- function(p, vec)
{
	try { p.ApplyAbsVelocityImpulse(vec); }
	catch (e) { try { p.SetVelocity(p.GetVelocity() + vec); } catch (e2) {} }
}

//-----------------------------------------------------------------------------
// Per-player state
//-----------------------------------------------------------------------------
::NF.NewState <- function()
{
	return {
		cls = null
		level = 1
		runes = 0
		flask = 3
		ult = 0.0
		skillReadyAt = 0.0
		prevButtons = 0
		lastDuck = -10.0
		lastShove = -10.0
		dodgeReadyAt = 0.0
		invulnUntil = 0.0
		downs = 0
		reviveProgress = 0.0
		reviveNeeded = 100.0
		lastReviveHit = 0.0
		secondWindUsed = false
		buffs = {}
		lastSpeed = -1.0
		familiarNext = 0.0
		behindSince = 0.0
		thirdPerson = null      // null = not chosen yet, use NF.Config.ThirdPerson
	};
}

::NF.State <- function(p)
{
	local k = NF.Key(p);
	if (!(k in NF.Players))
		NF.Players[k] <- NF.NewState();
	return NF.Players[k];
}

::NF.AddBuff <- function(st, name, dur)
{
	st.buffs[name] <- Time() + dur;
}

::NF.HasBuff <- function(st, name)
{
	return (name in st.buffs) && st.buffs[name] > Time();
}

::NF.Invuln <- function(p, dur)
{
	local st = NF.State(p);
	local until = Time() + dur;
	if (until > st.invulnUntil)
		st.invulnUntil = until;
}
