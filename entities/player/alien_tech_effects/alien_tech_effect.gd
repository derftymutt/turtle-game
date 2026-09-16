extends RefCounted
class_name AlienTechEffect

## Base class for one alien tech's runtime effect. TurtlePlayer creates one
## instance per dispatch-table tech in _ready() and keeps it for the node's
## lifetime — activate() turns the effect on, physics_process() drives its
## per-frame behavior. Override only the hooks your tech actually needs;
## every hook below defaults to a no-op.

## Called once from TurtlePlayer._ready(), for effects that need to create
## runtime child nodes (areas, visuals) that live for the whole node's
## lifetime rather than being created/destroyed per activation.
func setup(_player) -> void:
	pass

## Fired from TurtlePlayer._on_alien_tech_activated() when the player presses
## this tech's slot button.
func activate(_player, _slot_index: int) -> void:
	pass

## Called every physics frame from TurtlePlayer._physics_process(), whether
## or not the effect is currently active — mirrors the timer-countdown blocks
## it replaces, which always ran and checked their own flag internally.
func physics_process(_player, _delta: float) -> void:
	pass

## Called from TurtlePlayer._on_alien_tech_slots_changed_player() whenever
## either slot's contents change, for effects that need to reset if their
## tech was swapped out mid-effect (AlienTechManager.has_tech() is what
## distinguishes "swapped out" from "still equipped").
func on_slots_changed(_player) -> void:
	pass

## Called from TurtlePlayer.take_damage() right before a real hit lands, so
## an in-progress windup/channel/attachment can be aborted. Not called when
## the hit was absorbed by something else (e.g. Bubble Shield) instead of
## actually landing.
func cancel_on_damage(_player) -> void:
	pass
