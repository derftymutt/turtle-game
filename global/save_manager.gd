# save_manager.gd
extends Node

## Autoload: SaveManager
## One-slot save/load for continue support.
## Saves: current level, cumulative (total) score, and tech slot IDs.

const SAVE_PATH = "user://save_game.json"

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func get_save_level() -> int:
	return load_save().get("level_number", 1)

func save_game():
	var data = {
		"level_number": LevelManager.current_level_number,
		"total_score":  GameManager.total_score,
		"tech_slot_0":  AlienTechManager.slots[0].get("id", ""),
		"tech_slot_1":  AlienTechManager.slots[1].get("id", ""),
	}
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()
		print("💾 Saved: Level %d, Total Score %d" % [data.level_number, data.total_score])

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
	AlienTechManager.reset_run()
	var slot0: String = data.get("tech_slot_0", "")
	var slot1: String = data.get("tech_slot_1", "")
	if not slot0.is_empty():
		AlienTechManager.assign_tech(slot0, 0)
	if not slot1.is_empty():
		AlienTechManager.assign_tech(slot1, 1)
	LevelManager.current_level_number = data.get("level_number", 1)
	print("📂 Restored: Level %d, Total Score %d" % [LevelManager.current_level_number, GameManager.total_score])
