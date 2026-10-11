class_name Frappable
extends Area3D
## CE QUI SE FRAPPE — un ennemi, une caisse, une cruche, un PNJ qu'on bouscule : la zone que les coups de Knil
## touchent (couche physique 6, valeur 32). Elle ne décide de rien : elle DIT le coup reçu (`struck`), et son
## porteur (le parent) en fait ce qu'il veut — perdre de la vie, reculer, se briser. Sa forme : un CollisionShape3D
## enfant, comme toute Area3D.

signal struck(damage: int, knockback: Vector3, source: Node)

## La couche des Frappables : la zone du coup de Knil ne regarde qu'elle.
const LAYER := 32

## Vrai : les coups sont dits, mais ne comptent pas (un mur, un objet sacré… que Knil frappe quand même).
@export var invulnerable := false


func _ready() -> void:
	add_to_group("frappables")
	collision_layer = LAYER
	collision_mask = 0
	monitoring = false


## Un coup reçu. `knockback` : la poussée (m/s, dans le monde).
func take_hit(damage: int, knockback: Vector3, source: Node) -> void:
	struck.emit(0 if invulnerable else damage, knockback, source)
