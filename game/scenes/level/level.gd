# SPDX-FileCopyrightText: 2026 Siegefall contributors
# SPDX-License-Identifier: MIT
class_name Level
extends Node2D
## Builds a level from LevelData and runs the shot loop:
## READY -tap-> SWINGING -tap-> FLYING -> SETTLING -> READY ... -> WON.
##
## Dev/test options (after `--` on the command line):
##   --level=<id>            start in this level (handled by boot)
##   --autoplay=p1,p2,...    release at these swing phases, one per shot
## (--screenshots and --quit-after are handled by the Game autoload.)

signal won(shots: int)
## Bot mode only: emitted once with {won, shots, score, state, eliminated}.
signal bot_done(result: Dictionary)

enum State { INTRO, READY, SWINGING, FLYING, SETTLING, WON }

const SETTLE_HOLD: float = 1.1
const HOLD_STEP: float = 0.6
const WIN_SETTLE_MAX: float = 2.5

var data: LevelData
var state: State = State.INTRO
var shots: int = 0
var points: int = 0
var targets_left: int = 0
var ammo_index: int = 0
var ammo_list: Array[Dictionary] = []

var world: Node2D
var camera: CameraRig
var trebuchet: Trebuchet
var hud: Hud
var projectile: Projectile = null
var castle_rect: Rect2 = Rect2()

var debris: DebrisManager
## Validator bot: set both before adding the level to the tree.
var bot_mode: bool = false
var bot_shots: Array[Dictionary] = []
var _enemies: Array[Enemy] = []
var _settle_t: float = 0.0
var _win_t: float = 0.0
var _won_pending: bool = false
var _time: float = 0.0
## Scripted shots: {"ammo": String, "phase": float, "tap": float (s, <0 = none)}
var _autoplay: Array[Dictionary] = []
var _pending_tap_tick: int = -1
## Every projectile of the current shot still in play (splits add more).
var _live: Array[Projectile] = []
var _ghost: Line2D
var _ghost_points: PackedVector2Array = PackedVector2Array()
var _frame_tick: int = 0
var _bot_reported: bool = false
var _broken_blocks: int = 0
var _hostages_hit: int = 0
var _targets_total: int = 0
var _hold_t: float = -1.0
var _hold_cycled: bool = false


func _ready() -> void:
	Block.clear_shared()
	if not Game.custom_level.is_empty():
		data = Data.parse_level(Game.custom_level)
	else:
		data = Data.load_level(Game.current_level_id)
	if not data.is_valid():
		push_error("level failed to load: %s" % "; ".join(data.errors))
		Game.goto_menu()
		return
	_parse_dev_options()
	_build()
	if Game.cli.has("debug-damage"):
		var frac: float = str(Game.cli["debug-damage"]).to_float()
		for n: Node in get_tree().get_nodes_in_group("blocks"):
			var b := n as Block
			b.apply_damage(b.max_hp * frac, 0.0, b.global_position + Vector2(10, -10))
	if Game.cli.has("debug-ignite"):
		for n: Node in get_tree().get_nodes_in_group("blocks"):
			(n as Block).ignite()
	if Game.cli.has("debug-freeze"):
		for n: Node in get_tree().get_nodes_in_group("blocks"):
			(n as Block).freeze_solid()
	if Game.cli.get("camera", "") == "castle":
		camera.frame(castle_rect.grow(200.0))
		camera.smoothing = 50.0
		state = State.READY
	elif _autoplay.is_empty() and not Game.cli.has("no-intro"):
		camera.start_intro()
	else:
		camera.go_aim(true)
		state = State.READY


## "[ammo:]phase[@tap_seconds]", e.g. "0.62", "keg:0.6@0.9".
static func parse_shot(s: String) -> Dictionary:
	var shot: Dictionary = {"ammo": "", "phase": 0.0, "tap": -1.0}
	var rest: String = s
	if rest.contains(":"):
		shot["ammo"] = rest.get_slice(":", 0)
		rest = rest.get_slice(":", 1)
	if rest.contains("@"):
		shot["tap"] = rest.get_slice("@", 1).to_float()
		rest = rest.get_slice("@", 0)
	shot["phase"] = rest.to_float()
	return shot


func _parse_dev_options() -> void:
	if bot_mode:
		_autoplay = bot_shots.duplicate()
		return
	if Game.cli.has("autoplay"):
		for s: String in str(Game.cli["autoplay"]).split(",", false):
			_autoplay.append(parse_shot(s))


# ----------------------------------------------------------------- build ---
func _build() -> void:
	var realm: Dictionary = Data.realm(data.realm)
	var palette: Dictionary = realm.get("palette", {})
	var grade: Dictionary = Data.grade(data.time_of_day)

	if not bot_mode:
		var backdrop := Backdrop.new()
		backdrop.name = "Backdrop"
		add_child(backdrop)
		backdrop.build(palette, grade, realm.get("backdrop", {}), data.world_right, data.id.hash())

	var ambient := CanvasModulate.new()
	ambient.color = Units.color(grade.get("ambient"), Color(0.85, 0.85, 0.85))
	add_child(ambient)
	var sun := DirectionalLight2D.new()
	sun.color = Units.color(grade.get("sun_color"), Color.WHITE)
	sun.energy = float(grade.get("sun_energy", 0.8))
	sun.rotation_degrees = float(grade.get("sun_angle_deg", 30.0)) - 90.0
	sun.height = 0.45
	sun.max_distance = 2600.0
	sun.shadow_enabled = _shadows_enabled()
	sun.shadow_filter = Light2D.SHADOW_FILTER_PCF13
	sun.shadow_filter_smooth = 6.0
	sun.shadow_color = Color(0.1, 0.07, 0.12, 0.45)
	add_child(sun)

	world = Node2D.new()
	world.name = "World"
	add_child(world)
	var terrain := Terrain.new()
	terrain.name = "Terrain"
	world.add_child(terrain)
	terrain.build(data.terrain, data.kill_y, palette)

	debris = DebrisManager.new()
	debris.name = "Debris"
	debris.world = world
	add_child(debris)
	debris.piece_spawned.connect(_hook_block)

	var rect_init: bool = false
	for i: int in data.blocks.size():
		var spec: Dictionary = data.blocks[i]
		var b := Block.new()
		b.setup(spec, Data.material(str(spec["material"])), i)
		world.add_child(b)
		debris.register(b)
		_hook_block(b)
		castle_rect = (
			Rect2(b.position, Vector2.ZERO) if not rect_init else castle_rect.expand(b.position)
		)
		rect_init = true
	for e: Dictionary in data.enemies:
		var en := Enemy.new()
		en.setup(str(e["type"]), Data.enemy(str(e["type"])), e["pos"], bool(e.get("flip", false)))
		en.kill_y_px = Units.to_px(Vector2(0, data.kill_y)).y
		world.add_child(en)
		en.eliminated.connect(_on_enemy_eliminated)
		en.hurt.connect(
			func(x: Enemy, a: float) -> void: _log("%s hurt %.1f (hp %.1f)" % [x.type_id, a, x.hp])
		)
		_enemies.append(en)
		if en.is_target:
			targets_left += 1
		castle_rect = (
			Rect2(en.position, Vector2.ZERO) if not rect_init else castle_rect.expand(en.position)
		)
		rect_init = true
	castle_rect = castle_rect.grow(150.0)
	_targets_total = targets_left

	_ghost = Line2D.new()
	_ghost.width = 10.0
	_ghost.default_color = Color(1.0, 0.98, 0.9, 0.7)
	_ghost.texture = _dot_texture()
	_ghost.texture_mode = Line2D.LINE_TEXTURE_TILE
	_ghost.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_ghost.z_index = -1
	world.add_child(_ghost)

	trebuchet = Trebuchet.new()
	trebuchet.name = "Trebuchet"
	trebuchet.position = Units.to_px(data.trebuchet_pos)
	world.add_child(trebuchet)
	trebuchet.setup(TrebuchetModel.from_dict(Data.trebuchet))
	trebuchet.released.connect(_on_released)
	trebuchet.ready_to_fire.connect(_on_trebuchet_ready)

	ammo_list = Game.unlocked_ammo_list()
	ammo_index = maxi(0, ammo_list.find(Data.ammo_def(Game.selected_ammo)))
	trebuchet.set_ammo(ammo_list[ammo_index] if not ammo_list.is_empty() else {})

	camera = CameraRig.new()
	camera.name = "Camera"
	add_child(camera)
	camera.make_current()
	camera.setup(trebuchet.position, castle_rect)

	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.setup(tr(data.name), data.par)
	hud.set_ammo(trebuchet.ammo, ammo_list.size())
	hud.set_hint(tr("Tap to swing, tap again to let go"))
	if not bot_mode and not Game.cli.has("autoplay"):
		hud.show_intro(tr(data.name), tr(data.grievance))
	hud.restart_pressed.connect(Game.restart_level)
	hud.pause_pressed.connect(toggle_pause)
	hud.resume_pressed.connect(toggle_pause)
	hud.menu_pressed.connect(Game.goto_levels)
	hud.next_pressed.connect(_go_next)
	hud.ammo_cycle.connect(cycle_ammo)


## One dot per tile: a dotted line for the last shot's ghost trail.
static func _dot_texture() -> Texture2D:
	var img := Image.create(32, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y: int in 16:
		for x: int in 16:
			var d: float = Vector2(x - 7.5, y - 7.5).length()
			img.set_pixel(x, y, Color(1, 1, 1, clampf(7.0 - d, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


func _shadows_enabled() -> bool:
	if Settings.quality == "low":
		return false
	return (
		Settings.quality == "high"
		or RenderingServer.get_current_rendering_method() != "gl_compatibility"
	)


# ----------------------------------------------------------------- input ---
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		toggle_pause()
	elif get_tree().paused:
		return
	elif event.is_action_pressed("restart"):
		Game.restart_level()
	elif event.is_action_pressed("ammo_next"):
		cycle_ammo(1)
	elif event.is_action_pressed("ammo_prev"):
		cycle_ammo(-1)
	elif event.is_action_pressed("next_level") and state == State.WON:
		_go_next()
	elif Settings.one_button and state == State.READY and _one_button(event):
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("fire") or _is_touch_tap(event):
		get_viewport().set_input_as_handled()
		on_fire()


## One-button mode while aiming: a short press swings; holding cycles the
## ammo every HOLD_STEP seconds and releasing keeps the shown ammo.


func _one_button(event: InputEvent) -> bool:
	if event.is_action_pressed("fire"):
		_hold_t = 0.0
		_hold_cycled = false
		return true
	if event.is_action_released("fire") and _hold_t >= 0.0:
		var was_hold: bool = _hold_cycled
		_hold_t = -1.0
		if not was_hold:
			on_fire()
		return true
	return false


func _tick_hold(delta: float) -> void:
	if _hold_t < 0.0:
		return
	if not Input.is_action_pressed("fire") or state != State.READY:
		_hold_t = -1.0
		return
	_hold_t += delta
	if _hold_t >= HOLD_STEP:
		_hold_t -= HOLD_STEP
		_hold_cycled = true
		cycle_ammo(1)


static func _is_touch_tap(event: InputEvent) -> bool:
	# Real touch events only arrive when mouse emulation is off (it is on by
	# default, in which case the emulated click maps to "fire").
	return event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed


func on_fire() -> void:
	match state:
		State.INTRO:
			camera.go_aim()
			state = State.READY
		State.READY:
			if trebuchet.can_fire():
				trebuchet.start_swing()
				state = State.SWINGING
				hud.fade_hint()
				hud.hide_intro()
		State.SWINGING:
			trebuchet.release()
		State.FLYING, State.SETTLING:
			tap_projectile()
		_:
			pass


## Mid-air action: the first projectile in play that still has one uses it.
func tap_projectile() -> bool:
	for p: Projectile in _live:
		if is_instance_valid(p) and p.can_tap():
			_log("tap after %d ticks" % p.ticks)
			return p.tap()
	return false


func toggle_pause() -> void:
	if state == State.WON:
		return
	var p: bool = not get_tree().paused
	get_tree().paused = p
	if p:
		hud.show_pause()
	else:
		hud.hide_pause()


func cycle_ammo(direction: int) -> void:
	if ammo_list.size() <= 1 or state != State.READY:
		return
	ammo_index = posmod(ammo_index + direction, ammo_list.size())
	Game.selected_ammo = str(ammo_list[ammo_index].get("id", "boulder"))
	trebuchet.set_ammo(ammo_list[ammo_index])
	hud.set_ammo(trebuchet.ammo, ammo_list.size())


# ------------------------------------------------------------- shot loop ---
func _on_released(phase: float, pos: Vector2, vel: Vector2) -> void:
	shots += 1
	_log(
		(
			"shot %d: phase %.3f, v=%s m/s"
			% [shots, phase, (Units.to_m(vel)).snapped(Vector2(0.1, 0.1))]
		)
	)
	hud.set_shots(shots)
	_live.clear()
	projectile = Projectile.new()
	world.add_child(projectile)
	projectile.setup(trebuchet.ammo, pos, vel)
	var right: float = Units.to_px(Vector2(data.world_right + 25.0, 0)).x
	projectile.world_rect_px = Rect2(
		Vector2(-3000.0, -8000.0),
		Vector2(right + 3000.0, 8000.0 + Units.to_px(Vector2(0, data.kill_y)).y)
	)
	_track(projectile)
	camera.follow_node(projectile)
	state = State.FLYING
	_ghost_points = PackedVector2Array([pos])


func _log(msg: String) -> void:
	if Game.cli.has("verbose"):
		print("[t=%.2f] %s" % [_time, msg])


func _track(p: Projectile) -> void:
	_live.append(p)
	p.settled.connect(_on_projectile_settled)
	p.impacted.connect(_on_projectile_impacted)
	p.split.connect(_on_projectile_split)


func _on_projectile_split(parent: Projectile, children: Array[Projectile]) -> void:
	for c: Projectile in children:
		_track(c)
	if parent == projectile and not children.is_empty():
		projectile = children[children.size() / 2]
		camera.follow_node(projectile)


func _on_projectile_impacted(p: Projectile, speed_mps: float) -> void:
	if not is_instance_valid(p):
		return
	var pos: Vector2 = p.global_position
	_log("impact at %s m, %.1f m/s" % [Units.to_m(pos).snapped(Vector2(0.1, 0.1)), speed_mps])
	Effects.shake(clampf(speed_mps / 40.0, 0.1, 0.6))
	Effects.haptic(clampf(speed_mps / 30.0, 0.1, 0.8))
	Effects.ground_puff(world, pos + Vector2(0, 30), speed_mps)
	Sfx.play_at("thud", pos, clampf(speed_mps - 24.0, -12.0, 0.0))
	if state == State.FLYING and p == projectile:
		var r := castle_rect.grow(120.0)
		if castle_rect.grow(600.0).has_point(pos):
			r = r.expand(pos)
		camera.frame(r)


func _on_projectile_settled(p: Projectile) -> void:
	_live.erase(p)
	for q: Projectile in _live.duplicate():
		if not is_instance_valid(q) or q.is_done:
			_live.erase(q)
	if state != State.FLYING or not _live.is_empty():
		return
	state = State.SETTLING
	_settle_t = 0.0
	_ghost.points = _ghost_points
	_ghost.visible = Settings.show_ghost_trail


func _on_trebuchet_ready() -> void:
	if state == State.SETTLING:
		state = State.READY


func _hook_block(b: Block) -> void:
	b.broken.connect(_on_block_broken)
	b.hit.connect(
		func(x: Block, imp: float) -> void:
			_log("%s hit %.0f N*s (hp %.0f/%.0f)" % [x.material_id, imp, x.hp, x.max_hp])
	)


func _on_block_broken(b: Block, pts: int) -> void:
	points += pts
	_broken_blocks += 1
	_log("broke %s block (+%d)" % [b.material_id, pts])


func _on_enemy_eliminated(e: Enemy, pts: int) -> void:
	points += pts
	_log("eliminated %s (+%d)" % [e.type_id, pts])
	if not e.is_target:
		_hostages_hit += 1
	if e.is_target:
		targets_left -= 1
		Effects.shake(0.35)
		Effects.haptic(0.5)
		# A beat of slow motion on every royal/knight down (cosmetic only:
		# the physics step size is unchanged, see Effects.slow_motion).
		Effects.slow_motion(0.3, 0.45 if targets_left <= 0 else 0.25)
		Sfx.play_at("poof", e.global_position)
		if targets_left <= 0 and not _won_pending:
			_won_pending = true
			_win_t = 0.0


func _physics_process(delta: float) -> void:
	if state == State.FLYING and is_instance_valid(projectile) and not projectile.has_impacted:
		_ghost_points.append(projectile.global_position)
	if (
		_pending_tap_tick >= 0
		and is_instance_valid(projectile)
		and projectile.ticks >= _pending_tap_tick
	):
		_pending_tap_tick = -1
		tap_projectile()
	_frame_collapse()
	if _won_pending and state != State.WON:
		_win_t += delta
		if _win_t > 0.6 and (_world_asleep() or _win_t > WIN_SETTLE_MAX):
			_win()


func _process(delta: float) -> void:
	_time += delta
	_tick_hold(delta)
	if state == State.SETTLING:
		_settle_t += delta
		if _settle_t > SETTLE_HOLD and trebuchet.state == Trebuchet.State.FOLLOW_THROUGH:
			trebuchet.reload()
			camera.go_aim()
	hud.update_gauge(
		trebuchet.phase, trebuchet.last_release_phase, trebuchet.state == Trebuchet.State.SWINGING
	)
	_run_autoplay()


## After impact, keep everything that is still moving in frame
## (docs/DESIGN.md §5: "pull back to frame the collapse").
func _frame_collapse() -> void:
	if not (
		state == State.SETTLING
		or (state == State.FLYING and is_instance_valid(projectile) and projectile.has_impacted)
	):
		if not (_won_pending and state != State.WON):
			return
	_frame_tick += 1
	if _frame_tick % 6 != 0:
		return
	var r := Rect2()
	var have: bool = false
	for n: Node in get_tree().get_nodes_in_group("blocks"):
		var b := n as Block
		if b == null or b.is_broken or b.linear_velocity.length() < 40.0:
			continue
		r = Rect2(b.global_position, Vector2.ZERO) if not have else r.expand(b.global_position)
		have = true
	for e: Enemy in _enemies:
		if is_instance_valid(e) and not e.is_dead:
			r = Rect2(e.global_position, Vector2.ZERO) if not have else r.expand(e.global_position)
			have = true
	if have:
		var core := Rect2(castle_rect.get_center() - Vector2(250, 250), Vector2(500, 500))
		camera.frame(r.grow(260.0).merge(core))


func _world_asleep() -> bool:
	for n: Node in get_tree().get_nodes_in_group("blocks"):
		var b: Block = n as Block
		if b != null and not b.is_broken and not b.sleeping and b.linear_velocity.length() > 15.0:
			return false
	return true


func _exit_tree() -> void:
	Effects.reset_time()


func _win() -> void:
	state = State.WON
	if bot_mode:
		_bot_report(true)
		return
	var medal: Scoring.Medal = Scoring.medal_for(shots, data.par)
	var score: int = Scoring.final_score(points, shots, data.par)
	var prev_best: int = int(Game.save.levels.get(data.id, {}).get("best_score", 0))
	var unlocked: PackedStringArray = Game.record_win(data.id, shots, medal, score)
	var has_next: bool = not Game.next_level_id(data.id).is_empty()
	hud.show_win(medal, shots, data.par, score, score > prev_best, unlocked, has_next)
	won.emit(shots)
	Game.last_level_won = true
	print(
		(
			"[level] won %s in %d shot(s), medal=%s score=%d state=%s"
			% [data.id, shots, Scoring.medal_key(medal), score, state_hash()]
		)
	)


## Progress score for the validator bot's search: targets down dominate,
## then damage to the survivors, then general destruction.
func bot_score() -> float:
	var s: float = 1000.0 * maxi(0, _targets_total - targets_left)
	for e: Enemy in _enemies:
		if is_instance_valid(e) and not e.is_dead and e.is_target:
			s += 400.0 * clampf(1.0 - e.hp / e.max_hp, 0.0, 1.0)
			s += 60.0 * clampf(absf(e.rotation) / 1.5, 0.0, 1.0)
	return s + _broken_blocks * 3.0 - _hostages_hit * 300.0


func _bot_report(did_win: bool) -> void:
	if _bot_reported:
		return
	_bot_reported = true
	(
		bot_done
		. emit(
			{
				"won": did_win,
				"shots": shots,
				"score": bot_score() + (100000.0 if did_win else 0.0),
				"state": state_hash(),
				"targets_left": targets_left,
				"hostages_hit": _hostages_hit,
			}
		)
	)


## Hash of every block's and enemy's position, rounded to 0.01 px. Equal
## hashes mean two runs simulated identically (used by the slow-mo test).
func state_hash() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var bodies: Array[Node] = get_tree().get_nodes_in_group("blocks")
	for e: Enemy in _enemies:
		if is_instance_valid(e):
			bodies.append(e)
	for n: Node in bodies:
		var b := n as Node2D
		if b == null or not is_instance_valid(b):
			continue
		var p: Vector2 = b.global_position
		ctx.update(("%d,%d;" % [roundi(p.x * 100.0), roundi(p.y * 100.0)]).to_utf8_buffer())
	return ctx.finish().hex_encode().left(16)


func _go_next() -> void:
	var nxt: String = Game.next_level_id(data.id)
	if nxt.is_empty():
		Game.goto_menu()
	else:
		Game.play_level(nxt)


# ------------------------------------------------------------ dev tools ---
func _run_autoplay() -> void:
	if bot_mode and not _bot_reported and _autoplay.is_empty() and shots > 0:
		# Last shot is done once every projectile settled and the world rests.
		if (
			state == State.READY
			or (state == State.SETTLING and _world_asleep() and not _won_pending)
		):
			_bot_report(false)
			return
		if _time > 30.0 * shots:
			_bot_report(false)
			return
	if _autoplay.is_empty():
		return
	var shot: Dictionary = _autoplay[0]
	if state == State.READY and trebuchet.can_fire():
		var want: String = str(shot["ammo"])
		if not want.is_empty() and str(trebuchet.ammo.get("id", "")) != want:
			var def: Dictionary = Data.ammo_def(want)
			if not def.is_empty():
				trebuchet.set_ammo(def)
				hud.set_ammo(def, ammo_list.size())
		trebuchet.start_swing()
		state = State.SWINGING
		hud.fade_hint()
	elif state == State.SWINGING and trebuchet.current_phase() >= float(shot["phase"]):
		trebuchet.release_at(float(shot["phase"]))
		var tap: float = float(shot["tap"])
		_pending_tap_tick = roundi(tap * Units.TICKS_PER_SECOND) if tap >= 0.0 else -1
		_autoplay.remove_at(0)
