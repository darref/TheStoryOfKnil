extends Node
## BANC DE COURSE — avec fenêtre : le VRAI jeu (main.tscn, Knil, sa caméra) ; Knil court tout droit dans une direction
## puis dans l'autre, les morceaux se chargent en fond. Chaque image lente (> `--seuil` ms, 25 par défaut) est
## détaillée : ce que le ChunkStreamer a fait (entrées, libérations, formes), la physique, le rendu.
##   Godot --path D:/TheStoryOfKnil --windowed res://tests/banc_course.tscn [-- --duree=20 --seuil=25 --dir=1,0 --gel]
## `--gel` : le ChunkStreamer figé après le départ (plus rien ne se charge) — ce qui reste lent vient d'ailleurs.
## Sort avec 0.

func _ready() -> void:
	var duration := 20.0
	var threshold := 25.0
	var dir := Vector2(1, 0)
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		match kv[0]:
			"duree": duration = float(kv[1])
			"seuil": threshold = float(kv[1])
			"dir": dir = Vector2(float(kv[1].split(",")[0]), float(kv[1].split(",")[1])).normalized()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	var streamer: ChunkStreamer = main.get_node("Monde")
	var player: Player = main.get_node("Player")
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	await get_tree().create_timer(4.0).timeout
	if "--gel" in OS.get_cmdline_user_args():  # plus aucun chargement : ce qui reste lent n'est pas le streamer
		streamer.set_process(false)
	if "--sans-camera" in OS.get_cmdline_user_args():  # la caméra ne lance plus de requêtes (bras, bascule)
		main.get_node("CameraRig").arm_mask = 0
	if "--sans-hud" in OS.get_cmdline_user_args():
		main.get_node("HUD").set_process(false)
	if "--sans-rig" in OS.get_cmdline_user_args():
		main.get_node("CameraRig").set_process(false)
	if "--arret" in OS.get_cmdline_user_args():  # Knil ne court pas : le coût de l'immobilité
		duration = -duration
	var frames := 0
	var slow := 0
	var worst := 0.0
	var t0 := Time.get_ticks_usec()
	var last := t0
	var half := duration * 0.5
	var flipped := false
	var still := duration < 0.0
	duration = absf(duration)
	if not still:
		Input.action_press("run")
		_press(dir)
	while (Time.get_ticks_usec() - t0) / 1e6 < duration:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var dt := (now - last) / 1000.0
		last = now
		frames += 1
		worst = maxf(worst, dt)
		if not still and not flipped and (now - t0) / 1e6 > half:
			flipped = true
			_release()
			dir = -dir
			_press(dir)
		if dt > threshold:
			slow += 1
			var c: Dictionary = streamer.last_costs
			print("LENTE %.1f ms · process %.1f · physique %.1f · rendu cpu %.1f gpu %.1f · entrées %d (%.1f ms, max %.1f %s) · libérés %d · formes %.1f · étalés %.1f · get %.1f · file %d · objets %d" % [
				dt, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
				RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()),
				RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()),
				c.get("n_enter", 0), c.get("enter", 0.0), c.get("enter_max", 0.0), c.get("enter_track", ""),
				c.get("n_free", 0), c.get("shapes", 0.0), c.get("staged", 0.0), c.get("get", 0.0), c.get("queue", 0),
				Performance.get_monitor(Performance.OBJECT_COUNT)])
	_release()
	Input.action_release("run")
	var secs := (Time.get_ticks_usec() - t0) / 1e6
	print("COURSE : %.0f s · %.0f img/s · pire image %.1f ms · %d images > %.0f ms · Knil fini en (%.0f, %.0f)" % [
		secs, frames / secs, worst, slow, threshold, player.global_position.x, player.global_position.z])
	get_tree().quit()


func _press(d: Vector2) -> void:
	for pair in [["move_right", d.x], ["move_left", -d.x], ["move_back", d.y], ["move_forward", -d.y]]:
		if pair[1] > 0.01:
			Input.action_press(pair[0], pair[1])


func _release() -> void:
	for a in ["move_right", "move_left", "move_back", "move_forward"]:
		Input.action_release(a)
