@tool
extends RefCounted
## ANIMATED TEXTURES — a material of `tiles.glb` may carry `extras.mb_animation` (scroll, frames, pulse, on the
## albedo, normal, orm and emission channels). Its frames travel in `<tileset>.mbset/animation/`.
##
## The rule is written in `animation_conformance.json` (`rules_text`); this file implements it from that text, and
## that file's cases prove it, case by case — like `mb_rule.gd`, it uses nothing from the MarchingBlocks tool.
## The SHADER is the tool's own (a generated copy, `mb_shaders.gd`): one clock (Godot's TIME), and the phase of a tile
## read from its ORIGIN in FORMAT space (`mb_world_to_format`, set by the layer node).
##
## ⚠ A shader computes the phase in 32-bit floats: on some tiles a de-synced track may show another frame than the
## double-precision cases say (up to 0.025 of a phase) — the MarchingBlocks tool itself does the same. Accepted.

const Shaders := preload("res://addons/marchingblocks_paint/mb_shaders.gd")

const FORMAT := "marchingblocks-animation"
const VERSION := 1
const CHANNELS := ["albedo", "normal", "orm", "emission"]
const TRACKS := ["scroll", "frames", "pulse"]
const FRAMES_MAX := 256
const FPS_MAX := 60.0
const SCROLL_MAX := 10.0
const DEFAULTS := {
	"scroll": {"u": 0.0, "v": -0.25, "synced": true},
	"frames": {"images": [], "fps": 12.0, "ping_pong": false, "synced": false},
	"pulse": {"frequency": 0.5, "minimum": 0.2, "synced": false},
}
## Each setting: [its type, the tracks it belongs to].
const SETTINGS := {"u": "number", "v": "number", "synced": "bool", "images": "images", "fps": "number",
	"ping_pong": "bool", "frequency": "number", "minimum": "number"}
## The shader's names for the channels (the tool's shader keeps its own words).
const SHADER_CHANNEL := {"albedo": "albedo", "normal": "normale", "orm": "orm", "emission": "emission"}


# ── THE RULE ─────────────────────────────────────────────────────────────────────────────────────────

## READS `mb_animation`: the normalized animation, under the format's own names (with "format" and "version"), or
## {} — not an animation, a version newer than this plugin, or nothing left once normalized. A value of the wrong
## type takes its default, a number out of range is clamped, an unknown channel or track is ignored, a frames track
## without a frame and a pulse outside the emission do not exist.
static func read(e: Variant) -> Dictionary:
	if not e is Dictionary or str((e as Dictionary).get("format", "")) != FORMAT:
		return {}
	var v: Variant = e.get("version")
	if not (v is float or v is int) or int(v) != v or int(v) < 1 or int(v) > VERSION:
		return {}
	var out := {}
	for channel in CHANNELS:
		var c: Variant = e.get(channel)
		if not c is Dictionary:
			continue
		var tracks := {}
		for track in TRACKS:
			var g: Variant = (c as Dictionary).get(track)
			if not g is Dictionary or (track == "pulse" and channel != "emission"):
				continue
			var r := _settings(track, g)
			if track == "frames" and (r["images"] as Array).is_empty():
				continue
			tracks[track] = r
		if not tracks.is_empty():
			out[channel] = tracks
	if out.is_empty():
		return {}
	out["format"] = FORMAT
	out["version"] = VERSION
	return out


## One track's settings, complete: typed, clamped, defaults for what is missing or of the wrong type.
static func _settings(track: String, g: Dictionary) -> Dictionary:
	var d: Dictionary = DEFAULTS[track]
	var r := {}
	match track:
		"scroll":
			r["u"] = clampf(_number(g, "u", d["u"]), -SCROLL_MAX, SCROLL_MAX)
			r["v"] = clampf(_number(g, "v", d["v"]), -SCROLL_MAX, SCROLL_MAX)
		"frames":
			var images: Array = []
			var raw: Variant = g.get("images", [])
			if raw is Array:
				for p in raw:
					if p is String and p != "" and images.size() < FRAMES_MAX:
						images.append(p)
			r["images"] = images
			r["fps"] = clampf(_number(g, "fps", d["fps"]), 0.1, FPS_MAX)
			r["ping_pong"] = _bool(g, "ping_pong", d["ping_pong"])
		"pulse":
			r["frequency"] = clampf(_number(g, "frequency", d["frequency"]), 0.0, 20.0)
			r["minimum"] = clampf(_number(g, "minimum", d["minimum"]), 0.0, 1.0)
	r["synced"] = _bool(g, "synced", d["synced"])
	return r


static func _number(g: Dictionary, key: String, default: float) -> float:
	var x: Variant = g.get(key)
	return float(x) if x is float or x is int else default


static func _bool(g: Dictionary, key: String, default: bool) -> bool:
	var x: Variant = g.get(key)
	return x if x is bool else default


## The frame shown at time t: k = floor(t fps + phase n); ping-pong (n > 1) runs back; mod is always >= 0.
static func frame_at(count: int, fps: float, ping_pong: bool, t: float, phase := 0.0) -> int:
	if count <= 0:
		return 0
	var k := int(floor(t * fps + phase * float(count)))
	if ping_pong and count > 1:
		var p := 2 * count - 2
		k = posmod(k, p)
		return k if k < count else p - k
	return posmod(k, count)


## The emission factor of a pulse at time t: 1 at the top, `minimum` at the bottom, a cosine in between.
static func pulse_at(frequency: float, minimum: float, t: float, phase := 0.0) -> float:
	if frequency <= 0.0:
		return 1.0
	return lerpf(minimum, 1.0, 0.5 + 0.5 * cos(TAU * (t * frequency + phase)))


## The UV offset of a scroll at time t; a de-synced track starts 7 x its phase ahead.
static func scroll_at(u: float, v: float, t: float, synced: bool, phase := 0.0) -> Vector2:
	return Vector2(u, v) * (t + (0.0 if synced else phase * 7.0))


## The phase of a tile whose ORIGIN (v + piece_offset, FORMAT space) is `origin` — the shader's hash, line by line.
static func phase_of(origin: Vector3) -> float:
	var p := (origin + Vector3(0.5, 0.5, 0.5)).floor()
	p = Vector3(_fract(p.x * 0.3183099 + 0.71), _fract(p.y * 0.3183099 + 0.113), _fract(p.z * 0.3183099 + 0.419)) * 17.0
	return _fract(p.x * p.y * p.z * (p.x + p.y + p.z))


static func _fract(x: float) -> float:
	return x - floor(x)


# ── THE TILESET ──────────────────────────────────────────────────────────────────────────────────────

## The animations a `tiles.glb` carries: {material name: normalized animation}. Read in the glTF JSON chunk of the
## file itself (12-byte header, then the chunk length and type, then the JSON) — the most certain way, the same in
## the three plugins. Several materials may share a name: they are copies of the same, with the same animation.
## {} when the file cannot be read (an exported game that does not ship the .glb): `of_material` then reads the
## "extras" metadata Godot's importer gives a material.
static func of_glb(glb_path: String) -> Dictionary:
	if not FileAccess.file_exists(glb_path):
		return {}
	var bytes := FileAccess.get_file_as_bytes(glb_path)
	if bytes.size() < 20 or bytes.decode_u32(0) != 0x46546C67 or bytes.decode_u32(16) != 0x4E4F534A:
		return {}
	var length := bytes.decode_u32(12)
	var json = JSON.parse_string(bytes.slice(20, 20 + length).get_string_from_utf8())
	var out := {}
	if not json is Dictionary or not json.get("materials") is Array:
		return out
	for m in json["materials"]:
		if not m is Dictionary or not m.get("extras") is Dictionary:
			continue
		var a := read((m["extras"] as Dictionary).get("mb_animation"))
		if not a.is_empty():
			out[str(m.get("name", ""))] = a
	return out


## The animation a material carries in its glTF "extras" metadata ({} without).
static func of_material(m: Material) -> Dictionary:
	if m == null or not m.has_meta("extras"):
		return {}
	var e: Variant = m.get_meta("extras")
	return read((e as Dictionary).get("mb_animation")) if e is Dictionary else {}


static var _arrays := {}


## The images of a frames track, as one Texture2DArray (the size of the first; a lost image shows MAGENTA — a hole
## must be seen). `base` is the .mbset folder the paths are relative to. Shared: the same frames, the same array.
static func frames_texture(paths: Array, base: String) -> Texture2DArray:
	var key := base + "|" + "|".join(PackedStringArray(paths))
	if _arrays.has(key) and is_instance_valid(_arrays[key]):
		return _arrays[key]
	var tex := _frames_texture(paths, base)
	_arrays[key] = tex
	return tex


static func _frames_texture(paths: Array, base: String) -> Texture2DArray:
	var images: Array[Image] = []
	var size := Vector2i.ZERO
	for p in paths:
		var img := _image(base.path_join(str(p)))
		if img == null:
			if size == Vector2i.ZERO:
				return null
			img = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
			img.fill(Color.MAGENTA)
		if img.is_compressed():
			img.decompress()
		img.clear_mipmaps()
		img.convert(Image.FORMAT_RGBA8)
		if size == Vector2i.ZERO:
			size = img.get_size()
		elif img.get_size() != size:
			img.resize(size.x, size.y, Image.INTERPOLATE_BILINEAR)
		img.generate_mipmaps()
		images.append(img)
	var tex := Texture2DArray.new()
	if images.is_empty() or tex.create_from_images(images) != OK:
		return null
	return tex


## An image from a path: the imported texture when the project has one (res://, and an exported game), else the file.
static func _image(path: String) -> Image:
	if path.begins_with("res://") and ResourceLoader.exists(path):
		var t = load(path)
		if t is Texture2D:
			return (t as Texture2D).get_image()
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null and not img.is_empty():
			return img
	return null


static var _shader: Shader


## The tool's shader, generated (`mb_shaders.gd`).
static func shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = Shaders.ANIMATION
	return _shader


## The ANIMATED material of a still one: its values and textures (frame 0 of each animated channel is already in
## them), plus the tracks. `base`: the .mbset folder. The still material is kept as meta "still".
static func material(still: BaseMaterial3D, a: Dictionary, base: String) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = shader()
	sm.resource_name = still.resource_name
	sm.set_meta("still", still)
	sm.set_meta("mb_animation", a)
	sm.set_shader_parameter("couleur", still.albedo_color)
	sm.set_shader_parameter("rugosite", still.roughness)
	sm.set_shader_parameter("metal", still.metallic)
	sm.set_shader_parameter("albedo_fixe", still.albedo_texture)
	var orm := still.roughness_texture != null
	sm.set_shader_parameter("a_normale", still.normal_enabled and still.normal_texture != null)
	sm.set_shader_parameter("normale_fixe", still.normal_texture)
	sm.set_shader_parameter("a_orm", orm)
	sm.set_shader_parameter("a_ao", orm and still.ao_enabled)
	sm.set_shader_parameter("orm_fixe", still.roughness_texture)
	sm.set_shader_parameter("a_emission", still.emission_enabled and still.emission_texture != null)
	sm.set_shader_parameter("emission_fixe", still.emission_texture)
	sm.set_shader_parameter("force_emission", still.emission_energy_multiplier if still.emission_enabled else 0.0)
	for channel in CHANNELS:
		var c: Dictionary = a.get(channel, {})
		var s: Dictionary = c.get("scroll", {})
		var f: Dictionary = c.get("frames", {})
		var tex: Texture2DArray = frames_texture(f.get("images", []), base) if not f.is_empty() else null
		var n := tex.get_layers() if tex != null else 0
		var name: String = SHADER_CHANNEL[channel]
		sm.set_shader_parameter("%s_images" % name, tex)
		sm.set_shader_parameter("%s_reglages" % name, Vector4i(n, 1 if bool(f.get("ping_pong", false)) else 0,
			1 if bool(f.get("synced", true)) else 0, 1 if bool(s.get("synced", true)) else 0))
		sm.set_shader_parameter("%s_mouvement" % name, Vector4(float(s.get("u", 0.0)), float(s.get("v", 0.0)),
			float(f.get("fps", 12.0)), 1.0 if bool(s.get("synced", true)) else 0.0))
	var p: Dictionary = (a.get("emission", {}) as Dictionary).get("pulse", {})
	sm.set_shader_parameter("pulsation", Vector3(float(p.get("frequency", 0.0)), float(p.get("minimum", 1.0)),
		1.0 if bool(p.get("synced", true)) else 0.0))
	return sm
