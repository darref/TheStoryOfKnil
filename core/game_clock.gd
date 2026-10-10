extends Node
## L'HORLOGE DU MONDE — une seule source du temps : `minutes` depuis le début de la partie.
##
## En jeu, une minute réelle vaut `minutes_per_second` × 60 minutes du monde. Pendant le sommeil, l'horloge
## passe en accéléré (`fast_forward`) : le cycle jour / nuit défile à l'écran, rien d'autre ne change de règle.

const MINUTES_PER_DAY := 24 * 60
const DAYS_PER_WEEK := 7
const DAYS_PER_SEASON := 28
const SEASONS := ["printemps", "ete", "automne", "hiver"]
const START_HOUR := 8

## Minutes du monde par seconde réelle, en jeu normal (1.0 : une journée = 24 minutes réelles).
@export var minutes_per_second := 1.0

var minutes := float(START_HOUR * 60)
var paused := false

var _ff_target := -1.0
var _ff_rate := 0.0
var _ff_done: Callable
var _last_hour := -1
var _last_day := -1


func _process(delta: float) -> void:
	if paused:
		return
	if _ff_target >= 0.0:
		advance(minf(_ff_rate * delta, _ff_target - minutes))
		if minutes >= _ff_target:
			_ff_target = -1.0
			var done := _ff_done
			_ff_done = Callable()
			if done.is_valid():
				done.call()
		return
	advance(minutes_per_second * delta)


## Fait avancer le temps, et dit les heures et les jours franchis. C'est le SEUL endroit qui bouge `minutes`.
func advance(amount: float) -> void:
	if amount <= 0.0:
		return
	minutes += amount
	var h := hour()
	var d := day()
	if d != _last_day:
		_last_day = d
		EventBus.day_changed.emit(d)
	if h != _last_hour:
		_last_hour = h
		EventBus.hour_changed.emit(d, h)


## Avance en accéléré jusqu'à `target_minutes`, en `real_seconds` secondes réelles, puis appelle `done`.
func fast_forward(target_minutes: float, real_seconds: float, done: Callable) -> void:
	_ff_target = maxf(target_minutes, minutes)
	_ff_rate = (_ff_target - minutes) / maxf(real_seconds, 0.01)
	_ff_done = done


func is_fast_forwarding() -> bool:
	return _ff_target >= 0.0


func day() -> int:
	return int(minutes / MINUTES_PER_DAY)


func hour() -> int:
	return int(fmod(minutes, MINUTES_PER_DAY) / 60.0)


func minute() -> int:
	return int(fmod(minutes, 60.0))


## L'heure en fraction de journée, 0..1 (0 = minuit) — ce que lit le cycle jour / nuit.
func day_fraction() -> float:
	return fmod(minutes, MINUTES_PER_DAY) / MINUTES_PER_DAY


func phase() -> String:
	var h := hour()
	if h < 5:
		return "nuit"
	if h < 8:
		return "aube"
	if h < 18:
		return "jour"
	if h < 21:
		return "crepuscule"
	return "nuit"


func weekday() -> int:
	return day() % DAYS_PER_WEEK


func season() -> String:
	return SEASONS[(day() / DAYS_PER_SEASON) % SEASONS.size()]


## Les minutes du prochain `target_hour` (strictement après maintenant).
func next_time_at(target_hour: int) -> float:
	var base := float(day() * MINUTES_PER_DAY + target_hour * 60)
	return base if base > minutes else base + MINUTES_PER_DAY


## Ce que le moteur de décision lit sous `time.*`.
func snapshot() -> Dictionary:
	return {"day": day(), "hour": hour(), "minute": minute(), "phase": phase(),
		"weekday": weekday(), "season": season(), "minutes": minutes}


func to_save() -> Dictionary:
	return {"minutes": minutes}


func from_save(d: Dictionary) -> void:
	minutes = float(d.get("minutes", START_HOUR * 60))
	_last_hour = hour()
	_last_day = day()
	_ff_target = -1.0
