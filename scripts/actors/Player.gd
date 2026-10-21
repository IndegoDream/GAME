extends CharacterBody3D
## The player: third-person movement, a camera that orbits with the
## mouse, a melee attack, interacting (E), and sitting to cultivate (M,
## or E at a shrine). All numbers that grow -- HP, damage -- come from
## Game (cultivation + gear), so this script never stores progress.

const WALK_SPEED := 5.0
const SPRINT_SPEED := 8.5
const JUMP_SPEED := 7.0
const GRAVITY := 20.0
const ATTACK_TIME := 0.55
const ATTACK_REACH := 2.6
const INTERACT_REACH := 2.8

var dead := false
const Acc := preload("res://scripts/core/Access.gd")
var meditating := false
var _acc_moved := false

var _yaw := 0.0
var _pitch := -0.62
var _cam_rig: Node3D
var _spring: SpringArm3D
var camera: Camera3D
var _model: Node3D
var _anim: AnimationPlayer
var _lantern: OmniLight3D
var _attack_t := 0.0
var _hit_done := false
var _hurt_cool := 0.0
var _qi_tick := 0.0
var _at_shrine := false
var _sat_for := 0.0           # seconds in this sitting (a long sitting flows at half: Game.SITTING_FATIGUE_SECONDS)
var _focus = null           # the interactable we'd use if E were pressed
var _cool := {}             # technique id -> seconds until usable again
var _dash_t := 0.0
var _dash_dir := Vector3.ZERO
var _sense_t := 0.0
var _calm_t := 0.0          # seconds since you were last hurt or swung (Survival: wounds close between fights)
var _regen_acc := 0.0
const CALM_BEFORE_REGEN := 8.0
# round 20: the guard, and what the step arts leave behind
var guarding := false
var _guard_t := 99.0        # seconds since the guard went up (a blow inside Game.parry_window() is parried)
var _dodge_t := 0.0         # a step's slip: a blow now is a blow stepped through
# round 32: the fight itself -- combos, the charged heavy, the roll, lock-on
var _combo := 0             # which blow of the chain the last one was (0..2)
var _combo_t := 0.0         # time left to continue the chain
var _hold_t := -1.0         # how long the attack button has been held (-1: not held)
var _charging := false
var _heavy := false         # the blow in the air is a heavy
var _recover_t := 0.0       # after a heavy: a beat before you can act
var _roll_t := 0.0
var _roll_dir := Vector3.ZERO
var _roll_cool := 0.0
var lock_target: Node = null
var _ambush_t := 0.0        # Hollow Step / fire step: the next strike lands harder
var _ambush_mult := 1.0
var _air_kicks := 0         # Cloud Ladder: kicks off the air since you last stood
var _water_t := 0.0


var _ac                      # round 122: casts the ki arts of data/arts_ext.json (ArtCaster.gd)
var _dash_dist := 0.0        # round 122: how far an art's dash goes (0: the wind-step distance)
var _sprint_acc := 0.0


func _ready() -> void:
	add_to_group("player")
	_ac = preload("res://scripts/actors/ArtCaster.gd").new(self)
	_model = preload("res://scripts/core/Art.gd").person(dress_spec())       # realistic at Medium+, Kenney at Low
	add_child(_model)
	_dress_up()
	Game.stats_changed.connect(_dress_up)
	Game.stats_changed.connect(_blood_aura)
	_anim = _find_anim(_model)
	for n in ["idle", "walk", "sprint", "sit"]:
		if _anim and _anim.has_animation(n):
			_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	_play("idle")

	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.42
	cap.height = 1.5
	shape.shape = cap
	shape.position = Vector3(0, 0.75, 0)
	add_child(shape)

	# a little lantern so dungeons are never pitch black
	_lantern = OmniLight3D.new()
	_lantern.light_color = Color(1.0, 0.85, 0.65)
	_lantern.omni_range = 7.5
	_lantern.light_energy = 0.9
	_lantern.position = Vector3(0, 2.0, 0)
	add_child(_lantern)

	_cam_rig = Node3D.new()
	_cam_rig.position = Vector3(0, 1.3, 0)
	add_child(_cam_rig)
	_spring = SpringArm3D.new()
	_spring.spring_length = 9.0
	_spring.margin = 0.3
	_spring.add_excluded_object(get_rid())
	_cam_rig.add_child(_spring)
	camera = Camera3D.new()
	camera.fov = 62.0
	camera.current = true
	_spring.add_child(camera)
	set_camera_mode(str(preload("res://scripts/core/Gfx.gd").load_settings()["camera"]))
	_xr_try()


# ---- the camera: far third person, over the shoulder, first person (C) -------
# (Robert, 2026-10-02: Morrowind/Skyrim style -- "First/third toggle")

const PITCH_RANGE := {"far": [-1.25, -0.15], "shoulder": [-1.1, 0.75], "first": [-1.45, 1.45]}
const FX := preload("res://scripts/fx/FX.gd")
var _air_vy := 0.0             # how fast you were falling, for the dust when you land (round 29)
const OWN_BODY_LAYER := 1 << 19          # your own body: hidden from your eyes in first person (its shadow stays)
var _vm = null               # round 128: the first-person hand and weapon (ViewModel.gd)
var cam_mode := "far"
var _far_len := 9.0


func set_camera_mode(m: String) -> void:
	if not PITCH_RANGE.has(m):
		m = "far"
	if cam_mode == "far" and _spring:
		_far_len = _spring.spring_length
	cam_mode = m
	if _cam_rig == null:
		return
	match m:
		"far":
			_cam_base = Vector3(0, 1.3, 0)
			_cam_rig.position = _cam_base
			_spring.spring_length = _far_len
			camera.position = Vector3.ZERO
			camera.fov = 62.0
			if _pitch > -0.15:
				_pitch = -0.62
		"shoulder":
			_cam_base = Vector3(0, 1.85, 0)
			_cam_rig.position = _cam_base
			_spring.spring_length = 3.0
			camera.position = Vector3(0.75, 0, 0)
			camera.fov = 70.0
			_pitch = clampf(_pitch, -0.6, 0.2) if _pitch > -0.6 else -0.25
		"first":
			_cam_base = Vector3(0, 1.72, 0)
			_cam_rig.position = _cam_base
			_spring.spring_length = 0.0
			camera.position = Vector3(0, 0, -0.12)
			camera.fov = 75.0
			_pitch = clampf(_pitch, -0.5, 0.3) if _pitch > -0.5 else -0.1
	camera.cull_mask = (camera.cull_mask & ~OWN_BODY_LAYER) if m == "first" else (camera.cull_mask | OWN_BODY_LAYER)
	_viewmodel_for(m)
	_fov_base = camera.fov
	_cam_have = false                 # (the follow snaps to the new place)
	_apply_layers()
	_apply_cam()


var _xr = null                 # round 135: the VR rig, when a headset is on


func _xr_try() -> void:
	const XRM := preload("res://scripts/core/XRMode.gd")
	if not XRM.wanted():
		return
	_xr = XRM.start(self)
	if _xr == null:
		return
	# the right hand holds your weapon (no swing animation: your arm is the swing)
	_vm = preload("res://scripts/actors/ViewModel.gd").new()
	_vm.name = "ViewModel"
	_vm.tracked = true
	_xr.right.add_child(_vm)
	_vm.setup(self)
	Game.stats_changed.connect(func(): if _vm != null and is_instance_valid(_vm): _vm.refresh())


func _viewmodel_for(m: String) -> void:
	if _xr != null:
		return                           # in VR the viewmodel is the right hand's; the camera views don't apply
	## round 128: first person shows your hand and what it holds; the other views don't make one
	if m == "first" and camera != null:
		if _vm == null or not is_instance_valid(_vm):
			_vm = preload("res://scripts/actors/ViewModel.gd").new()
			_vm.name = "ViewModel"
			camera.add_child(_vm)
			_vm.setup(self)
			Game.stats_changed.connect(func(): if _vm != null and is_instance_valid(_vm): _vm.refresh())
		_vm.visible = true
	elif _vm != null and is_instance_valid(_vm):
		_vm.visible = false


func cycle_camera() -> String:
	var m := preload("res://scripts/core/Gfx.gd").next_camera()
	set_camera_mode(m)
	Game.message.emit(I18n.t("Camera: ") + str(preload("res://scripts/core/Gfx.gd").CAMERA_LABEL.get(m, m)))
	return m


func _apply_layers() -> void:
	## Every mesh of your own body (and what you wear) on its own layer, so
	## the first-person camera can leave it out.
	if _model == null:
		return
	for n in _model.find_children("*", "VisualInstance3D", true, false):
		(n as VisualInstance3D).layers = 1 | OWN_BODY_LAYER


func _face_camera() -> void:
	## Over the shoulder and first person: you face where you look.
	if cam_mode != "far" and _model:
		_model.rotation.y = _yaw + PI


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_view") and not _ui_open():
		cycle_camera()
		get_viewport().set_input_as_handled()
		return
	if (event is InputEventMouseMotion or event is InputEventMouseButton) and event.device == InputEvent.DEVICE_ID_EMULATION:
		return              # a finger on a touch screen, seen as a mouse: TouchUI handles fingers
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * 0.004
		var pr: Array = PITCH_RANGE.get(cam_mode, PITCH_RANGE["far"])
		_pitch = clamp(_pitch - event.relative.y * 0.003, float(pr[0]), float(pr[1]))
		_apply_cam()
	elif event is InputEventMouseButton and event.pressed and cam_mode != "far" and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		# Skyrim-style: scroll in to first person, out to over the shoulder
		set_camera_mode("first" if event.button_index == MOUSE_BUTTON_WHEEL_UP else "shoulder")
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_spring.spring_length = max(_spring.spring_length - 0.8, 3.5)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_spring.spring_length = min(_spring.spring_length + 0.8, 16.0)
		elif Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not _ui_open():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func touch_look(rel: Vector2) -> void:
	## a thumb dragged on the right of a touch screen (TouchUI), already scaled
	_yaw -= rel.x
	var pr: Array = PITCH_RANGE.get(cam_mode, PITCH_RANGE["far"])
	_pitch = clamp(_pitch - rel.y * 0.75, float(pr[0]), float(pr[1]))
	_apply_cam()


func _apply_cam() -> void:
	_cam_rig.rotation = Vector3(_pitch, _yaw, 0)


# ---- smooth motion (round 27, Robert: "make it more realistic and smooth") -----
# The body moves in physics ticks (60 a second); a screen refreshing faster
# would see it step. Between ticks, what you SEE of yourself -- your body and
# the camera that follows you -- is drawn where you are part-way between the
# last tick and this one. Nothing about play changes; only the picture.
var _cam_base := Vector3(0, 1.3, 0)
var _cam_world := Vector3.ZERO      # round 52: where the camera's pivot is (it follows softly)
var _cam_have := false
var _want_yaw := 0.0                # round 52: which way you're turning to (turned every frame)
var _turning := false
var _fov_base := 62.0
var _trauma := 0.0                  # round 52: camera shake builds and fades
var _shake_t := 0.0
var _punch_tw: Tween
var _tick_prev := Vector3.ZERO
var _tick_now := Vector3.ZERO
var _tick_have := false


func _note_tick() -> void:
	var p := global_position
	if not _tick_have or p.distance_to(_tick_now) > 3.0:      # a step through a door, not a walk
		_tick_prev = p
	else:
		_tick_prev = _tick_now
	_tick_now = p
	_tick_have = true


var _globals_ok := false


func _process(delta: float) -> void:
	# round 48: the foliage shader thins leaves between the camera and you
	if not _globals_ok:
		preload("res://scripts/world/Tree.gd").ensure_globals()
		_globals_ok = true
	RenderingServer.global_shader_parameter_set("player_pos", global_position)
	_shake_tick(delta)
	if _model == null or _cam_rig == null or not _tick_have:
		return
	var f := Engine.get_physics_interpolation_fraction()
	var off := _tick_prev.lerp(_tick_now, f) - global_position
	if off.length() > 3.0 or global_position.distance_to(_tick_now) > 0.01:
		off = Vector3.ZERO          # moved since the last tick by something else: draw it where it is
	_model.position = off
	# round 52: you turn every frame, not every tick -- smooth at any refresh rate
	if _turning and not dead:
		var M := FX.feel("move")
		_model.rotation.y = lerp_angle(_model.rotation.y, _want_yaw, 1.0 - exp(-float(M.get("turn_rate", 13.0)) * delta))
	# round 52: the camera follows softly -- a touch of lag, never a jolt
	var target := global_position + _cam_base + off
	var C := FX.feel("camera")
	if not _cam_have or cam_mode == "first" or _cam_world.distance_to(target) > float(C.get("snap_distance", 4.0)):
		_cam_world = target
		_cam_have = true
	else:
		var k := 1.0 - exp(-float(C.get("follow", 16.0)) * delta)
		var ky := 1.0 - exp(-float(C.get("follow_y", 9.0)) * delta)
		_cam_world = Vector3(lerpf(_cam_world.x, target.x, k), lerpf(_cam_world.y, target.y, ky), lerpf(_cam_world.z, target.z, k))
	_cam_rig.position = _cam_world - global_position


func _ui_open() -> bool:
	var hud = get_tree().get_first_node_in_group("hud")
	return hud != null and hud.is_blocking()


func _physics_process(delta: float) -> void:
	if dead:
		return
	_hurt_cool = max(_hurt_cool - delta, 0.0)
	var blocked := _ui_open()
	_regen(delta)

	# camera turn with keys too (Q / R), for anyone not using a mouse
	if not blocked:
		if Input.is_action_pressed("cam_left"):
			_yaw += 2.2 * delta
			_apply_cam()
		if Input.is_action_pressed("cam_right"):
			_yaw -= 2.2 * delta
			_apply_cam()
		# a game pad's right stick (round 29)
		var lk := Input.get_vector("look_left", "look_right", "look_up", "look_down")
		if lk.length() > 0.0:
			_yaw -= lk.x * 2.8 * delta
			var pr: Array = PITCH_RANGE.get(cam_mode, PITCH_RANGE["far"])
			_pitch = clamp(_pitch - lk.y * 1.8 * delta, float(pr[0]), float(pr[1]))
			_apply_cam()

	var input := Vector2.ZERO
	if not blocked:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if _xr != null:
			var xv: Vector2 = _xr.move_vector()
			if xv.length() > input.length():
				input = xv
			_yaw += _xr.snap_turn()
	var basis_yaw := Basis(Vector3.UP, _yaw + (_xr.head_yaw() if _xr != null else 0.0))
	var dir := basis_yaw * Vector3(input.x, 0, input.y)
	dir.y = 0
	if dir.length() > 1.0:
		dir = dir.normalized()

	if dir.length() > 0.1:
		_acc_moved = true
	elif _acc_moved:
		_acc_moved = false
		Acc.release("sprint")          # round 142a: tap-to-run stops when you stop
	if meditating and not blocked and (dir.length() > 0.1 or Input.is_action_just_pressed("attack")):
		stop_meditating()

	# the guard (right mouse / B): up while held
	var want_guard := not blocked and not meditating and Acc.held("guard")
	if want_guard and not guarding:
		_guard_t = 0.0
	guarding = want_guard
	_guard_t += delta
	_dodge_t = maxf(_dodge_t - delta, 0.0)
	_ambush_t = maxf(_ambush_t - delta, 0.0)
	Game.heat_tick(delta, _calm_t > 3.0, guarding, meditating)
	_water_t -= delta
	if _water_t <= 0.0:
		_water_t = 1.0
		Game.near_water = _near_water()
	Game.nanite_tick(delta, _calm_t <= 3.0, meditating, Game.near_water, _sat_for)
	if is_on_floor():
		_air_kicks = 0

	var speed := (SPRINT_SPEED if Acc.held("sprint") else WALK_SPEED) * Game.tech_effect("move_mult", 1.0)
	var asp0 = Game.sys("aspect")
	if asp0 != null and asp0.flowing:
		speed = minf(speed, WALK_SPEED * float(asp0.data.get("walk_mult", 0.85)) * Game.tech_effect("move_mult", 1.0))    # round 146: flowing is a walk
	if _attack_t > 0.0 or _charging:
		speed *= 0.35
	if guarding:
		speed = WALK_SPEED * 0.4
	# a little weight to your feet: you get up to speed (and stop) over a
	# tenth of a second instead of instantly -- smoother, still responsive
	# round 52: data/feel.json "move" -- up to speed in about an eighth of a
	# second, and a short, controlled stop (no ice, no brick wall)
	var MV := FX.feel("move")
	var rate := speed / maxf(float(MV.get("accel_time", 0.12)), 0.02) if is_on_floor() else speed * float(MV.get("air_accel", 5.0))
	if dir.length() <= 0.1:
		rate = (SPRINT_SPEED / maxf(float(MV.get("stop_time", 0.1)), 0.02)) if is_on_floor() else float(MV.get("air_stop", 8.0))
	velocity.x = move_toward(velocity.x, dir.x * speed, rate * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, rate * delta)
	for k in _cool.keys():
		_cool[k] = max(float(_cool[k]) - delta, 0.0)
	if _roll_t > 0.0:
		_roll_t -= delta
		var D0: Dictionary = Game.combat_data().get("dodge", {})
		var rs := float(D0.get("distance", 4.2)) / maxf(float(D0.get("time", 0.42)), 0.1)
		velocity.x = _roll_dir.x * rs
		velocity.z = _roll_dir.z * rs
	if _dash_t > 0.0:
		_dash_t -= delta
		var dd: float = _dash_dist if _dash_dist > 0.0 else Game.tech_effect("dash", 7.0)
		velocity.x = _dash_dir.x * dd / 0.22
		velocity.z = _dash_dir.z * dd / 0.22
		if _dash_t <= 0.0:
			_dash_dist = 0.0
	if _lunge_t > 0.0:
		_lunge_t -= delta
		velocity.x = _lunge_dir.x * _lunge_v
		velocity.z = _lunge_dir.z * _lunge_v
	if not blocked:
		_techniques_input(dir)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif not blocked and Input.is_action_just_pressed("jump") and not meditating:
		velocity.y = JUMP_SPEED
		_play("jump", true)
	var was_air := not is_on_floor()
	if was_air:
		_air_vy = minf(_air_vy, velocity.y)
	if Game.world_frozen:
		velocity = Vector3.ZERO         # round 157: the level's walls are switched off while a menu holds the world -- don't fall through
	else:
		move_and_slide()
	_guard_bounds(delta)
	_note_tick()
	if was_air and is_on_floor():
		if _air_vy < -7.0:
			FX.dust(global_position, clampf(-_air_vy / 10.0, 0.8, 2.0))      # boots on the ground
			Game.sfx("thud", 0.5)
		_air_vy = 0.0

	_body_motion(delta)                  # round 37: lean, stride and gaze
	_lock_tick(delta)
	_turning = false
	if lock_target != null:
		pass                     # (facing the locked foe)
	elif cam_mode != "far":
		_face_camera()
	elif guarding:
		_face_nearest_foe(delta)
	elif dir.length() > 0.1:
		_want_yaw = atan2(dir.x, dir.z)       # (turned every frame in _process)
		_turning = true

	_unstick(delta, blocked)
	# attack
	if _attack_t > 0.0:
		_attack_t -= delta
		if not _hit_done and _attack_t < ATTACK_TIME / Game.attack_speed() - 0.22 / Game.attack_speed():
			_hit_done = true
			_deal_hit()
		if _attack_t <= 0.0:
			_end_blow()
	elif not blocked and not guarding and _recover_t <= 0.0 and _roll_t <= 0.0:
		_attack_input(delta)
	_combo_t = maxf(_combo_t - delta, 0.0)
	if _combo_t <= 0.0 and _attack_t <= 0.0:
		_combo = 0
	_recover_t = maxf(_recover_t - delta, 0.0)
	_roll_cool = maxf(_roll_cool - delta, 0.0)

	if _attack_t <= 0.0 and not meditating and _roll_t <= 0.0 and not _charging:
		if not is_on_floor():
			pass
		elif guarding:
			_play("guard")
		elif dir.length() > 0.1:
			_play("sprint" if Acc.held("sprint") else "walk")
			_stride_speed()
			if Acc.held("sprint") and is_on_floor():
				_sprint_acc += get_physics_process_delta_time()
				if _sprint_acc >= 3.0:
					_sprint_acc = 0.0
					Game.glimpse("sprint")              # round 122: Reed Glide grows from long running
			if Acc.held("sprint") and is_on_floor() and FX.on():
				_dust_t -= get_physics_process_delta_time()
				if _dust_t <= 0.0:
					_dust_t = 0.32
					FX.dust(global_position, 0.45)         # round 37: running kicks up the ground
			if is_on_floor() and Game.audio:
				var lv0 = get_parent().get_node_or_null("Level")
				Game.audio.footstep(lv0 != null and lv0.is_outdoor(), Acc.held("sprint"), delta)
		else:
			_play("idle")
			if _anim:
				_anim.speed_scale = 1.0

	# interact
	_focus = _nearest_interactable()
	var hud = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.set_prompt(_focus.prompt() if _focus else "")
	if not blocked and Input.is_action_just_pressed("interact") and _focus:
		_focus.interact(self)
	if not blocked and Input.is_action_just_pressed("vault_dump") and Game.sys("tester") != null and not Game.sys("tester").clean():
		Game.message.emit(Game.sys("tester").dump_text())          # round 156: straight into the vault
	if not blocked and Input.is_action_just_pressed("mech") and Game.sys("constructs") != null:
		Game.message.emit(Game.sys("constructs").toggle_mech())      # round 154: the power frame
	var asp = Game.sys("aspect")
	var walking := Vector2(velocity.x, velocity.z).length() > 0.5 and not meditating
	if not blocked and asp != null and Input.is_action_just_pressed("flow"):
		# round 146: active meditation -- walk and draw breath
		if asp.flowing:
			asp.stop_flow(I18n.t("You let the flow go."))
		else:
			var fm: String = asp.start_flow()
			if fm != "":
				Game.message.emit(fm)
	elif not blocked and Input.is_action_just_pressed("meditate"):
		if meditating:
			stop_meditating()
		elif walking and asp != null and asp.available():
			if asp.flowing:
				asp.stop_flow(I18n.t("You let the flow go."))
			else:
				Game.message.emit(asp.start_flow())
		else:
			start_meditating(false)
	if asp != null and asp.flowing:
		if Input.is_action_just_pressed("attack") and not blocked:
			asp.stop_flow(I18n.t("The flow breaks -- you struck."))
		else:
			asp.flow_tick(delta, walking)
	if not blocked and Input.is_action_just_pressed("use_salve"):
		Game.use_best("healing_salve")
	if not blocked and Input.is_action_just_pressed("use_pill"):
		Game.use_best("qi_pill")
	if not blocked and Input.is_action_just_pressed("use_gourd"):
		Game.drink_gourd()
	if not blocked and Input.is_action_just_pressed("talisman"):
		use_talisman()                     # round 38: burn the readied talisman
	if not blocked and Input.is_action_just_pressed("talisman_cycle"):
		Game.message.emit(Game.talisman_cycle())

	# cultivation while sitting
	if meditating:
		_qi_tick += delta
		_sat_for += delta
		if _qi_tick >= 1.0:
			_qi_tick = 0.0
			# slow on your own; a shrine, the Lotus Seat and meditation
			# techniques are the aids that make it worth sitting (Game.meditate_tick)
			Game.meditate_tick(1.0, _at_shrine, _sat_for)
			Game.heal(3)
			if _at_shrine:
				Game.bump("shrine_seconds")

	# spirit sense: hidden things near you glow
	_sense_t -= delta
	if _sense_t <= 0.0:
		_sense_t = 0.5
		_spirit_sense()

	if global_position.y < -20.0:
		global_position = get_parent().get_node("Level").spawn_point("P") if get_parent().has_node("Level") else Vector3(2, 2, 2)


func _deal_hit() -> void:
	var fwd := Vector3(sin(_model.rotation.y), 0, cos(_model.rotation.y))
	# the blade's sweep, drawn (a fist's is short and faint)
	if Game.weapon != "":
		FX.slash(self, Color(0.85, 0.92, 1.0), 1.0 + Game.weapon_reach() * 0.6 + 0.6, _model.rotation.y)
	else:
		FX.slash(self, Color(1.0, 0.9, 0.75), 1.1, _model.rotation.y, 1.2)
	var hit_any := false
	var C := Game.combat_data()
	var finisher := not _heavy and _combo == 2
	var W := Game.weapon_trait()                    # round 60: how this weapon fights
	var arc_min := -0.2 if finisher else 0.25          # the finisher sweeps wide
	if finisher and W.has("finisher_arc"):
		arc_min = float(W["finisher_arc"])           # (a saber's whirl, a halberd's reaping arc)
	var reach_bonus: float = float(C.get("combo", {}).get("finisher_reach_bonus", 0.6)) if finisher else 0.0
	if finisher:
		reach_bonus += float(W.get("finisher_reach", 0.0))
	for e in get_tree().get_nodes_in_group("enemy"):
		var to: Vector3 = e.global_position - global_position
		to.y = 0
		var reach := ATTACK_REACH + Game.weapon_reach() + float(e.stats.get("scale", 1.0)) * 0.4 + reach_bonus
		if to.length() <= reach and (to.length() < 0.8 or fwd.dot(to.normalized()) > arc_min):
			# round 30: what you've studied you hit harder; White Tiger blood
			# finds the gap; Asura blood hits harder the closer you are to falling
			var crit: float = Game.crit_mult()
			if finisher and crit <= 1.0 and randf() < float(W.get("finisher_crit", 0.0)):
				crit = float(W.get("crit_mult", 1.6))       # a sword's third cut finds the gap
			var wmult := 1.0
			if W.has("behind_mult") and is_instance_valid(e) and e.get("_model") != null:
				var em: Node3D = e._model
				var efwd := Vector3(sin(em.rotation.y), 0, cos(em.rotation.y))
				if efwd.dot(-to.normalized()) < -0.25:      # its back is to you
					wmult = float(W["behind_mult"])
					if FX.on():
						FX.word(e.global_position + Vector3(0, 2.0, 0), "FROM BEHIND", Color(0.75, 0.6, 1.0), 38)
			var stag_mult: float = float(C.get("poise", {}).get("stagger_damage_mult", 1.35)) if e.staggered() else 1.0
			var dmg := int(round(Game.damage() * _blow_mult * stag_mult * (_ambush_mult if _ambush_t > 0.0 else 1.0) * Game.bestiary_mult(str(e.etype)) * Game.fury_mult() * crit * wmult))
			if crit > 1.0:
				e.set_meta("_crit_next", true)          # round 52: the number says so
				_punch(1.0)
			e.take_damage(dmg, "you" if not _heavy else "you (heavy)")
			if e.has_method("poise_hit") and is_instance_valid(e):
				e.poise_hit(float(dmg) * (float(C.get("heavy", {}).get("poise_mult", 3.0)) if _heavy else 1.0) * float(W.get("poise_mult", 1.0)), _heavy)
			if finisher and is_instance_valid(e) and e.has_method("stagger") and not bool(e.stats.get("boss", false)):
				e.stagger(float(C.get("combo", {}).get("finisher_stagger", 0.8)) * float(W.get("finisher_stagger", 1.0)))
			if finisher and is_instance_valid(e):
				_finisher_trait(e, W, dmg, fwd)
			if _heavy and is_instance_valid(e):
				FX.hit(e.global_position + Vector3(0, 1.1, 0), Color(1.0, 0.7, 0.3), true)
				_shake(0.2)
				_punch(0.7)
			if crit > 1.0:
				FX.hit(e.global_position + Vector3(0, 1.2, 0), Color(1.0, 1.0, 0.85), true)
			var bo: float = Game.tech_effect("burn_on_hit", 0.0)
			if bo > 0.0 and e.has_method("burn") and is_instance_valid(e):
				e.burn(int(round(bo * 3.0)), 3.0)          # Golden Crow blood: your blows burn
			var psn = Game.sys("poison")                                    # round 138: a coated blade
			if psn != null and psn.coat_hits > 0 and is_instance_valid(e):
				psn.on_player_hit(e, dmg)
			hit_any = true
	_calm_t = 0.0
	if hit_any and finisher and W.has("quake_radius"):
		_quake(W)
	if hit_any and W.has("heat_per_hit"):
		Game.heat = maxf(0.0, Game.heat - float(W["heat_per_hit"]))     # a staff: qi in the wood
	if hit_any:
		Game.sfx(("hit_heavy" if _heavy or finisher else "hit_metal") if Game.weapon != "" else ("hit_heavy" if _heavy else "hit_flesh"), 0.9)
		if _heavy or finisher:
			hit_stop(0.07 if _heavy else 0.05)         # round 37: the world holds its breath on a big blow
		_ambush_t = 0.0
		if not is_on_floor():
			Game.glimpse("air_hit")    # a blow from the air (Cloud Ladder grows from these)
		_shake(0.12)
		Game.train_weapon(1)        # the hand learns the weapon it holds


func _nearest_interactable():
	## Whoever walks beside you ("low_priority") only gets the E key when
	## nothing else is in reach -- a chest at your feet comes first.
	## round 157 (Robert: companions get in the way of each other and of whoever you want to talk to): the one you FACE wins,
	## and a follower only gets the key when nothing else is a fair choice -- so two followers never fight over it.
	var best = null
	var best_s := 999.0
	var fwd := Vector2(sin(_model.rotation.y), cos(_model.rotation.y)) if _model != null else Vector2(0, 1)
	for n in get_tree().get_nodes_in_group("interactable"):
		if not (n is Node3D) or not n.visible:
			continue
		var off := Vector2(n.global_position.x - global_position.x, n.global_position.z - global_position.z)
		var d := off.length()
		if d > INTERACT_REACH:
			continue
		var dot := 0.0
		if d > 0.05:
			dot = maxf(off.normalized().dot(fwd), 0.0)
		var s: float = d - 1.1 * dot
		if n.has_meta("low_priority"):
			s += 1.6
		if s < best_s:
			best_s = s
			best = n
	return best


var _stuck_t := 0.0
var _safe_pos := Vector3.ZERO
var _safe_t := 0.0
var _have_safe := false


func _guard_bounds(delta: float) -> void:
	## round 157 (Robert: "when i was checking the map i ended up outside the walls of the map"): remember the last good
	## footing, and if you are ever outside the level or below the world, put you back there.
	if Game.world_frozen or dead:
		return
	var lv = get_tree().get_first_node_in_group("level")
	if lv == null or lv.grid.is_empty():
		return
	var cell: Vector2i = lv.world_to_cell(global_position)
	var rows: int = lv.grid.size()
	var cols := 0
	for row in lv.grid:
		cols = maxi(cols, str(row).length())
	var inside: bool = cell.x >= -1 and cell.y >= -1 and cell.x <= cols and cell.y <= rows and global_position.y > -8.0
	if inside:
		_safe_t -= delta
		if _safe_t <= 0.0 and is_on_floor():
			_safe_t = 0.5
			_safe_pos = global_position
			_have_safe = true
		return
	var to: Vector3 = _safe_pos + Vector3.UP * 0.3 if _have_safe else lv.cell_to_world(Vector2i(clampi(cell.x, 1, maxi(cols - 2, 1)), clampi(cell.y, 1, maxi(rows - 2, 1)))) + Vector3.UP * 1.0
	global_position = to
	velocity = Vector3.ZERO
	Game.message.emit(I18n.t("You find your footing again."))
	Game.log_event("bounds_fix", {"cell": [cell.x, cell.y]})


func _unstick(delta: float, blocked: bool) -> void:
	## round 151 (Robert: "my character gets stuck in pose, can't swing but can use ki blast, like the player is locked but can move"):
	## the swing's own state (a charge held through a menu or a dodge, a frozen animation, a timer that never ran down) can be left
	## half-way; this puts every piece back, and says so in the log (stuck_fix) so a report can be traced.
	var why := ""
	if blocked or meditating:
		if _charging or _hold_t >= 0.0:
			why = "held through a menu"
			_charging = false
			_hold_t = -1.0
	if _attack_t > 4.0:
		why = "attack timer"
		_attack_t = 0.0
	if _recover_t > 2.5:
		why = "recovery timer"
		_recover_t = 0.0
	if _roll_t > 1.2:
		why = "roll timer"
		_roll_t = 0.0
	# not swinging, not drawing a shot, not sitting: nothing should be holding the body still
	if _attack_t <= 0.0 and not _charging and not meditating and _anim != null and _anim.speed_scale < 0.5:
		why = "frozen animation"
		_anim.speed_scale = 1.0
	# a charge that no longer has a held button behind it
	if _charging and not Input.is_action_pressed("attack") and _hold_t < 0.0:
		why = "charge without a button"
		_charging = false
		if _anim:
			_anim.speed_scale = 1.0
	# the body says it is mid-blow but nothing is running it
	if _attack_t <= 0.0 and _heavy and not _charging:
		_heavy = false
	if why != "":
		_stuck_t = 0.0
		Game.log_event("stuck_fix", {"why": why})
		if _anim and _attack_t <= 0.0 and not _charging:
			_play("idle", true)


func _attack_input(delta: float) -> void:
	## click: a light blow, three in a row chain into a finisher. Hold: a
	## charged heavy -- the longer the hold (to max_charge) the harder it
	## lands; it can't be blocked, and it breaks a foe's poise.
	if Game.weapon_is_ranged():
		_ranged_input(delta)             # round 119: a bow, a crossbow, a qi focus
		return
	_hide_aim()
	var C := Game.combat_data()
	var H: Dictionary = C.get("heavy", {})
	if Input.is_action_just_pressed("attack"):
		_hold_t = 0.0
		_charging = false
	elif Input.is_action_pressed("attack") and _hold_t >= 0.0:
		_hold_t += delta
		if not _charging and _hold_t >= float(H.get("hold", 0.4)):
			_charging = true
			_play("guard", true)                  # the wind-up: the blade held back
			if _anim:
				_anim.speed_scale = 0.3
			Game.sfx(_ranged_sound("draw"), 0.6)
	elif _hold_t >= 0.0:
		# released
		if _charging:
			var k := clampf((_hold_t - float(H.get("hold", 0.4))) / maxf(float(H.get("max_charge", 1.3)) - float(H.get("hold", 0.4)), 0.1), 0.0, 1.0)
			_start_blow(true, lerpf(float(H.get("mult_min", 1.6)), float(H.get("mult_max", 2.6)), k))
		else:
			_start_blow(false, 1.0)
		_hold_t = -1.0
		_charging = false
	if _charging and _anim and _hold_t > float(H.get("max_charge", 1.3)) + 0.05:
		_anim.speed_scale = 0.0                   # fully charged: held still


var _blow_mult := 1.0
var _lunge_t := 0.0                 # round 119: each blow steps into the foe a little
var _lunge_dir := Vector3.ZERO
var _lunge_v := 0.0


# ---- round 119: distance weapons ------------------------------------------
# click = a quick shot; hold = draw for a harder one (a faint line shows where
# it will go). A bow is quick and gets stronger the longer you draw; a crossbow
# is slow, hard, and pierces; a qi focus fires from a pool of bursts that
# refills as you breathe, and a held one is a single bursting orb.

var _shot_cool := 0.0
var ki_shots := 6.0
var _aim_line: MeshInstance3D = null


func _ki_regen(delta: float) -> void:
	_shot_cool = maxf(_shot_cool - delta, 0.0)
	var R := Game.ranged_data() if Game.weapon_is_ranged() else {}
	var cap := float(R.get("pool", 6.0)) if not R.is_empty() else 6.0
	if ki_shots < cap:
		ki_shots = minf(cap, ki_shots + float(R.get("regen", 0.9)) * Game.tech_effect("ki_mult", 1.0) * delta) if not R.is_empty() else ki_shots


func _aim_target(R: Dictionary):
	## the foe a shot will go for: your locked one, else the nearest one in front of you
	var fwd := Vector3(sin(_model.rotation.y), 0, cos(_model.rotation.y))
	var rng := float(R.get("range", 26.0))
	if lock_target != null and is_instance_valid(lock_target) and not lock_target._dead and lock_target.global_position.distance_to(global_position) < rng * 1.1:
		return lock_target
	var best = null
	var best_d := rng
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or e.get("_dead") == true:
			continue
		var to: Vector3 = e.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d > best_d or d < 0.05:
			continue
		if fwd.dot(to / d) >= float(R.get("cone", 0.78)):
			best_d = d
			best = e
	return best


func _aim_dir(R: Dictionary) -> Vector3:
	var tgt = _aim_target(R)
	var fwd := Vector3(sin(_model.rotation.y), 0, cos(_model.rotation.y))
	if tgt == null:
		return fwd
	var to: Vector3 = tgt.global_position - global_position
	to.y = 0.0
	return to.normalized() if to.length() > 0.05 else fwd


func _show_aim(R: Dictionary, k: float) -> void:
	if _aim_line == null:
		_aim_line = MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.025, 0.025, 1.0)
		_aim_line.mesh = bm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(1.0, 0.9, 0.6, 0.35)
		_aim_line.material_override = m
		_aim_line.top_level = true
		add_child(_aim_line)
	var d := _aim_dir(R)
	var len_ := lerpf(3.0, minf(float(R.get("range", 26.0)), 12.0), k)
	_aim_line.visible = true
	_aim_line.global_position = global_position + Vector3(0, 1.1, 0) + d * (len_ * 0.5 + 0.6)
	_aim_line.scale = Vector3(1, 1, len_)
	_aim_line.look_at(_aim_line.global_position + d, Vector3.UP)
	var mm := _aim_line.material_override as StandardMaterial3D
	mm.albedo_color = Color(1.0, 0.9 - 0.4 * k, 0.6 - 0.3 * k, 0.25 + 0.4 * k)


func _hide_aim() -> void:
	if _aim_line != null and _aim_line.visible:
		_aim_line.visible = false


func _ranged_input(delta: float) -> void:
	var R := Game.ranged_data()
	if R.is_empty():
		return
	var draw := float(R.get("draw", 0.3))
	var full := float(R.get("full_draw", 1.0))
	if Input.is_action_just_pressed("attack"):
		_hold_t = 0.0
		_charging = false
	elif Input.is_action_pressed("attack") and _hold_t >= 0.0:
		_hold_t += delta
		if not _charging and _hold_t >= draw:
			_charging = true
			_play("charge" if Game.weapon_skill() == "ki" else "aim", true)        # the draw (round 119: the arm raised and sighting)
			if _anim and not _anim.has_animation("aim"):
				_play("guard", true)
			if _anim and _anim.current_animation == "guard":
				_anim.speed_scale = 0.3
			Game.sfx("draw", 0.6)
	elif _hold_t >= 0.0:
		var k := clampf((_hold_t - draw) / maxf(full - draw, 0.1), 0.0, 1.0) if _charging else 0.0
		var was_charging := _charging
		_hold_t = -1.0
		_charging = false
		_hide_aim()
		_fire_ranged(R, k, was_charging)
		return
	if _charging:
		var kk := clampf((_hold_t - draw) / maxf(full - draw, 0.1), 0.0, 1.0)
		_show_aim(R, kk)
		var d := _aim_dir(R)
		_want_yaw = atan2(d.x, d.z)
		_turning = true
		if _anim and kk >= 1.0 and _anim.current_animation == "guard":
			_anim.speed_scale = 0.0               # fully drawn: held still
	else:
		_hide_aim()


func _ranged_sound(phase: String) -> String:
	## round 121: the string, the stock, the qi -- code-made sounds (assets/audio/sfx, tools/gen/ranged_sfx.py)
	var sk := Game.weapon_skill()
	var name := ""
	match sk:
		"bow":
			name = "bow_draw" if phase == "draw" else "bow_release"
		"crossbow":
			name = "bow_draw" if phase == "draw" else "bolt_release"
		"ki":
			name = "ki_charge" if phase == "draw" else "ki_shot"
	if name != "" and preload("res://scripts/core/Audio.gd").has_sound(name):
		return name
	return "draw" if phase == "draw" else "swing"


func _fire_ranged(R: Dictionary, k: float, charged: bool) -> void:
	if _anim:
		_anim.speed_scale = 1.0
	var skill := Game.weapon_skill()
	if _shot_cool > 0.0:
		return
	var heavy := charged and k >= 0.99
	var cost := 0.0
	if skill == "ki":
		cost = float(R.get("burst_cost", 3.0)) if charged and k >= 0.5 else 1.0
		if ki_shots < cost:
			if FX.on():
				FX.word(global_position + Vector3(0, 2.2, 0), "BREATHE", Color(0.6, 0.85, 1.0), 34)
			_shot_cool = 0.4
			return
		ki_shots -= cost
	var d := _aim_dir(R)
	_model.rotation.y = atan2(d.x, d.z)
	_want_yaw = _model.rotation.y
	var mult := lerpf(float(R.get("mult_min", 1.0)), float(R.get("mult_max", 2.0)), k) if charged else float(R.get("mult_min", 1.0))
	var crit: float = Game.crit_mult()
	var dmg := int(round(Game.damage() * mult * crit * Game.tech_effect("ranged_mult", 1.0) * (_ambush_mult if _ambush_t > 0.0 else 1.0)))
	var pierce := int(R.get("pierce_full", 0)) if charged and k >= 0.5 else int(R.get("pierce", 0))
	var burst := float(R.get("burst_radius", 0.0)) if skill == "ki" and cost > 1.0 else 0.0
	var style := "arrow" if skill == "bow" else ("bolt" if skill == "crossbow" else "ki")
	var shot: Node3D = preload("res://scripts/fx/Shot.gd").new()
	get_parent().add_child(shot)
	shot.setup(self, global_position + Vector3(0, 1.15, 0) + d * 0.7, d, style, R, dmg, pierce, burst, heavy or burst > 0.0)
	_shot_cool = float(R.get("cool", 0.5)) / maxf(Game.attack_speed(), 0.3)
	_attack_t = 0.28
	_hit_done = true
	_heavy = false
	_blow_mult = 1.0
	_play("shoot" if skill == "crossbow" else "cast", true)
	if _anim and not _anim.has_animation("cast"):
		_play("attack-melee-right", true)
	if _anim:
		_anim.speed_scale = 1.6
	Game.sfx(_ranged_sound("release"), 0.8)
	_calm_t = 0.0
	_shake(0.05 + 0.1 * k)
	if crit > 1.0:
		_punch(0.4)
	Game.log_event("shot", {"kind": skill, "charged": charged, "k": snappedf(k, 0.1)})


func _start_blow(heavy: bool, mult: float) -> void:
	if _vm != null and is_instance_valid(_vm) and _vm.visible:
		_vm.swing(heavy)
	var C := Game.combat_data()
	var K: Dictionary = C.get("combo", {})
	if _anim:
		_anim.speed_scale = 1.0
	_heavy = heavy
	if heavy:
		_combo = 0
		_blow_mult = mult
		_attack_t = ATTACK_TIME * 1.35 / Game.attack_speed()
		if _anim:
			_anim.speed_scale = 0.8
		_play("attack-melee-right" if Game.weapon != "" else "punch", true)
		_lunge_in(K, 2, 1.3)                  # a heavy blow drives in hardest
		Game.sfx("swing", 1.0)
	else:
		if _combo_t <= 0.0:
			_combo = 0
		var mults: Array = K.get("mults", [1.0, 1.1, 1.55])
		_blow_mult = float(mults[mini(_combo, mults.size() - 1)])
		var spd: Array = K.get("anim_speed", [1.0, 1.2, 0.85])
		_attack_t = ATTACK_TIME / Game.attack_speed() / float(spd[mini(_combo, spd.size() - 1)])
		if _anim:
			_anim.speed_scale = float(spd[mini(_combo, spd.size() - 1)])
		var anims: Array = Game.weapon_trait().get("anims", ["attack-melee-right", "attack-melee-right", "attack-melee-right"]) if Game.weapon != "" else ["jab", "punch", "punch"]
		_play(str(anims[mini(_combo, anims.size() - 1)]), true)
		_lunge_in(K, _combo)
		Game.sfx("swing", 0.6 + 0.15 * _combo)
	_hit_done = false


func _lunge_in(K: Dictionary, idx: int, boost: float = 1.0) -> void:
	## round 119: every blow steps into the foe in front (more on the later blows) --
	## the fight closes instead of flailing at air. It stops a body-length short.
	var L: Array = K.get("lunge", [1.6, 2.2, 3.4])
	var v := float(L[mini(idx, L.size() - 1)]) * boost * float(Game.weapon_trait().get("lunge_mult", 1.0))
	if v <= 0.0:
		return
	var fwd := Vector3(sin(_model.rotation.y), 0, cos(_model.rotation.y))
	var best_d := 4.5
	var best = null
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or e.get("_dead") == true:
			continue
		var to: Vector3 = e.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d < best_d and d > 0.05 and fwd.dot(to / d) > 0.5:
			best_d = d
			best = to / d
	if best == null:
		return                                    # nothing in front: no lunge (it would just slide)
	var gap := best_d - (1.0 + Game.weapon_reach() * 0.5)
	if gap <= 0.15:
		return                                    # already in range
	_lunge_dir = best
	_lunge_t = 0.16
	_lunge_v = minf(v, gap / 0.16)


func _end_blow() -> void:
	## the blow is over: what comes next (the chain, or a heavy's recovery)
	if _anim:
		_anim.speed_scale = 1.0
	var C := Game.combat_data()
	if _heavy:
		_recover_t = float(C.get("heavy", {}).get("recovery", 0.75))
		_heavy = false
		_combo = 0
	else:
		_combo = (_combo + 1) % 3
		_combo_t = float(C.get("combo", {}).get("window", 0.9)) * float(Game.weapon_trait().get("window", 1.0)) if _combo != 0 else 0.0


func _finisher_trait(e, W: Dictionary, dmg: int, fwd: Vector3) -> void:
	## round 60: what this weapon's third blow does besides hurt
	if e.get("_dead") == true:
		return
	if W.has("bleed") and e.has_method("burn"):
		e.burn(maxi(1, int(round(dmg * float(W["bleed"])))), 3.0)
	if W.has("sunder"):
		e.set("sundered", float(W.get("sunder_secs", 4.0)))
		e.set("sunder_mult", 1.0 + float(W["sunder"]))
		if FX.on():
			FX.word(e.global_position + Vector3(0, 2.0, 0), "SUNDERED", Color(1.0, 0.6, 0.35), 38)
	if W.has("knockback") and not bool(e.stats.get("boss", false)):
		var away: Vector3 = e.global_position - global_position
		away.y = 0.0
		e.set("_knock", (away.normalized() if away.length() > 0.05 else fwd) * float(W["knockback"]))


func _quake(W: Dictionary) -> void:
	## a hammer's finisher: the ground jumps round you
	var r := float(W.get("quake_radius", 2.4))
	if FX.on():
		FX.ring(global_position, Color(0.85, 0.7, 0.5), r, 0.3)
		FX.dust(global_position, 1.6)
	_shake(0.18)
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and e.global_position.distance_to(global_position) <= r:
			var d := int(round(Game.damage() * float(W.get("quake_share", 0.4))))
			e.take_damage(maxi(1, d), "you (quake)")
			if e.has_method("poise_hit") and is_instance_valid(e):
				e.poise_hit(float(d) * 2.0, true)


func _perfect_dodge(from: Node) -> void:
	## rolled through a heavy blow just as it landed: the world slows for a
	## breath, and whoever threw it is wide open
	var P: Dictionary = Game.combat_data().get("perfect_dodge", {})
	Game.slow_mo(float(P.get("slow", 0.35)), float(P.get("secs", 0.4)))
	if from.has_method("expose"):
		from.expose(float(P.get("opening", 1.8)))
	if FX.on():
		FX.word(global_position + Vector3(0, 2.2, 0), "PERFECT", Color(0.6, 0.95, 1.0), 50)
		FX.ring(global_position, Color(0.6, 0.95, 1.0), 2.6, 0.35)
	Game.sfx("parry", 0.7)
	Game.log_event("perfect_dodge", {})


func dodge(dir: Vector3) -> bool:
	## a roll: out of the way, through the blow (no damage for its first
	## third of a second), a little slower to come back from than a step
	var D: Dictionary = Game.combat_data().get("dodge", {})
	if _roll_t > 0.0 or _roll_cool > 0.0 or (not is_on_floor() and velocity.y > 1.0) or meditating:
		return false
	_roll_dir = dir if dir.length() > 0.1 else -Vector3(sin(_model.rotation.y), 0, cos(_model.rotation.y))
	_roll_dir = _roll_dir.normalized()
	_roll_t = float(D.get("time", 0.42))
	_roll_cool = float(D.get("cooldown", 0.65)) + _roll_t
	var ifr := float(D.get("iframes", 0.32)) + minf(Game.tech_effect("timing", 0.0), 0.15)     # round 41: Honing widens the slip
	_dodge_t = ifr
	_hurt_cool = maxf(_hurt_cool, ifr)
	_attack_t = 0.0
	_charging = false
	_hold_t = -1.0
	if _anim:
		_anim.speed_scale = 1.0
	_play("roll", true)
	Game.sfx("step_grass", 0.5)
	FX.dust(global_position, 0.8)
	Game.log_event("dodge", {})
	return true


func toggle_lock() -> void:
	## Z / the right stick: face the nearest foe and keep facing it; again to let go
	if lock_target != null and is_instance_valid(lock_target) and not lock_target._dead:
		lock_target = null
		Game.message.emit("Lock released.")
		return
	var L: Dictionary = Game.combat_data().get("lock_on", {})
	var best: float = float(L.get("range", 16.0))
	var pick = null
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or e._dead or bool(e.stats.get("passive", false)):
			continue
		var d: float = (e.global_position - global_position).length()
		if d < best:
			best = d
			pick = e
	lock_target = pick
	if pick:
		Game.sfx("ui_select", 0.6)


func _lock_tick(delta: float) -> void:
	if lock_target == null:
		return
	if not is_instance_valid(lock_target) or lock_target._dead or not lock_target.is_inside_tree():
		lock_target = null
		return
	var to: Vector3 = lock_target.global_position - global_position
	to.y = 0.0
	var L: Dictionary = Game.combat_data().get("lock_on", {})
	if to.length() > float(L.get("break_range", 22.0)):
		lock_target = null
		return
	if to.length() < 0.05:
		return
	var want := atan2(to.x, to.z)
	_model.rotation.y = lerp_angle(_model.rotation.y, want, float(L.get("turn_rate", 9.0)) * delta)
	if cam_mode == "far":
		_yaw = lerp_angle(_yaw, want + PI, 4.0 * delta)
		_apply_cam()


func _techniques_input(dir: Vector3) -> void:
	if Input.is_action_just_pressed("dodge"):
		dodge(dir)
	if Input.is_action_just_pressed("lock_on"):
		toggle_lock()
	if Input.is_action_just_pressed("wind_step"):
		use_step(dir)
	if Input.is_action_just_pressed("flying_sword") and Game.has_treasure("flying_sword"):
		fly_sword()
	if Input.is_action_just_pressed("qi_burst"):
		use_strike()
	for qi in range(4):
		if Input.is_action_just_pressed("quick%d" % (qi + 1)):
			use_quick(qi, dir)
	if Input.is_action_just_pressed("art_cycle"):
		Game.message.emit(Game.cycle_slot("strike"))
	if Input.is_action_just_pressed("path_art"):          # round 121: the path's signature art
		var pa = Game.sys("paths")
		if pa != null:
			var pl: String = pa.cast()
			if pl != "":
				Game.message.emit(pl)
	if Input.is_action_just_pressed("support_art"):        # round 122: the support arts
		use_support("support")
	if Input.is_action_just_pressed("support2_art"):
		use_support("support2")
	if Input.is_action_just_pressed("support_cycle"):
		Game.message.emit(Game.cycle_slot("support"))
	if Input.is_action_just_pressed("support2_cycle"):
		Game.message.emit(Game.cycle_slot("support2"))
	if Input.is_action_just_pressed("path_cycle"):
		var pa2 = Game.sys("paths")
		if pa2 != null:
			Game.message.emit(pa2.cycle_art())


func use_quick(i: int, dir: Vector3) -> void:
	## round 158: a quick key casts whatever art it holds, whichever family it belongs to
	var aid := Game.quick_art(i)
	if aid == "":
		Game.message.emit(I18n.t("Quick key %s is empty -- assign an art to it in the menu (Arts).") % Game.quick_key_label(i))
		return
	cast_art(aid, dir)


func cast_art(aid: String, dir: Vector3 = Vector3.ZERO) -> bool:
	match Game.art_template(aid):
		"qi_burst":
			return use_qi_burst(aid) >= 0
		"severing_finger":
			return use_severing_finger(aid) >= 0
		"collapsing_palm":
			return use_collapsing_palm(aid) >= 0
		"wind_step":
			return use_wind_step(dir, aid)
		"hollow_step":
			return use_hollow_step(aid)
		"cloud_ladder":
			return use_cloud_ladder(dir, aid)
	return _ac.cast(aid, dir) >= 0


func use_strike() -> int:
	## F: whichever strike art is wired (X switches, or wire one on K)
	var aid := Game.slot_art("strike")
	match Game.art_template(aid):          # (a sect's art runs on one of these, with its own numbers)
		"qi_burst":
			return use_qi_burst(aid)
		"severing_finger":
			return use_severing_finger(aid)
		"collapsing_palm":
			return use_collapsing_palm(aid)
	if aid != "":
		return _ac.cast(aid)               # round 122: the rest of the library (and a shared support art)
	return -1


func use_step(dir: Vector3) -> bool:
	## V: whichever step art is wired
	var aid := Game.slot_art("step")
	match Game.art_template(aid):
		"wind_step":
			return use_wind_step(dir, aid)
		"hollow_step":
			return use_hollow_step(aid)
		"cloud_ladder":
			return use_cloud_ladder(dir, aid)
	if aid != "":
		return _ac.cast(aid, dir) >= 0     # round 122
	return false


func use_support(slot: String) -> bool:
	## 8 (and 9 in two-slot mode): whichever support art is wired
	var axm = Game.sys("arts")
	if slot == "support2" and axm != null and axm.support_mode != "two":
		Game.message.emit("Key 9 is only used in two-slot support mode (menu > Arts > Support arts).")
		return false
	if axm != null and axm.support_mode == "share" and slot == "support":
		return use_strike() >= 0
	var aid := Game.slot_art(slot)
	if aid == "":
		Game.message.emit("You know no support art for this key yet. They come from tending wounds, from sects and from the roads (menu > Arts).")
		return false
	return _ac.cast(aid) >= 0


func _face_nearest_foe(delta: float) -> void:
	## in the far camera, a raised guard turns to meet whatever's closest
	var best := 6.0
	var to_best := Vector3.ZERO
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and not e._dead:
			var to: Vector3 = e.global_position - global_position
			to.y = 0.0
			if to.length() < best:
				best = to.length()
				to_best = to
	if to_best.length() > 0.01:
		_model.rotation.y = lerp_angle(_model.rotation.y, atan2(to_best.x, to_best.z), 14.0 * delta)


func _near_water() -> bool:
	## a fishing spot (water) within a few steps -- for Moonwater Breath
	for n in get_tree().get_nodes_in_group("interactable"):
		if n is Node3D and str(n.get("kind")) == "fish" and (n.global_position - global_position).length() < 8.0:
			return true
	return false


func _enemy_near(r: float) -> bool:
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and not e._dead and (e.global_position - global_position).length() < r:
			return true
	return false


func _near_post() -> bool:
	for p in get_tree().get_nodes_in_group("training_post"):
		if p is Node3D and (p.global_position - global_position).length() < 7.0:
			return true
	return false


func _art_cool(aid: String, base: float) -> void:
	var c := float(Game.technique_defs.get(aid, {}).get("cooldown", base)) * Game.art_cooldown_mult(aid)
	if Game.art_branch(aid) == "metal" and Game.art_family(aid) == "step":
		c *= 0.8
	_cool[aid] = c


func _strike_hit(aid: String, e, dmg: int, nth: int, src: String) -> void:
	e.take_damage(dmg, src)
	Game.branch_on_hit(aid, e, dmg, nth)


func _after_step(aid: String, real_fight: bool) -> void:
	## what a step art's element leaves behind, then practice (or a drill)
	_dodge_t = 0.4
	match Game.art_branch(aid):
		"fire":
			var prev := _ambush_mult if _ambush_t > 0.0 else 1.0
			_ambush_t = 2.0
			_ambush_mult = maxf(prev, 1.0) * 1.3
		"wood":
			if real_fight:
				Game.heal(maxi(1, int(round(Game.max_hp() * 0.04))))
		"earth":
			get_tree().create_timer(0.25).timeout.connect(func():
				if not is_instance_valid(self):
					return
				for e in get_tree().get_nodes_in_group("enemy"):
					if is_instance_valid(e) and not e._dead and (e.global_position - global_position).length() < 2.5:
						e.stagger(1.0))
	if real_fight:
		Game.practice(aid, true)
	elif _near_post():
		Game.post_drill(aid)
	else:
		Game.practice(aid, false)


func _art_ok(aid: String) -> bool:
	## known, off cooldown, and its route through your meridians open
	if not Game.has_tech(aid) or float(_cool.get(aid, 0.0)) > 0.0:
		return false
	var why := Game.art_blocked(aid)
	if why != "":
		Game.message.emit(why)
		_cool[aid] = 1.5          # (don't repeat the reminder every frame)
		return false
	return true


func use_wind_step(dir: Vector3, aid: String = "wind_step") -> bool:
	if not _art_ok(aid):
		return false
	_art_cool(aid, 2.5)
	var pw := Game.art_fire(aid)
	_dash_dir = dir if dir.length() > 0.1 else Vector3(sin(_model.rotation.y), 0, cos(_model.rotation.y))
	_dash_dir = _dash_dir.normalized()
	_dash_t = 0.22 * pw
	_hurt_cool = 0.4      # you slip through the blow
	_play("sprint", true)
	# practice: a step taken in a real fight (something close enough to hit you) counts three times
	_after_step(aid, _enemy_near(4.5))
	return true


func use_hollow_step(aid: String = "hollow_step") -> bool:
	## vanish; stand behind the nearest foe; the next strike lands harder
	if not _art_ok(aid):
		return false
	var target = null
	var best := Game.art_param(aid, "hollow_range", 9.0)
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and not e._dead:
			var d: float = (e.global_position - global_position).length()
			if d < best:
				best = d
				target = e
	if target == null:
		Game.message.emit("%s needs a foe to stand behind." % Game.technique_defs.get(aid, {}).get("name", "It"))
		_cool[aid] = 0.5
		return false
	_art_cool(aid, 5.0)
	var pw := Game.art_fire(aid)
	var away: Vector3 = global_position - target.global_position
	away.y = 0.0
	var behind: Vector3 = target.global_position - (away.normalized() if away.length() > 0.01 else Vector3.FORWARD) * 1.4
	global_position = Vector3(behind.x, maxf(global_position.y, target.global_position.y), behind.z)
	var to: Vector3 = target.global_position - global_position
	_model.rotation.y = atan2(to.x, to.z)
	_hurt_cool = 0.3
	_ambush_t = 2.0
	_ambush_mult = Game.art_param(aid, "ambush_mult", 1.6) * pw
	_after_step(aid, true)
	return true


func use_cloud_ladder(dir: Vector3, aid: String = "cloud_ladder") -> bool:
	## a kick off the air itself: high, even mid-jump (once per jump, more when Mastered)
	if not _art_ok(aid):
		return false
	var kicks := 1 + (1 if Game.art_stage(aid) >= 2 else 0)
	if not is_on_floor() and _air_kicks >= kicks:
		return false
	_art_cool(aid, 3.0)
	var pw := Game.art_fire(aid)
	if not is_on_floor():
		_air_kicks += 1
	var lift := Game.art_param(aid, "ladder_lift", 1.7)
	velocity.y = JUMP_SPEED * lift * clampf(pw, 0.85, 1.3)
	if dir.length() > 0.1:
		_dash_dir = dir.normalized()
		_dash_t = 0.12
	_play("jump", true)
	_after_step(aid, _enemy_near(4.5))
	return true


func use_qi_burst(aid: String = "qi_burst") -> int:
	## returns how many it struck (-1 = couldn't use it)
	if not _art_ok(aid):
		return -1
	_art_cool(aid, 7.0)
	var r := Game.tech_effect("burst_radius", 4.5) if aid == "qi_burst" else Game.art_param(aid, "burst_radius", 4.5)
	var mult := Game.art_param(aid, "burst_mult", 2.0) * Game.art_fire(aid) * Game.branch_damage_mult(aid)
	var hit := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if (e.global_position - global_position).length() <= r:
			_strike_hit(aid, e, int(Game.damage() * mult), hit, "qi burst")
			hit += 1
	_burst_fx(r)
	_shake(0.25)
	_play("cast", true)
	_strike_practice(aid, hit)
	Game.log_event("qi_burst" if aid == "qi_burst" else "art_used", {"hit": hit, "art": aid})
	return hit


func _strike_practice(aid: String, hit: int) -> void:
	if hit > 0:
		Game.practice(aid, true)
	elif _near_post():
		Game.post_drill(aid)
	else:
		Game.practice(aid, false)


func use_severing_finger(aid: String = "severing_finger") -> int:
	## a thread of qi at the nearest foe in front of you (or nearest at all)
	if not _art_ok(aid):
		return -1
	var reach := Game.art_param(aid, "finger_range", 14.0)
	var fwd := Vector3(sin(_model.rotation.y), 0, cos(_model.rotation.y))
	var target = null
	var best := 1e9
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or e._dead:
			continue
		var to: Vector3 = e.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d > reach:
			continue
		var score := d * (1.0 if d < 0.5 or fwd.dot(to.normalized()) > 0.5 else 3.0)   # in front first
		if score < best:
			best = score
			target = e
	_art_cool(aid, 3.5)
	var pw := Game.art_fire(aid)
	_play("cast", true)
	var hit := 0
	if target != null:
		var dmg := int(round(Game.damage() * Game.art_param(aid, "finger_mult", 2.2) * pw * Game.branch_damage_mult(aid)))
		_beam_fx(target.global_position)
		_strike_hit(aid, target, dmg, 0, "severing finger")
		hit = 1
	else:
		_beam_fx(global_position + fwd * reach)
	_strike_practice(aid, hit)
	return hit


func use_collapsing_palm(aid: String = "collapsing_palm") -> int:
	## the whole body through one palm: a cone ahead, heavy, staggering
	if not _art_ok(aid):
		return -1
	var reach := Game.art_param(aid, "palm_range", 5.0)
	var fwd := Vector3(sin(_model.rotation.y), 0, cos(_model.rotation.y))
	_art_cool(aid, 9.0)
	var pw := Game.art_fire(aid)
	var mult := Game.art_param(aid, "palm_mult", 3.2) * pw * Game.branch_damage_mult(aid)
	var hit := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or e._dead:
			continue
		var to: Vector3 = e.global_position - global_position
		to.y = 0.0
		if to.length() <= reach and (to.length() < 0.8 or fwd.dot(to.normalized()) > 0.5):
			_strike_hit(aid, e, int(Game.damage() * mult), hit, "collapsing palm")
			e.stagger(1.5)
			hit += 1
	_burst_fx(reach * 0.6)
	_shake(0.35)
	_play("attack-melee-right", true)
	_strike_practice(aid, hit)
	return hit


func _beam_fx(to: Vector3) -> void:
	if not is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	var from := global_position + Vector3(0, 1.3, 0)
	var tgt := to + Vector3(0, 1.0, 0)
	var beam := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.04
	c.bottom_radius = 0.04
	c.height = maxf(from.distance_to(tgt), 0.1)
	beam.mesh = c
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.7, 0.95, 1.0, 0.9)
	m.emission_enabled = true
	m.emission = Color(0.5, 0.9, 1.0)
	m.emission_energy_multiplier = 4.0
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam.material_override = m
	get_parent().add_child(beam)
	beam.global_position = (from + tgt) / 2.0
	var d := tgt - from
	if d.length() > 0.01:
		beam.look_at(tgt, Vector3.UP if absf(d.normalized().y) < 0.99 else Vector3.RIGHT)
		beam.rotate_object_local(Vector3.RIGHT, PI / 2)
	var tw := beam.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.0, 0.25)
	tw.tween_callback(beam.queue_free)


func fly_sword() -> bool:
	## The Azure Flying Sword: leaves your side, strikes the nearest enemy
	## in range, comes home. Returns true if it struck something.
	if float(_cool.get("flying_sword", 0.0)) > 0.0:
		return false
	var d: Dictionary = Game.items.get("flying_sword", {})
	var reach := float(d.get("range", 14.0))
	var target = null
	var best := reach
	for e in get_tree().get_nodes_in_group("enemy"):
		var dist: float = (e.global_position - global_position).length()
		if dist < best:
			best = dist
			target = e
	if target == null:
		Game.message.emit("The sword hums at your side. Nothing in reach.")
		return false
	_cool["flying_sword"] = float(d.get("cooldown", 2.5))
	var dmg := int(round(Game.damage() * float(d.get("strike_mult", 1.4))))
	var hit_type := str(target.etype)
	_sword_fx(target.global_position)
	target.take_damage(dmg, "flying sword")
	Game.log_event("flying_sword", {"hit": hit_type})
	return true


func _sword_fx(to: Vector3) -> void:
	var path := "res://assets/kenney/mini-dungeon/weapon-sword.glb"
	if not ResourceLoader.exists(path) or not is_inside_tree():
		return
	var sw: Node3D = load(path).instantiate()
	sw.scale = Vector3.ONE * 2.2
	get_parent().add_child(sw)
	var start := global_position + Vector3(0, 1.6, 0)
	sw.global_position = start
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.45, 0.75, 1.0)
	glow.omni_range = 3.0
	glow.light_energy = 2.0
	sw.add_child(glow)
	var tw := sw.create_tween()
	tw.tween_property(sw, "global_position", to + Vector3(0, 1.0, 0), 0.18)
	tw.parallel().tween_property(sw, "rotation:y", TAU * 2.0, 0.18)
	tw.tween_property(sw, "global_position", start, 0.22)
	tw.tween_callback(sw.queue_free)


func _burst_fx(r: float) -> void:
	var ring := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.6
	t.outer_radius = 0.9
	ring.mesh = t
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.5, 0.9, 1.0, 0.8)
	m.emission_enabled = true
	m.emission = Color(0.4, 0.9, 1.0)
	m.emission_energy_multiplier = 3.0
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = m
	ring.position = Vector3(0, 0.6, 0)
	add_child(ring)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3.ONE * r, 0.35)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.35)
	tw.chain().tween_callback(ring.queue_free)


func _spirit_sense() -> void:
	var bloom := Game.augment_on("sensor_bloom")
	if not Game.has_tech("spirit_sense") and not bloom:
		return
	var r := (Game.tech_effect("sense_radius", 12.0) if Game.has_tech("spirit_sense") else 4.0) + (8.0 if bloom else 0.0)
	for n in get_tree().get_nodes_in_group("discoverable"):
		if not (n is Node3D) or n.has_node("SenseGlow"):
			continue
		if n.has_method("sensed"):
			# round 46: a hidden wall or trap is noticed -- a brief shimmer, not a beacon
			if (n.global_position - global_position).length() <= r:
				n.sensed()
			continue
		if (n.global_position - global_position).length() <= r:
			var g := OmniLight3D.new()
			g.name = "SenseGlow"
			g.light_color = Color(0.6, 0.9, 1.0)
			g.omni_range = 3.0
			g.light_energy = 1.4
			g.position = Vector3(0, 1.4, 0)
			n.add_child(g)


func take_damage(amount: int, source: String = "", from: Node = null) -> void:
	if dead:
		return
	var asp_f = Game.sys("aspect")                                   # round 146: a blow breaks the flow
	if asp_f != null and asp_f.flowing:
		asp_f.stop_flow(I18n.t("The flow breaks -- you were struck."))
	# round 60: a heavy blow (a foe's wind-up, a master's slam) -- no guard holds it
	var heavy: bool = from != null and is_instance_valid(from) and from.get("heavy_now") == true
	if _hurt_cool > 0.0:
		if _dodge_t > 0.0 and from != null:
			Game.glimpse("dodge")      # stepped clean through it (Hollow Step grows from these)
			_dodge_t = 0.0
			if heavy:
				_perfect_dodge(from)
		return
	if guarding and from != null and is_instance_valid(from) and from is Node3D:
		var fwd := Vector3(sin(_model.rotation.y), 0, cos(_model.rotation.y))
		var to: Vector3 = (from as Node3D).global_position - global_position
		to.y = 0.0
		var front := to.length() < 0.3 or fwd.dot(to.normalized()) > -0.17
		if front and _guard_t <= Game.parry_window():
			var p := Game.parry(amount)
			if from.has_method("stagger"):
				from.stagger(float(p["stagger"]) * (float(Game.combat_data().get("foe_heavy", {}).get("parry_stagger_mult", 1.6)) if heavy else 1.0))
			if heavy and from.has_method("expose"):
				from.expose(float(Game.combat_data().get("foe_heavy", {}).get("opening", 1.6)))
			if int(p["reflect"]) > 0 and from.has_method("take_damage"):
				from.take_damage(int(p["reflect"]), "returning tide")
			if int(p["burn"]) > 0 and from.has_method("burn"):
				from.burn(int(p["burn"]), 3.0)
			if float(p.get("charge", 0.0)) > 0.0:             # round 122: Counter Current
				_ambush_t = float(p.get("charge_secs", 3.0))
				_ambush_mult = maxf(_ambush_mult if _ambush_t > 0.0 else 1.0, 1.0) * float(p["charge"])
				if FX.on():
					FX.word(global_position + Vector3(0, 2.4, 0), "CHARGED", Color(0.6, 0.9, 1.0), 38)
			_hurt_cool = 0.25
			_shake(0.1)
			_parry_fx()
			Game.sfx("parry", 1.0)
			FX.hit(global_position + Vector3(0, 1.2, 0) + Vector3(sin(_model.rotation.y), 0, cos(_model.rotation.y)) * 0.6, Color(1.0, 0.95, 0.7), true)
			FX.ring(global_position, Color(1.0, 0.92, 0.6), 2.2, 0.3)
			Game.message.emit("PARRIED -- %s staggers." % source)
			return
		if heavy:
			# too heavy to block: the guard breaks and it lands in full
			if FX.on():
				FX.word(global_position + Vector3(0, 2.2, 0), "GUARD BROKEN", Color(1.0, 0.4, 0.3), 44)
			Game.log_event("guard_broken", {"by": source})
			if not Game.has_flag("tut:guard_broken"):
				Game.set_flag("tut:guard_broken")
				Game.message.emit("Too heavy to block -- roll out of the red ring, or parry it just as it lands.")
			front = false
		var b := Game.block(amount, front) if not heavy else {"take": amount, "reflect": 0}
		if int(b["reflect"]) > 0 and from.has_method("take_damage"):
			from.take_damage(int(b["reflect"]), "returning tide")
		if int(b.get("burn", 0)) > 0 and from.has_method("burn"):
			from.burn(int(b["burn"]), 3.0)                     # round 122: Ember Ward
		amount = int(b["take"])
		if amount <= 0:
			_hurt_cool = 0.2
			return
	if Game.dodges():
		# Nine-Tailed Fox blood: the blow meets only where you were
		_hurt_cool = 0.3
		Game.message.emit("You slip the blow (%s)." % source)
		FX.dust(global_position, 0.8)
		return
	# round 32: a Guard companion steps into the blow, some of the time
	for comp in get_tree().get_nodes_in_group("companion"):        # round 39: either of a party of two
		if comp.has_method("near_player") and comp.near_player():
			amount = Game.companion_intercept(amount, true, int(comp.slot))
			if amount <= 0:
				_hurt_cool = 0.35
				return
	_hurt_cool = 0.35
	_calm_t = 0.0
	if meditating:
		stop_meditating()
	Game.hurt(amount)
	Game.glimpse("hurt")                           # round 122: Backwind Retreat grows from pain survived
	Game.message.emit("-%d HP (%s)" % [amount, source])
	Game.sfx("hurt", 0.8)
	if Game.hp <= 0 and Game.try_rebirth():
		FX.ring(global_position, Color(1.0, 0.5, 0.15), 3.5, 0.6)
		FX.puff(global_position + Vector3(0, 1.0, 0), Color(1.0, 0.45, 0.1), 1.4)
		_hurt_cool = 1.5
		return
	FX.hit(global_position + Vector3(0, 1.1, 0), Color(1.0, 0.3, 0.25), amount * 5 >= Game.max_hp())
	_shake(0.2)
	var hudh = get_tree().get_first_node_in_group("hud")
	if hudh and hudh.has_method("hurt_flash"):
		hudh.hurt_flash(float(amount) / maxf(float(Game.max_hp()), 1.0))          # round 52: the edges of the screen go red
	if Game.hp <= 0:
		_die(source)


var _aura_node: Node3D
var _aura_color := Color(0, 0, 0, 0)


func _blood_aura() -> void:
	## round 30: a dominant bloodline at Manifest (50%) shows -- faint embers
	## of its colour around you
	var c: Color = Game.blood_aura_color()
	var sc: Color = Game.Comfort.aura_color()          # round 127: the Style pack's aura (looks only)
	if sc.a > 0.0:
		c = sc
	if c == _aura_color:
		return
	_aura_color = c
	if _aura_node and is_instance_valid(_aura_node):
		_aura_node.queue_free()
		_aura_node = null
	if c.a > 0.0:
		_aura_node = FX.aura(self, c, 1.7, 22)


func _parry_fx() -> void:
	if not is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.95, 0.7)
	l.light_energy = 3.0
	l.omni_range = 3.0
	l.position = Vector3(0, 1.3, 0.6)
	add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.25)
	tw.tween_callback(l.queue_free)


func _die(cause: String = "") -> void:
	dead = true
	_play("die", true)
	var lvl = get_parent().get_node_or_null("Level")
	var where: Vector2i = lvl.world_to_cell(global_position) if lvl else Vector2i.ZERO
	get_tree().create_timer(2.0).timeout.connect(func():
		dead = false
		Game.player_died(cause, where))


func start_meditating(at_shrine: bool) -> void:
	_at_shrine = at_shrine or _near_shrine()
	if _at_shrine:
		Game.refill_gourd()
	meditating = true
	Game.sitting = true                     # round 40: the swarm can be rewired while you sit
	Game.set_flag("fs:meditate")
	_sat_for = 0.0
	Game.meditating = _at_shrine
	velocity = Vector3.ZERO
	_play("sit", true)
	Game.message.emit(I18n.t("You sit and cultivate%s.  Focus: %s -- change it in the menu (Tab, Mind).") % [(I18n.t(" at the shrine (fast qi)") if _at_shrine else ""), Game.sys("mind").summary() if Game.sys("mind") else "Cultivate"])
	_offer_tribulation()


func _offer_tribulation() -> void:
	## round 25: a full sea of qi, enough insight, the ring open -- sitting
	## is where the breakthrough is faced
	if not Game.at_threshold() or str(Game.current_level).begins_with("tribulation:"):
		return
	var miss: Array = Game.breakthrough_missing()
	if not miss.is_empty():
		Game.message.emit("Your sea of qi is full. To break through you still need %s." % ", ".join(miss))
		return
	var hud = get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	hud.open_dialog("The tribulation", "Your sea of qi is full, you understand enough, and your ring is open. To cross into %s you have to sit still while your nanites rewrite you -- and they resist. The resistance will have your face, your strength, and your favourite way of fighting.\n\nWin, and you break through. Lose, and it costs an injured meridian and an hour -- not your qi." % Game.realm_info(Game.realm + 1)["name"],
		[["Face it", func():
			hud.close_dialog()
			stop_meditating()
			Game.begin_tribulation()], ["Not yet", hud.close_dialog]])


func stop_meditating() -> void:
	meditating = false
	Game.sit_aid = 1.0          # (a hermitage's quiet only lasts while you sit in it)
	Game.meditating = false
	Game.sitting = false
	_play("idle")


func _near_shrine() -> bool:
	for s in get_tree().get_nodes_in_group("shrine"):
		if (s.global_position - global_position).length() < 3.5:
			return true
	return false


func _shake(amount: float) -> void:
	## round 52: shake is trauma -- it builds with each blow and fades out
	## smoothly (not one fixed wiggle per hit)
	_trauma = minf(1.0, _trauma + amount * 2.2 * Acc.motion())


func shake_amount() -> float:
	return _trauma


func _shake_tick(delta: float) -> void:
	if camera == null:
		return
	if _trauma <= 0.0:
		if camera.h_offset != 0.0 or camera.v_offset != 0.0:
			camera.h_offset = 0.0
			camera.v_offset = 0.0
			camera.rotation.z = 0.0
		return
	var C := FX.feel("camera")
	var real := delta / maxf(Engine.time_scale, 0.05)        # (it keeps fading through a hit-stop)
	_trauma = maxf(0.0, _trauma - float(C.get("shake_decay", 1.8)) * real)
	_shake_t += real * float(C.get("shake_freq", 24.0))
	var s := _trauma * _trauma
	var mx := float(C.get("shake_max", 0.35))
	camera.h_offset = mx * s * (sin(_shake_t) * 0.6 + sin(_shake_t * 1.73 + 1.1) * 0.4)
	camera.v_offset = mx * s * (sin(_shake_t * 1.31 + 2.3) * 0.6 + sin(_shake_t * 2.11) * 0.4)
	camera.rotation.z = float(C.get("shake_roll", 0.025)) * s * sin(_shake_t * 0.87 + 0.5)


func _punch(amount: float) -> void:
	## round 52: a big blow pulls the view in for an instant
	if camera == null or cam_mode == "first":
		return
	var C := FX.feel("camera")
	if _punch_tw and _punch_tw.is_valid():
		_punch_tw.kill()
	camera.fov = _fov_base - float(C.get("punch_fov", 4.0)) * clampf(amount, 0.0, 1.5)
	_punch_tw = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_punch_tw.tween_property(camera, "fov", _fov_base, float(C.get("punch_secs", 0.22))).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _play(anim: String, restart: bool = false) -> void:
	if _anim == null or not _anim.has_animation(anim):
		return
	if restart or _anim.current_animation != anim:
		# round 27: attacks snap in, everything else eases into the next move
		_anim.play(anim, 0.08 if restart else 0.22)


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var a := _find_anim(c)
		if a:
			return a
	return null


func face_camera_toward(world_yaw: float) -> void:
	_yaw = world_yaw
	_apply_cam()


var _gear_regen_acc := 0.0


func _regen(delta: float) -> void:
	_ki_regen(delta)
	## Survival: away from a fight long enough, your wounds close on their own.
	_calm_t += delta
	# round 27: gear that mends you (Evergreen, Mending Swarm, Self-repair) works even mid-fight
	var gr := Game.tech_effect("regen", 0.0)
	if gr > 0.0 and Game.hp > 0 and Game.hp < Game.max_hp():
		_gear_regen_acc += gr * delta
		if _gear_regen_acc >= 1.0:
			var gn := int(_gear_regen_acc)
			_gear_regen_acc -= gn
			Game.hp = mini(Game.hp + gn, Game.max_hp())
	if _calm_t < CALM_BEFORE_REGEN or Game.hp >= Game.max_hp() or Game.hp <= 0 or Game.no_regen_here():
		_regen_acc = 0.0
		return
	_regen_acc += Game.survival_regen() * delta
	if _regen_acc >= 1.0:
		var n := int(_regen_acc)
		_regen_acc -= n
		Game.hp = mini(Game.hp + n, Game.max_hp())
		Game.add_skill_xp("survival", 0.05 * n, "resting your wounds")


# ---- what you wear (Dress.gd) ------------------------------------------------------

const ELEMENT_ROBE := {"wood": [0.3, 0.55, 0.32], "fire": [0.7, 0.25, 0.2], "earth": [0.65, 0.5, 0.28], "metal": [0.82, 0.82, 0.86], "water": [0.25, 0.4, 0.7]}
var _dressed_as := ""


func dress_spec() -> Dictionary:
	## A cultivator's robe in the colour of your strongest element (an Academy
	## disciple wears the Academy's), your hair up in a topknot, and the
	## weapon you're actually holding.
	var best := ""
	var bv := 10.0
	for e in Game.ELEMENTS:
		if float(Game.affinity[e]) > bv:
			bv = float(Game.affinity[e])
			best = e
	var s := {"hair": "topknot", "hair_color": [0.08, 0.07, 0.07], "robe": ELEMENT_ROBE.get(best, [0.35, 0.4, 0.55]), "sash": [0.8, 0.68, 0.3]}
	for k in ["sex", "skin", "hair", "hair_color", "beard"]:          # round 36: who you said you are
		if Game.look.has(k):
			s[k] = Game.look[k]
	if bool(Game.academy.get("enrolled", false)):
		s["robe"] = [0.92, 0.92, 0.95]
		s["sash"] = [0.55, 0.3, 0.75]
	if Game.partner != "":
		s["cape"] = [0.85, 0.75, 0.85]      # a partner's gift, worn where everyone can see it
	var k := ""
	if Game.weapon != "" and Game.has_item_def(Game.weapon):
		k = str(Game.item_def(Game.weapon).get("kind", "sword"))
	s["held"] = k
	s["gear"] = Game.worn_looks()       # round 27: everything you wear, drawn on you (Armour.gd)
	return s


func rebuild_model() -> void:
	## a new body (creation chose another sex or skin): the model is remade
	if _model:
		_model.queue_free()
	_model = preload("res://scripts/core/Art.gd").person(dress_spec())
	add_child(_model)
	_dressed_as = ""
	_dress_up()
	_anim = _find_anim(_model)
	for n in ["idle", "walk", "sprint", "sit"]:
		if _anim and _anim.has_animation(n):
			_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	_play("sit" if meditating else "idle")


func _dress_up() -> void:
	if _model == null:
		return
	var s := dress_spec()
	var key := JSON.stringify(s)
	if key == _dressed_as:
		return
	_dressed_as = key
	preload("res://scripts/world/Dress.gd").dress(_model, s)
	preload("res://scripts/actors/Armour.gd").dress_gear(_model, s.get("gear", []))
	_apply_layers()



# ---- round 37: a body that moves like one (Robert: "more realistic ... more
# fluid articulation") --------------------------------------------------------
# The stride matches how fast you're really going (no more feet sliding), the
# body leans into turns and forward into a run, and the head turns to look
# where you're looking (or at the foe you've locked on) -- a LookAtModifier3D
# on the realistic figure's Head bone, limited and eased so it never snaps.

var _lean := Vector2.ZERO        # x: forward pitch, y: roll into the turn
var _last_yaw := 0.0
var _last_speed := 0.0
var _gaze: LookAtModifier3D
var _gaze_target: Node3D
var _gaze_for := 0


func _stride_speed() -> void:
	if _anim == null:
		return
	var v := Vector2(velocity.x, velocity.z).length()
	var native := SPRINT_SPEED if _anim.current_animation == "sprint" else WALK_SPEED
	_anim.speed_scale = clampf(v / native, 0.55, 1.45)


func _body_motion(delta: float) -> void:
	if _model == null or delta <= 0.0:
		return
	var v := Vector2(velocity.x, velocity.z).length()
	var yaw_rate := wrapf(_model.rotation.y - _last_yaw, -PI, PI) / delta
	_last_yaw = _model.rotation.y
	var accel := (v - _last_speed) / delta
	_last_speed = v
	var want_pitch := clampf(v / SPRINT_SPEED, 0.0, 1.0) * 0.07 + clampf(accel * 0.006, -0.06, 0.06)
	var want_roll := clampf(-yaw_rate * 0.035 * clampf(v / WALK_SPEED, 0.0, 1.5), -0.14, 0.14)
	if not is_on_floor() or _roll_t > 0.0 or meditating:
		want_pitch = 0.0
		want_roll = 0.0
	_lean.x = lerpf(_lean.x, want_pitch, clampf(delta * 6.0, 0.0, 1.0))
	_lean.y = lerpf(_lean.y, want_roll, clampf(delta * 5.0, 0.0, 1.0))
	_model.rotation.x = _lean.x
	_model.rotation.z = _lean.y
	_gaze_tick()


func _setup_gaze() -> void:
	if _model == null:
		return
	var sk: Skeleton3D = preload("res://scripts/world/Dress.gd").skeleton(_model)
	if sk == null or sk.find_bone("Head") < 0:
		return
	if _gaze_target == null:
		_gaze_target = Node3D.new()
		_gaze_target.name = "GazeTarget"
		_gaze_target.top_level = true
		add_child(_gaze_target)
	_gaze = LookAtModifier3D.new()
	_gaze.name = "Gaze"
	_gaze.bone_name = "Head"
	_gaze.forward_axis = SkeletonModifier3D.BONE_AXIS_PLUS_Z
	_gaze.primary_rotation_axis = Vector3.AXIS_Y
	_gaze.use_secondary_rotation = true
	_gaze.duration = 0.35
	_gaze.transition_type = Tween.TRANS_SINE
	_gaze.ease_type = Tween.EASE_IN_OUT
	_gaze.use_angle_limitation = true
	_gaze.set("primary_limit_angle", deg_to_rad(110.0))
	_gaze.set("primary_damp_threshold", 0.6)
	_gaze.set("secondary_limit_angle", deg_to_rad(50.0))
	_gaze.set("secondary_damp_threshold", 0.6)
	_gaze.influence = 0.75
	sk.add_child(_gaze)
	_gaze.target_node = _gaze.get_path_to(_gaze_target)


func _gaze_tick() -> void:
	if _gaze == null or not is_instance_valid(_gaze) or not _model.is_ancestor_of(_gaze):
		if _model and _gaze_for != _model.get_instance_id():
			_gaze_for = _model.get_instance_id()          # (one try per body: a Kenney figure has no Head bone)
			_gaze = null
			_setup_gaze()
		return
	var head := global_position + Vector3(0, 1.6, 0)
	var at: Vector3
	if lock_target != null and is_instance_valid(lock_target):
		at = lock_target.global_position + Vector3(0, 1.2, 0)
	else:
		# where the camera looks, a few metres ahead -- or straight ahead while running
		var cam := get_viewport().get_camera_3d()
		var fwd := Vector3(sin(_model.rotation.y), 0, cos(_model.rotation.y))
		if cam and Vector2(velocity.x, velocity.z).length() < WALK_SPEED * 0.9:
			var cf := -cam.global_transform.basis.z
			cf.y = clampf(cf.y + 0.25, -0.4, 0.4)
			at = head + cf.normalized() * 6.0
		else:
			at = head + fwd * 6.0
	_gaze_target.global_position = _gaze_target.global_position.lerp(at, 0.25) if _gaze_target.global_position != Vector3.ZERO else at
	_gaze.active = not meditating and _roll_t <= 0.0


var _dust_t := 0.0


func hit_stop(secs: float) -> void:
	## a few frames of near-stillness on a heavy blow (Game ends it, in real time)
	if FX.on() and not get_tree().paused:
		Game.hit_stop(secs)


# ---- talismans (round 38) --------------------------------------------------------------

var _talisman_cd := 0.0


func use_talisman(base: String = "") -> int:
	## burn one: returns how many foes it touched (0 for a buff, a heal, the
	## map; -1 if there was none to burn)
	var now := Time.get_ticks_msec() / 1000.0
	if now < _talisman_cd:
		return -1
	var t := Game.talisman_take(base)
	if t.is_empty():
		Game.message.emit(Game.talisman_cycle())
		return -1
	_talisman_cd = now + 0.8
	var u: Dictionary = t.get("use", {})
	var pot := float(t.get("potency", 1.0))
	var cv: Array = u.get("color", [1.0, 0.9, 0.6])
	var col := Color(float(cv[0]), float(cv[1]), float(cv[2]))
	var hit := 0
	match str(u.get("kind", "")):
		"burst":
			var r := float(u.get("radius", 5.0))
			var dmg := int(round(float(Game.damage()) * float(u.get("mult", 2.0)) * pot))
			for e in get_tree().get_nodes_in_group("enemy"):
				if not is_instance_valid(e) or e._dead:
					continue
				if (e.global_position - global_position).length() > r:
					continue
				if dmg > 0:
					e.take_damage(dmg, "talisman")
				if float(u.get("burn", 0.0)) > 0.0 and is_instance_valid(e) and e.has_method("burn"):
					e.burn(int(round(float(u["burn"]) * pot * maxf(1.0, float(Game.damage()) * 0.2))), 3.0)
				if float(u.get("slow", 0.0)) > 0.0 and is_instance_valid(e):
					e.slow(float(u["slow"]) * pot)
				if float(u.get("stun", 0.0)) > 0.0 and is_instance_valid(e):
					e.stagger(float(u["stun"]) * pot)
				hit += 1
			if FX.on():
				FX.ring(global_position + Vector3(0, 0.3, 0), col, r, 0.5)
				FX.hit(global_position + Vector3(0, 1.2, 0), col, true)
			_shake(0.3 if dmg > 0 else 0.12)
			if hit > 0 and dmg > 0:
				hit_stop(0.06)
		"heal", "buff", "sight":
			if FX.on():
				FX.ring(global_position + Vector3(0, 0.2, 0), col, 1.6, 0.6)
			if bool(u.get("reveal", false)):
				var fog = get_tree().get_first_node_in_group("fog_of_war")
				if fog:
					fog.reveal_all()
	_play("cast", true)
	Game.sfx("page", 0.9)
	if hit > 0:
		Game.sfx("crystal", 0.8)
	Game.message.emit(I18n.t("%s burns%s.") % [Game.item_name(str(t.get("id", ""))), (I18n.t(" -- %d caught in it") % hit) if hit > 0 else ""])
	return hit
