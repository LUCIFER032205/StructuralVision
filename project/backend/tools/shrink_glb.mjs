// One-off: make a Sketchfab GLB light enough for SceneView/Filament on a
// budget phone. Usage: node shrink.mjs in.glb out.glb <maxTex> [simplifyRatio]
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS, KHRMaterialsUnlit } from '@gltf-transform/extensions';
import { dedup, prune, flatten, join, weld, simplify } from '@gltf-transform/functions';
import { MeshoptSimplifier } from 'meshoptimizer';
import sharp from 'sharp';

const [inp, out, maxTexArg, ratioArg] = process.argv.slice(2);
const maxTex = Number(maxTexArg);
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const doc = await io.read(inp);

// Downloads often sit on a huge ground board; it would dwarf the building
// once scaled to size_m and drop a 100 m floor into AR.
if (process.env.DROP) { const re = new RegExp(process.env.DROP); for (const n of doc.getRoot().listNodes()) if (n.getMesh() && re.test(n.getName() || n.getMesh().getName())) n.dispose(); }

// 1. Fewer draw calls: bake node transforms, merge meshes sharing a material.
await doc.transform(dedup(), flatten(), join({ keepNamed: false }), weld());

// 2. Optional gentle simplification (ratio = fraction of triangles to keep).
if (ratioArg) {
  await MeshoptSimplifier.ready;
  await doc.transform(simplify({ simplifier: MeshoptSimplifier, ratio: Number(ratioArg), error: Number(process.env.ERR || 0.001) }));
}

// Filament derives tangent frames itself; stored TANGENTs are dead weight.
if (process.env.NO_TANGENTS) for (const m of doc.getRoot().listMeshes()) for (const p of m.listPrimitives()) p.setAttribute('TANGENT', null);

// 3. Textures: cap the size; JPEG unless the image really has transparency.
for (const tex of doc.getRoot().listTextures()) {
  const src = sharp(tex.getImage());
  const meta = await src.metadata();
  let hasAlpha = false;
  if (meta.hasAlpha) {
    const { channels } = await sharp(tex.getImage()).stats();
    hasAlpha = channels[3].min < 250;
  }
  const size = Math.min(maxTex, Math.max(meta.width, meta.height));
  const resized = sharp(tex.getImage()).resize(size, size, { fit: 'inside' });
  const buf = hasAlpha
    ? await resized.png({ compressionLevel: 9 }).toBuffer()
    : await resized.removeAlpha().jpeg({ quality: 85 }).toBuffer();
  tex.setImage(buf).setMimeType(hasAlpha ? 'image/png' : 'image/jpeg');
}

// 4. "Transparent" materials with nothing see-through draw as opaque. Blending
// skips the depth test's early-out, so every hidden layer is shaded and
// blended: the apartment's 128k-triangle interior was BLEND with an opaque
// texture and alpha 1, and ran ARCore's tracking down to 5 Hz (2026-10-07).
for (const mat of doc.getRoot().listMaterials()) {
  if (mat.getAlphaMode() === 'OPAQUE') continue;
  const tex = mat.getBaseColorTexture();
  if (mat.getBaseColorFactor()[3] >= 0.999 && (!tex || tex.getMimeType() === 'image/jpeg')) {
    mat.setAlphaMode('OPAQUE');
  }
}

// 5. UNLIT=1: no per-pixel lighting. The phone is fill-rate bound once a
// model covers the screen: the full apartment at 80 cm ran 9 fps lit and
// 29 fps unlit (2026-10-07, vivo V2307), while cutting it to a third of the
// triangles only reached 12.5. Lighting maps are dead weight once unlit.
if (process.env.UNLIT) {
  const unlit = doc.createExtension(KHRMaterialsUnlit);
  for (const mat of doc.getRoot().listMaterials()) {
    mat.setNormalTexture(null).setMetallicRoughnessTexture(null).setOcclusionTexture(null);
    if (mat.getAlphaMode() === 'OPAQUE') mat.setDoubleSided(false);
    mat.setExtension('KHR_materials_unlit', unlit.createUnlit());
  }
}

// keepAttributes: unlit materials never read NORMAL, so prune would drop it;
// the phone-tested files kept normals, and filament_problems() expects them.
await doc.transform(prune({ keepAttributes: true }));
await io.write(out, doc);

const root = doc.getRoot();
let tris = 0;
for (const m of root.listMeshes()) for (const p of m.listPrimitives()) {
  const idx = p.getIndices();
  tris += (idx ? idx.getCount() : p.getAttribute('POSITION').getCount()) / 3;
}
console.log(JSON.stringify({ out, meshes: root.listMeshes().length, tris,
  textures: root.listTextures().map(t => t.getMimeType()) }));
