//=============================================================================
// Nightfall — Melted assets
//
// The converter (tools/melt.py) turns models from YOUR OWN Nightreign install
// into L4D2 models and packs them into a second addon, nightfall_assets.vpk.
// That addon carries a small script, nightfall_assets_manifest.nut, which
// tells the mod which roles have a converted model:
//
//   ::NF_ASSETS <- {
//       hero_vanguard = "models/nightfall/hero_vanguard.mdl"
//       nightlord     = "models/nightfall/nightlord.mdl"
//       commons       = ["models/nightfall/common_0.mdl", ...]
//       ...
//   }
//
// No asset pack installed? Everything falls back to the vanilla models.
//=============================================================================

::NF.Assets <- {};
::NF.AssetsLoaded <- false;
::NF.SeenCommons <- {};

// zombie type -> role name
::NF.SpecialRoles <- {
	[1] = "smoker",
	[2] = "boomer",
	[3] = "hunter",
	[4] = "spitter",
	[5] = "jockey",
	[6] = "charger"
};

::NF.LoadAssets <- function()
{
	local root = getroottable();
	if ("NF_ASSETS" in root)
		delete root.NF_ASSETS;
	local found = false;
	try { found = IncludeScript("nightfall_assets_manifest"); } catch (e) { found = false; }
	if (!found || !("NF_ASSETS" in getroottable()))
	{
		printl("[Nightfall] no melted asset pack found - using vanilla models");
		return;
	}
	NF.Assets = ::NF_ASSETS;

	// Precache everything up front so swaps never hitch mid-fight
	local n = 0;
	foreach (role, path in NF.Assets)
	{
		if (typeof path == "array")
		{
			foreach (p in path) { PrecacheModel(p); n++; }
		}
		else if (typeof path == "string")
		{
			PrecacheModel(path);
			n++;
		}
	}
	NF.AssetsLoaded = n > 0;
	printl("[Nightfall] melted asset pack loaded: " + n + " models");
}

::NF.AssetFor <- function(role)
{
	if (!NF.AssetsLoaded || !(role in NF.Assets)) return null;
	local v = NF.Assets[role];
	if (typeof v == "array")
		return v.len() > 0 ? v[RandomInt(0, v.len() - 1)] : null;
	return v;
}

::NF.SwapModel <- function(ent, path)
{
	if (path == null || !NF.Valid(ent)) return false;
	try
	{
		ent.SetModel(path);
		return true;
	}
	catch (e)
	{
		printl("[Nightfall] model swap failed for " + path + ": " + e);
		return false;
	}
}

//-----------------------------------------------------------------------------
// Survivors wear the hero of their class
//-----------------------------------------------------------------------------
::NF.ApplyHeroModel <- function(p)
{
	if (!NF.AssetsLoaded || !NF.IsSurvivor(p)) return;
	local st = NF.State(p);
	if (!("origModel" in st))
		st.origModel <- p.GetModelName();

	local path = st.cls != null ? NF.AssetFor("hero_" + st.cls) : null;
	if (path == null)
	{
		// This class has no converted model: go back to the original survivor
		if (p.GetModelName() != st.origModel) NF.SwapModel(p, st.origModel);
		return;
	}
	if (p.GetModelName() != path) NF.SwapModel(p, path);
}

//-----------------------------------------------------------------------------
// Enemies
//-----------------------------------------------------------------------------
::NF.ApplySpecialModel <- function(p, elite)
{
	if (!NF.AssetsLoaded) return;
	local zt = p.GetZombieType();
	if (!(zt in NF.SpecialRoles)) return;
	local role = NF.SpecialRoles[zt];
	local path = null;
	if (elite) path = NF.AssetFor("elite_" + role);
	if (path == null) path = NF.AssetFor("special_" + role);
	NF.SwapModel(p, path);
}

::NF.ApplyTankModel <- function(p, kind)
{
	if (!NF.AssetsLoaded) return;
	local path = null;
	if (kind == "nightlord") path = NF.AssetFor("nightlord");
	else if (kind == "field") path = NF.AssetFor("field_boss");
	if (path == null) path = NF.AssetFor("tank");
	NF.SwapModel(p, path);
}

::NF.ApplyWitchModel <- function(w)
{
	if (!NF.AssetsLoaded) return;
	NF.SwapModel(w, NF.AssetFor("witch"));
}

// Commons are swapped as they appear. Runs every 0.5s.
::NF.UpdateCommonModels <- function()
{
	if (!NF.AssetsLoaded || !("commons" in NF.Assets)) return;
	local live = {};
	local ent = null;
	while (ent = Entities.FindByClassname(ent, "infected"))
	{
		local idx = ent.GetEntityIndex();
		live[idx] <- true;
		if (idx in NF.SeenCommons) continue;
		NF.SeenCommons[idx] <- true;
		if (ent.GetHealth() > 0) NF.SwapModel(ent, NF.AssetFor("commons"));
	}
	// forget entity slots that were freed so recycled indices get swapped again
	local stale = [];
	foreach (idx, v in NF.SeenCommons) if (!(idx in live)) stale.append(idx);
	foreach (idx in stale) delete NF.SeenCommons[idx];
}
