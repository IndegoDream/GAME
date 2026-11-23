"""Make a low-poly copy of a Poly Haven glTF rock (2026-11-06, the Lands' crags).

usage: python3 -I decimate_gltf.py <in.gltf> <out.gltf> <target_triangles>

Every mesh primitive is reduced by the same share so the whole model lands near
the target; UVs follow each vertex (the old vertex that collapsed into it),
normals are worked out again from the new shape, and the model keeps the
original's materials and textures (the image paths are rewritten to point at the
original files, so nothing is copied).
"""
import sys, os, json, struct
import numpy as np
import fast_simplification as fs

src, dst, target = sys.argv[1], sys.argv[2], int(sys.argv[3])
g = json.load(open(src))
base = os.path.dirname(os.path.abspath(src))
blob = open(os.path.join(base, g['buffers'][0]['uri']), 'rb').read()

CT = {5126: ('f', 4), 5125: ('I', 4), 5123: ('H', 2), 5121: ('B', 1)}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}


def read(ai):
    a = g['accessors'][ai]
    bv = g['bufferViews'][a['bufferView']]
    fmt, size = CT[a['componentType']]
    n = NC[a['type']]
    off = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    stride = bv.get('byteStride', size * n)
    out = np.empty((a['count'], n), dtype={'f': np.float32, 'I': np.uint32, 'H': np.uint16, 'B': np.uint8}[fmt])
    for i in range(a['count']):
        out[i] = struct.unpack_from('<' + fmt * n, blob, off + i * stride)
    return out


total = 0
for m in g['meshes']:
    for p in m['primitives']:
        total += g['accessors'][p['indices']]['count'] // 3
keep = min(1.0, target / max(1, total))

new_bin = bytearray()
views, accs = [], []


def put(arr, kind, comp, target_kind=None, minmax=False):
    while len(new_bin) % 4:
        new_bin.append(0)
    off = len(new_bin)
    raw = arr.astype({5126: np.float32, 5125: np.uint32}[comp]).tobytes()
    new_bin.extend(raw)
    v = {'buffer': 0, 'byteOffset': off, 'byteLength': len(raw)}
    if target_kind:
        v['target'] = target_kind
    views.append(v)
    a = {'bufferView': len(views) - 1, 'componentType': comp, 'count': int(arr.shape[0] if kind != 'SCALAR' else arr.size), 'type': kind}
    if minmax:
        a['min'] = [float(x) for x in arr.min(axis=0)]
        a['max'] = [float(x) for x in arr.max(axis=0)]
    accs.append(a)
    return len(accs) - 1


done = 0
for m in g['meshes']:
    for p in m['primitives']:
        pos = read(p['attributes']['POSITION']).astype(np.float64)
        uv = read(p['attributes']['TEXCOORD_0']).astype(np.float32) if 'TEXCOORD_0' in p['attributes'] else None
        tri = read(p['indices']).reshape(-1, 3).astype(np.int64)
        if keep < 1.0 and len(tri) > 60:
            _, _, coll = fs.simplify(pos, tri, target_reduction=1.0 - keep, return_collapses=True)
            npos, ntri, mapping = fs.replay_simplification(pos, tri, coll)
            nuv = None
            if uv is not None:
                nuv = np.zeros((len(npos), 2), dtype=np.float32)
                seen = np.zeros(len(npos), dtype=bool)
                for old, new in enumerate(mapping):
                    if 0 <= new < len(npos) and not seen[new]:
                        nuv[new] = uv[old]
                        seen[new] = True
        else:
            npos, ntri, nuv = pos, tri, uv
        # smooth normals from the new shape
        nrm = np.zeros_like(npos)
        f = npos[ntri]
        fn = np.cross(f[:, 1] - f[:, 0], f[:, 2] - f[:, 0])
        for k in range(3):
            np.add.at(nrm, ntri[:, k], fn)
        ln = np.linalg.norm(nrm, axis=1, keepdims=True)
        nrm = nrm / np.where(ln < 1e-12, 1.0, ln)
        attrs = {'POSITION': put(npos.astype(np.float32), 'VEC3', 5126, 34962, True),
                 'NORMAL': put(nrm.astype(np.float32), 'VEC3', 5126, 34962)}
        if nuv is not None:
            attrs['TEXCOORD_0'] = put(nuv, 'VEC2', 5126, 34962)
        p['attributes'] = attrs
        p['indices'] = put(ntri.astype(np.uint32).reshape(-1), 'SCALAR', 5125, 34963)
        done += len(ntri)

g['accessors'] = accs
g['bufferViews'] = views
name = os.path.splitext(os.path.basename(dst))[0]
g['buffers'] = [{'byteLength': len(new_bin), 'uri': name + '.bin'}]
rel = os.path.relpath(base, os.path.dirname(os.path.abspath(dst)))
for im in g.get('images', []):
    im['uri'] = os.path.join(rel, im['uri']).replace(os.sep, '/')
os.makedirs(os.path.dirname(os.path.abspath(dst)), exist_ok=True)
open(os.path.join(os.path.dirname(os.path.abspath(dst)), name + '.bin'), 'wb').write(new_bin)
json.dump(g, open(dst, 'w'))
print('%s: %d -> %d triangles' % (os.path.basename(src), total, done))
