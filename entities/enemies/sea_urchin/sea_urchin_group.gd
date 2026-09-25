# sea_urchin_group.gd
extends Node2D
class_name SeaUrchinGroup

## Container for a level's seeded sea urchins.
## Place every candidate urchin as a child of this node. On load, `active_count`
## of them are kept (chosen at random) and the rest remove themselves, so each
## run of the level gets a different urchin layout. Works like the UFO Workshop
## election, but keeps a subset instead of exactly one.

## How many urchins stay active this load. -1 (or any value >= the number of
## children) keeps them all.
@export var active_count: int = -1

func _ready() -> void:
	# Children are already ready by the time the parent's _ready() runs.
	var urchins: Array[Node] = get_children().filter(func(c: Node) -> bool:
		return c is SeaUrchin)
	if active_count < 0 or active_count >= urchins.size():
		return

	urchins.shuffle()
	var kept: PackedStringArray = []
	for i in urchins.size():
		var urchin := urchins[i] as SeaUrchin
		if i < active_count:
			kept.append(urchin.name)
			continue
		# Stand it down immediately so it can't be seen, collide, or show up in
		# group lookups ("enemies", "sea_urchins") before the free lands.
		urchin.visible = false
		urchin.process_mode = Node.PROCESS_MODE_DISABLED
		for group in urchin.get_groups():
			if not String(group).begins_with("_"):
				urchin.remove_from_group(group)
		urchin.queue_free()

	print("🦔 Sea Urchins: %d candidates, kept %s" % [urchins.size(), ", ".join(kept)])
