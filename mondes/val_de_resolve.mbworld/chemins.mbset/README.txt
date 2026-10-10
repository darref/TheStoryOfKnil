MarchingBlocks tileset, format 1. The tiles are placed by the rule below; nothing else.
Frame: right-handed, +Y up (glTF). 1 unit = 1 cell. Cell c covers [c, c+1] on each axis.
A layer is a set of full cells, with its own tiles. A world may stack several layers, in PRIORITY
   order (the first is the highest); see 7. One layer alone is the same rule.
1. Vertices. A full cell c touches the 8 vertices c - corners[t], t = 0..7.
2. Bits. At vertex v, bit t is 1 when cell v + corners[t] is full (t = x + 2y + 4z).
3. Class. table[bits] = [class, quarter_turns]. class = -1: nothing is placed at v.
4. Context. Only if classes[class].outdoor_possible. Let top = the highest y of any full cell of
   the layer. v is OUTDOOR when, for EVERY EMPTY cell e among its 8, no cell (e.x, y, e.z) is full
   for y from v.y + 2 to top inclusive. Outdoor: use key '<class id>_outdoor' if the tileset has it,
   otherwise fall back on the bare key '<class id>'. Indoor: the bare key.
5. Tile. Each key has exactly one tile, tiles[key]. If the key is absent, place a clearly visible
   error marker instead. Never fill in.
6. Pose. The tile mesh is centred on the origin. Place it at (v + piece_offset) * cell_size,
   rotated by quarter_turns * 90 degrees about +Y, right-hand rule (+Z turns towards +X).
7. Layers. Steps 1-4 read the UNION of the cells of every VISIBLE layer (a cell found in two layers
   belongs to the first), and top is the highest y of that union. Vertex v is placed by ONE layer:
   among the layers owning its 8 cells, the first in priority order, with ITS tiles (step 5). A
   hidden layer is not in the union and places nothing. Painting a cell in one layer removes it from
   the others of the same world.
8. Variants (optional). variants[key] lists other tiles of that key, in order: variant 1, 2, ... They
   have the same borders as tiles[key] and are placed exactly like it (step 6). After step 4 chose key
   K at vertex v (n = the number of variants of K; n = 0 places tiles[K]):
   a. If the layer that places v gives a CHOICE at v (the world's variant_choices) and 0 <= choice <= n,
      place tile number choice (0 is tiles[K], i the i-th variant).
   b. Otherwise DRAW: weights w[0..n] are that layer's variant_weights[K] (a missing entry is 1, a
      negative one 0). If they sum to 0, place tiles[K]. Else h = hash(v) mod sum, and the tile is the
      first i whose running sum of weights exceeds h.
   hash(v), on 64-bit integers, & = bitwise and, ^ = xor, >> = logical shift:
      h = ((v.x * 73856093) ^ (v.y * 19349663) ^ (v.z * 83492791)) & 0x7FFFFFFF
      h = ((h ^ (h >> 16)) * 0x45D9F3B) & 0x7FFFFFFF;  h = ((h ^ (h >> 16)) * 0x45D9F3B) & 0x7FFFFFFF
      hash = h ^ (h >> 16)
   Never draw at random at run time: the same world must give the same tiles at every rebuild.
Rebuilding after cell (x, y, z) changes: only the vertices of columns x-1..x, z-1..z at heights
   up to y can change (their bits, their context, or the layer that places them) — in every layer.
Engines with another frame must convert the cell grid with the SAME mapping their glTF importer
   applies to meshes. A mirroring conversion reverses the direction of the quarter turns.
Frame: tiles.glb carries a marker node, frame_marker.node, whose mesh has exactly the vertices
   frame_marker.points = (0,0,0), (1,0,0), (0,2,0), (0,0,3). Read where your importer put them
   (node pose included): the lengths 1, 2, 3 tell each axis apart, the shortest gives the scale.
   That linear map F is the conversion. Place a piece at F(v + piece_offset) * cell_size,
   rotated by F * R * F^-1 where R is the quarter-turn rotation. The marker is not a tile.

ANIMATED TEXTURES — a material of tiles.glb may carry extras.mb_animation:
  format "marchingblocks-animation", version 1 (refuse anything newer: ignore the animation, show the still material).
  channels: albedo, normal, orm (r ambient occlusion, g roughness, b metal), emission. Each has tracks:
    scroll {u, v (image repeats per second, in [-10.0, 10.0]), synced}
    frames {images (paths RELATIVE to the .mbset folder, in order; at most 256), fps (in [0.1, 60.0]),
            ping_pong, synced}   — a frames track without a frame does not exist
    pulse  {frequency (Hz, in [0, 20]), minimum (in [0, 1]), synced}   — emission only
  A value of the wrong type is ignored (its default takes its place), a number out of range is clamped, an
  unknown channel or track is ignored. Defaults: scroll u 0, v -0.25, synced; frames fps 12, no ping-pong,
  not synced; pulse frequency 0.5, minimum 0.2, not synced.
  The material itself is a standard glTF material showing frame 0: an engine that ignores the animation
  still shows the tile right.
TIME is global (one clock for every material). PHASE of a tile = hash of its ORIGIN in FORMAT space (the
  vertex v + piece_offset): p = floor(o + 0.5); p = fract(p * 0.3183099 + (0.71, 0.113, 0.419)) * 17;
  phase = fract(p.x * p.y * p.z * (p.x + p.y + p.z)). A synced track uses phase 0.
  scroll offset at time t = (u, v) * (t + (synced ? 0 : 7 * phase)), added to the UVs (they repeat).
  frame at time t, n frames: k = floor(t * fps + phase * n); ping_pong and n > 1: p = 2n - 2, k = k mod p,
    frame = k < n ? k : p - k; else frame = k mod n (mod is always >= 0).
  pulse at time t: frequency <= 0 gives 1; else minimum + (1 - minimum) * (0.5 + 0.5 cos(2 pi (t * frequency
    + phase))), multiplying the emission.
  The UVs of a tile turn with it: a v scroll stays vertical on every copy, a u scroll follows each copy's turn.

Open format — free plugins for Godot, Unity and Unreal read it. Made with MarchingBlocks 0.9.0 (Resolve : fabriquer_val.gd).
