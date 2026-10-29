#!/usr/bin/env python3
"""Makes downloaded model packs phone-friendly (run by tools/fetch_assets.sh).

    prep_assets.py trim-glb <in.glb> <out.glb> <animation>...
        Keeps only the named animations (KayKit characters ship ~95 clips
        each, ~4.8 MB) and repacks the binary chunk without the dropped data.
    prep_assets.py slim-gltf <dir>
        Quaternius nature models: drops normal maps (2-6 MB each, barely
        visible with toon shading) and scales every texture down to 1024 px.
"""
import json
import os
import struct
import sys

from PIL import Image


def _read_glb(path):
    data = open(path, "rb").read()
    jlen = struct.unpack("<I", data[12:16])[0]
    j = json.loads(data[20:20 + jlen])
    off = 20 + jlen
    blen = struct.unpack("<I", data[off:off + 4])[0]
    return j, data[off + 8:off + 8 + blen]


def _write_glb(path, j, binbuf):
    js = json.dumps(j, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    binbuf += b"\0" * ((4 - len(binbuf) % 4) % 4)
    total = 12 + 8 + len(js) + 8 + len(binbuf)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(binbuf), 0x004E4942) + binbuf)


def trim_glb(src, dst, keep):
    j, binbuf = _read_glb(src)
    j["animations"] = [a for a in j.get("animations", []) if a["name"] in keep]
    # accessors still referenced by anything
    used_acc = set()
    for m in j.get("meshes", []):
        for p in m["primitives"]:
            used_acc.update(p["attributes"].values())
            if "indices" in p:
                used_acc.add(p["indices"])
            for t in p.get("targets", []):
                used_acc.update(t.values())
    for s in j.get("skins", []):
        if "inverseBindMatrices" in s:
            used_acc.add(s["inverseBindMatrices"])
    for a in j["animations"]:
        for s in a["samplers"]:
            used_acc.update([s["input"], s["output"]])
    acc_map, new_acc = {}, []
    for i, a in enumerate(j["accessors"]):
        if i in used_acc:
            acc_map[i] = len(new_acc)
            new_acc.append(a)
    used_bv = {a["bufferView"] for a in new_acc if "bufferView" in a}
    used_bv.update(im["bufferView"] for im in j.get("images", []) if "bufferView" in im)
    bv_map, new_bv, out = {}, [], bytearray()
    for i, bv in enumerate(j["bufferViews"]):
        if i not in used_bv:
            continue
        out += b"\0" * ((4 - len(out) % 4) % 4)
        chunk = binbuf[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]]
        nb = dict(bv)
        nb["byteOffset"] = len(out)
        out += chunk
        bv_map[i] = len(new_bv)
        new_bv.append(nb)
    for a in new_acc:
        if "bufferView" in a:
            a["bufferView"] = bv_map[a["bufferView"]]
    for im in j.get("images", []):
        if "bufferView" in im:
            im["bufferView"] = bv_map[im["bufferView"]]
    for m in j.get("meshes", []):
        for p in m["primitives"]:
            p["attributes"] = {k: acc_map[v] for k, v in p["attributes"].items()}
            if "indices" in p:
                p["indices"] = acc_map[p["indices"]]
            p["targets"] = [{k: acc_map[v] for k, v in t.items()} for t in p.get("targets", [])] or None
            if p["targets"] is None:
                del p["targets"]
    for s in j.get("skins", []):
        if "inverseBindMatrices" in s:
            s["inverseBindMatrices"] = acc_map[s["inverseBindMatrices"]]
    for a in j["animations"]:
        for s in a["samplers"]:
            s["input"] = acc_map[s["input"]]
            s["output"] = acc_map[s["output"]]
    j["accessors"] = new_acc
    j["bufferViews"] = new_bv
    j["buffers"] = [{"byteLength": len(out)}]
    _write_glb(dst, j, bytes(out))


def slim_gltf(folder):
    used = set()
    for f in os.listdir(folder):
        if not f.endswith(".gltf"):
            continue
        p = os.path.join(folder, f)
        j = json.load(open(p))
        for m in j.get("materials", []):
            m.pop("normalTexture", None)
        # drop images/textures nothing points at any more
        tex_used = set()
        for m in j.get("materials", []):
            t = m.get("pbrMetallicRoughness", {}).get("baseColorTexture")
            if t:
                tex_used.add(t["index"])
        tex_map, textures = {}, []
        for i, t in enumerate(j.get("textures", [])):
            if i in tex_used:
                tex_map[i] = len(textures)
                textures.append(t)
        img_used = {t["source"] for t in textures}
        img_map, images = {}, []
        for i, im in enumerate(j.get("images", [])):
            if i in img_used:
                img_map[i] = len(images)
                images.append(im)
                used.add(im["uri"])
        for t in textures:
            t["source"] = img_map[t["source"]]
        for m in j.get("materials", []):
            t = m.get("pbrMetallicRoughness", {}).get("baseColorTexture")
            if t:
                t["index"] = tex_map[t["index"]]
        j["textures"], j["images"] = textures, images
        if not textures:
            j.pop("textures")
            j.pop("images")
            j.pop("samplers", None)
        json.dump(j, open(p, "w"), indent=1)
    for f in os.listdir(folder):
        if f.endswith(".png"):
            p = os.path.join(folder, f)
            if f not in used:
                os.remove(p)
                continue
            im = Image.open(p)
            if max(im.size) > 1024:
                im.thumbnail((1024, 1024), Image.LANCZOS)
                im.save(p, optimize=True)


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "trim-glb":
        trim_glb(sys.argv[2], sys.argv[3], set(sys.argv[4:]))
    elif cmd == "slim-gltf":
        slim_gltf(sys.argv[2])
    else:
        sys.exit("unknown command " + cmd)
