extends RefCounted
## LA TRICHE — pour tester le monde : voler, traverser, aller vite, avancer l'heure. ACTIVE tant que Jordan ne demande
## pas de l'éteindre (Jordan, 9 octobre 2026 : « active le cheat et tu le désactiveras quand je te le demanderai ») :
## `data/triche.json`, « actif ». Éteinte, aucune de ses touches ne fait rien.
##
##   F1 · Start (manette)         le VOL — Espace / A monte, C / gâchette gauche descend, pas de gravité
##   F2                           le FANTÔME — on traverse tout (vol compris) ; les LIMITES du monde, elles, tiennent
##   F3 · clic du stick droit     la VITESSE : ×1, ×3, ×8
##   F4                           avancer l'heure d'une heure
## Le Player lit ces états ; le HUD les montre.

const FICHIER := "res://data/triche.json"
const VITESSES := [1.0, 3.0, 8.0]

static var actif := false
static var vol := false
static var fantome := false
static var vitesse := 1.0
static var _lu := false


static func lire() -> void:
	if _lu:
		return
	_lu = true
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FICHIER)) if FileAccess.file_exists(FICHIER) else null
	actif = d is Dictionary and bool((d as Dictionary).get("actif", false))


## Une touche de triche : rend vrai si l'événement en était une (et qu'elle a joué).
static func touche(event: InputEvent) -> bool:
	lire()
	if not actif:
		return false
	if event.is_action_pressed("cheat_fly"):
		vol = not vol
		if not vol:
			fantome = false
		return true
	if event.is_action_pressed("cheat_ghost"):
		fantome = not fantome
		if fantome:
			vol = true
		return true
	if event.is_action_pressed("cheat_speed"):
		vitesse = VITESSES[(VITESSES.find(vitesse) + 1) % VITESSES.size()]
		return true
	if event.is_action_pressed("cheat_time"):
		GameClock.advance(60.0)
		return true
	return false


## Ce que le HUD montre : "" quand rien n'est allumé.
static func etat() -> String:
	lire()
	if not actif:
		return ""
	var parts: Array = []
	if fantome:
		parts.append("fantôme")
	elif vol:
		parts.append("vol")
	if vitesse != 1.0:
		parts.append("×%d" % int(vitesse))
	return "TRICHE" + (" : " + " · ".join(parts) if not parts.is_empty() else " (F1 vol · F2 fantôme · F3 vitesse · F4 +1 h)")
