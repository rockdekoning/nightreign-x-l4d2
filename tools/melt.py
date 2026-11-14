#!/usr/bin/env python3
"""
Nightfall melt — turn models from YOUR OWN Nightreign install into an L4D2 asset pack.

    python tools/melt.py setup     create tools/melt_config.json and auto-detect paths
    python tools/melt.py check     verify every tool and folder the pipeline needs
    python tools/melt.py scan      list candidate Nightreign model files to put in assets.json
    python tools/melt.py build     convert every role in assets.json and install the addons
    python tools/melt.py build hero_vanguard nightlord    convert only these roles

Nothing is ever written into the Nightreign folder; it is only read. Everything produced
stays on this PC (tools/work/ and your L4D2 addons folder) and is git-ignored.
Nightreign never needs to be running.
"""

from __future__ import annotations

import glob
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
REPO = TOOLS.parent
WORK = TOOLS / "work"
CONFIG_PATH = TOOLS / "melt_config.json"
EXAMPLE_CONFIG = TOOLS / "melt_config.example.json"
ASSETS_PATH = TOOLS / "assets.json"
BLENDER_SCRIPT = TOOLS / "blender" / "flver_to_smd.py"

MODEL_DIR = "nightfall"            # models/nightfall/<role>.mdl
ASSET_ADDON_NAME = "nightfall_assets"
MAIN_ADDON_NAME = "nightfall"


class MeltError(Exception):
    pass


def say(msg: str) -> None:
    print(f"[melt] {msg}", flush=True)


# --------------------------------------------------------------------------------------
# Config
# --------------------------------------------------------------------------------------
def load_json(path: Path) -> dict:
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def load_config() -> dict:
    if not CONFIG_PATH.exists():
        raise MeltError("tools/melt_config.json not found. Run:  python tools/melt.py setup")
    cfg = load_json(CONFIG_PATH)
    ref = Path(cfg.get("reference_dir", "tools/work/reference"))
    cfg["reference_dir"] = str(ref if ref.is_absolute() else REPO / ref)
    return cfg


def steam_library_dirs() -> list[Path]:
    roots = [
        Path(os.environ.get("ProgramFiles(x86)", "C:/Program Files (x86)")) / "Steam",
        Path(os.environ.get("ProgramFiles", "C:/Program Files")) / "Steam",
        Path.home() / ".steam" / "steam",
        Path.home() / ".local" / "share" / "Steam",
    ]
    libs = []
    for root in roots:
        vdf = root / "steamapps" / "libraryfolders.vdf"
        if vdf.exists():
            libs.append(root)
            for m in re.finditer(r'"path"\s+"([^"]+)"', vdf.read_text(encoding="utf-8", errors="ignore")):
                libs.append(Path(m.group(1).replace("\\\\", "/")))
    seen, out = set(), []
    for lib in libs:
        key = str(lib).lower()
        if key not in seen:
            seen.add(key)
            out.append(lib)
    return out


def detect_l4d2() -> str | None:
    for lib in steam_library_dirs():
        cand = lib / "steamapps" / "common" / "Left 4 Dead 2"
        if (cand / "left4dead2").is_dir():
            return str(cand)
    return None


def detect_blender() -> str | None:
    found = shutil.which("blender")
    if found:
        return found
    pf = os.environ.get("ProgramFiles", "C:/Program Files")
    hits = sorted(glob.glob(os.path.join(pf, "Blender Foundation", "Blender*", "blender.exe")))
    return hits[-1] if hits else None


def cmd_setup(_args: list[str]) -> None:
    if CONFIG_PATH.exists():
        say(f"{CONFIG_PATH} already exists; edit it directly. Delete it to regenerate.")
        return
    cfg = load_json(EXAMPLE_CONFIG)
    l4d2 = detect_l4d2()
    if l4d2:
        cfg["l4d2_dir"] = l4d2
        say(f"found Left 4 Dead 2: {l4d2}")
    blender = detect_blender()
    if blender:
        cfg["blender"] = blender
        say(f"found Blender: {blender}")
    with open(CONFIG_PATH, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2)
    say(f"wrote {CONFIG_PATH}. Fill in the remaining paths, then run:  python tools/melt.py check")


# --------------------------------------------------------------------------------------
# Check
# --------------------------------------------------------------------------------------
def tool_paths(cfg: dict) -> dict[str, Path]:
    l4d2 = Path(cfg["l4d2_dir"])
    return {
        "studiomdl": l4d2 / "bin" / "studiomdl.exe",
        "vpk": l4d2 / "bin" / "vpk.exe",
        "game": l4d2 / "left4dead2",
        "addons": l4d2 / "left4dead2" / "addons",
    }


def cmd_check(_args: list[str]) -> bool:
    cfg = load_config()
    tp = tool_paths(cfg)
    checks = [
        ("Nightreign unpacked folder", Path(cfg["nightreign_unpacked"]), True,
         "Unpack your Nightreign install with an unpacker that supports it (e.g. UXM Selective Unpack or "
         "Smithbox) and point 'nightreign_unpacked' at the result. It should contain a 'chr' folder."),
        ("WitchyBND", Path(cfg["witchybnd"]), True,
         "Download WitchyBND and set 'witchybnd'. Nightreign's archives are Oodle-compressed: copy "
         "oo2core_9_win64.dll from your Nightreign game folder next to WitchyBND.exe."),
        ("Blender", Path(cfg["blender"]), True,
         "Install Blender with Blender Source Tools and a FromSoftware FLVER importer add-on."),
        ("texconv", Path(cfg["texconv"]), True, "Download texconv.exe (Microsoft DirectXTex) and set 'texconv'."),
        ("VTFCmd", Path(cfg["vtfcmd"]), True, "Download VTFEdit (includes VTFCmd.exe) and set 'vtfcmd'."),
        ("L4D2 studiomdl", tp["studiomdl"], True, "Install 'Left 4 Dead 2 Authoring Tools' from Steam > Library > Tools."),
        ("L4D2 vpk.exe", tp["vpk"], True, "vpk.exe ships with L4D2 in the bin folder."),
        ("L4D2 addons folder", tp["addons"], True, "Check 'l4d2_dir' in melt_config.json."),
        ("Reference models folder", Path(cfg["reference_dir"]), False,
         "Decompile the L4D2 reference models listed in assets.json with Crowbar into this folder "
         "(see docs/MELTING.md)."),
    ]
    ok = True
    for name, path, required, fix in checks:
        exists = path.exists()
        mark = "OK " if exists else ("MISSING" if required else "todo")
        print(f"  [{mark:7}] {name}: {path}")
        if not exists:
            print(f"            -> {fix}")
            ok = ok and not required
    nr = Path(cfg["nightreign_unpacked"])
    if nr.exists() and not (nr / "chr").is_dir():
        print("  [WARN   ] the unpacked Nightreign folder has no 'chr' subfolder - is it fully unpacked?")
    # Reference decompiles for roles that have sources
    assets = load_json(ASSETS_PATH)["roles"]
    for role, spec in assets.items():
        if spec.get("source"):
            try:
                find_reference(cfg, spec["reference"])
                print(f"  [OK     ] reference for {role}: {spec['reference']}")
            except MeltError as e:
                print(f"  [MISSING] reference for {role}: {e}")
                ok = False
    print()
    say("all good - run:  python tools/melt.py build" if ok else "fix the MISSING items above first")
    return ok


# --------------------------------------------------------------------------------------
# Scan
# --------------------------------------------------------------------------------------
def cmd_scan(_args: list[str]) -> None:
    cfg = load_config()
    root = Path(cfg["nightreign_unpacked"])
    if not root.exists():
        raise MeltError(f"unpacked Nightreign folder not found: {root}")
    for sub, pattern in (("chr", "*.chrbnd.dcx"), ("parts", "*.partsbnd.dcx")):
        files = sorted((root / sub).glob(pattern)) if (root / sub).is_dir() else []
        print(f"\n{sub}/  ({len(files)} files)")
        for f in files:
            print(f"  {sub}/{f.name:40} {f.stat().st_size / 1_048_576:7.1f} MB")
    print("\nIdentify which ID is which character in Smithbox's model viewer, then add the paths to "
          "the 'source' lists in tools/assets.json.")


# --------------------------------------------------------------------------------------
# Build helpers
# --------------------------------------------------------------------------------------
def run(cmd: list[str], cwd: Path | None = None, what: str = "") -> subprocess.CompletedProcess:
    say(f"  $ {' '.join(str(c) for c in cmd)}")
    try:
        proc = subprocess.run([str(c) for c in cmd], cwd=str(cwd) if cwd else None,
                              capture_output=True, text=True, errors="replace")
    except OSError as e:
        raise MeltError(f"could not start {what or cmd[0]}: {e}. Run 'python tools/melt.py check'.") from e
    WORK.mkdir(parents=True, exist_ok=True)
    with open(WORK / "melt.log", "a", encoding="utf-8") as log:
        log.write(f"\n$ {' '.join(str(c) for c in cmd)}\n{proc.stdout}{proc.stderr}\n[exit {proc.returncode}]\n")
    if proc.returncode != 0:
        tail = "\n".join((proc.stdout + proc.stderr).strip().splitlines()[-25:])
        raise MeltError(f"{what or cmd[0]} failed (exit {proc.returncode}):\n{tail}")
    return proc


def find_reference(cfg: dict, reference_model: str) -> tuple[Path, Path]:
    """Return (decompile folder, qc file) for an L4D2 model decompiled with Crowbar."""
    stem = Path(reference_model).with_suffix("")
    ref_root = Path(cfg["reference_dir"])
    candidates = [ref_root / stem, ref_root / stem.name]
    for folder in candidates:
        if folder.is_dir():
            qcs = sorted(folder.glob("*.qc"))
            if qcs:
                return folder, qcs[0]
    raise MeltError(f"no Crowbar decompile of '{reference_model}' in {ref_root} "
                    f"(expected a .qc in {candidates[0]})")


QC_BLOCK_DROP = ("$bodygroup", "$texturegroup", "$lod", "$shadowlod")
QC_LINE_DROP = ("$modelname", "$cdmaterials", "$body", "$model", "$texturegroup")


def qc_reference_mesh(qc_text: str) -> str | None:
    """The first mesh SMD referenced by a QC ($body, $model or the first $bodygroup studio)."""
    m = re.search(r'^\s*\$(?:body|model)\s+"?[^"\s]+"?\s+"([^"]+)"', qc_text, re.M | re.I)
    if m:
        return m.group(1)
    m = re.search(r'\$bodygroup[^{]*\{[^}]*?studio\s+"([^"]+)"', qc_text, re.I | re.S)
    return m.group(1) if m else None


def rewrite_qc(qc_text: str, model_name: str, cdmaterials: str, body_smd: str) -> str:
    """Keep the reference's skeleton, animations, hitboxes, attachments and physics;
    swap only the mesh, model name and material folder."""
    out, depth, skipping = [], 0, False
    lines = qc_text.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        low = line.strip().lower()
        if skipping:
            depth += line.count("{") - line.count("}")
            if depth <= 0 and ("}" in line or "{" in line):
                skipping = False
            i += 1
            continue
        if low.startswith(QC_BLOCK_DROP):
            depth = line.count("{") - line.count("}")
            # block may open on the next line
            if depth == 0 and i + 1 < len(lines) and lines[i + 1].strip().startswith("{"):
                i += 1
                depth = lines[i].count("{") - lines[i].count("}")
            skipping = depth > 0
            i += 1
            continue
        if low.startswith(QC_LINE_DROP):
            # $model can carry a { flex block }
            if "{" in line and line.count("{") > line.count("}"):
                skipping, depth = True, line.count("{") - line.count("}")
            elif i + 1 < len(lines) and lines[i + 1].strip().startswith("{") and low.startswith("$model"):
                i += 1
                skipping, depth = True, lines[i].count("{") - lines[i].count("}")
            i += 1
            continue
        out.append(line)
        i += 1
    header = [
        "// Generated by Nightfall melt from a Crowbar decompile of the vanilla model.",
        f'$modelname "{model_name}"',
        f'$cdmaterials "{cdmaterials}"',
        f'$body "body" "{body_smd}"',
        "",
    ]
    return "\n".join(header + out) + "\n"


TEX_ALBEDO = re.compile(r"_a(\d*)$", re.I)
TEX_NORMAL = re.compile(r"_n(\d*)$", re.I)


def pick_textures(images: list[str], dds_index: dict[str, Path], original: str) -> tuple[Path | None, Path | None]:
    names = [n for n in images if n.lower() in dds_index]
    if not names:
        # fall back to any texture whose name contains the material's name
        key = re.sub(r"[^a-z0-9]", "", original.lower())
        names = [n for n in dds_index if key and key in re.sub(r"[^a-z0-9]", "", n)]
    albedo = next((dds_index[n.lower()] for n in names if TEX_ALBEDO.search(n)), None)
    normal = next((dds_index[n.lower()] for n in names if TEX_NORMAL.search(n)), None)
    return albedo, normal


def rebuild_normal(tga: Path, flip_green: bool) -> None:
    """FromSoftware normal maps are two-channel (BC5); Source wants a full RGB normal."""
    try:
        from PIL import Image, ImageChops  # type: ignore
    except ImportError:
        say("    (Pillow not installed - normal map left as-is; pip install pillow)")
        return
    img = Image.open(tga).convert("RGB")
    r, g, _ = img.split()
    try:
        import numpy as np  # type: ignore
        nx = np.asarray(r, dtype=np.float32) / 127.5 - 1.0
        ny = np.asarray(g, dtype=np.float32) / 127.5 - 1.0
        nz = np.sqrt(np.clip(1.0 - nx * nx - ny * ny, 0.0, 1.0))
        b = Image.fromarray(((nz * 0.5 + 0.5) * 255).astype(np.uint8), "L")
    except ImportError:
        # Without numpy, a flat "pointing straight out" blue channel is a close approximation.
        b = Image.new("L", img.size, 255)
    if flip_green:
        g = ImageChops.invert(g)
    Image.merge("RGB", (r, g, b)).save(tga)


def convert_texture(cfg: dict, dds: Path, out_dir: Path, out_stem: str, normal: bool) -> None:
    tmp = out_dir / "_tga"
    tmp.mkdir(parents=True, exist_ok=True)
    run([cfg["texconv"], "-ft", "tga", "-y", "-o", tmp, dds], what="texconv")
    tga = tmp / (dds.stem + ".tga")
    if not tga.exists():
        raise MeltError(f"texconv produced no TGA for {dds.name}")
    if normal:
        rebuild_normal(tga, bool(cfg.get("flip_normal_green", False)))
    final_tga = tmp / (out_stem + ".tga")
    shutil.move(str(tga), final_tga)
    # Normal maps stay uncompressed: DXT compression makes lighting look blocky.
    fmt, alpha_fmt = ("bgr888", "bgra8888") if normal else ("dxt1", "dxt5")
    run([cfg["vtfcmd"], "-file", final_tga, "-output", out_dir, "-format", fmt, "-alphaformat", alpha_fmt], what="VTFCmd")


def write_vmt(path: Path, base: str | None, bump: str | None, original: str) -> None:
    lines = ['"VertexLitGeneric"', "{"]
    lines.append(f'\t"$basetexture" "{base}"' if base else '\t"$basetexture" "vgui/white"')
    if not base:
        lines.append('\t"$color" "[0.55 0.55 0.55]"')
    if bump:
        lines.append(f'\t"$bumpmap" "{bump}"')
    if re.search(r"hair|fur|cloth_?alpha|feather|veil", original, re.I):
        lines.append('\t"$alphatest" "1"')
        lines.append('\t"$nocull" "1"')
    lines.append('\t"$halflambert" "1"')
    lines.append("}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def unpack_archives(cfg: dict, folder: Path) -> None:
    """Unpack every BND/DCX and then every TPF under folder with WitchyBND."""
    args = cfg.get("witchybnd_args", [])
    done: set[Path] = set()
    for _ in range(3):  # archives can contain archives
        todo = [p for p in folder.rglob("*")
                if p.is_file() and p not in done
                and re.search(r"\.(chrbnd|partsbnd|texbnd|anibnd)(\.dcx)?$|\.tpf(\.dcx)?$", p.name, re.I)]
        if not todo:
            break
        for p in todo:
            done.add(p)
            run([cfg["witchybnd"], *args, p], what=f"WitchyBND ({p.name})")


def stage_sources(cfg: dict, sources: list[str], dest: Path) -> list[Path]:
    """Copy source archives out of the Nightreign folder (read-only) into the work folder."""
    root = Path(cfg["nightreign_unpacked"])
    dest.mkdir(parents=True, exist_ok=True)
    staged = []
    for rel in sources:
        src = Path(rel) if Path(rel).is_absolute() else root / rel
        if not src.exists():
            raise MeltError(f"source file not found: {src}")
        shutil.copy2(src, dest / src.name)
        staged.append(dest / src.name)
        # chrbnds keep their textures in sibling texbnds (cXXXX.texbnd.dcx, cXXXX_h.texbnd.dcx, ...)
        stem = src.name.split(".")[0]
        for tex in src.parent.glob(f"{stem}*.texbnd*"):
            shutil.copy2(tex, dest / tex.name)
    return staged


# --------------------------------------------------------------------------------------
# Build one role
# --------------------------------------------------------------------------------------
def build_role(cfg: dict, role: str, spec: dict, staging: Path) -> str:
    tp = tool_paths(cfg)
    rdir = WORK / "roles" / role
    if rdir.exists():
        shutil.rmtree(rdir)
    src_dir, blend_dir, compile_dir = rdir / "src", rdir / "blender", rdir / "compile"
    blend_dir.mkdir(parents=True)

    # 1. reference skeleton
    ref_folder, ref_qc = find_reference(cfg, spec["reference"])
    qc_text = ref_qc.read_text(encoding="utf-8", errors="ignore")
    ref_mesh = qc_reference_mesh(qc_text)
    if not ref_mesh or not (ref_folder / ref_mesh).exists():
        raise MeltError(f"could not find the reference mesh SMD in {ref_qc}")

    # 2. source files
    sources = spec["source"]
    direct = [s for s in sources if s.lower().endswith((".fbx", ".smd"))]
    if direct:
        model_files = [Path(s) if Path(s).is_absolute() else REPO / s for s in direct]
        src_dir.mkdir(parents=True)
    else:
        stage_sources(cfg, sources, src_dir)
        unpack_archives(cfg, src_dir)
        model_files = sorted(src_dir.rglob("*.flver"))
        # LOD meshes (_1.flver, _2.flver) would double up the model
        primary = [p for p in model_files if not re.search(r"_\d\.flver$", p.name, re.I)]
        model_files = primary or model_files
    if not model_files:
        raise MeltError("no .flver/.fbx model found in the source files")

    # 3. Blender: fit onto the L4D2 skeleton, export SMD
    job = {
        "role": role,
        "sources": [str(p) for p in model_files],
        "reference_smd": str(ref_folder / ref_mesh),
        "rig": spec.get("rig", "humanoid"),
        "scale": spec.get("scale", 1.0),
        "bone_map": spec.get("bone_map"),
        "rigid_bone": spec.get("rigid_bone"),
        "flver_operator": cfg.get("flver_import_operator", "import_scene.flver"),
        "out_dir": str(blend_dir),
        "materials_json": str(blend_dir / "materials.json"),
    }
    job_path = rdir / "job.json"
    job_path.write_text(json.dumps(job, indent=2), encoding="utf-8")
    run([cfg["blender"], "--background", "--python", BLENDER_SCRIPT, "--", job_path], what="Blender")

    # 4. textures + materials
    materials = load_json(blend_dir / "materials.json")
    tex_dirs = [src_dir] + sorted({p.parent for p in model_files if src_dir not in p.parents})
    dds_index = {p.stem.lower(): p for d in tex_dirs for p in d.rglob("*.dds")}
    mat_rel = f"models/{MODEL_DIR}/{role}"
    mat_out = staging / "materials" / mat_rel
    mat_out.mkdir(parents=True, exist_ok=True)
    missing = 0
    for mat_name, info in materials.items():
        albedo, normal = pick_textures(info["images"], dds_index, info["original"])
        base = bump = None
        try:
            if albedo:
                convert_texture(cfg, albedo, mat_out, f"{mat_name}_a", normal=False)
                base = f"{mat_rel}/{mat_name}_a"
            if normal:
                convert_texture(cfg, normal, mat_out, f"{mat_name}_n", normal=True)
                bump = f"{mat_rel}/{mat_name}_n"
        except MeltError as e:
            say(f"    texture conversion failed for {mat_name}: {e}")
        if not base:
            missing += 1
        write_vmt(mat_out / f"{mat_name}.vmt", base, bump, info["original"])
    shutil.rmtree(mat_out / "_tga", ignore_errors=True)
    if missing:
        say(f"  {missing} material(s) had no albedo texture and will render flat grey")

    # 5. QC from the reference decompile, compile with studiomdl
    shutil.copytree(ref_folder, compile_dir)
    shutil.copy2(blend_dir / "nf_body.smd", compile_dir / "nf_body.smd")
    model_name = f"{MODEL_DIR}/{role}.mdl"
    qc_path = compile_dir / f"nf_{role}.qc"
    qc_path.write_text(rewrite_qc(qc_text, model_name, f"{mat_rel}/", "nf_body.smd"), encoding="utf-8")
    run([tp["studiomdl"], "-game", tp["game"], "-nop4", "-verbose", qc_path.name], cwd=compile_dir, what="studiomdl")

    # studiomdl writes into the game folder: move the result into our staging area
    built_dir = tp["game"] / "models" / MODEL_DIR
    out_dir = staging / "models" / MODEL_DIR
    out_dir.mkdir(parents=True, exist_ok=True)
    produced = list(built_dir.glob(f"{role}.*"))
    if not any(p.suffix == ".mdl" for p in produced):
        raise MeltError(f"studiomdl reported success but {built_dir / (role + '.mdl')} is missing")
    for p in produced:
        shutil.move(str(p), out_dir / p.name)
    return f"models/{model_name}"


# --------------------------------------------------------------------------------------
# Build all
# --------------------------------------------------------------------------------------
def expand_roles(roles: dict) -> list[tuple[str, str, dict]]:
    """Commons: each source file becomes its own variant (common_0, common_1, ...)."""
    jobs = []
    for role, spec in roles.items():
        if role.startswith("_") or not spec.get("source"):
            continue
        if role == "commons":
            for i, src in enumerate(spec["source"]):
                sub = dict(spec)
                sub["source"] = src if isinstance(src, list) else [src]
                jobs.append((f"common_{i}", "commons", sub))
        else:
            jobs.append((role, role, spec))
    return jobs


def write_manifest(staging: Path, built: dict[str, object]) -> None:
    lines = [
        "// Generated by tools/melt.py - lists the models converted from your Nightreign install.",
        "::NF_ASSETS <- {",
    ]
    for role in sorted(built):
        val = built[role]
        if isinstance(val, list):
            items = ", ".join(f'"{v}"' for v in val)
            lines.append(f"\t{role} = [{items}]")
        else:
            lines.append(f'\t{role} = "{val}"')
    lines.append("}")
    path = staging / "scripts" / "vscripts" / "nightfall_assets_manifest.nut"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_asset_addoninfo(staging: Path) -> None:
    (staging / "addoninfo.txt").write_text(
        '"AddonInfo"\n{\n'
        '\taddonSteamAppID\t\t550\n'
        '\taddontitle\t\t"Nightfall - Melted Assets (local)"\n'
        '\taddonversion\t\t"1.0"\n'
        '\taddonauthor\t\t"generated on this PC by tools/melt.py"\n'
        '\taddonDescription\t"Models converted from your own Nightreign install. Do not redistribute."\n'
        '\taddonContent_Script\t1\n'
        '\taddonContent_prop\t1\n'
        '}\n', encoding="utf-8")


def pack_vpk(cfg: dict, folder: Path, name: str) -> Path:
    tp = tool_paths(cfg)
    run([tp["vpk"], folder], what="vpk.exe")
    vpk = folder.with_suffix(".vpk")
    if not vpk.exists():
        raise MeltError(f"vpk.exe did not create {vpk}")
    dest = tp["addons"] / f"{name}.vpk"
    shutil.copy2(vpk, dest)
    return dest


def cmd_build(args: list[str]) -> None:
    cfg = load_config()
    tp = tool_paths(cfg)
    for need in ("vpk", "addons"):
        if not tp[need].exists():
            raise MeltError(f"{tp[need]} not found - check 'l4d2_dir' in tools/melt_config.json")
    roles = load_json(ASSETS_PATH)["roles"]
    jobs = expand_roles(roles)
    if args:
        wanted = set(args)
        jobs = [j for j in jobs if j[0] in wanted or j[1] in wanted]
    if not jobs:
        say("no roles have a 'source' in tools/assets.json yet - nothing to convert.")
        say("run 'python tools/melt.py scan' to find model files, add them to assets.json, then build again.")

    staging = WORK / ASSET_ADDON_NAME
    # keep previously built roles when rebuilding a subset
    manifest_cache = WORK / "built_roles.json"
    built: dict[str, object] = load_json(manifest_cache) if (args and manifest_cache.exists()) else {}
    if not args and staging.exists():
        shutil.rmtree(staging)
    staging.mkdir(parents=True, exist_ok=True)

    results = []
    for role, group, spec in jobs:
        say(f"=== {role} ===")
        try:
            path = build_role(cfg, role, spec, staging)
            if group == "commons":
                lst = [p for p in built.get("commons", []) if not p.endswith(f"/{role}.mdl")]
                lst.append(path)
                built["commons"] = lst
            else:
                built[role] = path
            results.append((role, "OK", path))
        except (MeltError, OSError, ValueError, KeyError) as e:
            first_line = (str(e).splitlines() or [type(e).__name__])[0]
            results.append((role, "FAILED", first_line))
            say(f"  FAILED: {e}")

    WORK.mkdir(exist_ok=True)
    manifest_cache.write_text(json.dumps(built, indent=2), encoding="utf-8")
    write_manifest(staging, built)
    write_asset_addoninfo(staging)

    installed = []
    if built:
        installed.append(pack_vpk(cfg, staging, ASSET_ADDON_NAME))
    if cfg.get("install_main_mod", True):
        main_stage = WORK / MAIN_ADDON_NAME
        if main_stage.exists():
            shutil.rmtree(main_stage)
        shutil.copytree(REPO / "addon", main_stage)
        installed.append(pack_vpk(cfg, main_stage, MAIN_ADDON_NAME))

    print("\n================ melt summary ================")
    for role, status, info in results:
        print(f"  {status:7} {role:18} {info}")
    for p in installed:
        print(f"  installed {p}")
    print("\nStart L4D2 and run in the console:  map c1m1_hotel nightfall")
    if any(s == "FAILED" for _, s, _ in results):
        print("Some roles failed - those keep their vanilla L4D2 model. Full tool output: tools/work/melt.log")


def main() -> int:
    commands = {"setup": cmd_setup, "check": cmd_check, "scan": cmd_scan, "build": cmd_build}
    argv = sys.argv[1:]
    cmd = argv[0] if argv else "build"
    if cmd in ("-h", "--help", "help") or cmd not in commands:
        print(__doc__)
        return 0 if cmd in ("-h", "--help", "help") else 2
    try:
        if commands[cmd](argv[1:]) is False:
            return 1
    except MeltError as e:
        say(f"ERROR: {e}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
