class_name Creature
extends Node3D
## Every non-player creature. Gameplay happens in the plane z = 0;
## predators can sink to the background layer (z < 0) where they cannot bite.

static var TYPES := {
	"plankton": {"r": [0.08, 0.13], "spd": 0.9, "color": Color("9ff7ff"), "glow": true, "food": 3.0, "depth": [0.0, 160.0]},
	"minnow": {"r": [0.16, 0.33], "spd": 7.5, "color": Color("b9cfd9"), "food": 9.0, "depth": [5.0, 75.0]},
	"shrimp": {"r": [0.18, 0.28], "spd": 3.0, "color": Color("e8907a"), "food": 7.0, "depth": [35.0, 135.0]},
	"jelly": {"r": [0.45, 0.6], "spd": 1.1, "color": Color("5ff2d4"), "glow": true, "food": 12.0, "depth": [25.0, 120.0], "organ": "light"},
	"dart": {"r": [0.4, 0.5], "spd": 12.5, "color": Color("e9f2f6"), "food": 14.0, "depth": [10.0, 90.0], "organ": "dash"},
	"pred": {"r": [1.2, 1.7], "spd": 8.75, "color": Color("5d6f7a"), "food": 40.0, "depth": [25.0, 140.0]},
}

var type := "plankton"
var info: Dictionary
var r := 0.1
var p := Vector2.ZERO        # position in the play plane (x right, y up)
var v := Vector2.ZERO
var z := 0.0
var ang := 0.0
var t := 0.0
var wob := 0.0
var state := "wander"
var st := 0.0
var stamina := 1.0
var cd := 0.0
var school := 0
var alive := true

var _tail: Node3D
var _eye: MeshInstance3D
var _eye_mat: StandardMaterial3D
var _bell: Node3D


func setup(kind: String, pos: Vector2, school_id := 0) -> void:
	type = kind
	info = TYPES[kind]
	r = randf_range(info.r[0], info.r[1])
	p = pos
	school = school_id
	ang = randf() * TAU
	t = randf() * 10.0
	wob = randf() * TAU
	if kind == "pred":
		z = Feel.BACK_Z
	_build()
	_apply_transform()


static func mat(color: Color, glow := false, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, alpha)
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if glow:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 2.5
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	else:
		m.roughness = 0.55
		m.metallic = 0.15
	return m


static func sphere(radius: float, segs := 10, rings := 6) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = segs
	s.rings = rings
	return s


static func fish_mesh(parent: Node3D, radius: float, color: Color) -> Node3D:
	var m := mat(color)
	var body := MeshInstance3D.new()
	body.mesh = sphere(1.0)
	body.material_override = m
	body.scale = Vector3(1.25, 0.6, 0.42) * radius
	parent.add_child(body)
	var tail := Node3D.new()
	tail.position = Vector3(-radius * 1.1, 0, 0)
	parent.add_child(tail)
	var fin := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(radius * 1.1, radius * 0.9, radius * 0.12)
	fin.mesh = prism
	fin.material_override = m
	fin.rotation.z = -PI / 2.0
	fin.position = Vector3(-radius * 0.45, 0, 0)
	tail.add_child(fin)
	return tail


func _build() -> void:
	var c: Color = info.color
	match type:
		"plankton":
			var m := MeshInstance3D.new()
			m.mesh = sphere(r, 6, 3)
			m.material_override = mat(c, true)
			add_child(m)
		"jelly":
			_bell = Node3D.new()
			add_child(_bell)
			var bell := MeshInstance3D.new()
			var s := sphere(r, 12, 6)
			s.is_hemisphere = true
			bell.mesh = s
			bell.material_override = mat(c, true, 0.65)
			_bell.add_child(bell)
			for k in 5:
				var tc := MeshInstance3D.new()
				var cyl := CylinderMesh.new()
				cyl.top_radius = 0.025
				cyl.bottom_radius = 0.01
				cyl.height = r * 2.2
				cyl.radial_segments = 4
				tc.mesh = cyl
				tc.material_override = bell.material_override
				tc.position = Vector3((k - 2) * r * 0.35, -r * 1.1, 0)
				add_child(tc)
			var light := OmniLight3D.new()
			light.light_color = c
			light.omni_range = 4.0
			light.light_energy = 0.8
			add_child(light)
		"shrimp":
			var m := MeshInstance3D.new()
			var cap := CapsuleMesh.new()
			cap.radius = r * 0.35
			cap.height = r * 1.8
			m.mesh = cap
			m.material_override = mat(c)
			m.rotation.z = PI / 2.0
			add_child(m)
		_:
			_tail = fish_mesh(self, r, c)
			if type == "pred":
				# bone plates and a dorsal fin, the abyss-reconstruction look
				var bone := mat(Color("cfc6a8"))
				for k in 4:
					var plate := MeshInstance3D.new()
					var tm := TorusMesh.new()
					tm.inner_radius = r * 0.5
					tm.outer_radius = r * 0.58
					tm.rings = 10
					tm.ring_segments = 4
					plate.mesh = tm
					plate.material_override = bone
					plate.rotation.z = PI / 2.0
					plate.position = Vector3(r * 0.3 - k * r * 0.4, 0, 0)
					add_child(plate)
				var dorsal := MeshInstance3D.new()
				var pm := PrismMesh.new()
				pm.size = Vector3(r * 0.7, r * 0.7, r * 0.1)
				dorsal.mesh = pm
				dorsal.material_override = mat(c)
				dorsal.position = Vector3(-r * 0.2, r * 0.75, 0)
				add_child(dorsal)
				_eye = MeshInstance3D.new()
				_eye.mesh = sphere(r * 0.11, 6, 4)
				_eye_mat = mat(Color("d9e3e8"), true)
				_eye.material_override = _eye_mat
				_eye.position = Vector3(r * 1.0, r * 0.18, r * 0.3)
				add_child(_eye)


func _apply_transform() -> void:
	position = Vector3(p.x, p.y, z)
	var f := Vector2(cos(ang), sin(ang))
	if type == "jelly" or type == "plankton":
		return
	var up := Vector2(-f.y, f.x) if f.x >= 0.0 else Vector2(f.y, -f.x)
	var x3 := Vector3(f.x, f.y, 0)
	var y3 := Vector3(up.x, up.y, 0)
	basis = Basis(x3, y3, x3.cross(y3))


func update(dt: float, g) -> void:
	t += dt
	cd = maxf(0.0, cd - dt)
	var pl = g.player
	var d: Vector2 = pl.p - p
	var dist := maxf(d.length(), 0.001)
	if dist > 120.0 and type != "pred":
		return
	var bigger: bool = pl.r > r * 1.08 and not pl.dead
	var noise_r: float = pl.noise * 13.0
	var a := Vector2.ZERO
	var spd: float = info.spd
	wob += dt * randf_range(-1.5, 1.5)
	match type:
		"plankton":
			a = Vector2(cos(wob), sin(wob)) * 0.5 + Vector2(0, 0.1)
			if pl.light_on and dist < 16.0:
				a += d / dist * 3.5
				spd = 2.75
		"minnow":
			var sc = g.school_center.get(school)
			if sc:
				a += (sc.p / sc.n - p) * 1.4 + (sc.v / sc.n) * 0.8
			a += Vector2(cos(wob) * 3.0, sin(wob) * 2.0)
			if bigger and dist < 7.5 + noise_r:
				a -= d / dist * 45.0
				spd = 8.25
		"shrimp":
			a = Vector2(cos(wob), sin(wob)) * 0.75
			if bigger and dist < 4.25 + noise_r * 0.5 and cd <= 0.0:
				v -= d / dist * 16.5
				cd = 1.4
				spd = 20.0
			if cd > 1.0:
				spd = 20.0
		"jelly":
			var pulse := maxf(0.0, sin(t * 2.2))
			a = Vector2(cos(wob) * 0.3, pulse * 2.0 - 0.4)
			if _bell:
				_bell.scale = Vector3(1.0 + pulse * 0.15, 1.0 - pulse * 0.1, 1.0 + pulse * 0.15)
		"dart":
			a = Vector2(cos(wob) * 2.0, sin(wob) * 1.25)
			if state == "tired":
				spd = 2.75
				st -= dt
				if st <= 0.0:
					state = "wander"
					stamina = 1.0
			elif bigger and dist < 11.5 + noise_r:
				a -= d / dist * 70.0
				stamina -= dt * 0.45
				if stamina <= 0.0:
					state = "tired"
					st = 1.8
			else:
				stamina = minf(1.0, stamina + dt * 0.3)
		"pred":
			a = _predator(dt, g, d, dist)
			spd = _pred_speed
	# keep each species in its depth band
	var depth := -p.y
	if depth < info.depth[0]:
		a.y -= 3.0
	if depth > info.depth[1]:
		a.y += 3.0
	v += a * dt
	var s := v.length()
	if s > spd:
		v *= (spd + (s - spd) * exp(-4.0 * dt)) / s
	v *= exp(-0.6 * dt)
	p += v * dt
	if state != "notice" and s > 0.25:
		ang += clampf(angle_difference(ang, v.angle()), -5.0 * dt, 5.0 * dt)
	# bounds: surface, sea floor, world edges
	if p.y > -0.75:
		p.y = -0.75
		v.y = -absf(v.y)
	var fy: float = g.floor_y(p.x) + r
	if p.y < fy:
		p.y = fy
		v.y = absf(v.y)
	p.x = clampf(p.x, 1.0, g.WORLD_W - 1.0)
	if _tail:
		_tail.rotation.y = sin(t * (8.0 + s)) * 0.5
	_apply_transform()


var _pred_speed := 0.0

func _predator(dt: float, g, d: Vector2, dist: float) -> Vector2:
	var pl = g.player
	var detect: float = 11.5 * (1.9 if pl.light_on else 1.0) + pl.noise * 13.0
	var threat: bool = r > pl.r * 1.05 and not pl.dead
	var a := Vector2.ZERO
	_pred_speed = info.spd
	var target_z := 0.0
	match state:
		"wander":
			a = Vector2(cos(wob) * 2.5, sin(wob) * 1.5)
			_pred_speed = info.spd * 0.35
			if threat and dist < detect and pl.hurt_t <= 0.0:
				state = "notice"
				st = 0.8
			elif not threat and dist < 13.0:
				state = "flee"
				st = 3.0
		"notice":
			# readable warning: stops, turns to face the player, rises into the play plane
			_pred_speed = 1.0
			st -= dt
			ang += clampf(angle_difference(ang, d.angle()), -6.0 * dt, 6.0 * dt)
			if st <= 0.0:
				state = "chase"
				st = Feel.chase_give_up
		"chase":
			st -= dt
			a = d / dist * 35.0
			if st <= 0.0 and threat:
				state = "retreat"
				st = Feel.retreat_time
			elif not threat or dist > 32.0:
				state = "wander"
		"retreat":
			st -= dt
			_pred_speed = info.spd * 0.5
			a = -d / dist * 25.0 if st > Feel.retreat_time - 1.5 else Vector2(cos(wob) * 2.5, sin(wob) * 1.5)
			if st <= 0.0:
				state = "wander"
		"flee":
			st -= dt
			a = -d / dist * 35.0
			_pred_speed = info.spd * 0.85
			if st <= 0.0:
				state = "wander"
	# layer: wandering and retreating predators live in the background; they rise to bite
	if state == "wander" or state == "retreat":
		target_z = Feel.BACK_Z
	if state == "flee":
		target_z = z
	z = lerpf(z, target_z, 1.0 - exp(-(2.5 if state == "notice" else 0.8) * dt))
	if _eye_mat:
		var hot := state == "notice" or state == "chase"
		_eye_mat.albedo_color = Color("ff6b5a") if hot else Color("d9e3e8")
		_eye_mat.emission = _eye_mat.albedo_color
		_eye_mat.emission_energy_multiplier = 4.0 if hot else 0.6
	return a


func in_play_plane() -> bool:
	return absf(z) < 1.5
