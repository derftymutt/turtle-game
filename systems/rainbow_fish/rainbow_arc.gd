extends Node2D
class_name RainbowArc

## The rainbow the freed rainbow fish paint across the sky: seven stacked
## half-ellipse stripes (red outermost) whose ends all rest on the ocean
## surface. Each stripe is painted progressively from whichever end its fish
## leapt out of. dissolve() shatters it: chunks crash down into the ocean,
## splash, sink and fade, then it frees itself.
##
## Lives in level space with its origin at the level origin — `center` and
## stripe_point() are global positions.

const STRIPE_COUNT := 7
const STRIPE_WIDTH := 6.0
## Quads per stripe along the full arc
const SEGMENTS := 72

const _GRAVITY := 520.0
## Underwater: chunks sink slowly and fade over this long
const _SINK_GRAVITY := 40.0
const _SINK_FADE_TIME := 1.1
const _WATER_DRAG := 3.0
## Pieces crack loose over this window, so it crumbles rather than drops
const _CRACK_SPREAD := 0.35
const _DROPLET_LIFE := 0.55

## Middle of the arc's base, on the ocean surface (global)
var center: Vector2 = Vector2.ZERO
## Outer edge half-width / height of the red stripe
var radius: Vector2 = Vector2(300.0, 150.0)
var colors: Array[Color] = []

var _progress: Array[float] = []
var _from_left: Array[bool] = []
## The secret-level entrance glowing at the apex (open_portal())
var _portal_open: bool = false
var _shattered: bool = false
## Falling chunks once shattered: {pos, vel, rot, spin, delay, wet, alpha,
## polys: Array[PackedVector2Array] (local to pos), colors: Array[Color]}
var _pieces: Array[Dictionary] = []
## Splash droplets: {pos, vel, life, color}
var _droplets: Array[Dictionary] = []

func _init() -> void:
	for i in STRIPE_COUNT:
		_progress.append(0.0)
		_from_left.append(true)

func _ready() -> void:
	z_index = -1  # behind sky stars, debris and the airborne turtle
	top_level = true  # coordinates are global whatever the parent's transform
	global_position = Vector2.ZERO

## Global point on the centre line of `stripe`, `t` = 0 at the left end on
## the surface, 1 at the right end.
func stripe_point(stripe: int, t: float) -> Vector2:
	return _ellipse_point(_stripe_radius(stripe, 0.5), t)

## Global point on the centre line of the whole seven-stripe band — the line
## the secret-entrance currents ride. `t` as in stripe_point().
func band_point(t: float) -> Vector2:
	return _ellipse_point(radius - Vector2.ONE * STRIPE_WIDTH * STRIPE_COUNT * 0.5, t)

## Top of the band — where the secret entrance opens.
func apex() -> Vector2:
	return band_point(0.5)

## Full width of the painted band.
func band_width() -> float:
	return STRIPE_WIDTH * STRIPE_COUNT

## Lights the pulsing secret-level entrance at the apex.
func open_portal() -> void:
	_portal_open = true

## Stripe `stripe` painted up to `progress` (0–1) from its left or right end.
func paint(stripe: int, progress: float, from_left: bool) -> void:
	_progress[stripe] = clampf(progress, 0.0, 1.0)
	_from_left[stripe] = from_left
	queue_redraw()

## Shatters the rainbow: the painted band breaks into chunks that crash into
## the ocean, splash, sink and fade. Frees itself when they're all gone.
func dissolve() -> void:
	if _shattered:
		return
	_shattered = true
	_portal_open = false
	z_index = 3  # in front of the water, so the chunks can be seen sinking
	_build_pieces()
	if _pieces.is_empty():
		queue_free()

## Chops the painted band into chunks a few segments long and a few stripes
## deep — each chunk keeps its stripes' colours.
func _build_pieces() -> void:
	var seg := 0
	while seg < SEGMENTS:
		var seg_end := mini(SEGMENTS, seg + randi_range(3, 6))
		var stripe := 0
		while stripe < STRIPE_COUNT:
			var stripe_end := mini(STRIPE_COUNT, stripe + randi_range(2, 4))
			_add_piece(seg, seg_end, stripe, stripe_end)
			stripe = stripe_end
		seg = seg_end

func _add_piece(seg0: int, seg1: int, stripe0: int, stripe1: int) -> void:
	var polys: Array[PackedVector2Array] = []
	var piece_colors: Array[Color] = []
	var sum := Vector2.ZERO
	var count := 0
	for stripe in range(stripe0, stripe1):
		var range_t := _painted_range(stripe)
		var a := maxf(float(seg0) / SEGMENTS, range_t.x)
		var b := minf(float(seg1) / SEGMENTS, range_t.y)
		if b - a < 0.002:
			continue
		var outer := _stripe_radius(stripe, 0.0) + Vector2.ONE * 0.5
		var inner := _stripe_radius(stripe, 1.0)
		var steps := maxi(1, int(ceil((b - a) * SEGMENTS)))
		var poly := PackedVector2Array()
		for i in steps + 1:
			poly.append(_ellipse_point(outer, lerpf(a, b, float(i) / steps)))
		for i in range(steps, -1, -1):
			poly.append(_ellipse_point(inner, lerpf(a, b, float(i) / steps)))
		for p in poly:
			sum += p
		count += poly.size()
		polys.append(poly)
		piece_colors.append(colors[stripe] if stripe < colors.size() else Color.WHITE)
	if polys.is_empty():
		return
	var origin := sum / count
	for i in polys.size():
		var local := PackedVector2Array()
		for p in polys[i]:
			local.append(p - origin)
		polys[i] = local
	# A little pop outward from the arc's centre as it cracks free
	var out := (origin - center).normalized()
	_pieces.append({
		"pos": origin,
		"vel": out * randf_range(20.0, 60.0) + Vector2(randf_range(-25.0, 25.0), randf_range(-40.0, 0.0)),
		"rot": 0.0,
		"spin": randf_range(-4.0, 4.0),
		"delay": randf() * _CRACK_SPREAD,
		"wet": false,
		"alpha": 1.0,
		"polys": polys,
		"colors": piece_colors,
	})

## (t0, t1) of the painted part of `stripe`, or an empty range.
func _painted_range(stripe: int) -> Vector2:
	var progress := _progress[stripe]
	if progress <= 0.0:
		return Vector2(1.0, 0.0)
	if _from_left[stripe]:
		return Vector2(0.0, progress)
	return Vector2(1.0 - progress, 1.0)

func _process(delta: float) -> void:
	if _portal_open:
		queue_redraw()  # portal pulse
	if not _shattered:
		return
	_update_pieces(delta)
	_update_droplets(delta)
	queue_redraw()
	if _pieces.is_empty() and _droplets.is_empty():
		queue_free()

func _update_pieces(delta: float) -> void:
	var surface := center.y
	for i in range(_pieces.size() - 1, -1, -1):
		var piece := _pieces[i]
		if piece.delay > 0.0:
			piece.delay -= delta
			continue
		var vel: Vector2 = piece.vel
		if piece.wet:
			vel.y += _SINK_GRAVITY * delta
			vel *= exp(-_WATER_DRAG * delta)
			piece.spin *= exp(-_WATER_DRAG * delta)
			piece.alpha -= delta / _SINK_FADE_TIME
		else:
			vel.y += _GRAVITY * delta
		piece.vel = vel
		piece.pos += vel * delta
		piece.rot += piece.spin * delta
		if not piece.wet and piece.pos.y > surface:
			piece.wet = true
			_splash(piece)
			# Hits the water hard and loses most of its speed
			piece.vel = Vector2(vel.x * 0.4, vel.y * 0.2)
		if piece.alpha <= 0.0:
			_pieces.remove_at(i)

func _splash(piece: Dictionary) -> void:
	var piece_colors: Array[Color] = piece.colors
	for i in randi_range(4, 7):
		var tint: Color = piece_colors[randi() % piece_colors.size()]
		_droplets.append({
			"pos": Vector2(piece.pos.x + randf_range(-10.0, 10.0), center.y),
			"vel": Vector2(randf_range(-70.0, 70.0), randf_range(-190.0, -90.0)),
			"life": _DROPLET_LIFE * randf_range(0.7, 1.0),
			"color": Color.WHITE.lerp(tint, 0.5) if i % 2 == 0 else Color.WHITE,
		})

func _update_droplets(delta: float) -> void:
	for i in range(_droplets.size() - 1, -1, -1):
		var drop := _droplets[i]
		var vel: Vector2 = drop.vel
		vel.y += _GRAVITY * delta
		drop.vel = vel
		drop.pos += vel * delta
		drop.life -= delta
		if drop.life <= 0.0:
			_droplets.remove_at(i)

## `edge` 0 = outer edge of the stripe, 1 = inner edge.
func _stripe_radius(stripe: int, edge: float) -> Vector2:
	return radius - Vector2.ONE * STRIPE_WIDTH * (stripe + edge)

func _ellipse_point(r: Vector2, t: float) -> Vector2:
	var ang := PI * (1.0 - t)
	return center + Vector2(cos(ang) * r.x, -sin(ang) * r.y)

func _draw() -> void:
	if _shattered:
		_draw_shattered()
		return
	for stripe in STRIPE_COUNT:
		var progress := _progress[stripe]
		if progress <= 0.0:
			continue
		var t0 := 0.0 if _from_left[stripe] else 1.0 - progress
		var t1 := progress if _from_left[stripe] else 1.0
		var outer := _stripe_radius(stripe, 0.0)
		var inner := _stripe_radius(stripe, 1.0)
		var color := colors[stripe] if stripe < colors.size() else Color.WHITE
		for seg in SEGMENTS:
			var a := float(seg) / SEGMENTS
			var b := float(seg + 1) / SEGMENTS
			a = maxf(a, t0)
			b = minf(b, t1)
			if b - a < 0.0005:
				continue
			# Slight overlap with the next stripe so no gap shows between them
			var quad := PackedVector2Array([
				_ellipse_point(outer + Vector2.ONE * 0.5, a),
				_ellipse_point(outer + Vector2.ONE * 0.5, b),
				_ellipse_point(inner, b),
				_ellipse_point(inner, a),
			])
			draw_colored_polygon(quad, color)
	if _portal_open:
		_draw_portal()

func _draw_shattered() -> void:
	for piece in _pieces:
		# Underwater chunks shrink as they fade — dissolving away
		var shrink: float = 1.0 if not piece.wet else lerpf(0.4, 1.0, piece.alpha)
		draw_set_transform(piece.pos, piece.rot, Vector2.ONE * shrink)
		var piece_colors: Array[Color] = piece.colors
		for i in piece.polys.size():
			var c: Color = piece_colors[i]
			c.a = piece.alpha
			draw_colored_polygon(piece.polys[i], c)
	draw_set_transform(Vector2.ZERO)
	for drop in _droplets:
		var c: Color = drop.color
		c.a = clampf(drop.life / _DROPLET_LIFE, 0.0, 1.0)
		draw_rect(Rect2(drop.pos - Vector2.ONE, Vector2(2.0, 2.0)), c)

## Pulsing white glow at the apex: rings breathing out over a solid core, no
## rest beat, so it reads at any instant.
func _draw_portal() -> void:
	var p := apex()
	var wave := (sin(Time.get_ticks_msec() * 0.001 * TAU * 1.5) + 1.0) * 0.5
	var r := band_width() * 0.5
	draw_circle(p, r * (0.9 + 0.3 * wave), Color(1.0, 1.0, 1.0, 0.25 + 0.2 * wave))
	draw_circle(p, r * 0.6, Color(1.0, 1.0, 1.0, 0.6))
	draw_circle(p, r * (0.25 + 0.1 * wave), Color.WHITE)
