class_name HdArt

## High-res art experiment. The stretch mode is canvas_items, so 2D is drawn at
## window resolution: art drawn at SCALE x a sprite's pixel size and shown at
## 1/SCALE keeps its detail instead of being squashed into the 640x360 grid.
## Vector drawing (_draw()) gets the same benefit, which is how the dead walls and
## flippers do it. Godot's antialiased lines feather in canvas units (blurry at 3x+),
## so those draw hard-edged and 2D MSAA smooths them while the environment is HD.
##
## Two independent categories, toggled at runtime in debug builds:
##   F7 — environment (bumpers, dead walls, flippers, workshop, tiles, wave)
##   F8 — creatures (the turtle, and enemies with hd_sprite_frames set)
## The choice is saved to user://hd_art.cfg so it survives restarts. HD art is
## runtime-only: the editor always shows the pixel art, so scenes never get the
## HD frames saved into them.
##
## A node that has HD art joins GROUP_ENVIRONMENT or GROUP_CREATURES and defines
## refresh_hd_art(), which is called whenever its category is toggled.

const SCALE: float = 8.0
const GROUP_ENVIRONMENT := &"hd_environment"
const GROUP_CREATURES := &"hd_creatures"
const _CONFIG_PATH := "user://hd_art.cfg"

static var _loaded: bool = false
static var _environment: bool = true
static var _creatures: bool = true

static func environment_on() -> bool:
	_ensure_loaded()
	return _environment and not Engine.is_editor_hint()

static func creatures_on() -> bool:
	_ensure_loaded()
	return _creatures and not Engine.is_editor_hint()

static func toggle_environment(tree: SceneTree) -> void:
	_ensure_loaded()
	_environment = not _environment
	_save()
	sync_viewport(tree)
	tree.call_group(GROUP_ENVIRONMENT, "refresh_hd_art")
	print("🎨 HD environment art: %s" % ("on" if _environment else "off"))

static func toggle_creatures(tree: SceneTree) -> void:
	_ensure_loaded()
	_creatures = not _creatures
	_save()
	tree.call_group(GROUP_CREATURES, "refresh_hd_art")
	print("🎨 HD creature art: %s" % ("on" if _creatures else "off"))

## 2D MSAA on the root viewport while the vector-drawn environment art is showing.
static func sync_viewport(tree: SceneTree) -> void:
	tree.root.msaa_2d = Viewport.MSAA_4X if environment_on() else Viewport.MSAA_DISABLED

## Debug-build hotkeys, fed from GameSettings._input().
static func handle_debug_input(event: InputEvent, tree: SceneTree) -> void:
	if not OS.is_debug_build() or not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_F7:
			toggle_environment(tree)
		KEY_F8:
			toggle_creatures(tree)

## Swaps an AnimatedSprite2D between its pixel frames and an HD set with the same
## animation names, keeping the current animation playing.
static func apply(sprite: AnimatedSprite2D, frames: SpriteFrames, hd: bool) -> void:
	if sprite == null or frames == null or sprite.sprite_frames == frames:
		return
	var anim: StringName = sprite.animation
	var was_playing: bool = sprite.is_playing()
	sprite.sprite_frames = frames
	sprite.scale = Vector2.ONE / SCALE if hd else Vector2.ONE
	sprite.texture_filter = (CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if hd
			else CanvasItem.TEXTURE_FILTER_PARENT_NODE)
	if frames.has_animation(anim):
		sprite.animation = anim
		if was_playing:
			sprite.play(anim)

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(_CONFIG_PATH) == OK:
		_environment = cfg.get_value("hd_art", "environment", _environment)
		_creatures = cfg.get_value("hd_art", "creatures", _creatures)

static func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("hd_art", "environment", _environment)
	cfg.set_value("hd_art", "creatures", _creatures)
	cfg.save(_CONFIG_PATH)
