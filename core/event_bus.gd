extends Node
## LE BUS D'ÉVÉNEMENTS — les systèmes ne se connaissent pas, ils se parlent ici.
##
## Le backend (horloge, état, moteur de décision, sommeil) émet ; la présentation (caméra, UI, animations,
## lumière) écoute. Changer l'expression visuelle ne doit jamais toucher au backend.

# --- Lieux -------------------------------------------------------------------------------------------------
signal region_entered(region_id: String, region_type: String)
signal region_exited(region_id: String)
signal interior_entered(interior_id: String, interior_type: String)
signal interior_exited(interior_id: String)

# --- Vue ---------------------------------------------------------------------------------------------------
## Le rayon du sol que la caméra voit autour du joueur (zoom, vue haute) : le ChunkStreamer charge assez loin pour lui.
signal view_radius_changed(radius: float)
## Un message pour le joueur (ou pour qui teste) : le HUD le montre un moment.
signal notice(text: String, seconds: float)

# --- Rencontres --------------------------------------------------------------------------------------------
## Le joueur peut interagir avec `target` (un Interactable), ou plus avec rien (null).
signal focus_changed(target: Node)
## Le moteur a proposé des actions pour une rencontre : la barre les montre.
signal encounter_opened(target_id: String, actions: Array)
signal encounter_closed(target_id: String)
## Une action a été choisie et appliquée.
signal action_resolved(target_id: String, action_id: String, record: Dictionary)

# --- Temps et sommeil --------------------------------------------------------------------------------------
signal hour_changed(day: int, hour: int)
signal day_changed(day: int)
signal fatigue_changed(awake_hours: float, limit_hours: float)
signal sleep_warning(hours_left: float)
signal sleep_started(spot_kind: String, forced: bool)
signal sleep_finished(outcome: Dictionary)

# --- Partie ------------------------------------------------------------------------------------------------
signal game_started(seed: int)
signal game_loaded()
signal state_changed(path: String, value: Variant)
