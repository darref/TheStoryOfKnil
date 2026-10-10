extends Node3D
## BANC DE MARCHE — avec fenêtre : une cible traverse le grand monde cuit en courant (8 cases/s), caméra de jeu en
## vue de dessus ; le chargement en fond doit suivre SANS À-COUP. Images/s moyennes, pire image, morceaux chargés.
##   Godot --path D:/Resolve --windowed res://tests/banc_marche.tscn [-- --monde=res://cuit/grand]
## (le grand monde : fabriquer_monde_essai -- --taille=512 --nom=grand, --import, puis la cuisson)

const SPEED := 8.0

func _ready() -> void:
	var dir := "res://cuit/grand"
	var dist := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--monde="):
			dir = a.trim_prefix("--monde=")
		elif a.begins_with("--distances="):  # piste:distance,piste:distance
			for kv in a.trim_prefix("--distances=").split(","):
				dist[kv.split(":")[0]] = float(kv.split(":")[1])
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.4, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var target := Node3D.new()
	target.position = Vector3(-110, 0, -100)
	add_child(target)
	var s := ChunkStreamer.new()
	s.baked_dir = dir
	s.target = target
	s.distances = dist
	if "--garder" in OS.get_cmdline_user_args():
		s.unload_margin = 5000.0  # rien ne se décharge : au retour, plus rien ne se charge
	add_child(s)
	if "--sans-transitions" in OS.get_cmdline_user_args() and s._transitions_mat != null:
		# La passe des transitions retirée : son shader ne dessine plus rien.
		var vide := Shader.new()
		vide.code = "shader_type spatial;
void fragment() { discard; }"
		s._transitions_mat.shader = vide
	var cam := Camera3D.new()
	cam.fov = 55
	add_child(cam)
	cam.current = true
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	for i in 30:
		await get_tree().process_frame
	var frames := 0
	var poll_sum := 0.0
	var under_sum := 0.0
	var qmax := 0
	var worst := 0.0
	var spikes := 0
	var t0 := Time.get_ticks_usec()
	var last := t0
	var max_loaded := 0
	var back := "--aller-retour" in OS.get_cmdline_user_args()
	var dir_v := Vector3(1, 0, 0.9).normalized()
	var spikes_go := -1
	# Deux phases : l'aller jusqu'à x = 110 ; puis, avec --aller-retour, le retour jusqu'à x = −110 (les morceaux sont
	# relus, les shaders sont déjà compilés : ce qui reste est le coût de CHAQUE chargement).
	while true:
		if spikes_go < 0 and target.position.x >= 110:
			if not back:
				break
			spikes_go = spikes
			dir_v = -dir_v
			print("aller : %d images > 33 ms" % spikes)
		elif spikes_go >= 0 and target.position.x <= -110:
			break
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var dt := (now - last) / 1000.0
		last = now
		worst = maxf(worst, dt)
		spikes += 1 if dt > 33.3 else 0
		if dt > 33.3 and "--detail" in OS.get_cmdline_user_args():
			var vp := get_viewport().get_viewport_rid()
			print("LENTE %.1f ms · process %.1f · physique %.1f · préparation %.1f · rendu cpu %.1f gpu %.1f ms · flux get %.2f poll %.2f · entrées %d (%.1f ms, %s ; en cours : %s) · libérés %d (%.1f ms) · objets %d" % [
				dt, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, RenderingServer.get_frame_setup_time_cpu(),
				RenderingServer.viewport_get_measured_render_time_cpu(vp), RenderingServer.viewport_get_measured_render_time_gpu(vp),
				s.last_costs.get("get", 0.0), s.last_costs.get("poll", 0.0), s.last_costs.get("n_enter", 0),
				s.last_costs.get("enter", 0.0), s.last_costs.get("enter_track", "-"), s.last_costs.get("busy", ""), s.last_costs.get("n_free", 0), s.last_costs.get("free", 0.0),
				Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
		frames += 1
		poll_sum += float(s.last_costs.get("poll", 0.0))
		under_sum += float(s.last_costs.get("under", 0.0))
		qmax = maxi(qmax, int(s.last_costs.get("queue", 0)))
		target.position += dir_v * SPEED * (dt / 1000.0)
		cam.look_at_from_position(target.position + Vector3(0, 14 + 4, 9), target.position + Vector3(0, 4, 0))
		max_loaded = maxi(max_loaded, s.loaded_count())
	print("streamer : poll %.2f ms/image en moyenne, sous-sol %.2f ms/image, file jusqu'à %d" % [poll_sum / frames, under_sum / frames, qmax])
	if back:
		print("retour : %d images > 33 ms" % (spikes - spikes_go))
	var secs := (Time.get_ticks_usec() - t0) / 1e6
	print("MARCHE : %.0f cases en %.1f s · %.0f img/s · pire image %.1f ms · %d images > 33 ms · jusqu'à %d morceaux chargés / %d · %d appels de dessin" % [
		SPEED * secs, secs, frames / secs, worst, spikes, max_loaded, (s.manifest["chunks"] as Array).size(),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	get_tree().quit()
