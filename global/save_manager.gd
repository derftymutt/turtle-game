# save_manager.gd
extends Node

## Autoload: SaveManager
## Two separate files:
##   save_game.json  — run-in-progress (level, score, techs, attempts). Deleted on new game.
##   best_scores.json — all-time bests (best victory score). Never deleted automatically.

const SAVE_PATH   = "user://save_game.json"
const SCORES_PATH = "user://best_scores.json"

# ─── Run save ────────────────────────────────────────────────────────────────

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func get_save_level() -> int:
	return load_save().get("level_number", 1)

func get_save_hard_mode() -> bool:
	return load_save().get("hard_mode", false)

func save_game():
	var data = {
		"level_number":        LevelManager.current_level_number,
		"total_score":         GameManager.total_score,
		"tech_slot_0":         AlienTechManager.slots[0].get("id", ""),
		"tech_slot_1":         AlienTechManager.slots[1].get("id", ""),
		"continue_count":      LevelManager.continue_count,
		"total_time_ms":       LevelManager.total_time_ms,
		"successful_time_ms":  LevelManager.successful_time_ms,
		"hard_mode":           GameSettings.hard_mode,
		"persisted_health":    GameManager.persisted_health,
	}
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()
		print("💾 Saved: Level %d, Total Score %d, Continues %d, Hard Mode %s" % [
			data.level_number, data.total_score, data.continue_count, data.hard_mode])

func load_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return {}
	var text = file.get_as_text()
	file.close()
	var result = JSON.parse_string(text)
	return result if result is Dictionary else {}

func delete_save():
	var dir = DirAccess.open("user://")
	if dir and dir.file_exists("save_game.json"):
		dir.remove("save_game.json")
		print("🗑️ Save deleted")

func apply_save():
	var data = load_save()
	if data.is_empty():
		return
	GameManager.total_score = data.get("total_score", 0)
	LevelManager.continue_count = data.get("continue_count", 1)
	AlienTechManager.reset_run()
	var slot0: String = data.get("tech_slot_0", "")
	var slot1: String = data.get("tech_slot_1", "")
	if not slot0.is_empty():
		AlienTechManager.assign_tech(slot0, 0)
	if not slot1.is_empty():
		AlienTechManager.assign_tech(slot1, 1)
	LevelManager.current_level_number = data.get("level_number", 1)
	LevelManager.total_time_ms = data.get("total_time_ms", 0)
	LevelManager.successful_time_ms = data.get("successful_time_ms", 0)
	GameSettings.hard_mode = data.get("hard_mode", false)
	GameManager.persisted_health = data.get("persisted_health", -1.0)
	print("📂 Restored: Level %d, Total Score %d, Continues %d, Hard Mode %s" % [
		LevelManager.current_level_number, GameManager.total_score,
		LevelManager.continue_count, GameSettings.hard_mode])

# ─── Best scores (permanent) ─────────────────────────────────────────────────

func _load_best_scores() -> Dictionary:
	if not FileAccess.file_exists(SCORES_PATH):
		return {}
	var file = FileAccess.open(SCORES_PATH, FileAccess.READ)
	if not file:
		return {}
	var result = JSON.parse_string(file.get_as_text())
	file.close()
	return result if result is Dictionary else {}

func _save_best_scores(data: Dictionary):
	var file = FileAccess.open(SCORES_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()

# Normal mode

func get_best_victory_score() -> int:
	return _load_best_scores().get("best_victory_score", 0)

func save_victory_score(score: int):
	var data = _load_best_scores()
	var current_best: int = data.get("best_victory_score", 0)
	if score > current_best:
		data["best_victory_score"] = score
		_save_best_scores(data)
		print("🏆 New best victory score: %d (was %d)" % [score, current_best])

func get_best_victory_time_ms() -> int:
	return _load_best_scores().get("best_victory_time_ms", 0)

func save_victory_time(ms: int):
	if ms <= 0:
		return
	var data = _load_best_scores()
	var current_best: int = data.get("best_victory_time_ms", 0)
	if current_best == 0 or ms < current_best:
		data["best_victory_time_ms"] = ms
		_save_best_scores(data)
		print("⏱️ New best victory time: %d ms (was %d ms)" % [ms, current_best])

# Hard mode

func get_best_victory_score_hard() -> int:
	return _load_best_scores().get("best_victory_score_hard", 0)

func save_victory_score_hard(score: int):
	var data = _load_best_scores()
	var current_best: int = data.get("best_victory_score_hard", 0)
	if score > current_best:
		data["best_victory_score_hard"] = score
		_save_best_scores(data)
		print("💀 New hard mode best score: %d (was %d)" % [score, current_best])

func get_best_victory_time_ms_hard() -> int:
	return _load_best_scores().get("best_victory_time_ms_hard", 0)

func save_victory_time_hard(ms: int):
	if ms <= 0:
		return
	var data = _load_best_scores()
	var current_best: int = data.get("best_victory_time_ms_hard", 0)
	if current_best == 0 or ms < current_best:
		data["best_victory_time_ms_hard"] = ms
		_save_best_scores(data)
		print("💀 New hard mode best time: %d ms (was %d ms)" % [ms, current_best])
