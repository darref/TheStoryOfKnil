extends Resource
## LES DONNÉES DES TRANSITIONS D'UN MONDE CUIT — ce que le matériau des transitions (le shader de MB) lit : la texture
## 3D des cases (un octet par case : sa couche, le choix au sommet) et le tableau des images représentantes.
##
## ⚠ RANGÉES EN DONNÉES, PAS EN TEXTURES : la cuisson tourne sans fenêtre, et le rendu factice de --headless ne garde
## pas le contenu d'une texture faite à la volée — enregistrées telles quelles, elles revenaient VIDES (vu au chargement :
## « img.is_null() »). Une Image, elle, s'enregistre avec ses octets. Le ChunkStreamer rebâtit les textures au
## chargement du monde (`apply`), sur le matériau partagé par tous les morceaux.

@export var cells := PackedByteArray()
@export var origin := Vector3i.ZERO
@export var size := Vector3i.ONE
## Une image par couche (RGBA8, 256², avec mipmaps), dans l'ordre des couches.
@export var images: Array[Image] = []
## La table des paires (2·15 × 15 texels, flottants) : en (2 D, C) active, douceur, avancée, irrégularité ; en
## (2 D + 1, C) comblement, grain — quand C couvre D. Vide ou absente : aucune paire ne se dessine.
@export var table: Image
## La couleur de chaque représentant (multiplie son image). ⚠ En données aussi : posée en tableau de couleurs sur un
## `vec4 rep_couleur[15]`, elle ne survivait pas à l'enregistrement du matériau (relue nulle — vu : des bords NOIRS là
## où le greffon les dessine verts).
@export var colors := PackedColorArray()


func apply(mat: ShaderMaterial) -> void:
	var per := size.x * size.y
	var slices: Array[Image] = []
	for z in size.z:
		slices.append(Image.create_from_data(size.x, size.y, false, Image.FORMAT_R8, cells.slice(z * per, (z + 1) * per)))
	var tex := ImageTexture3D.new()
	tex.create(Image.FORMAT_R8, size.x, size.y, size.z, false, slices)
	mat.set_shader_parameter("cases", tex)
	mat.set_shader_parameter("origine", origin)
	mat.set_shader_parameter("taille", size)
	if not colors.is_empty():
		mat.set_shader_parameter("rep_couleur", colors)
	if table != null:
		mat.set_shader_parameter("table", ImageTexture.create_from_image(table))
	if not images.is_empty():
		var arr := Texture2DArray.new()
		arr.create_from_images(images)
		mat.set_shader_parameter("representants", arr)
