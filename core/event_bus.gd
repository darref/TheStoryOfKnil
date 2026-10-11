extends Node
## LE BUS D'ÉVÉNEMENTS — les systèmes ne se connaissent pas, ils se parlent ici.
##
## Le backend (horloge, état, sauvegarde) émet ; la présentation (caméra, UI, animations, lumière) écoute.
## Changer l'expression visuelle ne doit jamais toucher au backend.

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
## Une réplique à montrer (`speaker` parle) ; `dialogue_closed` : la boîte se ferme.
signal dialogue_shown(speaker: String, text: String)
signal dialogue_closed()

# --- Combat ----------------------------------------------------------------------------------------------
## Knil commence un coup (`kind` : « genou ») ; il touche `target` (un Frappable).
signal player_attacked(kind: String)
signal player_hit(target: Node, kind: String)
## Knil se met en boule sous son bouclier (vrai), ou en sort (faux).
signal player_guard_changed(guarding: bool)
## Knil est frappé : `amount` demi-cœurs perdus (0 si `blocked` : le bouclier a tout pris).
signal player_damaged(amount: int, blocked: bool)

# --- Temps -------------------------------------------------------------------------------------------------
signal hour_changed(day: int, hour: int)
signal day_changed(day: int)

# --- Partie ------------------------------------------------------------------------------------------------
signal game_started(seed: int)
signal game_loaded()
signal state_changed(path: String, value: Variant)
