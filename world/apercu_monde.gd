@tool
extends Node3D
## L'APERÇU DU MONDE CUIT, DANS L'ÉDITEUR SEULEMENT — pour POSER des choses sur la carte (ennemis, PNJ, régions…).
## En jeu, le monde n'existe que par le ChunkStreamer, qui charge les morceaux autour du joueur : l'éditeur, lui, ne
## voyait rien (Jordan, 12 octobre 2026 : « je ne vois pas la map pour pouvoir les positionner »). Ici, dans l'éditeur,
## TOUS les morceaux visibles se chargent (en fond, à petites doses : l'éditeur ne gèle pas), avec le feuillage, et
## leur COLLISION — glisser une scène dans la vue 3D la pose SUR le sol, et « Snap Object to Floor » (Page Down) marche.
##
## ⚠ RIEN N'EST ENREGISTRÉ : les morceaux sont des enfants INTERNES sans propriétaire — la scène ne grossit pas (la
## leçon de §2 : un `MarchingBlocksWorld` posé dans une scène y enregistrait ses grilles). En jeu, ce nœud s'efface au
## démarrage. Verrouillé (`_edit_lock_`) : un clic sur le sol ne le déplace pas.
## Les morceaux sont relus quand on recuit : rouvrir la scène, ou décocher / recocher `show_in_editor`.

## Le dossier du monde cuit ; vide : celui du ChunkStreamer parent.
@export_dir var baked_dir := ""
@export var show_in_editor := true:
	set(v):
		show_in_editor = v
		if is_inside_tree() and Engine.is_editor_hint():
			_clear()
			if v:
				_start()
## Les galeries (« Souterrain ») : cachées comme en jeu vu de dessus.
@export var show_underground := false:
	set(v):
		show_underground = v
		for n in get_children(true):
			var u := n.get_node_or_null("Souterrain") as Node3D
			if u:
				u.visible = v
@export var with_collision := true
@export var with_foliage := true
## Le temps donné par image à faire entrer les morceaux (ms).
@export var budget_ms := 8.0

var _pending: Array = []   # [chemin, piste]
var _loading: Array = []   # [chemin, piste] en lecture
var _pieces: Array = []    # [corps, propriétaire, PackedVector3Array] à faire en formes
var _count := 0


func _ready() -> void:
	if not Engine.is_editor_hint():
		queue_free()
		return
	set_meta("_edit_lock_", true)
	if show_in_editor:
		_start()


func _start() -> void:
	var dir := baked_dir
	if dir == "" and get_parent() != null and "baked_dir" in get_parent():
		dir = get_parent().baked_dir
	var path := dir.path_join("monde.json")
	if not FileAccess.file_exists(path):
		push_warning("Aperçu du monde : %s introuvable — le monde a-t-il été cuit (recuire.bat) ?" % path)
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	_apply_transitions(dir, manifest.get("transitions", {}))
	for c: Dictionary in manifest["chunks"]:
		for track: String in c["files"]:
			if track == "collision" and not with_collision:
				continue
			_pending.append([dir.path_join(c["files"][track]), track])
	print("Aperçu du monde : %d morceaux à charger depuis %s" % [_pending.size(), dir])


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	var t0 := Time.get_ticks_usec()
	while _loading.size() < 4 and not _pending.is_empty():
		var it: Array = _pending.pop_front()
		ResourceLoader.load_threaded_request(it[0])
		_loading.append(it)
	var i := 0
	while i < _loading.size() and _ms(t0) < budget_ms:
		var it: Array = _loading[i]
		var status := ResourceLoader.load_threaded_get_status(it[0])
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			i += 1
			continue
		_loading.remove_at(i)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_enter((ResourceLoader.load_threaded_get(it[0]) as PackedScene).instantiate(), it[1])
	while not _pieces.is_empty() and _ms(t0) < budget_ms:
		var p: Array = _pieces.pop_back()
		if is_instance_valid(p[0]):
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(p[2])
			(p[0] as CollisionObject3D).shape_owner_add_shape(p[1], shape)
	if _count > 0 and _pending.is_empty() and _loading.is_empty() and _pieces.is_empty():
		print("Aperçu du monde : %d morceaux posés" % _count)
		_count = 0


func _enter(n: Node, track: String) -> void:
	if n == null:
		return
	_count += 1
	add_child(n, false, Node.INTERNAL_MODE_BACK)  # sans propriétaire : jamais enregistré
	var under := n.get_node_or_null("Souterrain") as Node3D
	if under:
		under.visible = show_underground
	# Les scripts du jeu ne tournent pas dans l'éditeur : le feuillage et la collision sont faits ici, depuis leurs
	# données (les propriétés exportées restent lisibles).
	var fol := n.get_node_or_null("Feuillage")
	if fol != null and with_foliage:
		for p: Dictionary in fol.get("parts") if fol.get("parts") != null else []:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = p["mesh"]
			mm.instance_count = (p["buffer"] as PackedFloat32Array).size() / 16
			mm.buffer = p["buffer"]
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			fol.add_child(mmi)
	if track == "collision" and n is CollisionObject3D:
		var formes := n.get_node_or_null("Formes")
		if formes != null and formes.get("pieces") != null:
			var body := n as CollisionObject3D
			var owner_id := body.create_shape_owner(body)
			for piece: PackedVector3Array in formes.get("pieces"):
				_pieces.append([body, owner_id, piece])


## Les transitions entre matières : rebâties sur le matériau partagé, comme le fait le ChunkStreamer
## (`world/transitions_cuites.gd`, dont le script ne tourne pas dans l'éditeur).
func _apply_transitions(dir: String, tr: Dictionary) -> void:
	if tr.is_empty():
		return
	var mat := load(dir.path_join(tr["material"])) as ShaderMaterial
	var data := load(dir.path_join(tr["data"]))
	if mat == null or data == null:
		return
	var size: Vector3i = data.get("size")
	var cells: PackedByteArray = data.get("cells")
	var per := size.x * size.y
	var slices: Array[Image] = []
	for z in size.z:
		slices.append(Image.create_from_data(size.x, size.y, false, Image.FORMAT_R8, cells.slice(z * per, (z + 1) * per)))
	var tex := ImageTexture3D.new()
	tex.create(Image.FORMAT_R8, size.x, size.y, size.z, false, slices)
	mat.set_shader_parameter("cases", tex)
	mat.set_shader_parameter("origine", data.get("origin"))
	mat.set_shader_parameter("taille", size)
	var colors: PackedColorArray = data.get("colors")
	if not colors.is_empty():
		mat.set_shader_parameter("rep_couleur", colors)
	if data.get("table") != null:
		mat.set_shader_parameter("table", ImageTexture.create_from_image(data.get("table")))
	var images: Array = data.get("images")
	if not images.is_empty():
		var arr := Texture2DArray.new()
		arr.create_from_images(images)
		mat.set_shader_parameter("representants", arr)


func _clear() -> void:
	for n in get_children(true):
		n.queue_free()
	_pending.clear()
	_loading.clear()
	_pieces.clear()
	_count = 0


func _ms(t0: int) -> float:
	return (Time.get_ticks_usec() - t0) / 1000.0
