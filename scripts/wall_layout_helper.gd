@tool
extends Node2D
class_name WallLayoutHelper

## Helper tool for quickly prototyping wall layouts
## Add this to your scene, assign wall scenes, and click buttons to spawn layouts!

@export var dead_wall_scene: PackedScene
@export var bumper_wall_scene: PackedScene

@export_group("Quick Spawn Controls")
@export var spawn_dead_wall: bool = false:
	set(value):
		if value and Engine.is_editor_hint():
			_spawn_wall(dead_wall_scene, "DeadWall")
		spawn_dead_wall = false

@export var spawn_bumper_wall: bool = false:
	set(value):
		if value and Engine.is_editor_hint():
			_spawn_wall(bumper_wall_scene, "BumperWall")
		spawn_bumper_wall = false

@export var clear_all_walls: bool = false:
	set(value):
		if value and Engine.is_editor_hint():
			_clear_walls()
		clear_all_walls = false

@export_group("Preset Layouts")
@export var create_corridor: bool = false:
	set(value):
		if value and Engine.is_editor_hint():
			_create_corridor_layout()
		create_corridor = false

@export var create_pinball_chamber: bool = false:
	set(value):
		if value and Engine.is_editor_hint():
			_create_pinball_chamber()
		create_pinball_chamber = false

@export var create_staggered_descent: bool = false:
	set(value):
		if value and Engine.is_editor_hint():
			_create_staggered_descent()
		create_staggered_descent = false

func _spawn_wall(scene: PackedScene, type_name: String):
	if not scene:
		push_error("No %s scene assigned! Assign it in the Inspector." % type_name)
		return
	
	if not get_tree() or not get_tree().edited_scene_root:
		push_error("No edited scene root found!")
		return
	
	var wall = scene.instantiate()
	add_child(wall)
	wall.owner = get_tree().edited_scene_root
	wall.position = Vector2.ZERO
	
	print("✓ Spawned %s at origin - select and move it where you want!" % type_name)

func _clear_walls():
	var count = 0
	var children_to_remove = []
	
	for child in get_children():
		if child.has_method("get_class"):
			var script = child.get_script()
			if script and (script.resource_path.contains("dead_wall") or script.resource_path.contains("bumper_wall")):
				children_to_remove.append(child)
				count += 1
	
	for child in children_to_remove:
		child.queue_free()
	
	print("✓ Cleared %d walls" % count)

func _create_corridor_layout():
	if not dead_wall_scene:
		push_error("No DeadWall scene assigned!")
		return
	
	# Top wall
	var top = dead_wall_scene.instantiate()
	add_child(top)
	top.owner = get_tree().edited_scene_root
	top.position = Vector2(0, -100)
	top.wall_length = 400
	top.name = "CorridorTop"
	
	# Bottom wall
	var bottom = dead_wall_scene.instantiate()
	add_child(bottom)
	bottom.owner = get_tree().edited_scene_root
	bottom.position = Vector2(0, 100)
	bottom.wall_length = 400
	bottom.name = "CorridorBottom"
	
	print("✓ Created corridor layout (400px wide, 200px tall)")

func _create_pinball_chamber():
	if not bumper_wall_scene:
		push_error("No BumperWall scene assigned!")
		return
	
	# Create angled bumpers in a diamond pattern
	var angles = [45, 135, 225, 315]
	var distance = 80
	
	for i in range(4):
		var bumper = bumper_wall_scene.instantiate()
		add_child(bumper)
		bumper.owner = get_tree().edited_scene_root
		
		var angle_rad = deg_to_rad(angles[i])
		bumper.position = Vector2(cos(angle_rad), sin(angle_rad)) * distance
		bumper.rotation = angle_rad + deg_to_rad(90)
		bumper.wall_length = 60
		bumper.name = "PinballBumper%d" % (i + 1)
	
	print("✓ Created pinball chamber (4 bumpers in diamond)")

func _create_staggered_descent():
	if not dead_wall_scene or not bumper_wall_scene:
		push_error("Need both DeadWall and BumperWall scenes assigned!")
		return
	
	# Create alternating walls going down
	var y_start = -150
	var y_spacing = 75
	var x_offset = 100
	
	for i in range(5):
		var use_bumper = (i % 2 == 1)  # Alternate
		var scene = bumper_wall_scene if use_bumper else dead_wall_scene
		
		var wall = scene.instantiate()
		add_child(wall)
		wall.owner = get_tree().edited_scene_root
		
		# Stagger left/right
		var x_pos = x_offset if (i % 2 == 0) else -x_offset
		wall.position = Vector2(x_pos, y_start + (i * y_spacing))
		wall.wall_length = 150
		wall.rotation = deg_to_rad(15) if (i % 2 == 0) else deg_to_rad(-15)
		wall.name = ("Bumper%d" if use_bumper else "Wall%d") % (i + 1)
	
	print("✓ Created staggered descent (5 alternating walls)")
