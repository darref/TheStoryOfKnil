MARCHINGBLOCKS WORLD v1 — world.json

format   must be "marchingblocks-world". version: refuse anything newer than 1.
layers   an array, in PRIORITY order (the first is the highest: where layers meet, its tiles are
		 placed — the tileset rule, step 7). Each layer:
  name      a string
  visible   true or false
  tileset   the path of a tileset.json RELATIVE to world.json, or null (a layer without tiles:
			its cells still travel; show that it has no tiles, never invent some)
  cells     a flat array of integers, x y z per cell, in FORMAT space: cell c covers [c, c+1],
			+Y is up. Its length is a multiple of 3. The same cell never appears twice.
  variant_weights   (optional) an object: key → an array of INTEGERS, the weights of the base tile and
					of each variant of that key in the draw (the tileset rule, step 8)
  variant_choices   (optional) a flat array of integers, x y z c per vertex (FORMAT space, the vertex of
					the tileset rule): at that vertex, place variant c (0 is the base tile). Its length
					is a multiple of 4. The same vertex never appears twice.
Refuse the whole file, and say why, if any of these does not hold.

water    (optional) an array of water layers, in order. Each water layer:
  name      a string
  visible   true or false
  look      a string: "stylized", "clear", "reflective", "lava", "swamp" or "acid" — a
			SUGGESTION only (lava, swamp and acid flow and fill hollows exactly like water). The looks shipped
			with the plugins are examples: assign any water shader you like, it gets the data below.
  mesh      the path of a .glb RELATIVE to world.json, or null (nothing to draw). Its vertices are in
			FORMAT space, like the cells. Every vertex carries the water data:
			  COLOR_0 r, g   the flow along x and z, mapped from [-1, 1] to [0, 1]; 0.5 0.5 is still water
			  COLOR_0 b      the kind of water: 0 still (lake, sea), 0.5 river, 0.75 foam (the churning
							 water at the foot of a waterfall, its spray, a spring), 1 waterfall
			  COLOR_0 a      on still water and rivers, the depth below, in cells / 8, capped at 1 (1 too
							 for a bottomless sea); on a waterfall and on foam, the amount of foam, 0 to 1
			  NORMAL         the shape of the water (a waterfall is a curved, closed sheet)
			  TEXCOORD_0     x, z on still water and rivers; across, height on a waterfall
			Colours are quantized to 1/255.
  sources   a flat array of integers, x y z per source cell: where the water was placed. The mesh
			is deduced from them and from the cells of EVERY layer; a plugin may deduce it again.
			Only ONE sea: taking the sources of every water layer in order, the first source in the void
			is the sea; any other source in the void is refused (it makes no water).
water_floor  (optional, beside water) where the ground of the tiles is drawn, for the heights of the water:
			0.25 (inset: the top of a full cell y - 1 is seen at y - 0.25), 0 (centred: at y) or -0.25 (outset:
			at y + 0.25). Absent: 0.25 (worlds exported before it). Any other value refuses the world. A plugin
			that deduces the mesh again uses it (lakes at L + 1 - |floor| - 0.05, rivers at y + 0.1 - floor).

transitions   (optional) how two tile layers blend where they meet. The GEOMETRY never changes (the tiles are
			  the ones the tileset rule places); only the LOOK of the surface does. Absent: nothing blends.
  pairs             an array of {a, b, active, a_covers_b, b_covers_a}: a < b are layer indices (in layers), active a
					bool, the two settings say how the first layer covers the second. The same pair never twice.
  settings          softness in [0.05, 1] (default 0.45), reach in [-0.5, 0.5] (0.2), irregularity in [0, 1] (0.35),
					grain in [0.25, 6] (1.5), fills_hollows in [0, 1] (0.5). A missing setting takes its default,
					one out of range is clamped.
  representatives   one per layer, in layer order: {image, color, scale, roughness}. image: a PNG path RELATIVE to
					world.json, or null (plain colour). color [r, g, b, a] multiplies the image AS IS (no sRGB
					conversion of the colour). scale: world cells per repeat of the image (at least 0.01). The image is
					projected in a box: weights w = |n|^4 / sum (n the world normal), samples at p.zy/scale, p.xz/scale,
					p.xy/scale. A layer's representative is what is laid over the OTHER layer's surface.
  choices           a flat array x y z L per vertex (FORMAT space): at that vertex, layer L covers. The same vertex
					never twice. A choice of a layer that is not in the blending pair counts as no choice.
  Only layers 0 to 14 blend (a pair with a larger index blends nothing). Hidden layers place no cell.
  Refuse the whole file, and say why, if any of these does not hold.
THE BLEND at a point p of the surface of the tile of vertex v (that tile covers [v + 1/2, v + 3/2]; take v from the
  TILE, never from p: on a joint, p belongs to two tiles):
  f = clamp(p - v - 1/2, 0, 1) on each axis. Corner k = dx + 2 dy + 4 dz (d in {0, 1}^3) is the cell v + d: rank_k
	= its layer index (-1 empty), choice_k = the layer chosen at VERTEX v + d (-1 none), weight w_k =
	(dx ? f.x : 1 - f.x) (dy ? f.y : 1 - f.y) (dz ? f.z : 1 - f.z).
  owner = the smallest rank among the corners; none: nothing. For every other rank r, part_r = the sum of its
	weights; other = the rank with the largest part, ties to the first corner in k order; none: nothing.
  The pair {owner, other} must be active (both directions known), else nothing. s = part_other / (part_other +
	w_owner), where w_owner = the sum of the owner's weights.
  covering_k = choice_k if it is owner or other, else owner (the higher priority). vote = the sum of w_k where
    covering_k = other.
  visible(S, x, h, n) = smoothstep(0.5 - S.softness / 2, 0.5 + S.softness / 2, x + (S.reach + S.fills_hollows (0.5
    - h) + S.irregularity (n - 0.5)) 4 x (1 - x)) — the shift is ZERO at both ends.
  alpha = vote visible(other covers owner, s, h_owner, n) + (1 - vote) (1 - visible(owner covers other, 1 - s,
	h_other, n)): draw the OTHER layer's representative over the surface with that alpha (nothing below 0.004).
  h_L = the luminance (0.299 r + 0.587 g + 0.114 b) of layer L's representative at p. n = a value noise in [0, 1]
    at p times the grain of the direction (the conformance cases give n, the same for both directions).

foliage   (optional) the plants of the whole world (not of a layer). Absent: no plant.
  models    an array of {id (an integer, unique), name, mesh (a .glb path RELATIVE to world.json, or null),
            ground_offset (model units: how far its origin sits ABOVE the ground; negative buries it), scale,
            scale_random (each plant draws a factor in [1 - a, 1 + a], a <= 0.9), footprint (radius in cells, at
            scale 1), height (the top of the model above its origin, model units), wind (0 still to 1)}.
            A missing number takes its default (0, 1, 0.2, 0.5, 1, 0.5); one of another type refuses the file.
  plants    a flat array of numbers, 7 per plant: model id, x, y, z (the point ON THE GROUND, FORMAT space), yaw
			(radians around +Y), scale (the plant's own draw), mode (0 placed in the air, 1 planted).
			A plant of an unknown model refuses the file.
  A plant's model sits at T = translate(p + (0, ground_offset s, 0)) rotateY(yaw) scale(s), s = model.scale * plant
  scale; its height above the ground is max(0, (height + ground_offset) s).
  WIND (each engine writes its own shader on the same data): per plant (ground = p.y, height above ground,
  phase = (0.37 p.x + 0.71 p.z) mod 2 pi, amplitude = wind). In WORLD space, for a vertex P with normal N at time t:
  h = clamp((P.y - ground) / height, 0, 1); b = 0.35 + 0.6 sin(1.1 t + phase) + 0.3 sin(2.3 t + 1.7 phase);
  P.xz += normalize(1.0, 0.34999999403954) b amplitude height 0.05 h^2; then P += N sin(7 t + P.(2.1, 1.7, 2.9)) 0.015 amplitude h.
  A height of 0 does not move.

Made with MarchingBlocks 0.9.0. Open it with the free MarchingBlocks Paint plugin for Godot, Unity or Unreal: Import MarchingBlocks world.
