# MarchingBlocks Paint — Godot

Free, open plugin that paints worlds with **MarchingBlocks tilesets** (the `.mbset` folders made by the
MarchingBlocks tool): you paint cells, the non-cubic 3D tiles follow.

1. Copy `addons/marchingblocks_paint` into your project and enable **MarchingBlocks Paint**.
2. Add a **MarchingBlocksWorld** node, and set its **Tileset** to the `tileset.json` of a `.mbset` folder.
3. Select the node: a MarchingBlocks toolbar appears above the 3D viewport. Paint in the viewport.
   The toolbar is the MarchingBlocks tool's panel in one row — aim, tool, brush, floor, selection — and
   only shows what the current tool uses; hover an icon for its name and key.
   Every change is one Ctrl+Z. (Selecting its **Cells** child gives Godot's own GridMap editor instead —
   both paint the same cells.)

**A whole painted world** (every layer, its cells and its tiles) comes as a `.mbworld` folder: copy it into
your project, then **Project → Tools → Import MarchingBlocks world...** and pick its `world.json`. One
MarchingBlocksWorld node per layer is built, in order, under a new node — one Ctrl+Z. Sibling
MarchingBlocksWorld nodes are the layers of ONE world, and their order is their priority: where two layers meet
there is no wall, and each corner takes the tiles of the higher layer. A cell belongs to one layer — painting it
in one layer removes it from the others, in the same Ctrl+Z. A hidden layer leaves the world. A layer exported
without tiles arrives with its cells and no tiles, and the Output panel says so. `world_conformance.json`
holds the reading rule's reference cases.

What else a world exported by MarchingBlocks brings comes with it, next to the layers:

- **Animated textures** — a material of a tileset whose glTF extras carry `mb_animation` (scroll, frames,
  pulse, on the base colour, normal, ORM and emission) is drawn by the MarchingBlocks tool's own shader; its
  frames travel in `<tileset>.mbset/animation/`. A de-synced track starts each tile at its own phase.
- **Transitions** (a *MarchingBlocksTransitions* node) — where two layers meet, the surface of one takes the
  look of the other, softly: a pass laid over the tiles' materials. It follows the cells as you paint (in a
  game, call `refresh()` after changing cells).
- **Foliage** (a *MarchingBlocksFoliage* node) — every plant, drawn as MultiMeshes, swaying in the wind. The
  models' own animations (skeletons) are not played.
- **Water** (a *MarchingBlocksWater* node per water layer) — the water sheet MarchingBlocks baked, drawn with
  one of six example looks (stylized, clear, reflective, lava, swamp, acid) — **or your own material**: the looks
  are examples, not an obligation. Any water shader gets the data: COLOR_0 r, g the flow along x and z ([-1, 1]
  mapped to [0, 1]); b the kind (0 still, 0.5 river, 0.75 foam, 1 waterfall); a the depth / 8 on still water and
  rivers, the amount of foam on waterfalls and foam; NORMAL the shape; TEXCOORD_0. **The water follows the
  cells**: while you paint, the sheet says it is stale; half a second after the stroke, the plugin rebuilds it on
  a worker thread — the tool's own rule (`mb_water.gd`) and mesher (`mb_water_mesh.gd`), redoing only what the
  stroke changed — and swaps it in. *Rebuild water* (inspector) rebuilds at any time; if a rebuild after a stroke
  takes longer than *Auto Limit* (1 s: a huge sea), the automatic rebuild pauses itself until you press it.

| Aim (Tab switches) | |
|---|---|
| Grid | aims at the floor plane — Page Up / Page Down move it |
| Sculpt | aims at the matter itself — Add builds against the face you point at |
| **Navigate (Space)** | a switch, not an aim: fly as usual (right drag + W A S D, Q E), no click paints. Space again — or an aim — brings you back, the aim unchanged |

| Keys | |
|---|---|
| A · D · S · G · B | Add · Dig · Select · Rect (flat, on the floor) · Box (3D volume, can be Hollow) |
| Shift | the opposite (Add ↔ Dig; adds to the selection) · Ctrl removes from it |
| [ ] | brush size 1–7 — sphere, cube or disc in the toolbar |
| Delete · Escape | delete the selection · clear it or cancel a paste |
| Arrows | move the selection; they follow the camera. Shift + ↑ ↓ lift and lower |
| Ctrl + C · X · V | copy · cut · paste (then click to place) |

Once something is selected, the toolbar holds Fill, Delete, Clear, Grow, **Shrink** (drops the EDGE of the
selection: a rectangle loses its rim), Connected, **Room from selection**, Move, Copy, Cut, Paste.

**Extrude** ↑ · ↓ · **facing** (with Select, Rect, Box, or a selection) acts on the selection — or, with nothing
selected, on the matter of the floor:

| | |
|---|---|
| Click | adds matter one cell that way; the selection and the floor follow — click again to keep going |
| Shift + click | **Extend selection**: the selection grows one cell that way, empty cells included — no matter added |
| Alt + click | moves the selection one cell that way — no matter added |

*Facing* goes away from the matter behind the cells: a wall thickens toward the air, a cave ceiling comes down.
So *Rect, Fill, Extrude, Fill…* raises a wall, and *Select empty cells too* (a toggle under Select) paints a
room's footprint on the floor grid — then **Room from selection** turns it into a room (Floors and Up / Down
are the Room shape's), or Extend selection ↑ and Fill.

| Mouse wheel | |
|---|---|
| alone | the editor's zoom — except during a gesture: a Rect / Box drag (its height: a flat Rect becomes a box), a Room being traced (its floors), a paste (its height) |
| Ctrl | the floor |
| Ctrl + Shift | the Stairs' step |
| with a selection (Select, Rect, Box) | Shift: Extend selection ↑ ↓ · Alt ↑: widen it, a flat ring · Alt ↓: shrink its edge |
| a shape | Alt: its size (a Room: its floors) · Shift: its length (a Room: rises / sinks) |
| Add · Dig · Select | Alt: the brush size · Shift: the next brush shape |

Each notch says its value near the mouse. Navigate never takes the wheel, and the inspector's own fields keep
theirs. (Godot's F keeps framing the selected node: the 3D view's camera belongs to the editor.)

A red cube is a tile your tileset does not have. Nothing is ever filled in for you. One node is one
layer. The placement rule is written in `tileset.json` (`rules_text`), the tools in
`tools_conformance.json` (`rules_text`); `conformance.json` and `tools_conformance.json` prove this plugin
follows both exactly — the same reference cases as the Unity and Unreal plugins. So do
`editing_conformance.json` (Extrude, Shrink, Widen, the Select brush, Room from selection, the mouse wheel),
`animation_conformance.json`, `transitions_conformance.json`, `foliage_conformance.json`,
`water_conformance.json` and `water_mesh_conformance.json` (the water sheet, compared as a bag of triangles): each
holds its rule in full (`rules_text`) and the cases every plugin passes.
