extends Node3D
## LE FEUILLAGE D'UN MORCEAU CUIT — les plants gardés en DONNÉES par la cuisson (une MultiMesh ne se cuit pas sans
## fenêtre : le rendu factice ne garde pas ses instances). Au chargement : une MultiMesh par partie de modèle, le vent
## dans ses données (sol, hauteur, phase, amplitude — le shader de vent de MarchingBlocks, cuit avec le matériau).

## [{"mesh": Mesh, "buffer": PackedFloat32Array}] — 16 nombres par plant : la pose (3 × 4, par lignes) puis le vent.
@export var parts: Array = []
## Au-delà, les plants s'effacent (en fondu).
@export var view_distance := 80.0


var _prepared := false


func _ready() -> void:
	# La vue s'éloigne (zoom, vue haute) : les plants se voient d'aussi loin que la caméra.
	EventBus.view_radius_changed.connect(_on_view_radius)
	prepare()


## Bâtit les MultiMesh. HORS DE L'ARBRE, donc dans le FIL DE TRAVAIL du ChunkStreamer (juste après l'instanciation) :
## mesuré, 30 à 48 ms par morceau sur le fil principal quand c'était fait au `_ready`. Une seule fois.
func prepare() -> void:
	if _prepared:
		return
	_prepared = true
	for p: Dictionary in parts:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = p["mesh"]
		mm.instance_count = (p["buffer"] as PackedFloat32Array).size() / 16
		mm.buffer = p["buffer"]
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_end = view_distance
		mmi.visibility_range_end_margin = 10.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(mmi)


func _on_view_radius(r: float) -> void:
	# La caméra est à ~r / tan(fov/2) / format du joueur : on garde de la marge.
	var reach := maxf(view_distance, r * 2.6)
	for c in get_children():
		if c is MultiMeshInstance3D:
			(c as MultiMeshInstance3D).visibility_range_end = reach
