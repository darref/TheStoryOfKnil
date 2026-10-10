extends Node
## LE SOUS-SOL D'UN MORCEAU CUIT — les cases d'AIR enfouies (au moins `profondeur_souterrain` cases pleines au-dessus :
## les galeries), en tronçons de colonne. Rangé avec la collision du morceau (chargé près du joueur seulement) ; le
## ChunkStreamer s'en sert pour savoir si le joueur est SOUS TERRE — la caméra passe alors en troisième personne,
## la torche s'allume, les tuiles souterraines se montrent. Une arche, un surplomb (une case de couvert) n'en sont pas.

## 4 entiers par tronçon : x, z, y du bas, y du haut (cases d'air, bornes comprises).
@export var runs := PackedInt32Array()

var _by_column := {}


func _ready() -> void:
	for i in range(0, runs.size(), 4):
		var k := Vector2i(runs[i], runs[i + 1])
		if not _by_column.has(k):
			_by_column[k] = []
		_by_column[k].append(Vector2i(runs[i + 2], runs[i + 3]))


## La case `c` est-elle de l'air enfoui ?
func contains(c: Vector3i) -> bool:
	for r: Vector2i in _by_column.get(Vector2i(c.x, c.z), []):
		if c.y >= r.x and c.y <= r.y:
			return true
	return false
