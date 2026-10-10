extends SceneTree
## LE VAL DE RÉSOLVE — le premier monde de Resolve, fait PAR LE LOGICIEL MARCHINGBLOCKS (son code, sans fenêtre) :
## un vrai projet `.mbproj` (à rouvrir et retoucher dans MB) et son export `.mbworld` (« Export the world… »).
##
##   godot --headless --path D:/MarchingBlocks --script D:/Resolve/Resolve_MB_project/outils/fabriquer_val.gd
##         [-- --taille=784 --racine=D:/Resolve/Resolve_MB_project --export=D:/Resolve/mondes] [--ecraser]
## ⚠ N'ÉCRASE PAS un `val_de_resolve.mbproj` existant (la carte se peint à la main dans MB) sans `--ecraser`.
##
## ⚠ Ce script tourne DANS le projet MarchingBlocks (ses `res://` sont ceux de MB) ; il n'écrit QUE dans `--racine`
## et `--export`. Le dossier Resolve_MB_project porte un `.gdignore` : le projet Resolve ne le lit pas.
##
## LES DIX MATIÈRES (une couche MB = une matière = un jeu de tuiles) :
##   l'exemple de MB    Prairie (Grass), Roche (GreyRock), Désert (Desert) — sculptées, texturées
##   neuves (ici)       Pavés, Chemins, Sous-bois, Marais, Neige, Basalte, Profondeurs — sur le témoin de MB,
##                      DEUX textures chacune (le dessus, les flancs), générées ici, sans couture, projetées en
##                      « boîte », leurs cartes PBR déduites par MB
##
## LE MONDE, v2 (Jordan, 9 octobre 2026 : « de grandes étendues plates… un réseau irrégulier de massifs qui bordent la
## zone parcourable… des bords montagneux qui encadrent toute la map », et MB plantait sur la v1 — 6,7 M cases ; l'exemple
## de MB, 740 000 cases, lui coûte déjà 1,7 Go) : taille × taille colonnes, 1 case = 1 m, ~1,2 M cases.
##   Neige        le haut du cadre                    Volcan      le Basalte du volcan du nord-est, lave au cratère
##   Montagnes    le CADRE : 7 à 13 cases de haut, 6 à 9 d'épaisseur, tout le pourtour
##   Massifs      le RÉSEAU : 4 à 7 cases de haut, entre de grandes étendues plates (un pavage de Voronoï, ~100 m),
##                percé de passages (toutes les étendues reliées) ; quelques ESCALIERS (marches d'une case) y montent :
##                les étages où l'on s'infiltre ; et les remparts de la capitale
##   Paves Chemins SousBois Marais Desert Prairie   la DALLE plate (une case, dessus à y = 1), sa matière selon la région
##   Profondeurs  les GALERIES : des tubes (sol, parois, plafond) sous la dalle, un couloir tous les 64 m, des escaliers
## L'eau : le lac du Val, l'étang du marais, la lave du cratère. Le feuillage : les arbres de HEARTWORLD (Spirit3D),
## sauf les décimés. UN projet MB, UN export ; les limites de la zone jouable dans `<export>/<nom>.limites.json`, à
## côté du dossier `.mbworld` (que MB réécrit à chaque export). LES TRANSITIONS (l'atelier Transitions) : TOUTES les paires de couches actives, réglages
## par défaut ; le représentant d'une matière neuve est son DESSUS (des pavés, pas des moellons), celui d'une matière de
## l'exemple, son matériau le plus porté (le choix par défaut de l'atelier). Tout se règle ensuite dans MB.

const Exemple := preload("res://app/exemple.gd")
const Projet := preload("res://app/projet.gd")
const BM := preload("res://addons/marchingblocks_core/blocs_maitres.gd")
const TL := preload("res://addons/marchingblocks_core/temoin_lie.gd")
const FM := preload("res://addons/marchingblocks_core/format_monde.gd")
const FL := preload("res://addons/marchingblocks_core/fluides.gd")
const EM := preload("res://addons/marchingblocks_core/eau_maillage.gd")
const FE := preload("res://addons/marchingblocks_core/feuillage.gd")
const Cartes := preload("res://addons/marchingblocks_core/cartes_pbr.gd")
const FS := preload("res://addons/marchingblocks_core/formes_speciales.gd")
const TR := preload("res://addons/marchingblocks_core/transitions.gd")
const MB := preload("res://addons/marchingblocks_core/marching_blocks.gd")
const VOISINS := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1),
	Vector3i(0, 0, -1)]

const TEX := 512
const CAPITAL_R := 30.0            # la place pavée ; les remparts juste derrière

var N := 784
var RACINE := "D:/Resolve/Resolve_MB_project"
var EXPORT := "D:/Resolve/mondes"
var NOM := "val_de_resolve"

var _n_base := FastNoiseLite.new()
var _n_detail := FastNoiseLite.new()
var _n_peak := FastNoiseLite.new()
var _n_edge := FastNoiseLite.new()
var _villages: Array = []   # [centre Vector2, rayon de la place]
var _roads: Array = []      # [a Vector2, b Vector2]
var _volcano := Vector2.ZERO
var _volcano_r := 80.0
var _lake := Vector2.ZERO
var _pond := Vector2.ZERO
var _marsh := Vector2.ZERO


func _initialize() -> void:
	_fabriquer.call_deferred()


func _fabriquer() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		match kv[0]:
			"taille": N = int(kv[1])
			"racine": RACINE = kv[1]
			"export": EXPORT = kv[1]
			"nom": NOM = kv[1]
	# ⚠ LA CARTE SE PEINT À LA MAIN DANS MB (Jordan, 9 octobre 2026) : ce script refait TOUT le projet. Il n'écrase pas
	# un projet existant — on l'efface soi-même, ou `--ecraser`.
	var existant := RACINE.path_join(NOM + "." + Projet.EXTENSION)
	if FileAccess.file_exists(existant) and not "--ecraser" in OS.get_cmdline_user_args():
		return _echec("%s existe déjà — peut-être peint à la main. Rien n'est écrasé (--ecraser pour le refaire)." % existant)
	var t0 := Time.get_ticks_msec()
	_layout()
	DirAccess.make_dir_recursive_absolute(RACINE.path_join("matieres"))
	DirAccess.make_dir_recursive_absolute(RACINE.path_join("modeles"))

	# 1. LES TROIS MATIÈRES DE L'EXEMPLE, installées comme l'appli les installe (chemins réécrits).
	var erreurs: Array = []
	var projet_exemple: String = Exemple.installer(Exemple.ARCHIVE, RACINE.path_join("matieres/exemple"), erreurs)
	if projet_exemple == "":
		return _echec("l'exemple ne s'installe pas : %s" % str(erreurs))
	var ex := projet_exemple.get_base_dir()
	var sources := {
		"roche": {"glb": ex.path_join("example_layer2.glb"), "temoin": ex.path_join("example_layer2.mbtiles")},
		"prairie": {"glb": ex.path_join("example_layer3.glb"), "temoin": ex.path_join("example_layer3.mbtiles")},
		"desert": {"glb": ex.path_join("example_layer4.glb"), "temoin": ex.path_join("example_layer4.mbtiles")},
	}
	print("exemple installé : %s (%d ms)" % [ex, Time.get_ticks_msec() - t0])

	# 2. LES SEPT MATIÈRES NEUVES, sur le témoin de MB.
	for spec in _specs():
		var r := _matiere(spec)
		if r.has("erreur"):
			return _echec(r["erreur"])
		sources[spec["id"]] = r
	print("matières neuves écrites (%d ms)" % (Time.get_ticks_msec() - t0))

	# 3. LES LOTS : chaque source tranchée par MB (le témoin lié, relu tuile par tuile).
	var lots := {}
	for id in sources:
		var bilan: Dictionary = BM.librairie_depuis_glb(sources[id]["glb"])
		if not (bilan.get("erreurs", ["?"]) as Array).is_empty():
			return _echec("la matière %s ne se tranche pas : %s" % [id, str(bilan.get("erreurs"))])
		lots[id] = bilan["lot"]
	print("%d matières tranchées (%d ms)" % [lots.size(), Time.get_ticks_msec() - t0])

	# 4. LE MONDE : chaque case à sa couche.
	var couches_def := [
		["Neige", "neige"], ["Volcan", "basalte"], ["Montagnes", "roche"], ["Massifs", "roche"],
		["Paves", "paves"], ["Chemins", "chemins"], ["SousBois", "sousbois"], ["Marais", "marais"],
		["Desert", "desert"], ["Prairie", "prairie"], ["Profondeurs", "profondeurs"],
	]
	var cells := {}
	for d in couches_def:
		cells[d[0]] = []
	for x in range(-_half, N - _half):
		for z in range(-_half, N - _half):
			_column(x, z, cells)
	var total := 0
	for k in cells:
		total += (cells[k] as Array).size()
	print("monde : %d × %d colonnes, %d cases, %d étages, %d escaliers de galerie (%d ms)" % [N, N, total, _etages,
		_stairs.size(), Time.get_ticks_msec() - t0])
	for d in couches_def:
		print("  %-12s %9d cases" % [d[0], (cells[d[0]] as Array).size()])
	# LE MONDE SANS CONTACT DIAGONAL (la charte de MB) : deux cases qui ne se touchent que par une arête n'ont pas de tuile
	# — un trou, vu dans les pics du relief. On répare comme le bouton « Fix diagonal contacts » (mode COMBLER, sur l'union
	# des couches) et comme `DEV_TOOLS/reparer_diagonales_exemple.gd` : une case ajoutée va à la couche qui possède le
	# plus de ses six voisines (à égalité, la plus prioritaire).
	var union := {}
	var rang := {}
	for i in couches_def.size():
		for c in cells[couches_def[i][0]]:
			if not union.has(c):
				union[c] = true
				rang[c] = i
	var avant := MB.contacts_par_arete(union)
	var rep: Dictionary = FS.reparer_les_diagonales(union, false)
	var cles: Array = (rep["poser"] as Dictionary).keys()
	cles.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return [a.y, a.z, a.x] < [b.y, b.z, b.x])
	for k: Vector3i in cles:
		var votes := {}
		for dv in VOISINS:
			if rang.has(k + dv):
				votes[rang[k + dv]] = int(votes.get(rang[k + dv], 0)) + 1
		var meilleure := couches_def.size() - 2
		var vmax := -1
		for i in votes:
			if votes[i] > vmax or (votes[i] == vmax and i < meilleure):
				meilleure = i
				vmax = votes[i]
		rang[k] = meilleure
		union[k] = true
		cells[couches_def[meilleure][0]].append(k)
	var apres := MB.contacts_par_arete(union)
	print("contacts diagonaux : %d → %d (%d cases comblées) (%d ms)" % [avant, apres, cles.size(), Time.get_ticks_msec() - t0])
	if apres != 0:
		return _echec("il reste %d contacts diagonaux" % apres)
	union = {}
	rang = {}

	# 5. L'EAU, calculée par MB (fluides.gd, eau_maillage.gd), chaque corps dans sa boîte.
	var eaux_export: Array = []
	var eaux_projet: Array = []
	var waters := [
		["Lac du Val", "transparent", _lake, 24],
		["Etang du marais", "marais", _pond, 18],
		["Lave du cratere", "lave", _volcano, int(_crater) + 8],
	]
	for i in waters.size():
		var w: Array = waters[i]
		var r := _eau(w[2], int(w[3]))
		if r.has("erreur"):
			print("  ⚠ %s : %s" % [w[0], r["erreur"]])
			continue
		eaux_export.append({"nom": w[0], "visible": true, "preset": w[1], "sources": [r["source"]], "maillage": r["maillage"]})
		var e := Projet.couche_d_eau(w[0], str(i + 1))
		e["preset"] = w[1]
		e["sources"] = [r["source"]]
		eaux_projet.append(e)
		print("  eau %s : %d cases d'eau, source %s" % [w[0], r["cases"], r["source"]])
	print("eau (%d ms)" % (Time.get_ticks_msec() - t0))

	# 6. LE FEUILLAGE (le format de l'atelier Foliage).
	var feuillage := _feuillage()
	print("feuillage : %d plants" % (feuillage["plants"] as Array).size())

	# 7. LE PROJET MB, puis L'EXPORT DU MONDE.
	var couches_projet: Array = []
	var couches_export: Array = []
	for i in couches_def.size():
		var nom: String = couches_def[i][0]
		var src: Dictionary = sources[couches_def[i][1]]
		var c := Projet.couche(nom, str(i + 1))
		c["source"] = src["glb"]
		c["temoin"] = src["temoin"]
		c["cases"] = cells[nom]
		couches_projet.append(c)
		couches_export.append({"nom": nom, "visible": true, "source": src["glb"], "lot": lots[couches_def[i][1]],
			"cases": cells[nom]})
	var ids: Array = couches_projet.map(func(c: Dictionary) -> String: return str(c["id"]))
	var etat := {"paires": {}, "representants": {}, "choix": {}}
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var paire: Dictionary = TR.paire_neuve(ids[i], ids[j])
			paire["actif"] = true
			etat["paires"][TR.cle_de_paire(ids[i], ids[j])] = paire
	var reps: Array = []
	for i in couches_def.size():
		var neuve: bool = not (couches_def[i][1] in ["roche", "prairie", "desert"])
		if neuve:
			etat["representants"][ids[i]] = 0
		reps.append(_representant(sources[couches_def[i][1]]["temoin"], 0 if neuve else -1))
	print("transitions : %d paires actives" % (etat["paires"] as Dictionary).size())
	# UN SEUL PROJET, UN SEUL EXPORT (Jordan, 9 octobre 2026 : « je ne veux pas avoir plusieurs sous-maps ») — l'éditeur
	# de MB plantait sur le monde entier : réparé dans MB (`MassifPeint.collision_des_pieces`).
	var fe := FE.vers_donnees(feuillage["modeles_fe"], feuillage["plants_fe"])
	var chemin_projet := RACINE.path_join(NOM + "." + Projet.EXTENSION)
	var f := FileAccess.open(chemin_projet, FileAccess.WRITE)
	f.store_string(Projet.vers_texte(couches_projet, couches_projet.size() - 2, eaux_projet, [], etat, fe))
	f.close()
	print("projet MB écrit : %s (%d ms)" % [chemin_projet, Time.get_ticks_msec() - t0])
	var r: Dictionary = FM.exporter(couches_export, EXPORT, NOM, "MarchingBlocks %s (Resolve : fabriquer_val.gd)"
		% ProjectSettings.get_setting("application/config/version", ""), eaux_export,
		{"etat": etat, "ids": ids, "representants": reps}, fe)
	if r.has("erreur"):
		return _echec("export : " + str(r["erreur"]))
	print("MONDE EXPORTÉ : %s — %d couches, %d jeux de tuiles, %d eaux, feuillage %s (%d ms)" % [r["dossier"],
		r["couches"], r["jeux"], r["eaux"], str(r["feuillage"]), Time.get_ticks_msec() - t0])
	# LES LIMITES DE LA ZONE JOUABLE (en dedans du cadre) : la cuisson les lit à côté du `world.json`, le joueur n'en
	# sort JAMAIS.
	# Hors du dossier d'export (que MB réécrit) : `mondes/<nom>.limites.json`.
	var lf := FileAccess.open(EXPORT.path_join(NOM + ".limites.json"), FileAccess.WRITE)
	lf.store_string(JSON.stringify(limites()))
	lf.close()
	quit(0)


## Le représentant d'une couche, RÉSOLU comme l'atelier Transitions le résout (`app/transitions.gd`) : le matériau
## `k` de son témoin, ou (k < 0) le plus porté par les faces de ses tuiles ; son image, sa couleur, son échelle.
func _representant(temoin: String, k: int) -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(temoin))
	var t: RefCounted = TL.depuis_dictionnaire(d) if d is Dictionary else null
	if t == null or t.materiaux.is_empty():
		return {"image": null, "couleur": Color.WHITE, "echelle": 1.0, "rugosite": 0.9}
	if k < 0:
		var comptes := {}
		for nom in t.tuiles:
			for m in t.tuiles[nom].mats:
				if int(m) >= 0:
					comptes[int(m)] = int(comptes.get(int(m), 0)) + 1
		for m in comptes:
			if k < 0 or comptes[m] > comptes[k] or (comptes[m] == comptes[k] and m < k):
				k = m
	var mat: Dictionary = t.materiaux[maxi(k, 0)]
	var chemin := str(mat.get("texture", ""))
	var img: Image = Image.load_from_file(chemin) if chemin != "" and FileAccess.file_exists(chemin) else null
	return {"image": img, "couleur": mat.get("couleur", Color.WHITE), "echelle": float(mat.get("echelle", 1.0)),
		"rugosite": float(mat.get("rugosite", 0.8))}


func _echec(why: String) -> void:
	printerr("ÉCHEC : " + why)
	quit(1)


# --- Le plan du val (v2 : de grandes étendues PLATES, un réseau de massifs, un cadre) -------------------------------
#
# Tout est calculé une fois, colonne par colonne, dans des tableaux (`_layout`) ; `_column` ne fait que les lire.
#   _up / _up_layer   les cases AU-DESSUS de la dalle : massifs (4 à 7), cadre de montagnes (8 à 14, enneigé en haut),
#                     volcan — 0 : rien, la dalle est à l'air
#   _bio              la matière de la dalle (Prairie, Paves, Chemins, SousBois, Marais, Desert)
#   _hole             1 : cuvette d'un lac (la dalle descend d'une case) ; 2..2+STAIR_STEPS−1 : marche d'un escalier de
#                     galerie ; 2+STAIR_STEPS : son palier (le sol de la galerie, À CIEL OUVERT)
#   _gal              1 : couloir de galerie (air), 2 : paroi de galerie

const LAYER_NONE := 0
const LAYER_MASSIFS := 1
const LAYER_MONTAGNES := 2
const LAYER_VOLCAN := 3
const BIOMES := ["Prairie", "Paves", "Chemins", "SousBois", "Marais", "Desert"]
const B_PRAIRIE := 0
const B_PAVES := 1
const B_CHEMINS := 2
const B_SOUSBOIS := 3
const B_MARAIS := 4
const B_DESERT := 5
## Les arbres de HEARTWORLD (Spirit3D) gardés : ceux qui n'ont PAS été décimés. Écartés : les trois de la jungle (exactement
## 30 000 triangles), le palmier, le « stylized tree » et l'arbre des marais (~5 000 : 5 006, 5 151, 4 956), woodland 08
## (9 996) et woodland 01 (24 978) — leurs comptes ronds sont ceux d'une cible de décimation (Spirit3D, _INTAKE/A_FORGER).
const ARBRES_SOURCE := "D:/Spirit3D/HEART_WORLD/biomes/maps"
const ARBRES_PLAINES := ["biome_plains/obstacles/plains_tree_01/plains_tree_01.glb",
	"biome_plains/obstacles/plains_tree_02/plains_tree_02.glb", "biome_plains/obstacles/plains_tree_03/plains_tree_03.glb",
	"biome_plains/obstacles/plains_tree_04/plains_tree_04.glb"]
const ARBRES_BOIS := ["biome_woodland/obstacles/woodland_tree_02/woodland_tree_02.glb",
	"biome_woodland/obstacles/woodland_tree_03/woodland_tree_03.glb", "biome_woodland/obstacles/woodland_tree_04/woodland_tree_04.glb",
	"biome_woodland/obstacles/woodland_tree_05/woodland_tree_05.glb", "biome_woodland/obstacles/woodland_tree_06/woodland_tree_06.glb",
	"biome_woodland/obstacles/woodland_tree_07/woodland_tree_07.glb", "biome_woodland/obstacles/woodland_tree_09/woodland_tree_09.glb"]

const FRAME_MIN := 6          # le cadre : au moins 6 cases d'épaisseur…
const FRAME_MAX := 9          # …au plus 9 ; la zone jouable s'arrête avant (`<nom>.limites.json`)
const REGION := 100.0         # la taille d'une étendue plate (entre ses massifs)
const GALLERY_STEP := 64      # un couloir de galerie tous les 64 m, dans les deux sens
## LA COUPE D'UNE GALERIE (Jordan, 10 octobre 2026 : « l'étroitesse et les escaliers ne permettent pas de rentrer
## dedans » — la v2 : 2 de large, 2 de haut, et le plafond du couloir coupait la tête au bas de l'escalier).
const GALLERY_W := 4          # 4 cases de large (2,5 m libres mesurés dans la v2 pour 2 cases : les tuiles arrondissent)
const GALLERY_FLOOR := -5     # le sol (une case) ; le plafond en −1, sous la dalle : 3 cases d'air (−4..−2)
const STAIR_STEPS := 4        # marches d'une case de haut (le saut : 1,4 m) : dessus à 0, −1, −2, −3, puis le sol (−4)
const STAIR_TREAD := 2        # chaque marche fait 2 cases de long
const STAIR_LANDING := 3      # puis un PALIER à ciel ouvert, au sol de la galerie : on y est debout avant le plafond

var _up := PackedInt32Array()
var _up_layer := PackedByteArray()
var _bio := PackedByteArray()
var _hole := PackedByteArray()
var _gal := PackedByteArray()
var _half := 0
var _crater := 0.0
var _volcano_h := 0.0
var _stairs: Array = []           # Vector2i : le coin d'un escalier de galerie (GALLERY_W de large, le long de x)
var _etages := 0


func _i(x: int, z: int) -> int:
	return (x + _half) + (z + _half) * N


func _inside(x: int, z: int) -> bool:
	return x >= -_half and x < N - _half and z >= -_half and z < N - _half


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _near_road(p: Vector2, d: float) -> bool:
	for r in _roads:
		if _seg_dist(p, r[0], r[1]) < d:
			return true
	return false


func _layout() -> void:
	var s := N / 784.0
	_half = N >> 1
	var n := N * N
	_up.resize(n)
	_up_layer.resize(n)
	_bio.resize(n)
	_hole.resize(n)
	_gal.resize(n)
	_n_base.seed = 11
	_n_base.frequency = 0.02
	_n_edge.seed = 15
	_n_edge.frequency = 0.01
	_n_peak.seed = 14
	_n_peak.frequency = 0.05
	_volcano = Vector2(0.33, -0.3) * N
	_volcano_r = 45.0 * maxf(s, 0.4)
	_volcano_h = 24.0 * maxf(s, 0.5)
	_crater = 9.0 * maxf(s, 0.4)
	_lake = Vector2(0.08, 0.18) * N
	_marsh = Vector2(-0.27, 0.29) * N
	_pond = _marsh + Vector2(6, -4)
	_villages = [[Vector2(-0.29, -0.04) * N, 9.0], [Vector2(0.24, 0.2) * N, 9.0], [Vector2(-0.17, 0.24) * N, 8.0],
		[Vector2(0.05, -0.25) * N, 8.0]]
	# Les routes : de la place, par la porte qui fait face au village, puis en équerre.
	_roads = []
	for v in _villages:
		var c: Vector2 = v[0]
		var dir := Vector2(signf(c.x), 0) if absf(c.x) > absf(c.y) else Vector2(0, signf(c.y))
		var gate := dir * (CAPITAL_R + 6.0)
		var corner := Vector2(c.x, gate.y) if dir.x != 0.0 else Vector2(gate.x, c.y)
		_roads.append([dir * (CAPITAL_R - 2.0), gate])
		_roads.append([gate, corner])
		_roads.append([corner, c])

	# 1. LES ÉTENDUES : un pavage de Voronoï (des germes tous les ~100 m) ; entre deux, une bande de massifs.
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var inner := float(_half - FRAME_MAX)
	var g := int(ceil(2.0 * inner / REGION))
	var seeds: Array = []
	for gz in g:
		for gx in g:
			seeds.append(Vector2(-inner + (gx + 0.5 + rng.randf_range(-0.35, 0.35)) * REGION,
				-inner + (gz + 0.5 + rng.randf_range(-0.35, 0.35)) * REGION))
	# La capitale au centre de son étendue.
	var nearest := 0
	for k in seeds.size():
		if (seeds[k] as Vector2).length() < (seeds[nearest] as Vector2).length():
			nearest = k
	seeds[nearest] = Vector2.ZERO
	var pair_of := PackedInt32Array()
	pair_of.resize(n)
	var best_gap := {}   # paire (a * 4096 + b) -> [distance au milieu des germes, x, z]
	for z in range(-_half, N - _half):
		for x in range(-_half, N - _half):
			var p := Vector2(x + 0.5, z + 0.5)
			var gx := clampi(int(floor((p.x + inner) / REGION)), 0, g - 1)
			var gz := clampi(int(floor((p.y + inner) / REGION)), 0, g - 1)
			var d1 := INF
			var d2 := INF
			var a := -1
			var b := -1
			for dz in range(-2, 3):
				for dx in range(-2, 3):
					var cx := gx + dx
					var cz := gz + dz
					if cx < 0 or cz < 0 or cx >= g or cz >= g:
						continue
					var k := cz * g + cx
					var d := p.distance_to(seeds[k])
					if d < d1:
						d2 = d1
						b = a
						d1 = d
						a = k
					elif d < d2:
						d2 = d
						b = k
			var i := _i(x, z)
			pair_of[i] = -1
			var width := 3.0 + 2.5 * (_n_base.get_noise_2dv(p) * 0.5 + 0.5)
			if d2 - d1 < width and b >= 0:
				var key := mini(a, b) * 4096 + maxi(a, b)
				pair_of[i] = key
				_up[i] = 4 + int(floor((_n_peak.get_noise_2dv(p) * 0.5 + 0.5) * 4.0))
				_up_layer[i] = LAYER_MASSIFS
				var mid: Vector2 = ((seeds[a] as Vector2) + (seeds[b] as Vector2)) * 0.5
				var dm := p.distance_to(mid)
				if not best_gap.has(key) or dm < best_gap[key][0]:
					best_gap[key] = [dm, x, z]
	# 2. LES PASSAGES : un arbre couvrant des étendues (toutes reliées) et un tiers de passages en plus.
	var keys: Array = best_gap.keys()
	keys.shuffle()
	var parent := {}
	var open: Array = []
	for key: int in keys:
		var a: int = key / 4096
		var b: int = key % 4096
		var ra := _find(parent, a)
		var rb := _find(parent, b)
		if ra != rb:
			parent[ra] = rb
			open.append(key)
		elif rng.randf() < 0.33:
			open.append(key)
	for key: int in open:
		var c := Vector2i(best_gap[key][1], best_gap[key][2])
		_carve(Vector2(c) + Vector2(0.5, 0.5), 3.5 + rng.randf() * 2.0)

	# 3. LA CAPITALE, LES VILLAGES, LES ROUTES, LES LACS : à plat, sans massif ; les remparts de la capitale.
	for z in range(-_half, N - _half):
		for x in range(-_half, N - _half):
			var p := Vector2(x + 0.5, z + 0.5)
			var i := _i(x, z)
			var r := p.length()
			var clear := r < 44.0 or _near_road(p, 2.8)
			for v in _villages:
				if p.distance_to(v[0]) < 22.0:
					clear = true
			var dl := p.distance_to(_lake)
			var dp := p.distance_to(_pond)
			if dl < 22.0 or dp < 16.0:
				clear = true
			if clear and _up_layer[i] == LAYER_MASSIFS:
				_up[i] = 0
				_up_layer[i] = LAYER_NONE
			# Les remparts de la capitale (percés là où passent les routes).
			if r >= CAPITAL_R + 1.0 and r < CAPITAL_R + 3.5 and not _near_road(p, 4.0):
				_up[i] = 4
				_up_layer[i] = LAYER_MASSIFS
			# La matière de la dalle.
			var bio := B_PRAIRIE
			if p.distance_to(_marsh) < 0.12 * N + _n_edge.get_noise_2dv(p) * 12.0:
				bio = B_MARAIS
			elif p.x > 0.17 * N + _n_edge.get_noise_2dv(p) * 25.0 and p.y > 0.05 * N + _n_edge.get_noise_2dv(p + Vector2(300, 0)) * 25.0:
				bio = B_DESERT
			elif p.x < -0.18 * N + _n_edge.get_noise_2dv(p + Vector2(500, 0)) * 30.0:
				bio = B_SOUSBOIS
			if _near_road(p, 2.6):
				bio = B_CHEMINS
			if r < CAPITAL_R:
				bio = B_PAVES
			for v in _villages:
				if p.distance_to(v[0]) < v[1]:
					bio = B_PAVES
			_bio[i] = bio
			if dl < 16.0 or dp < 11.0:
				_hole[i] = 1  # la cuvette du lac : la dalle descend d'une case
				_bio[i] = B_MARAIS if dp < 11.0 else B_PRAIRIE

	# 4. LE VOLCAN : un cône de Basalte, son cratère creusé (la lave).
	for z in range(int(_volcano.y - _volcano_r) - 1, int(_volcano.y + _volcano_r) + 2):
		for x in range(int(_volcano.x - _volcano_r) - 1, int(_volcano.x + _volcano_r) + 2):
			if not _inside(x, z):
				continue
			var d := Vector2(x + 0.5, z + 0.5).distance_to(_volcano)
			if d > _volcano_r:
				continue
			var top := int(round(_volcano_h * pow(1.0 - d / _volcano_r, 1.1)))
			if d < _crater:
				top = int(round(_volcano_h * pow(1.0 - _crater / _volcano_r, 1.1))) - 5
			var i := _i(x, z)
			_up[i] = maxi(top, 1)
			_up_layer[i] = LAYER_VOLCAN

	# 5. LE CADRE : des montagnes de 8 à 14 cases sur tout le pourtour, 8 à 12 d'épaisseur — on n'en sort pas.
	for z in range(-_half, N - _half):
		for x in range(-_half, N - _half):
			var p := Vector2(x + 0.5, z + 0.5)
			var edge := mini(mini(x + _half, N - _half - 1 - x), mini(z + _half, N - _half - 1 - z))
			var thick := FRAME_MIN + int(round((_n_edge.get_noise_2dv(p * 3.0) * 0.5 + 0.5) * (FRAME_MAX - FRAME_MIN)))
			if edge < thick:
				var i := _i(x, z)
				_up[i] = 7 + int(round((_n_peak.get_noise_2dv(p) * 0.5 + 0.5) * 4.0)) + mini(thick - edge, 2)
				_up_layer[i] = LAYER_MONTAGNES

	# 6. LES ÉTAGES : quelques escaliers (marches d'une case) qui montent sur les massifs — on s'y infiltre là, et là seulement.
	var tries := 0
	while _etages < int(14 * s * s) + 4 and tries < 20000:
		tries += 1
		var x := rng.randi_range(-_half + FRAME_MAX + 6, N - _half - FRAME_MAX - 6)
		var z := rng.randi_range(-_half + FRAME_MAX + 6, N - _half - FRAME_MAX - 6)
		if _up_layer[_i(x, z)] != LAYER_NONE or _hole[_i(x, z)] != 0:
			continue
		# Un massif juste à côté (dans une des quatre directions) : l'escalier y monte.
		for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var first := Vector2i(x, z) + dir
			if not _inside(first.x, first.y) or _up_layer[_i(first.x, first.y)] != LAYER_MASSIFS:
				continue
			var h := _up[_i(first.x, first.y)]
			var side := Vector2i(dir.y, dir.x)
			var ok := true
			for k in h:
				for w in 2:
					var c := first + dir * k + side * w
					if not _inside(c.x, c.y) or _up_layer[_i(c.x, c.y)] != LAYER_MASSIFS:
						ok = false
			if not ok:
				continue
			for k in h:
				for w in 2:
					var c := first + dir * k + side * w
					_up[_i(c.x, c.y)] = mini(k + 1, h)
			_etages += 1
			break

	# 7. LES GALERIES : des couloirs en TUBE (sol, parois, plafond) sous la dalle, un tous les 64 m, et des escaliers.
	for z in range(-_half, N - _half):
		for x in range(-_half, N - _half):
			if _corridor(x, z):
				_gal[_i(x, z)] = 1
	for z in range(-_half, N - _half):
		for x in range(-_half, N - _half):
			if _gal[_i(x, z)] == 0:
				for dv: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1),
						Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
					var q := Vector2i(x, z) + dv
					if _inside(q.x, q.y) and _gal[_i(q.x, q.y)] == 1:
						_gal[_i(x, z)] = 2
						break
	# Les escaliers : un sur un couloir le long de x, tous les deux couloirs, à 8 m d'un croisement ; toute la largeur
	# du couloir ; les marches, puis le palier.
	var stair_len := STAIR_STEPS * STAIR_TREAD + STAIR_LANDING
	for gz in range(-_half, N - _half, GALLERY_STEP * 2):
		for gx in range(-_half, N - _half, GALLERY_STEP * 2):
			var cz := int(ceil(float(gz) / GALLERY_STEP)) * GALLERY_STEP
			var cx := int(ceil(float(gx) / GALLERY_STEP)) * GALLERY_STEP + 8
			var ok := true
			for k in stair_len:
				for w in GALLERY_W:
					if not _inside(cx + k, cz + w) or _gal[_i(cx + k, cz + w)] != 1 or _up_layer[_i(cx + k, cz + w)] != LAYER_NONE \
							or _hole[_i(cx + k, cz + w)] != 0:
						ok = false
			if not ok:
				continue
			for k in stair_len:
				for w in GALLERY_W:
					_hole[_i(cx + k, cz + w)] = 2 + mini(k / STAIR_TREAD, STAIR_STEPS)  # marche j : dessus à −j ; le palier
			_stairs.append(Vector2i(cx, cz))


func _find(parent: Dictionary, a: int) -> int:
	while parent.has(a) and parent[a] != a:
		a = parent[a]
	return a


## Ouvre un passage dans les massifs : un disque, à plat.
func _carve(c: Vector2, r: float) -> void:
	for z in range(int(c.y - r) - 1, int(c.y + r) + 2):
		for x in range(int(c.x - r) - 1, int(c.x + r) + 2):
			if _inside(x, z) and Vector2(x + 0.5, z + 0.5).distance_to(c) <= r and _up_layer[_i(x, z)] == LAYER_MASSIFS:
				_up[_i(x, z)] = 0
				_up_layer[_i(x, z)] = LAYER_NONE


## Un couloir de galerie passe-t-il là ? Dans la zone jouable, loin des lacs, du volcan et du cadre.
func _corridor(x: int, z: int) -> bool:
	if posmod(x, GALLERY_STEP) >= GALLERY_W and posmod(z, GALLERY_STEP) >= GALLERY_W:
		return false
	var p := Vector2(x + 0.5, z + 0.5)
	if absi(x) > _half - FRAME_MAX - 6 or absi(z) > _half - FRAME_MAX - 6:
		return false
	if p.distance_to(_lake) < 22.0 or p.distance_to(_pond) < 16.0 or p.distance_to(_volcano) < _volcano_r + 4.0:
		return false
	return true


## Les limites de la zone jouable (en dedans du cadre) : le jeu ne laisse JAMAIS le joueur en sortir.
func limites() -> Dictionary:
	# Au pied du cadre là où il est le plus mince ; là où il est épais, la montagne arrête le joueur avant.
	var m := float(_half - FRAME_MIN - 1)
	return {"min": [-m, -m], "max": [m, m]}


func _column(x: int, z: int, cells: Dictionary) -> void:
	var i := _i(x, z)
	var bio: String = BIOMES[_bio[i]]
	var hole := _hole[i]
	var gal := _gal[i]
	# La dalle (y = 0), ou la cuvette d'un lac (y = −1), ou une marche d'escalier de galerie.
	if hole == 1:
		cells[bio].append(Vector3i(x, -1, z))
	elif hole >= 2:
		# Marche j = hole − 2 : pleine du sol de la galerie jusqu'à la case −1 − j (son dessus à −j) ; le palier : le sol seul.
		var top := -1 - (hole - 2) if hole - 2 < STAIR_STEPS else GALLERY_FLOOR
		for y in range(GALLERY_FLOOR, top + 1):
			cells["Profondeurs"].append(Vector3i(x, y, z))
		return
	else:
		cells[bio].append(Vector3i(x, 0, z))
	# La galerie sous la dalle : un couloir (sol en GALLERY_FLOOR, plafond en −1, de l'air entre) ou sa paroi (pleine).
	if gal == 1 and hole == 0:
		cells["Profondeurs"].append(Vector3i(x, GALLERY_FLOOR, z))
		cells["Profondeurs"].append(Vector3i(x, -1, z))
	elif gal == 2 and hole == 0:
		for y in range(GALLERY_FLOOR, 0):
			cells["Profondeurs"].append(Vector3i(x, y, z))
	# Au-dessus : massif, cadre (enneigé en haut), volcan.
	var up := _up[i]
	if up <= 0:
		return
	var layer: String = ["", "Massifs", "Montagnes", "Volcan"][_up_layer[i]]
	for y in range(1, up + 1):
		var l := layer
		if layer == "Montagnes" and up >= 10 and y >= up - 1:
			l = "Neige"
		cells[l].append(Vector3i(x, y, z))


# --- L'eau ------------------------------------------------------------------------------------------------------

## Un corps d'eau calculé par MB dans une boîte autour de `centre` : les cases pleines de la boîte (toutes couches),
## une source juste au-dessus du fond. Rend {"source", "maillage", "cases"} ou {"erreur"}.
func _eau(centre: Vector2, rayon: int) -> Dictionary:
	var occ := {}
	var cx := int(floor(centre.x))
	var cz := int(floor(centre.y))
	for x in range(cx - rayon, cx + rayon + 1):
		for z in range(cz - rayon, cz + rayon + 1):
			if not _inside(x, z):
				continue
			var col := {"Profondeurs": [], "Paves": [], "Chemins": [], "SousBois": [], "Marais": [], "Desert": [],
				"Prairie": [], "Montagnes": [], "Neige": [], "Volcan": [], "Massifs": []}
			_column(x, z, col)
			for k in col:
				for c in col[k]:
					occ[c] = true
	var top := -10
	for yy in range(-10, 80):
		if occ.has(Vector3i(cx, yy, cz)):
			top = yy
	var src := Vector3i(cx, top + 1, cz)
	var w: Dictionary = FL.monde(occ, [src])
	var corps: Array = w["corps"]
	if corps.is_empty() or str(corps[0].get("erreur", "")) != "":
		return {"erreur": str(corps[0].get("erreur", "aucun corps")) if not corps.is_empty() else "aucun corps"}
	var m: ArrayMesh = EM.maillage(corps, occ, w["boite"])
	return {"source": src, "maillage": m, "cases": (corps[0].get("eau", {}) as Dictionary).size()}


# --- Le feuillage : les arbres de HEARTWORLD -------------------------------------------------------------------

func _feuillage() -> Dictionary:
	DirAccess.make_dir_recursive_absolute(RACINE.path_join("modeles/arbres"))
	var modeles: Array = []
	var plaines: Array = []
	var bois: Array = []
	var id := 1
	for groupe in [[ARBRES_PLAINES, 5.5, plaines], [ARBRES_BOIS, 6.5, bois]]:
		for rel: String in groupe[0]:
			var src := ARBRES_SOURCE.path_join(rel)
			var dst := RACINE.path_join("modeles/arbres").path_join(rel.get_file())
			if not FileAccess.file_exists(dst):
				DirAccess.copy_absolute(src, dst)
			var box := _boite_du_modele(dst)
			if box.size.y <= 0.0:
				print("  ⚠ arbre illisible : %s" % rel)
				continue
			var ech: float = float(groupe[1]) / box.size.y
			# `decalage`, `rayon`, `hauteur` : en unités DU MODÈLE (`feuillage.gd`) — le pied du tronc posé au sol.
			modeles.append({"id": id, "nom": rel.get_file().get_basename(), "chemin": dst,
				"decalage": -box.position.y, "echelle": ech, "echelle_alea": 0.25,
				"rayon": maxf(box.size.x, box.size.z) * 0.4, "hauteur": box.end.y, "vent": 0.8})
			(groupe[2] as Array).append(id)
			id += 1
	var plants: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for z in range(-_half + FRAME_MAX + 2, N - _half - FRAME_MAX - 2, 5):
		for x in range(-_half + FRAME_MAX + 2, N - _half - FRAME_MAX - 2, 5):
			var p := Vector2(x + rng.randf_range(0.5, 4.5), z + rng.randf_range(0.5, 4.5))
			var c := Vector2i(int(floor(p.x)), int(floor(p.y)))
			if not _inside(c.x, c.y):
				continue
			var i := _i(c.x, c.y)
			if _up[i] > 0 or _hole[i] != 0 or _near_road(p, 4.0) or p.length() < 38.0:
				continue
			var near_village := false
			for v in _villages:
				if p.distance_to(v[0]) < 16.0:
					near_village = true
			if near_village:
				continue
			# Ni trop près d'un massif (un arbre coincé contre un mur) : les 2 cases autour sont libres.
			var free := true
			for dz in range(-2, 3):
				for dx in range(-2, 3):
					var q := c + Vector2i(dx, dz)
					if _inside(q.x, q.y) and (_up[_i(q.x, q.y)] > 0 or _hole[_i(q.x, q.y)] != 0):
						free = false
			if not free:
				continue
			var chance := 0.0
			var pool: Array = plaines
			match _bio[i]:
				B_SOUSBOIS:
					chance = 0.5
					pool = bois
				B_PRAIRIE:
					chance = 0.07
				B_MARAIS:
					chance = 0.08
					pool = bois
			if pool.is_empty() or rng.randf() >= chance:
				continue
			plants.append({"modele": pool[rng.randi() % pool.size()], "p": Vector3(p.x, 1.0, p.y), "lacet": rng.randf() * TAU,
				"echelle": 0.85 + rng.randf() * 0.35, "mode": "plante"})
	return {"modeles_fe": modeles, "plants_fe": plants, "plants": plants}


## La boîte d'un modèle .glb (ses maillages, à leur pose), en unités du modèle.
func _boite_du_modele(chemin: String) -> AABB:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(chemin, st) != OK:
		return AABB()
	var scene := doc.generate_scene(st)
	var box := AABB()
	var first := true
	var stack: Array = [[scene, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var it: Array = stack.pop_back()
		var node: Node = it[0]
		var xf: Transform3D = it[1]
		if node is Node3D:
			xf = xf * (node as Node3D).transform
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var b := xf * (node as MeshInstance3D).mesh.get_aabb()
			box = b if first else box.merge(b)
			first = false
		for ch in node.get_children():
			stack.append([ch, xf])
	scene.free()
	return box


# --- Les sept matières neuves ------------------------------------------------------------------------------------

func _specs() -> Array:
	return [
		{"id": "paves", "nom": "Paves", "dessus": _tex_paves, "flancs": _tex_moellons, "rug": [0.85, 0.9],
			"pbr": {"normale": 5.0, "contraste": 1.7}},
		{"id": "chemins", "nom": "Chemins", "dessus": _tex_terre_battue, "flancs": _tex_terre, "rug": [0.95, 1.0],
			"pbr": {"normale": 3.0}},
		{"id": "sousbois", "nom": "SousBois", "dessus": _tex_sous_bois, "flancs": _tex_humus, "rug": [0.9, 1.0],
			"pbr": {"normale": 3.5}},
		{"id": "marais", "nom": "Marais", "dessus": _tex_vase, "flancs": _tex_boue, "rug": [0.35, 0.6],
			"pbr": {"normale": 2.0}},
		{"id": "neige", "nom": "Neige", "dessus": _tex_neige, "flancs": _tex_glace, "rug": [0.7, 0.4],
			"pbr": {"normale": 2.0, "contraste": 1.2}},
		{"id": "basalte", "nom": "Basalte", "dessus": _tex_cendre, "flancs": _tex_orgues, "rug": [0.95, 0.8],
			"pbr": {"normale": 4.5}},
		{"id": "profondeurs", "nom": "Profondeurs", "dessus": _tex_gravier, "flancs": _tex_strates, "rug": [0.95, 0.9],
			"pbr": {"normale": 4.0}},
	]


## Une matière neuve : le témoin de MB, deux matériaux (le dessus, les flancs : par la normale de chaque face),
## enregistrée comme l'appli l'enregistre — son témoin lié (`.mbtiles`) et son `.glb`.
func _matiere(spec: Dictionary) -> Dictionary:
	var dir := RACINE.path_join("matieres").path_join(spec["id"])
	DirAccess.make_dir_recursive_absolute(dir)
	var mats: Array = []
	for i in 2:
		var part: String = ["dessus", "flancs"][i]
		var img: Image = (spec[part] as Callable).call()
		var png := dir.path_join("%s_%s.png" % [spec["id"], part])
		img.save_png(png)
		var pbr := Cartes.DEFAUTS.duplicate()
		pbr.merge(spec.get("pbr", {}), true)
		mats.append({"nom": "%s %s" % [spec["nom"], part], "couleur": Color.WHITE, "rugosite": spec["rug"][i],
			"metal": 0.0, "texture": png, "echelle": 1.0, "projection": "boite", "pbr": pbr})
	var t: RefCounted = TL.depuis_le_temoin_calcule()
	# ⚠ Le tableau des matériaux est PARTAGÉ avec chaque tuile du témoin (`_partager`) : on le remplit, sans le remplacer.
	t.materiaux.clear()
	t.materiaux.append_array(mats)
	for c in t.tuiles:
		var tile = t.tuiles[c]
		var dessus: Array = []
		var flancs: Array = []
		for f in tile.faces.size():
			(dessus if tile.normale(f).y > 0.55 else flancs).append(f)
		tile.assigner(dessus, 0)
		tile.assigner(flancs, 1)
	var mbtiles := dir.path_join(spec["id"] + ".mbtiles")
	var fo := FileAccess.open(mbtiles, FileAccess.WRITE)
	fo.store_string(JSON.stringify(t.vers_dictionnaire()))
	fo.close()
	var glb := dir.path_join(spec["id"] + ".glb")
	var err: String = t.vers_glb(glb)
	if err != "":
		return {"erreur": "matière %s : %s" % [spec["id"], err]}
	return {"glb": glb, "temoin": mbtiles}


# --- Les textures : 512², SANS COUTURE (une tuile = une case = une période), projetées en « boîte » ---------------

func _noise(seed_: int, freq: float, oct := 4, kind := FastNoiseLite.TYPE_SIMPLEX_SMOOTH,
		fractal := FastNoiseLite.FRACTAL_FBM) -> Image:
	var n := FastNoiseLite.new()
	n.seed = seed_
	n.noise_type = kind
	n.frequency = freq
	n.fractal_octaves = oct
	n.fractal_type = fractal
	return n.get_seamless_image(TEX, TEX, false, false, 0.1, true)


## Un pavage de Voronoï PÉRIODIQUE : `g` × `g` germes, distance au plus proche (f1), au second (f2), et l'indice.
func _voronoi(g: int, jitter: float, seed_: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var pts: Array = []
	for j in g:
		for i in g:
			pts.append(Vector2(i + 0.5 + rng.randf_range(-jitter, jitter), j + 0.5 + rng.randf_range(-jitter, jitter)) / g)
	var f1 := PackedFloat32Array()
	var f2 := PackedFloat32Array()
	var ids := PackedInt32Array()
	f1.resize(TEX * TEX)
	f2.resize(TEX * TEX)
	ids.resize(TEX * TEX)
	for y in TEX:
		for x in TEX:
			var p := Vector2((x + 0.5) / TEX, (y + 0.5) / TEX)
			var ci := int(p.x * g)
			var cj := int(p.y * g)
			var d1 := 9.0
			var d2 := 9.0
			var id := 0
			for dj in range(-1, 2):
				for di in range(-1, 2):
					var ii := posmod(ci + di, g)
					var jj := posmod(cj + dj, g)
					var q: Vector2 = pts[jj * g + ii]
					var off := Vector2(floor(float(ci + di) / g), floor(float(cj + dj) / g))
					var d := p.distance_to(q + off)
					if d < d1:
						d2 = d1
						d1 = d
						id = jj * g + ii
					elif d < d2:
						d2 = d
			f1[y * TEX + x] = d1 * g
			f2[y * TEX + x] = d2 * g
			ids[y * TEX + x] = id
	return [f1, f2, ids]


static func _hash01(i: int) -> float:
	var h := (i * 73856093) ^ 0x5bd1e995
	h = (h ^ (h >> 13)) * 0x45d9f3b
	return float(h & 0xFFFF) / 65535.0


func _paint(f: Callable) -> Image:
	var img := Image.create(TEX, TEX, false, Image.FORMAT_RGBA8)
	for y in TEX:
		for x in TEX:
			img.set_pixel(x, y, f.call(x, y))
	return img


## Les pavés de la capitale : des pierres arrondies grises et ocre, joints sombres.
func _tex_paves() -> Image:
	var v := _voronoi(5, 0.32, 1)
	var grain := _noise(2, 0.08)
	return _paint(func(x: int, y: int) -> Color:
		var i := y * TEX + x
		var edge: float = v[1][i] - v[0][i]
		var k := _hash01(v[2][i])
		var stone := Color(0.55, 0.52, 0.47).lerp(Color(0.66, 0.58, 0.45), k).darkened(0.15 * float(v[0][i]))
		stone = stone.darkened((grain.get_pixel(x, y).r - 0.5) * 0.25)
		var joint := smoothstep(0.05, 0.16, edge)
		return Color(0.2, 0.18, 0.16).lerp(stone, joint))


## Les flancs pavés : des moellons en assises (deux par case), joints creux.
func _tex_moellons() -> Image:
	var grain := _noise(3, 0.06)
	return _paint(func(x: int, y: int) -> Color:
		var row := y / (TEX / 4)
		var off := (TEX / 4) if row % 2 == 1 else 0
		var col := ((x + off) % TEX) / (TEX / 2)
		var lx := ((x + off) % (TEX / 2))
		var ly := y % (TEX / 4)
		var k := _hash01(row * 7 + col)
		var stone := Color(0.6, 0.57, 0.5).lerp(Color(0.5, 0.46, 0.4), k)
		stone = stone.darkened((grain.get_pixel(x, y).r - 0.5) * 0.3)
		var m := minf(minf(lx, TEX / 2 - lx), minf(ly, TEX / 4 - ly))
		return Color(0.22, 0.2, 0.18).lerp(stone, smoothstep(2.0, 7.0, m)))


## La terre battue des routes : brune, des gravillons clairs, des traces.
func _tex_terre_battue() -> Image:
	var base := _noise(4, 0.012)
	var fine := _noise(5, 0.09)
	var peb := _voronoi(14, 0.45, 6)
	return _paint(func(x: int, y: int) -> Color:
		var i := y * TEX + x
		var c := Color(0.48, 0.37, 0.25).lerp(Color(0.6, 0.48, 0.33), base.get_pixel(x, y).r)
		c = c.darkened((fine.get_pixel(x, y).r - 0.5) * 0.3)
		if peb[0][i] < 0.18 and _hash01(peb[2][i]) > 0.55:
			c = c.lerp(Color(0.72, 0.68, 0.6), 0.75)
		return c)


func _tex_terre() -> Image:
	var base := _noise(7, 0.02)
	var fine := _noise(8, 0.1)
	return _paint(func(x: int, y: int) -> Color:
		var band := 0.5 + 0.5 * sin(TAU * (y / float(TEX)) * 3.0 + base.get_pixel(x, y).r * 4.0)
		var c := Color(0.36, 0.26, 0.17).lerp(Color(0.46, 0.34, 0.22), band)
		return c.darkened((fine.get_pixel(x, y).r - 0.5) * 0.35))


## Le sous-bois : mousse verte et litière de feuilles brunes, mêlées.
func _tex_sous_bois() -> Image:
	var mix := _noise(9, 0.015)
	var leaves := _voronoi(18, 0.48, 10)
	var fine := _noise(11, 0.12)
	return _paint(func(x: int, y: int) -> Color:
		var i := y * TEX + x
		var moss := Color(0.22, 0.36, 0.14).lerp(Color(0.33, 0.45, 0.18), fine.get_pixel(x, y).r)
		var k := _hash01(leaves[2][i])
		var leaf := Color(0.42, 0.28, 0.13).lerp(Color(0.58, 0.4, 0.16), k).darkened(leaves[0][i] * 0.35)
		var w := smoothstep(0.42, 0.62, mix.get_pixel(x, y).r)
		return moss.lerp(leaf, w))


func _tex_humus() -> Image:
	var base := _noise(12, 0.03)
	var roots := _noise(13, 0.02, 3, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, FastNoiseLite.FRACTAL_RIDGED)
	return _paint(func(x: int, y: int) -> Color:
		var c := Color(0.19, 0.13, 0.08).lerp(Color(0.28, 0.2, 0.12), base.get_pixel(x, y).r)
		var r := roots.get_pixel(x, y).r
		return c.lerp(Color(0.45, 0.33, 0.2), smoothstep(0.82, 0.95, r)))


## La vase du marais : olive sombre, flaques luisantes.
func _tex_vase() -> Image:
	var base := _noise(14, 0.018)
	var wet := _noise(15, 0.03)
	return _paint(func(x: int, y: int) -> Color:
		var c := Color(0.2, 0.22, 0.12).lerp(Color(0.3, 0.3, 0.16), base.get_pixel(x, y).r)
		var w := smoothstep(0.6, 0.7, wet.get_pixel(x, y).r)
		return c.lerp(Color(0.1, 0.12, 0.08), w))


func _tex_boue() -> Image:
	var base := _noise(16, 0.04)
	return _paint(func(x: int, y: int) -> Color:
		return Color(0.17, 0.15, 0.1).lerp(Color(0.25, 0.22, 0.14), base.get_pixel(x, y).r))


## La neige : blanche, ombrée de bleu, quelques cristaux.
func _tex_neige() -> Image:
	var base := _noise(17, 0.012)
	var fine := _noise(18, 0.15)
	return _paint(func(x: int, y: int) -> Color:
		var c := Color(0.83, 0.87, 0.94).lerp(Color(0.97, 0.98, 1.0), base.get_pixel(x, y).r)
		if fine.get_pixel(x, y).r > 0.86:
			c = Color.WHITE
		return c)


## Les flancs enneigés : roche glacée grise, la neige dans les fissures.
func _tex_glace() -> Image:
	var base := _noise(19, 0.025)
	var cracks := _noise(20, 0.02, 3, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, FastNoiseLite.FRACTAL_RIDGED)
	return _paint(func(x: int, y: int) -> Color:
		var c := Color(0.42, 0.46, 0.52).lerp(Color(0.6, 0.65, 0.72), base.get_pixel(x, y).r)
		return c.lerp(Color(0.92, 0.95, 1.0), smoothstep(0.75, 0.9, cracks.get_pixel(x, y).r)))


## La cendre du volcan : gris très sombre, des braises orangées éparses.
func _tex_cendre() -> Image:
	var base := _noise(21, 0.03)
	var embers := _voronoi(22, 0.48, 22)
	return _paint(func(x: int, y: int) -> Color:
		var i := y * TEX + x
		var c := Color(0.12, 0.11, 0.11).lerp(Color(0.24, 0.22, 0.21), base.get_pixel(x, y).r)
		if embers[0][i] < 0.12 and _hash01(embers[2][i]) > 0.86:
			c = c.lerp(Color(0.95, 0.42, 0.12), 0.8)
		return c)


## Les orgues basaltiques : des colonnes verticales noires, joints plus clairs.
func _tex_orgues() -> Image:
	var v := _voronoi(6, 0.3, 23)
	var streak := _noise(24, 0.05)
	return _paint(func(x: int, y: int) -> Color:
		# Une colonne = une cellule de Voronoï en x seulement : on lit la ligne du milieu.
		var i := (TEX / 2) * TEX + x
		var edge: float = v[1][i] - v[0][i]
		var k := _hash01(v[2][i])
		var c := Color(0.1, 0.1, 0.11).lerp(Color(0.2, 0.19, 0.2), k)
		c = c.darkened((streak.get_pixel(x, y).r - 0.5) * 0.4)
		return Color(0.32, 0.3, 0.3).lerp(c, smoothstep(0.03, 0.1, edge)))


## Le sol des galeries : un gravier sombre.
func _tex_gravier() -> Image:
	var v := _voronoi(16, 0.45, 25)
	return _paint(func(x: int, y: int) -> Color:
		var i := y * TEX + x
		var k := _hash01(v[2][i])
		var c := Color(0.2, 0.18, 0.16).lerp(Color(0.34, 0.31, 0.27), k).darkened(v[0][i] * 0.5)
		return Color(0.1, 0.09, 0.08).lerp(c, smoothstep(0.03, 0.12, v[1][i] - v[0][i])))


## Les parois des galeries : des strates de grès, brunes et grises, ondulées.
func _tex_strates() -> Image:
	var warp := _noise(26, 0.01)
	var fine := _noise(27, 0.09)
	return _paint(func(x: int, y: int) -> Color:
		var t := y / float(TEX) * 5.0 + (warp.get_pixel(x, y).r - 0.5) * 1.2
		var band := 0.5 + 0.5 * sin(TAU * t)
		var c := Color(0.32, 0.27, 0.22).lerp(Color(0.46, 0.4, 0.33), band)
		return c.darkened((fine.get_pixel(x, y).r - 0.5) * 0.35))
