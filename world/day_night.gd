extends Node3D
## LE CYCLE JOUR / NUIT — lit l'horloge, rien d'autre : le soleil tourne, la lumière et le ciel suivent.
## Pendant le sommeil l'horloge accélère : le cycle défile tout seul, sans code à part.
## LA NUIT n'est jamais noire : une LUNE (lumière directionnelle bleutée, en face du soleil) prend le relais quand il
## se couche, et l'ambiante ne descend pas sous `night_ambient` × `night_ambient_energy`. Dans un intérieur, l'ambiante
## du ciel baisse (`interior_ambient`) : la torche du joueur (`player/torche.gd`) éclaire.

@export var sun: DirectionalLight3D
@export var environment: WorldEnvironment
@export var sun_energy := 1.0
@export var day_sky := Color(0.55, 0.7, 0.95)
@export var dusk_sky := Color(0.95, 0.55, 0.35)
@export var night_sky := Color(0.03, 0.04, 0.1)
@export_group("Nuit")
## La lune ; vide : créée ici.
@export var moon: DirectionalLight3D
@export var moon_energy := 0.3
@export var moon_color := Color(0.6, 0.7, 1.0)
## Le plancher de l'ambiante : la nuit garde au moins cette lumière (la forme des choses reste lisible).
@export var night_ambient := Color(0.3, 0.36, 0.55)
@export var night_ambient_energy := 0.45
## Dans un intérieur (maison, grotte), l'ambiante du ciel n'entre qu'à cette part : la torche fait le reste.
@export var interior_ambient := 0.35

var _inside := 0.0


func _ready() -> void:
	if moon == null:
		moon = DirectionalLight3D.new()
		moon.name = "Lune"
		moon.shadow_enabled = true  # sans ombre, elle éclairait l'intérieur de l'auberge à travers le toit (vu)
		add_child(moon)
	# Tournés à chaque image (`_process`) : l'interpolation physique n'a rien à y lisser.
	for light: Node3D in [sun, moon]:
		if light:
			light.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _process(delta: float) -> void:
	_inside = move_toward(_inside, 1.0 if Interior.is_inside() else 0.0, delta / 0.8)
	var f := GameClock.day_fraction()
	# Midi = soleil au zénith ; minuit = sous l'horizon.
	var elevation := sin((f - 0.25) * TAU)  # -1 à minuit, 1 à midi
	if sun:
		sun.rotation = Vector3(-asin(clampf(elevation, -1.0, 1.0)) - 0.15, f * TAU, 0.0)
		sun.light_energy = sun_energy * smoothstep(-0.05, 0.25, elevation)
		sun.light_color = dusk_sky.lerp(Color.WHITE, smoothstep(0.0, 0.4, elevation))
	if moon:
		# En face du soleil, un peu plus bas sur l'horizon ; elle s'efface quand le soleil se lève.
		moon.rotation = Vector3(-asin(clampf(-elevation, -1.0, 1.0)) * 0.8 - 0.25, f * TAU + PI, 0.0)
		moon.light_color = moon_color
		moon.light_energy = moon_energy * smoothstep(0.05, -0.2, elevation)
		moon.visible = moon.light_energy > 0.001
	if environment and environment.environment:
		var sky := night_sky.lerp(dusk_sky, smoothstep(-0.25, 0.05, elevation)).lerp(day_sky, smoothstep(0.05, 0.35, elevation))
		var env := environment.environment
		env.background_color = sky
		var day := smoothstep(-0.2, 0.3, elevation)
		env.ambient_light_color = night_ambient.lerp(sky, day)
		env.ambient_light_energy = lerpf(night_ambient_energy, 0.35, day) * lerpf(1.0, interior_ambient, _inside)
