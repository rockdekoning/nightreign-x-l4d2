"""
Nightfall melt — Blender stage.

Run headless by melt.py:
    blender --background --python flver_to_smd.py -- job.json

What it does for one role:
  1. imports the L4D2 reference SMD (skeleton + mesh, for size and bone layout)
  2. imports the Nightreign model(s) (FLVER via a FromSoftware importer add-on, or FBX)
  3. scales/positions it to match the reference, and for humanoids poses each limb
     so it lines up with the L4D2 skeleton's rest pose
  4. bakes that pose into the mesh, renames/merges vertex groups onto ValveBiped bones
  5. binds the mesh to the L4D2 skeleton and exports nf_body.smd + materials.json

Needs Blender Source Tools (io_scene_valvesource) and, for .flver input, an add-on that
provides the import operator named in the job (default "import_scene.flver").
"""

import json
import os
import re
import sys

import bpy
from mathutils import Matrix, Vector

# --------------------------------------------------------------------------------------
# FromSoftware humanoid bone names -> ValveBiped.  Matched case-insensitively, ignoring
# spaces/underscores, so "L_UpperArm", "L UpperArm" and "l_upperarm" all match.
# Per-role overrides come from "bone_map" in assets.json.
# --------------------------------------------------------------------------------------
VB = "ValveBiped.Bip01_"
DEFAULT_BONE_MAP = {
    "Pelvis": VB + "Pelvis",
    "Spine": VB + "Spine",
    "Spine1": VB + "Spine1",
    "Spine2": VB + "Spine2",
    "Neck": VB + "Neck1",
    "Head": VB + "Head1",
}
for side in ("L", "R"):
    DEFAULT_BONE_MAP.update({
        f"{side}_Clavicle": f"{VB}{side}_Clavicle",
        f"{side}_UpperArm": f"{VB}{side}_UpperArm",
        f"{side}_Forearm": f"{VB}{side}_Forearm",
        f"{side}_Hand": f"{VB}{side}_Hand",
        f"{side}_Thigh": f"{VB}{side}_Thigh",
        f"{side}_Calf": f"{VB}{side}_Calf",
        f"{side}_Foot": f"{VB}{side}_Foot",
        f"{side}_Toe0": f"{VB}{side}_Toe0",
    })
    # fingers: FromSoft Finger0..4 with joints 0..2  ->  Valve Finger0, Finger01, Finger02 ...
    for f in range(5):
        DEFAULT_BONE_MAP[f"{side}_Finger{f}"] = f"{VB}{side}_Finger{f}"
        DEFAULT_BONE_MAP[f"{side}_Finger{f}1"] = f"{VB}{side}_Finger{f}1"
        DEFAULT_BONE_MAP[f"{side}_Finger{f}2"] = f"{VB}{side}_Finger{f}2"

# Which target child bone defines each target bone's direction when aligning limbs.
CHAINS = {
    "Pelvis": "Spine", "Spine": "Spine1", "Spine1": "Spine2", "Spine2": "Neck1", "Neck1": "Head1",
}
for side in ("L", "R"):
    CHAINS.update({
        f"{side}_Clavicle": f"{side}_UpperArm", f"{side}_UpperArm": f"{side}_Forearm",
        f"{side}_Forearm": f"{side}_Hand", f"{side}_Thigh": f"{side}_Calf",
        f"{side}_Calf": f"{side}_Foot", f"{side}_Foot": f"{side}_Toe0",
    })
CHAINS = {VB + k: VB + v for k, v in CHAINS.items()}

PELVIS = VB + "Pelvis"


def log(msg):
    print(f"[melt/blender] {msg}", flush=True)


def norm_name(s):
    return re.sub(r"[\s_.]", "", s).lower()


# --------------------------------------------------------------------------------------
# Scene helpers
# --------------------------------------------------------------------------------------
def clear_scene():
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for block in (bpy.data.meshes, bpy.data.armatures, bpy.data.materials, bpy.data.images):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


def enable_addons():
    import addon_utils
    for mod in ("io_scene_valvesource",):
        try:
            addon_utils.enable(mod, default_set=True)
        except Exception as e:  # noqa: BLE001
            log(f"could not enable add-on {mod}: {e}")


def imported(fn):
    """Run an import function and return the objects it created."""
    before = set(bpy.data.objects)
    fn()
    return [o for o in bpy.data.objects if o not in before]


def resolve_operator(path):
    op = bpy.ops
    for part in path.split("."):
        op = getattr(op, part)
    return op


def world_bbox(objs):
    pts = []
    for o in objs:
        if o.type != "MESH":
            continue
        pts.extend(o.matrix_world @ Vector(c) for c in o.bound_box)
    if not pts:
        return Vector((0, 0, 0)), Vector((0, 0, 0))
    mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return mn, mx


def set_active(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


# --------------------------------------------------------------------------------------
# Stages
# --------------------------------------------------------------------------------------
def import_reference(path):
    objs = imported(lambda: bpy.ops.import_scene.smd(filepath=path))
    arms = [o for o in objs if o.type == "ARMATURE"]
    if not arms:
        raise RuntimeError(f"reference SMD has no skeleton: {path}")
    target = arms[0]
    meshes = [o for o in objs if o.type == "MESH"]
    mn, mx = world_bbox(meshes)
    for m in meshes:
        bpy.data.objects.remove(m, do_unlink=True)
    return target, mn, mx


def import_sources(sources, flver_op):
    new_objs = []
    for src in sources:
        ext = os.path.splitext(src)[1].lower()
        if ext == ".fbx":
            new_objs += imported(lambda: bpy.ops.import_scene.fbx(filepath=src))
        elif ext == ".smd":
            new_objs += imported(lambda: bpy.ops.import_scene.smd(filepath=src))
        else:
            try:
                op = resolve_operator(flver_op)
            except AttributeError:
                raise RuntimeError(
                    f"FLVER import operator '{flver_op}' not found. Install a FromSoftware FLVER "
                    "importer add-on in Blender and set 'flver_import_operator' in melt_config.json, "
                    "or export the model to .fbx yourself and list the .fbx in assets.json."
                )
            new_objs += imported(lambda: op(filepath=src))
    arms = [o for o in new_objs if o.type == "ARMATURE"]
    meshes = [o for o in new_objs if o.type == "MESH"]
    if not meshes:
        raise RuntimeError("no meshes were imported from the source files")
    src_arm = arms[0] if arms else None

    # Several part files (head/body/arms/legs) share one skeleton: keep the first.
    for extra in arms[1:]:
        for m in meshes:
            for mod in m.modifiers:
                if mod.type == "ARMATURE" and mod.object == extra:
                    mod.object = src_arm
            if m.parent == extra:
                mw = m.matrix_world.copy()
                m.parent = src_arm
                m.matrix_world = mw
        bpy.data.objects.remove(extra, do_unlink=True)

    # Make sure every mesh is driven by the source armature and parented to it.
    if src_arm:
        for m in meshes:
            if not any(mod.type == "ARMATURE" for mod in m.modifiers):
                mod = m.modifiers.new("Armature", "ARMATURE")
                mod.object = src_arm
            if m.parent != src_arm:
                mw = m.matrix_world.copy()
                m.parent = src_arm
                m.matrix_world = mw
    # Shape keys block modifier application; converted models don't use them.
    for m in meshes:
        if m.data.shape_keys:
            set_active(m)
            bpy.ops.object.shape_key_remove(all=True)
    return src_arm, meshes


def build_mapping(src_arm, overrides):
    table = {norm_name(k): v for k, v in DEFAULT_BONE_MAP.items()}
    table.update({norm_name(k): v for k, v in (overrides or {}).items()})
    mapping = {}
    if src_arm:
        for b in src_arm.data.bones:
            t = table.get(norm_name(b.name))
            if t:
                mapping[b.name] = t
    return mapping


def fit_scale_and_place(src_arm, meshes, tgt_min, tgt_max, scale_mult):
    mn, mx = world_bbox(meshes)
    src_h = mx.z - mn.z
    tgt_h = tgt_max.z - tgt_min.z
    if src_h <= 1e-6:
        raise RuntimeError("source mesh has zero height")
    factor = (tgt_h / src_h) * scale_mult
    root = src_arm if src_arm else None
    movers = [root] if root else meshes
    for o in movers:
        o.scale = o.scale * factor
        o.location = o.location * factor
    bpy.context.view_layer.update()
    mn, mx = world_bbox(meshes)
    src_center = (mn + mx) / 2
    tgt_center = (tgt_min + tgt_max) / 2
    offset = Vector((tgt_center.x - src_center.x, tgt_center.y - src_center.y, tgt_min.z - mn.z))
    for o in movers:
        o.location = o.location + offset
    bpy.context.view_layer.update()
    log(f"scaled by {factor:.3f} to match reference height {tgt_h:.1f}")


def align_limbs(src_arm, tgt_arm, mapping):
    """Pose each mapped source bone so it points the same way as its L4D2 counterpart."""
    inv = {v: k for k, v in mapping.items()}
    tgt_bones = tgt_arm.data.bones

    def tgt_head(name):
        return tgt_arm.matrix_world @ tgt_bones[name].head_local

    set_active(src_arm)
    bpy.ops.object.mode_set(mode="POSE")
    order = sorted(src_arm.pose.bones, key=lambda pb: len(pb.parent_recursive))
    aligned = 0
    for pb in order:
        tname = mapping.get(pb.name)
        tchild = CHAINS.get(tname) if tname else None
        if not tchild or tchild not in inv or tname not in tgt_bones or tchild not in tgt_bones:
            continue
        spb_child = src_arm.pose.bones.get(inv[tchild])
        if spb_child is None:
            continue
        head = src_arm.matrix_world @ pb.head
        src_dir = (src_arm.matrix_world @ spb_child.head) - head
        tgt_dir = tgt_head(tchild) - tgt_head(tname)
        if src_dir.length < 1e-6 or tgt_dir.length < 1e-6:
            continue
        q = src_dir.normalized().rotation_difference(tgt_dir.normalized())
        rot = Matrix.Translation(head) @ q.to_matrix().to_4x4() @ Matrix.Translation(-head)
        world = src_arm.matrix_world @ pb.matrix
        pb.matrix = src_arm.matrix_world.inverted() @ (rot @ world)
        bpy.context.view_layer.update()
        aligned += 1
    bpy.ops.object.mode_set(mode="OBJECT")
    log(f"aligned {aligned} limb segments to the L4D2 rest pose")


def bake_pose(meshes):
    for m in meshes:
        set_active(m)
        for mod in list(m.modifiers):
            if mod.type == "ARMATURE":
                bpy.ops.object.modifier_apply(modifier=mod.name)
        mw = m.matrix_world.copy()
        m.parent = None
        m.matrix_world = mw
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def remap_weights(meshes, src_arm, tgt_arm, mapping, rig, rigid_bone):
    tgt_names = {b.name for b in tgt_arm.data.bones}
    fallback = PELVIS if PELVIS in tgt_names else tgt_arm.data.bones[0].name
    if rigid_bone and rigid_bone in tgt_names:
        fallback = rigid_bone

    def target_for(src_bone_name):
        if src_bone_name in mapping and mapping[src_bone_name] in tgt_names:
            return mapping[src_bone_name]
        if src_arm and src_bone_name in src_arm.data.bones:
            for parent in src_arm.data.bones[src_bone_name].parent_recursive:
                if parent.name in mapping and mapping[parent.name] in tgt_names:
                    return mapping[parent.name]
        if src_bone_name in tgt_names:
            return src_bone_name
        return fallback

    for m in meshes:
        if rig == "rigid":
            for vg in list(m.vertex_groups):
                m.vertex_groups.remove(vg)
            g = m.vertex_groups.new(name=fallback)
            g.add(range(len(m.data.vertices)), 1.0, "REPLACE")
            continue

        groups = {vg.index: vg.name for vg in m.vertex_groups}
        weights = {}  # vertex index -> {target bone: weight}
        for v in m.data.vertices:
            acc = {}
            for ge in v.groups:
                name = groups.get(ge.group)
                if name is None or ge.weight <= 0:
                    continue
                t = target_for(name)
                acc[t] = acc.get(t, 0.0) + ge.weight
            if not acc:
                acc = {fallback: 1.0}
            weights[v.index] = acc
        for vg in list(m.vertex_groups):
            m.vertex_groups.remove(vg)
        made = {}
        for vi, acc in weights.items():
            total = sum(acc.values())
            # Source supports at most 3 weights per vertex; keep the strongest.
            best = sorted(acc.items(), key=lambda kv: kv[1], reverse=True)[:3]
            total = sum(w for _, w in best) or total or 1.0
            for bone, w in best:
                if bone not in made:
                    made[bone] = m.vertex_groups.new(name=bone)
                made[bone].add([vi], w / total, "REPLACE")


def bind_to_target(meshes, tgt_arm):
    for m in meshes:
        for mod in list(m.modifiers):
            if mod.type == "ARMATURE":
                m.modifiers.remove(mod)
        mod = m.modifiers.new("Armature", "ARMATURE")
        mod.object = tgt_arm
        mw = m.matrix_world.copy()
        m.parent = tgt_arm
        m.matrix_world = mw


def collect_materials(meshes, role):
    """Rename materials to safe names and record which textures each one used."""
    out = {}
    seen = {}
    idx = 0
    for m in meshes:
        for slot in m.material_slots:
            mat = slot.material
            if mat is None:
                continue
            if mat.name in seen:
                continue
            images = []
            if mat.use_nodes and mat.node_tree:
                for node in mat.node_tree.nodes:
                    if node.type == "TEX_IMAGE" and node.image:
                        images.append(os.path.splitext(os.path.basename(node.image.filepath or node.image.name))[0])
            # Some importers store texture paths as custom properties instead of nodes.
            for key in mat.keys():
                val = mat[key]
                if isinstance(val, str) and re.search(r"\.(dds|tga|png|tif)$", val, re.I):
                    images.append(os.path.splitext(os.path.basename(val.replace("\\", "/")))[0])
            new_name = f"{role}_m{idx}"
            idx += 1
            out[new_name] = {"original": mat.name, "images": sorted(set(images))}
            seen[mat.name] = new_name
            mat.name = new_name
    return out


def export_smd(meshes, tgt_arm, out_dir):
    # Join everything into one body mesh so the exporter writes a single SMD.
    set_active(meshes[0])
    for m in meshes[1:]:
        m.select_set(True)
    if len(meshes) > 1:
        bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = "nf_body"
    scene = bpy.context.scene
    scene.vs.export_path = out_dir
    scene.vs.export_format = "SMD"
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    tgt_arm.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.export_scene.smd(export_scene=False)
    path = os.path.join(out_dir, "nf_body.smd")
    if not os.path.exists(path):
        raise RuntimeError(f"Blender Source Tools did not write {path}")
    log(f"exported {path}")


def main():
    argv = sys.argv
    job_path = argv[argv.index("--") + 1]
    with open(job_path, encoding="utf-8") as f:
        job = json.load(f)

    enable_addons()
    clear_scene()

    tgt_arm, tgt_min, tgt_max = import_reference(job["reference_smd"])
    src_arm, meshes = import_sources(job["sources"], job.get("flver_operator", "import_scene.flver"))
    rig = job.get("rig", "humanoid")
    mapping = build_mapping(src_arm, job.get("bone_map"))
    log(f"{len(mapping)} source bones map onto the L4D2 skeleton")
    if rig == "humanoid" and len(mapping) < 6:
        log("few humanoid bones recognised - falling back to 'rigid' (add a bone_map for better results)")
        rig = "rigid"

    fit_scale_and_place(src_arm, meshes, tgt_min, tgt_max, float(job.get("scale", 1.0)))
    if rig == "humanoid" and src_arm:
        align_limbs(src_arm, tgt_arm, mapping)
    bake_pose(meshes)
    remap_weights(meshes, src_arm, tgt_arm, mapping, rig, job.get("rigid_bone"))
    if src_arm:
        bpy.data.objects.remove(src_arm, do_unlink=True)
    bind_to_target(meshes, tgt_arm)

    materials = collect_materials(meshes, job["role"])
    with open(job["materials_json"], "w", encoding="utf-8") as f:
        json.dump(materials, f, indent=2)
    export_smd(meshes, tgt_arm, job["out_dir"])


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # noqa: BLE001
        log(f"FAILED: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
