//=============================================================================
// NIGHTFALL — Reign of the Long Night
// A Nightreign-style roguelite mutation for Left 4 Dead 2.
//
// Mode script for the "nightfall" mutation (modes/nightfall.txt).
// Start a game with:   map c1m1_hotel nightfall
//                 or:   mp_gamemode nightfall   then load any campaign map
//=============================================================================

printl("[Nightfall] loading mode script");

IncludeScript("nightfall/nf_util");
IncludeScript("nightfall/nf_classes");
IncludeScript("nightfall/nf_progression");
IncludeScript("nightfall/nf_night");
IncludeScript("nightfall/nf_hud");
IncludeScript("nightfall/nf_assets");
IncludeScript("nightfall/nf_fx");
IncludeScript("nightfall/nf_core");

//-----------------------------------------------------------------------------
// Tunables
//-----------------------------------------------------------------------------
::NF.Config <- {
	// Minutes for the Tide to sweep the whole map (it starts slightly behind the saferoom).
	TideMinutes = 10.0
	// The Tide never advances past this much of the map, keeping the exit saferoom safe.
	TideMaxPercent = 90.0
	// Start everyone in the third-person camera. Players switch with !1p / !3p.
	ThirdPerson = true
}

//-----------------------------------------------------------------------------
// Director options
//-----------------------------------------------------------------------------
MutationOptions <-
{
	ActiveChallenge = 1

	// Nightreign has no medkits: everyone carries a Flask of Tears instead.
	weaponsToRemove =
	{
		weapon_first_aid_kit = 0
		weapon_first_aid_kit_spawn = 0
		weapon_pain_pills = 0
		weapon_pain_pills_spawn = 0
		weapon_adrenaline = 0
		weapon_adrenaline_spawn = 0
	}

	function AllowWeaponSpawn(classname)
	{
		if (classname in weaponsToRemove)
			return false;
		return true;
	}

	function ShouldAvoidItem(classname)
	{
		if (classname in weaponsToRemove)
			return true;
		return false;
	}

	// A little more pressure than vanilla coop: this is an expedition, not a stroll.
	CommonLimit = 35
	MaxSpecials = 4
	SpecialRespawnInterval = 25
}

//-----------------------------------------------------------------------------
// Mode callbacks
//-----------------------------------------------------------------------------
function OnGameplayStart()
{
	::NF.Init();
}

function AllowTakeDamage(damageTable)
{
	return ::NF.OnTakeDamage(damageTable);
}

// Console: scripted_user_func skill   (so players can bind their own keys)
function UserConsoleCommand(player, arg)
{
	::NF.OnUserCommand(player, arg);
}

function InterceptChat(message, speaker)
{
	return ::NF.OnChat(message, speaker);
}

//-----------------------------------------------------------------------------
// Game events
//-----------------------------------------------------------------------------
function OnGameEvent_round_start(params)            { ::NF.Init(); }
function OnGameEvent_gauntlet_finale_start(params)  { ::NF.Ev_finale_start(params); }
function OnGameEvent_player_death(params)           { ::NF.Ev_player_death(params); }
function OnGameEvent_infected_death(params)         { ::NF.Ev_infected_death(params); }
function OnGameEvent_witch_killed(params)           { ::NF.Ev_witch_killed(params); }
function OnGameEvent_player_incapacitated(params)   { ::NF.Ev_player_incapacitated(params); }
function OnGameEvent_revive_success(params)         { ::NF.Ev_revive_success(params); }
function OnGameEvent_player_spawn(params)           { ::NF.Ev_player_spawn(params); }
function OnGameEvent_tank_spawn(params)             { ::NF.Ev_tank_spawn(params); }
function OnGameEvent_item_pickup(params)            { ::NF.Ev_item_pickup(params); }
function OnGameEvent_finale_start(params)           { ::NF.Ev_finale_start(params); }
function OnGameEvent_map_transition(params)         { ::NF.Ev_map_transition(params); }
function OnGameEvent_finale_vehicle_leaving(params) { ::NF.Ev_finale_vehicle_leaving(params); }
function OnGameEvent_witch_spawn(params)            { ::NF.Ev_witch_spawn(params); }

::NF.LoadAssets();

__CollectGameEventCallbacks(this);
