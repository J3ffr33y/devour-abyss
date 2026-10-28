extends Node3D
## Builds the 2.5D test sea and runs the feel prototype rules in Godot.
## Gameplay is in the plane z = 0. Everything at z < 0 is the background layer.

const WORLD_W := 260.0
const START := Vector2(45, -26)
const FOG_SHALLOW := Color("0f4a63")
const FOG_DEEP := Color("020910")

var player: Player
var creatures: Array[Creature] = []
var school_center := {}
var cam: Camera3D
var env: Environment
var sun: DirectionalLight3D

var _school_id := 0
var _respawn_q: Array = []
var _hitstop := 0.0
var _shake := 0.0
var _shake_mag := 0.0
var _cam_target := Vector3.ZERO
var _hud := {}
var _toast_t := 0.0
var _hint_t := 0.0
var _sounds := {}
var _lev := {"t": -6.0, "active": false, "segs": [], "trail": [], "dir": 1.0}
var _bg_schools: Array[Node3D] = []
var _time := 0.0
var _test_shot := OS.get_environment("ABYSS_TEST")  # automated check: autopilot, screenshot, quit


func _ready() -> void:
	randomize()
	_setup_input()
	_build_world()
	player = Player.new()
	player.p = START
	add_child(player)
	player.reset_tail()
	_populate()
	_build_hud()
	_build_sounds()
	_build_leviathan()
	hint("你很小。先吃发光的浮游生物和小鱼，慢慢长大。WASD 游动，空格冲刺，F 发光。", 7.0)


# ---------------- input ----------------
func _add_key(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)


func _add_joy(action: String, axis: int, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	InputMap.action_add_event(action, e)


func _setup_input() -> void:
	_add_key("move_left", [KEY_A, KEY_LEFT])
	_add_key("move_right", [KEY_D, KEY_RIGHT])
	_add_key("move_up", [KEY_W, KEY_UP])
	_add_key("move_down", [KEY_S, KEY_DOWN])
	_add_key("dash", [KEY_SPACE, KEY_SHIFT])
	_add_key("glow", [KEY_F])
	_add_joy("move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_joy("move_right", JOY_AXIS_LEFT_X, 1.0)
	_add_joy("move_up", JOY_AXIS_LEFT_Y, -1.0)
	_add_joy("move_down", JOY_AXIS_LEFT_Y, 1.0)
	var jb := InputEventJoypadButton.new()
	jb.button_index = JOY_BUTTON_A
	InputMap.action_add_event("dash", jb)
	var jg := InputEventJoypadButton.new()
	jg.button_index = JOY_BUTTON_Y
	InputMap.action_add_event("glow", jg)


func _input_dir() -> Vector2:
	if _test_shot != "":
		return _autopilot()
	var d := Input.get_vector("move_left", "move_right", "move_down", "move_up")
	if d.length() > 0.05:
		return d
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and cam:
		var mp := get_viewport().get_mouse_position()
		var from := cam.project_ray_origin(mp)
		var dir := cam.project_ray_normal(mp)
		if absf(dir.z) > 0.0001:
			var hit := from + dir * (-from.z / dir.z)
			var to := Vector2(hit.x, hit.y) - player.p
			if to.length() > player.r:
				return to.normalized() * minf(1.0, to.length() / 6.0)
	return Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("dash"):
		var res := player.try_dash(_input_dir())
		if res == "ok":
			burst(Vector3(player.p.x, player.p.y, 0), Color("c8f0ff"), 14, 6.0)
			shake(0.1, 0.12)
			_play("whoosh")
		elif res != "":
			hint(res, 2.5)
	if event.is_action_pressed("glow"):
		var res2 := player.toggle_light()
		if res2 != "ok" and res2 != "":
			hint(res2, 2.5)


# ---------------- world ----------------
func floor_y(x: float) -> float:
	var i := x / 5.0
	return -(147.5 + sin(i * 0.37) * 6.0 + sin(i * 1.3) * 2.25)


func _mesh(mesh: Mesh, m: Material, pos: Vector3, parent: Node = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func _build_world() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = FOG_SHALLOW
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("7fd4ee")
	env.ambient_light_energy = 0.6
	env.fog_enabled = true
	env.fog_light_color = FOG_SHALLOW
	env.fog_density = 0.02
	# glow off for now: it washed the whole frame cyan in testing; revisit with real art
	env.glow_enabled = false
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-70, 20, 0)
	sun.light_color = Color("bfefff")
	sun.light_energy = 1.0
	add_child(sun)

	cam = Camera3D.new()
	cam.fov = 48.0
	cam.far = 400.0
	add_child(cam)
	cam.position = Vector3(START.x, START.y, 20)
	_cam_target = cam.position
	# marine snow drifting around the camera
	var snow := CPUParticles3D.new()
	snow.amount = 700
	snow.lifetime = 10.0
	snow.preprocess = 10.0
	snow.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	snow.emission_box_extents = Vector3(40, 25, 30)
	snow.gravity = Vector3(0, -0.15, 0)
	snow.direction = Vector3(0, -1, 0)
	snow.initial_velocity_min = 0.0
	snow.initial_velocity_max = 0.3
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.06)
	var sm := Creature.mat(Color("cfeaf2"), true, 0.6)
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sm.emission_energy_multiplier = 0.6
	q.material = sm
	snow.mesh = q
	snow.position = Vector3(0, 0, -20)
	cam.add_child(snow)

	# sea floor that rises into cliffs further back
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var xs := []
	var zs := []
	var x := -40.0
	while x <= WORLD_W + 40.0:
		xs.append(x)
		x += 2.5
	var z := 12.0
	while z >= -110.0:
		zs.append(z)
		z -= 3.0
	var h := func(px: float, pz: float) -> float:
		var base := floor_y(px)
		if pz < -6.0:
			base += (-pz - 6.0) * 0.35 + sin(px * 0.07 + pz * 0.05) * 6.0 + sin(pz * 0.13) * 3.0
		return base
	for zi in zs.size() - 1:
		for xi in xs.size() - 1:
			var a := Vector3(xs[xi], h.call(xs[xi], zs[zi]), zs[zi])
			var b := Vector3(xs[xi + 1], h.call(xs[xi + 1], zs[zi]), zs[zi])
			var c := Vector3(xs[xi], h.call(xs[xi], zs[zi + 1]), zs[zi + 1])
			var d := Vector3(xs[xi + 1], h.call(xs[xi + 1], zs[zi + 1]), zs[zi + 1])
			st.add_vertex(a)
			st.add_vertex(b)
			st.add_vertex(c)
			st.add_vertex(b)
			st.add_vertex(d)
			st.add_vertex(c)
	st.generate_normals()
	var floor_mat := Creature.mat(Color("14262e"))
	floor_mat.roughness = 1.0
	floor_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh(st.commit(), floor_mat, Vector3.ZERO)

	# rocks and spires at many depths so the camera shows parallax
	var rock_mat := Creature.mat(Color("1b2f38"))
	rock_mat.roughness = 1.0
	for i in 160:
		var s := randf_range(1.0, 7.0)
		var rz := randf_range(3.0, 9.0) if i < 25 else randf_range(-90.0, -4.0)
		var rx := randf_range(-20.0, WORLD_W + 20.0)
		var rock := _mesh(Creature.sphere(s, 6, 3), rock_mat, Vector3(rx, h.call(rx, rz) + s * 0.2, rz))
		rock.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		rock.scale = Vector3(1, randf_range(0.6, 1.8), 1)
	for i in 50:
		var height := randf_range(8.0, 35.0)
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = randf_range(0.8, 2.5)
		cone.height = height
		cone.radial_segments = 5
		var sx := randf_range(-20.0, WORLD_W + 20.0)
		var sz := randf_range(-80.0, -8.0)
		_mesh(cone, rock_mat, Vector3(sx, h.call(sx, sz) + height * 0.45, sz))

	# the giant ribs near the start, behind the play plane
	var bone := Creature.mat(Color("cfc6a8"))
	var ribs := Node3D.new()
	ribs.position = Vector3(15, -62, -16)
	add_child(ribs)
	for i in 10:
		var tm := TorusMesh.new()
		var rr := 13.0 - absf(i - 4.5) * 0.8
		tm.inner_radius = rr
		tm.outer_radius = rr + 0.9
		tm.rings = 24
		tm.ring_segments = 6
		var rib := _mesh(tm, bone, Vector3(i * 4.5, 0, 0), ribs)
		rib.rotation = Vector3(PI / 2.0, PI / 2.0 + 0.12, 0)
	var spine := CylinderMesh.new()
	spine.top_radius = 1.0
	spine.bottom_radius = 1.0
	spine.height = 48.0
	spine.radial_segments = 6
	var sp := _mesh(spine, bone, Vector3(20, 12.5, 0), ribs)
	sp.rotation.z = PI / 2.0

	# water surface seen from below and a few light shafts
	var surf := PlaneMesh.new()
	surf.size = Vector2(700, 300)
	var surf_mat := Creature.mat(Color("9fe6f5"), true, 0.35)
	surf_mat.emission_energy_multiplier = 0.6
	surf_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh(surf, surf_mat, Vector3(WORLD_W / 2.0, 0.5, -100))
	var ray_mat := Creature.mat(Color("a8eaff"), true, 0.025)
	ray_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ray_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ray_mat.no_depth_test = false
	for i in 14:
		var quad := QuadMesh.new()
		quad.size = Vector2(randf_range(2.0, 5.0), 45.0)
		var ray := _mesh(quad, ray_mat, Vector3(randf_range(0.0, WORLD_W), -20, randf_range(-60.0, -3.0)))
		ray.rotation.z = randf_range(-0.35, -0.15)

	# decorative fish schools in the background layer
	for sc in 8:
		var grp := Node3D.new()
		grp.position = Vector3(randf_range(0.0, WORLD_W), randf_range(-70.0, -12.0), randf_range(-55.0, -12.0))
		grp.set_meta("v", randf_range(1.5, 3.0) * (1.0 if randf() < 0.5 else -1.0))
		add_child(grp)
		for i in 16:
			var f := Node3D.new()
			f.position = Vector3(randf_range(-4, 4), randf_range(-2, 2), randf_range(-3, 3))
			grp.add_child(f)
			Creature.fish_mesh(f, randf_range(0.3, 0.5), Color("9fb8c4"))
		if grp.get_meta("v") < 0.0:
			grp.rotation.y = PI
		_bg_schools.append(grp)


func _build_leviathan() -> void:
	var lm := Creature.mat(Color("24323b"))
	var gm := Creature.mat(Color("7ff0ff"), true)
	for i in 60:
		var rad := 2.8 * (1.0 - i / 75.0) + 0.3
		var seg := _mesh(Creature.sphere(rad, 10, 6), lm, Vector3(0, -40, -50))
		seg.scale = Vector3(1.5, 1, 1)
		if i % 4 == 2:
			_mesh(Creature.sphere(rad * 0.25, 6, 4), gm, Vector3(0, rad * 0.9, 0), seg)
		if i == 0:
			_mesh(Creature.sphere(0.5, 6, 4), Creature.mat(Color("ffa04a"), true), Vector3(rad * 0.8, rad * 0.3, rad * 0.7), seg)
		seg.visible = false
		_lev.segs.append(seg)


# ---------------- creatures ----------------
func spawn(kind: String, pos = null, school_id := 0) -> Creature:
	var info: Dictionary = Creature.TYPES[kind]
	if pos == null:
		var tries := 0
		pos = Vector2(randf_range(5.0, WORLD_W - 5.0), -randf_range(info.depth[0] + 2.0, minf(info.depth[1], 145.0)))
		while tries < 20 and pos.distance_to(player.p) < 35.0:
			pos = Vector2(randf_range(5.0, WORLD_W - 5.0), -randf_range(info.depth[0] + 2.0, minf(info.depth[1], 145.0)))
			tries += 1
	var c := Creature.new()
	add_child(c)
	c.setup(kind, pos, school_id)
	creatures.append(c)
	return c


func _spawn_school(pos = null, n := -1) -> void:
	_school_id += 1
	if pos == null:
		pos = Vector2(randf_range(10.0, WORLD_W - 10.0), -randf_range(8.0, 75.0))
		var tries := 0
		while tries < 20 and pos.distance_to(player.p) < 35.0:
			pos = Vector2(randf_range(10.0, WORLD_W - 10.0), -randf_range(8.0, 75.0))
			tries += 1
	if n < 0:
		n = 6 + randi() % 6
	for i in n:
		spawn("minnow", pos + Vector2(randf_range(-2.0, 2.0), randf_range(-1.25, 1.25)), _school_id)


func _populate() -> void:
	for i in 650:
		spawn("plankton")
	for i in 26:
		_spawn_school()
	for i in 70:
		spawn("shrimp")
	for i in 22:
		spawn("jelly")
	for i in 12:
		spawn("dart")
	for i in 11:
		spawn("pred")
	# guaranteed organs and a food-rich nursery near the start
	spawn("jelly", START + Vector2(26, -13))
	spawn("dart", START + Vector2(-19, -6))
	for i in 70:
		spawn("plankton", START + Vector2(randf_range(-22.0, 22.0), randf_range(-15.0, 12.0)))
	_spawn_school(START + Vector2(13, 3), 7)


# ---------------- rules ----------------
func eat(c: Creature) -> void:
	c.alive = false
	creatures.erase(c)
	player.eaten += 1
	var info: Dictionary = c.info
	player.energy = minf(100.0, player.energy + info.food)
	player.hp = minf(100.0, player.hp + info.food * 0.3)
	player.grow_from(c)
	player.chomp = 0.14
	player.squash = minf(1.0, 0.35 + c.r / player.r)
	player.gulps.append({"pos": 0.0, "sz": minf(0.6, c.r / player.r)})
	player.combo = player.combo + 1 if player.combo_t > 0.0 else 1
	player.combo_t = 1.3
	if player.combo >= 3:
		_float_text("连吞 ×%d" % player.combo)
	_play("gulp", clampf(1.0 - c.r / 1.5, 0.25, 1.0) * 1.2 + mini(player.combo, 8) * 0.05)
	burst(c.position, info.color, 6 + int(c.r * 20.0), 2.0 + c.r * 4.0)
	if c.r > 0.15:
		_hitstop = maxf(_hitstop, Feel.hitstop * minf(2.5, c.r / 0.3))
		shake(minf(0.5, c.r * 0.45), 0.16)
	if info.has("organ"):
		if info.organ == "light" and not player.has_light:
			player.has_light = true
			player.light_on = true
			toast("获得器官 · 发光")
			hint("按 F 开关发光。看得更远、会引来浮游生物，但掠食者也更容易发现你，还耗能量。", 7.0)
		elif info.organ == "dash" and not player.has_dash:
			player.has_dash = true
			toast("获得器官 · 冲刺")
			hint("按 空格 冲刺。冲刺会发出声响，惊动附近的生物。", 6.0)
	# swallow animation: pulled into the mouth and shrunk
	var mouth := Vector3(player.p.x + cos(player.ang) * player.r * 0.6, player.p.y + sin(player.ang) * player.r * 0.6, 0)
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "position", mouth, 0.13)
	tw.tween_property(c, "scale", Vector3.ONE * 0.1, 0.13)
	tw.chain().tween_callback(c.queue_free)
	_respawn_q.append({"type": c.type, "t": 4.0 if c.type == "plankton" else 18.0})


func hurt(dmg: float, from: Vector2) -> void:
	if player.hurt_t > 0.0 or player.dead > 0.0:
		return
	player.hp -= dmg
	player.hurt_t = 0.8
	var d := (player.p - from).normalized()
	player.v += d * 19.0
	burst(Vector3(player.p.x, player.p.y, 0), Color("ff6b5a"), 16, 7.0)
	shake(0.45, 0.3)
	_hitstop = maxf(_hitstop, 0.07)
	_play("hurt")
	_hud.hurt.modulate.a = 1.0
	if player.hp <= 0.0:
		die()


func die() -> void:
	if player.dead > 0.0:
		return
	player.dead = 1.8
	player.hp = 0.0
	player.visible = false
	toast("你被吞噬了", 1.8)
	burst(Vector3(player.p.x, player.p.y, 0), Color("c8f0ff"), 40, 8.0)


func _respawn() -> void:
	player.p = START
	player.v = Vector2.ZERO
	player.mass = maxf(1.0, player.mass * 0.6)
	player.hp = 100.0
	player.energy = 70.0
	player.dead = 0.0
	player.hurt_t = 1.5
	player.visible = true
	player.reset_tail()
	for c in creatures:
		if c.type == "pred" and c.state == "chase":
			c.state = "wander"
	hint("在巢穴重生。体型缩小了，但器官都还在。", 4.0)


# ---------------- loop ----------------
func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	_time += dt
	_update_fx(dt)
	if player.dead > 0.0:
		player.dead -= dt
		if player.dead <= 0.0:
			_respawn()
	elif _hitstop > 0.0:
		_hitstop -= dt
	else:
		player.update(dt, _input_dir(), self)
		_update_creatures(dt)
	_update_leviathan(dt)
	_update_depth_look()
	_update_camera(dt)
	_update_hud()
	if _test_shot != "":
		_test_step()


func _autopilot() -> Vector2:
	var best: Creature = null
	var bd := 1e9
	for c in creatures:
		if c.r < player.r * 0.92 and c.in_play_plane():
			var dd := c.p.distance_to(player.p)
			if dd < bd:
				bd = dd
				best = c
	return (best.p - player.p).normalized() if best else Vector2.RIGHT


func _test_step() -> void:
	if _time > 3.0 and not player.has_dash:
		player.has_dash = true
		player.has_light = true
		player.light_on = true
	if _time > 12.0:
		var img := get_viewport().get_texture().get_image()
		img.save_png(_test_shot)
		print("TEST eaten=%d r=%.2f hp=%.0f energy=%.0f creatures=%d depth=%d lev=%s" % [player.eaten, player.r, player.hp, player.energy, creatures.size(), int(-player.p.y * 20.0 / 3.0), str(_lev.active)])
		get_tree().quit()


func _update_creatures(dt: float) -> void:
	school_center.clear()
	for c in creatures:
		if c.school > 0:
			if not school_center.has(c.school):
				school_center[c.school] = {"p": Vector2.ZERO, "v": Vector2.ZERO, "n": 0}
			var s = school_center[c.school]
			s.p += c.p
			s.v += c.v
			s.n += 1
	for c in creatures.duplicate():
		if c.alive:
			c.update(dt, self)
	for i in range(_respawn_q.size() - 1, -1, -1):
		var q = _respawn_q[i]
		q.t -= dt
		if q.t <= 0.0:
			_respawn_q.remove_at(i)
			if q.type == "minnow" and school_center.size() > 0:
				var id = school_center.keys()[randi() % school_center.size()]
				var s = school_center[id]
				spawn("minnow", s.p / s.n + Vector2(randf_range(-1.5, 1.5), randf_range(-1.0, 1.0)), id)
			else:
				spawn(q.type)
	for g in _bg_schools:
		var vx: float = g.get_meta("v")
		g.position.x += vx * dt
		if g.position.x > WORLD_W + 40.0:
			g.position.x = -40.0
		elif g.position.x < -40.0:
			g.position.x = WORLD_W + 40.0


func _update_leviathan(dt: float) -> void:
	_lev.t += dt
	if not _lev.active and _lev.t > 0.0:
		_lev.active = true
		_lev.t = 0.0
		_lev.dir = 1.0 if randf() < 0.5 else -1.0
		_lev.trail.clear()
		for s in _lev.segs:
			s.visible = true
		hint("……有什么东西在深处游过。", 5.0)
	if not _lev.active:
		return
	var dur := 30.0
	var k: float = _lev.t / dur
	var head := Vector3(player.p.x + _lev.dir * lerpf(-90.0, 90.0, k), player.p.y - 8.0 + sin(_lev.t * 0.5) * 5.0, -42.0 + sin(_lev.t * 0.3) * 9.0)
	_lev.trail.push_front(head)
	if _lev.trail.size() > 400:
		_lev.trail.pop_back()
	var n: int = _lev.trail.size()
	for i in _lev.segs.size():
		var seg: MeshInstance3D = _lev.segs[i]
		var a: Vector3 = _lev.trail[mini(n - 1, i * 5)]
		var b: Vector3 = _lev.trail[mini(n - 1, i * 5 + 3)]
		seg.position = a
		seg.rotation = Vector3(0, 0.0 if _lev.dir > 0 else PI, atan2(a.y - b.y, absf(a.x - b.x) + 0.0001))
	if absf(head.x - player.p.x) < 25.0:
		shake(0.08, 0.1)
		if randf() < dt * 1.5:
			_play("rumble")
	if _lev.t > dur:
		_lev.active = false
		_lev.t = -40.0
		for s in _lev.segs:
			s.visible = false


func _update_depth_look() -> void:
	var depth_t := clampf(-player.p.y / 120.0, 0.0, 1.0)
	var fog := FOG_SHALLOW.lerp(FOG_DEEP, depth_t)
	env.fog_light_color = fog
	env.background_color = fog
	env.fog_density = lerpf(0.018, 0.06, depth_t) * (0.55 if player.light_on else 1.0)
	env.ambient_light_energy = lerpf(0.6, 0.05, depth_t)
	sun.light_energy = lerpf(1.0, 0.03, depth_t)


func _update_camera(dt: float) -> void:
	var k := 1.0 - exp(-Feel.cam_lag * dt)
	var dist := clampf(20.0 * pow(player.r / 0.3, 0.55), 20.0, 70.0)
	var look := Vector3(player.p.x + player.v.x * Feel.look_ahead, player.p.y + player.v.y * Feel.look_ahead, 0)
	_cam_target = _cam_target.lerp(look + Vector3(0, dist * 0.08, dist), k)
	var off := Vector3.ZERO
	if _shake > 0.0:
		off = Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake_mag * Feel.shake
	cam.position = _cam_target + off
	cam.look_at(_cam_target - Vector3(0, dist * 0.08, dist) + off * 0.5, Vector3.UP)


# ---------------- fx ----------------
func shake(mag: float, t: float) -> void:
	_shake_mag = maxf(_shake_mag if _shake > 0.0 else 0.0, mag)
	_shake = maxf(_shake, t)


func burst(pos: Vector3, color: Color, n: int, speed: float) -> void:
	var ps := CPUParticles3D.new()
	ps.one_shot = true
	ps.explosiveness = 1.0
	ps.amount = maxi(1, n)
	ps.lifetime = 0.5
	ps.spread = 180.0
	ps.gravity = Vector3.ZERO
	ps.initial_velocity_min = speed * 0.3
	ps.initial_velocity_max = speed
	ps.damping_min = 4.0
	ps.damping_max = 6.0
	var q := Creature.sphere(0.06, 4, 2)
	q.material = Creature.mat(color, true)
	ps.mesh = q
	ps.scale_amount_min = 0.6
	ps.scale_amount_max = 1.4
	ps.position = pos
	add_child(ps)
	ps.emitting = true
	get_tree().create_timer(1.0).timeout.connect(ps.queue_free)


func _update_fx(dt: float) -> void:
	_shake = maxf(0.0, _shake - dt)
	if _toast_t > 0.0:
		_toast_t -= dt
		if _toast_t <= 0.0:
			_hud.toast.text = ""
	if _hint_t > 0.0:
		_hint_t -= dt
		if _hint_t <= 0.0:
			_hud.hint.text = ""
	_hud.hurt.modulate.a = maxf(0.0, _hud.hurt.modulate.a - dt * 3.0)
	for f in _hud.floats.get_children():
		f.position.y -= 40.0 * dt
		f.modulate.a -= dt * 1.1
		if f.modulate.a <= 0.0:
			f.queue_free()


# ---------------- sound (synthesized, no files) ----------------
func _sweep(f0: float, f1: float, dur: float, vol: float, noise_amt := 0.0) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var tt := float(i) / n
		var f := f0 * pow(f1 / f0, tt)
		phase += TAU * f / rate
		var env_v := minf(1.0, tt * 40.0) * pow(1.0 - tt, 2.0)
		var s := (sin(phase) * (1.0 - noise_amt) + randf_range(-1.0, 1.0) * noise_amt) * env_v * vol
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w


func _build_sounds() -> void:
	_sounds.gulp = _sweep(260.0, 45.0, 0.16, 0.6, 0.15)
	_sounds.whoosh = _sweep(500.0, 180.0, 0.25, 0.35, 0.8)
	_sounds.hurt = _sweep(110.0, 40.0, 0.32, 0.8, 0.3)
	_sounds.rumble = _sweep(55.0, 32.0, 1.4, 0.5, 0.1)


func _play(snd: String, pitch := 1.0) -> void:
	var a := AudioStreamPlayer.new()
	a.stream = _sounds[snd]
	a.pitch_scale = clampf(pitch, 0.3, 3.0)
	add_child(a)
	a.play()
	a.finished.connect(a.queue_free)


# ---------------- HUD ----------------
func _label(text: String, size: int, color := Color("d8eef5")) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _bar(color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(220, 8)
	b.show_percentage = false
	b.max_value = 100.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.08)
	b.add_theme_stylebox_override("fill", fill)
	b.add_theme_stylebox_override("background", bg)
	return b


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var hurt := ColorRect.new()
	hurt.color = Color(1.0, 0.24, 0.16, 0.25)
	hurt.set_anchors_preset(Control.PRESET_FULL_RECT)
	hurt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hurt.modulate.a = 0.0
	layer.add_child(hurt)
	_hud.hurt = hurt
	var left := VBoxContainer.new()
	left.position = Vector2(20, 16)
	layer.add_child(left)
	left.add_child(_label("能量", 13, Color("7f9bab")))
	_hud.energy = _bar(Color("5ff2d4"))
	left.add_child(_hud.energy)
	left.add_child(_label("生命", 13, Color("7f9bab")))
	_hud.hp = _bar(Color("ff6b5a"))
	left.add_child(_hud.hp)
	_hud.organs = _label("", 14)
	left.add_child(_hud.organs)
	var right := VBoxContainer.new()
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.offset_left = -220.0
	right.offset_right = -20.0
	right.offset_top = 16.0
	layer.add_child(right)
	_hud.stats = _label("", 14)
	_hud.stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_hud.stats)
	_hud.toast = _label("", 30, Color("5ff2d4"))
	_hud.toast.anchor_right = 1.0
	_hud.toast.offset_top = 170.0
	_hud.toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(_hud.toast)
	_hud.hint = _label("", 15, Color("9fb6c2"))
	_hud.hint.anchor_top = 1.0
	_hud.hint.anchor_bottom = 1.0
	_hud.hint.anchor_right = 1.0
	_hud.hint.offset_left = 60.0
	_hud.hint.offset_right = -60.0
	_hud.hint.offset_top = -80.0
	_hud.hint.offset_bottom = -24.0
	_hud.hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layer.add_child(_hud.hint)
	_hud.floats = Control.new()
	_hud.floats.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.floats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hud.floats)


func _update_hud() -> void:
	_hud.energy.value = player.energy
	_hud.hp.value = maxf(0.0, player.hp)
	var dash := ("冲刺" + (" (冷却)" if player.dash_cd > 0.0 else "")) if player.has_dash else "— 空 —"
	var glow := ("发光 " + ("开" if player.light_on else "关")) if player.has_light else "— 空 —"
	_hud.organs.text = "[%s]  [%s]" % [dash, glow]
	_hud.stats.text = "深度 %d m\n体长 %.1f mm\n吞噬 %d" % [int(-player.p.y * 20.0 / 3.0), player.r * 10.0, player.eaten]


func toast(text: String, t := 2.6) -> void:
	_hud.toast.text = text
	_toast_t = t


func hint(text: String, t := 4.0) -> void:
	_hud.hint.text = text
	_hint_t = t


func _float_text(text: String) -> void:
	for old in _hud.floats.get_children():
		old.queue_free()
	var l := _label(text, 22, Color("5ff2d4"))
	var sp := cam.unproject_position(Vector3(player.p.x, player.p.y + player.r * 2.0, 0))
	l.position = sp - Vector2(50, 20)
	_hud.floats.add_child(l)
