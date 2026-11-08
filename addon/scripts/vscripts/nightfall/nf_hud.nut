//=============================================================================
// Nightfall — HUD
//=============================================================================

::NF.HUD <- {
	Fields = {
		night = { slot = HUD_MID_TOP,  dataval = "", flags = HUD_FLAG_ALIGN_CENTER | HUD_FLAG_NOBG }
		tide  = { slot = HUD_MID_BOT,  dataval = "", flags = HUD_FLAG_ALIGN_CENTER | HUD_FLAG_NOBG }
		p1    = { slot = HUD_SCORE_1,  dataval = "", flags = HUD_FLAG_ALIGN_LEFT }
		p2    = { slot = HUD_SCORE_2,  dataval = "", flags = HUD_FLAG_ALIGN_LEFT }
		p3    = { slot = HUD_SCORE_3,  dataval = "", flags = HUD_FLAG_ALIGN_LEFT }
		p4    = { slot = HUD_SCORE_4,  dataval = "", flags = HUD_FLAG_ALIGN_LEFT }
	}
}

::NF.SetupHUD <- function()
{
	HUDSetLayout(NF.HUD);
	HUDPlace(HUD_MID_TOP, 0.30, 0.01, 0.40, 0.04);
	HUDPlace(HUD_MID_BOT, 0.30, 0.05, 0.40, 0.035);
	HUDPlace(HUD_SCORE_1, 0.005, 0.30, 0.42, 0.035);
	HUDPlace(HUD_SCORE_2, 0.005, 0.34, 0.42, 0.035);
	HUDPlace(HUD_SCORE_3, 0.005, 0.38, 0.42, 0.035);
	HUDPlace(HUD_SCORE_4, 0.005, 0.42, 0.42, 0.035);
}

::NF.BossLine <- function()
{
	foreach (idx, b in NF.Bosses)
	{
		if (b.kind != "nightlord" && b.kind != "field") continue;
		local e = EntIndexToHScript(idx);
		if (!NF.Alive(e)) continue;
		local pct = (e.GetHealth() * 100 / b.maxhp).tointeger();
		return b.name + "  [" + pct + "%]";
	}
	return null;
}

::NF.UpdateHUD <- function()
{
	local F = NF.HUD.Fields;
	local omen = NF.Omen != null ? NF.Omen.name : "";
	F.night.dataval = "NIGHT " + NF.Day + "  |  Omen: " + omen;

	local boss = NF.BossLine();
	if (boss != null)
		F.tide.dataval = boss;
	else if (NF.Tide.disabled)
		F.tide.dataval = "";
	else if (NF.Tide.paused)
		F.tide.dataval = "The Tide is still";
	else if (!NF.Tide.active)
		F.tide.dataval = NF.AtGrace() ? "Site of Grace  -  !levelup  !class  !nfhelp" : "";
	else
	{
		local t = NF.Tide.pct < 0 ? 0 : NF.Tide.pct.tointeger();
		F.tide.dataval = "Tide " + t + "%   |   Lead " + NF.LeadFlow().tointeger() + "%";
	}

	local slots = [F.p1, F.p2, F.p3, F.p4];
	local i = 0;
	local now = Time();
	foreach (s in NF.AllSurvivors())
	{
		if (i >= 4) break;
		local st = NF.State(s);
		local c = NF.ClassOf(st);
		local cname = c != null ? c.title : "-";
		local line = s.GetPlayerName() + " | " + cname + " Lv" + st.level + " | " + st.runes + "r";
		if (s.IsDead())
			line += " | DEAD";
		else if (s.IsIncapacitated())
			line += " | DOWN " + (st.reviveProgress * 100 / st.reviveNeeded).tointeger() + "%";
		else
		{
			local cd = st.skillReadyAt - now;
			line += " | Skl " + (cd <= 0 ? "OK" : (cd.tointeger() + 1) + "s");
			line += " | Ult " + (st.ult >= 100 ? "OK" : st.ult.tointeger() + "%");
			line += " | Flask " + st.flask;
		}
		slots[i].dataval = line;
		i++;
	}
	for (; i < 4; i++) slots[i].dataval = "";
}
