class_name Player
extends Node3D
## The seed: a translucent larva that grows by devouring. Moves only in the plane z = 0.

var p := Vector2(45, -26)
var v := Vector2.ZERO
var ang := 0.0
var mass := 1.0
var r := 0.3
var energy := 100.0
var hp := 100.0
var has_dash := false
var has_light := false
var light_on := false
var dash_cd := 0.0
var noise := 0.0
var hurt_t := 0.0
var dead := 0.0
var eaten := 0
var squash := 0.0
var chomp := 0.0
var combo := 0
var combo_t := 0.0
var gulps: Array = []   # bulges travelling down the body: {pos, size}

var _body: Node3D
var _core_mat: StandardMaterial3D
var _body_mat: StandardMaterial3D
var _fins: Node3D
var _lure: MeshInstance3D
var _lure_mat: StandardMaterial3D
var light: OmniLight3D
var tail: Array[MeshInstance3D] = []


func _ready() -> void:
	_body = Node3D.new()
	add_child(_body)
	_body_mat = Creature.mat(Color("bfeeff"), false, 0.5)
	_body_mat.emission_enabled = true
	_body_mat.emission = Color("15434d")
	var body := MeshInstance3D.new()
	body.mesh = Creature.sphere(1.0, 20, 12)
	body.material_override = _body_mat
	_body.add_child(body)
	var core := MeshInstance3D.new()
	core.mesh = Creature.sphere(0.32)
	_core_mat = Creature.mat(Color("5ff2d4"), true)
	core.material_override = _core_mat
	core.position = Vector3(-0.25, 0, 0)
	_body.add_child(core)
	var eye := MeshInstance3D.new()
	eye.mesh = Creature.sphere(0.13, 6, 4)
	eye.material_override = Creature.mat(Color("eafcff"), true)
	eye.position = Vector3(0.45, 0.35, 0.75)
	_body.add_child(eye)
	_fins = Node3D.new()
	_fins.visible = false
	_body.add_child(_fins)
	var fin_mat := Creature.mat(Color("e6f2f6"), false, 0.6)
	for side in [-1.0, 1.0]:
		var fin := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.6, 0.8, 0.06)
		fin.mesh = pm
		fin.material_override = fin_mat
		fin.position = Vector3(-0.45, 0.75 * side, 0)
		fin.rotation.z = PI * 0.75 if side > 0 else PI * 0.25
		_fins.add_child(fin)
	_lure = MeshInstance3D.new()
	_lure.mesh = Creature.sphere(0.22, 8, 5)
	_lure_mat = Creature.mat(Color("f3c56b"), true)
	_lure.material_override = _lure_mat
	_lure.position = Vector3(1.3, 1.1, 0)
	_lure.visible = false
	_body.add_child(_lure)
	light = OmniLight3D.new()
	light.light_color = Color("9ff7ff")
	light.omni_range = 5.0
	light.light_energy = 1.2
	light.position = Vector3(0, 0, 1.5)
	add_child(light)
	for i in 8:
		var seg := MeshInstance3D.new()
		seg.mesh = Creature.sphere(1.0, 10, 6)
		seg.material_override = _body_mat
		seg.top_level = true
		add_child(seg)
		seg.global_position = Vector3(p.x - i * 0.15, p.y, 0)
		tail.append(seg)


func vision() -> float:
	return (21.0 + r * 3.0) if light_on else (7.5 + r * 3.2)


func reset_tail() -> void:
	for i in tail.size():
		tail[i].global_position = Vector3(p.x - i * 0.15, p.y, 0)


func try_dash(dir: Vector2) -> String:
	if dead > 0.0:
		return ""
	if not has_dash:
		return "还没有冲刺器官。找一条银色的箭鱼吞下去。"
	if dash_cd > 0.0 or energy < 12.0:
		return ""
	var a := dir.angle() if dir.length() > 0.01 else ang
	v += Vector2(cos(a), sin(a)) * Feel.dash_power
	ang = a
	dash_cd = Feel.dash_cooldown
	energy -= 12.0
	noise = 1.0
	return "ok"


func toggle_light() -> String:
	if dead > 0.0:
		return ""
	if not has_light:
		return "还没有发光器官。深一点的地方有发光水母。"
	light_on = not light_on
	return "ok"


func grow_from(c: Creature) -> void:
	var gain := pow(c.r / 0.3, 2.0) * 0.32 * Feel.growth
	mass = minf(110.0, mass + gain)


func update(dt: float, dir: Vector2, g) -> void:
	if dead > 0.0:
		return
	r = 0.3 * sqrt(mass)
	var size_k := r / 0.3
	var accel := Feel.accel * (1.0 + 0.15 * log(size_k))
	v += dir * accel * dt
	v *= exp(-Feel.drag * dt)
	var max_s := Feel.max_speed * (1.0 + 0.25 * log(size_k))
	var sp := v.length()
	if sp > max_s:
		v *= (max_s + (sp - max_s) * exp(-5.0 * dt)) / sp
	p += v * dt
	# bounds
	if p.y > -0.5 - r:
		p.y = -0.5 - r
		v.y = -absf(v.y) * 0.3
	var fy: float = g.floor_y(p.x) + r
	if p.y < fy:
		p.y = fy
		v.y = absf(v.y) * 0.3
	if p.x < r or p.x > g.WORLD_W - r:
		p.x = clampf(p.x, r, g.WORLD_W - r)
		v.x *= -0.3
	var want := dir.angle() if dir.length() > 0.01 else (v.angle() if sp > 1.25 else ang)
	var tr := Feel.turn_rate / (1.0 + 0.12 * (size_k - 1.0))
	ang += clampf(angle_difference(ang, want), -tr * dt, tr * dt)
	# timers and energy
	dash_cd = maxf(0.0, dash_cd - dt)
	noise = maxf(0.0, noise - dt * 0.8)
	hurt_t = maxf(0.0, hurt_t - dt)
	chomp = maxf(0.0, chomp - dt)
	squash = maxf(0.0, squash - dt * 5.0)
	combo_t = maxf(0.0, combo_t - dt)
	for i in range(gulps.size() - 1, -1, -1):
		gulps[i]["pos"] += dt * 3.2
		if gulps[i]["pos"] > 1.1:
			gulps.remove_at(i)
	energy -= (0.9 + (3.2 if light_on else 0.0)) * dt
	if energy <= 0.0:
		energy = 0.0
		if light_on:
			light_on = false
			g.hint("能量耗尽，光熄灭了。", 2.5)
		hp -= 6.0 * dt
		if hp <= 0.0:
			g.die()
	elif energy > 50.0:
		hp = minf(100.0, hp + 2.5 * dt)
	_eat_and_bump(dt, g)
	_visuals(dt, sp)


func _eat_and_bump(dt: float, g) -> void:
	var mouth := p + Vector2(cos(ang), sin(ang)) * r * 0.9
	var reach := r * 0.55 * Feel.bite_reach
	for c: Creature in g.creatures.duplicate():
		if not c.alive:
			continue
		var d := c.p - mouth
		if absf(d.x) > 10.0 or absf(d.y) > 10.0:
			continue
		var dist := maxf(d.length(), 0.001)
		var edible := c.r < r * 0.92 and c.in_play_plane()
		if edible:
			if dist < reach + c.r:
				g.eat(c)
			elif dist < r * 3.0 + c.r and Feel.suction > 0.0:
				# suction: prey in front of the mouth gets pulled in
				var front := cos(angle_difference(ang, d.angle()))
				if front > 0.3:
					var k := Feel.suction * 26.0 * front * (1.0 - dist / (r * 3.0 + c.r)) * dt
					c.v -= d / dist * k
					c.p -= d / dist * k * dt * 8.0
		elif c.type == "pred" and c.in_play_plane() and c.state != "retreat":
			if (c.p - p).length() < c.r * 0.85 + r * 0.8 and c.cd <= 0.0 and c.r > r * 1.05:
				g.hurt(24.0, c.p)
				c.cd = 1.1
				c.st = Feel.chase_give_up
				c.v *= -0.3


func _visuals(dt: float, sp: float) -> void:
	position = Vector3(p.x, p.y, 0)
	var sq := squash
	_body.scale = Vector3(r * (1.0 + sq * 0.22), r * (1.0 - sq * 0.16), r * (1.0 - sq * 0.16))
	_body.rotation = Vector3(sin(Time.get_ticks_msec() * 0.002) * 0.15, 0, ang)
	_fins.visible = has_dash
	_lure.visible = has_light
	_lure_mat.emission_energy_multiplier = 4.0 if light_on else 0.4
	_core_mat.emission_energy_multiplier = 2.5 + chomp * 40.0
	light.omni_range = vision() * 0.9
	light.light_energy = 1.6 if light_on else 1.0
	light.light_color = Color("ffe2a8") if light_on else Color("9ff7ff")
	visible = not (hurt_t > 0.0 and int(Time.get_ticks_msec() / 50) % 2 == 0)
	# tail chain with a swimming wiggle and gulp bulges
	var seg := r * 0.62
	var prev := Vector3(p.x - cos(ang) * r * 0.6, p.y - sin(ang) * r * 0.6, 0)
	var wig := sin(Time.get_ticks_msec() * 0.001 * (8.0 + sp * 1.0)) * minf(1.0, sp / 6.0) * r * 0.18
	var n := tail.size()
	for i in n:
		var m := tail[i]
		var k := 1.0 - float(i) / n
		var tp := m.global_position + Vector3(-sin(ang), cos(ang), 0) * wig * (float(i) / n) * 0.5
		var dd := tp - prev
		dd.z = 0
		var l := maxf(dd.length(), 0.0001)
		m.global_position = prev + dd / l * seg
		var bulge := 0.0
		for gq in gulps:
			bulge += gq["sz"] * maxf(0.0, 1.0 - absf(gq["pos"] - float(i) / n) * 6.0)
		m.scale = Vector3.ONE * r * (0.25 + k * 0.55 + bulge * 0.7)
		m.visible = visible
		prev = m.global_position
