class_name RaidEnemy
extends CharacterBody3D

const RaidRules = preload("res://scripts/raid_rules.gd")

var world: RaidWorld
var target
var home := Vector3.ZERO
var elite := false
var health := 100.0
var dead := false
var decision := 0.0
var cooldown := 1.0
var alerted := 0.0
var path := PackedVector2Array()
var path_step := 1
var goal := Vector3.ZERO
var visual: Node3D
var muzzle: MeshInstance3D
var rifle: MeshInstance3D
var muzzle_time := 0.0
var walk_cycle := 0.0
var limbs: Array[Node3D] = []
var replica := false
var last_known := Vector3.ZERO
var reaction := 0.0
var rules: Dictionary = {}
var had_sight := false

func _ready() -> void:
	rules=RaidRules.guard(world.raid_mode if is_instance_valid(world) else "普通",elite)
	collision_layer = 2
	collision_mask = 1 | 4 | 2
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.34
	shape.height = 1.8
	collision.shape = shape
	collision.position.y = 0.9
	add_child(collision)
	visual = Node3D.new()
	add_child(visual)
	var cloth := Arsenal.material(Color("667363") if not elite else Color("6b6660"))
	var armor := Arsenal.material(Color("303c37"))
	var skin := Arsenal.material(Color("b09b82"))
	var dark := Arsenal.material(Color("1d292d"),0.4)
	Arsenal.box(visual,Vector3(0.54,0.6,0.3),Vector3(0,1.14,0),cloth)
	Arsenal.box(visual,Vector3(0.48,0.46,0.36),Vector3(0,1.18,-0.01),armor)
	Arsenal.box(visual,Vector3(0.28,0.29,0.26),Vector3(0,1.64,0),skin)
	Arsenal.box(visual,Vector3(0.35,0.15,0.33),Vector3(0,1.8,0),armor)
	Arsenal.box(visual,Vector3(0.28,0.1,0.04),Vector3(0,1.67,-0.14),dark)
	for x in [-0.17,0.17]:
		var leg := Node3D.new()
		leg.position = Vector3(x,0.85,0)
		visual.add_child(leg)
		Arsenal.box(leg,Vector3(0.23,0.72,0.25),Vector3(0,-0.34,0),cloth)
		Arsenal.box(leg,Vector3(0.23,0.14,0.34),Vector3(0,-0.77,-0.045),dark)
		limbs.append(leg)
	for x in [-0.36,0.36]:
		var arm := Arsenal.box(visual,Vector3(0.19,0.55,0.22),Vector3(x,1.18,-0.15),cloth)
		arm.rotation.x = -0.8
	rifle=Arsenal.box(visual,Vector3(0.085,0.11,0.7),Vector3(0.22,1.29,-0.45),dark)
	var glow := Arsenal.material(Color("ffca79"))
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	muzzle = Arsenal.box(visual,Vector3(0.12,0.12,0.18),Vector3(0.22,1.29,-0.85),glow)
	muzzle.visible = false
	health = float(rules.health)
	goal = home
	decision = randf_range(0,0.8)

func _physics_process(delta: float) -> void:
	if replica or dead or not is_instance_valid(target): return
	if not target.game.active_simulation(): return
	var game = target.game
	if game.session.running:
		var nearest: float=rules.sight
		var found
		for candidate in game.session.combatants():
			var d: float=global_position.distance_to(candidate.global_position)
			if d>nearest: continue
			var toward: Vector3=(candidate.global_position-global_position).normalized()
			if alerted<=0 and d>6 and (-visual.global_basis.z).dot(toward)<0.35: continue
			var ray:=PhysicsRayQueryParameters3D.create(global_position+Vector3.UP*1.55,candidate.global_position+Vector3.UP*1.2,1|2|4,[get_rid()])
			var result:=get_world_3d().direct_space_state.intersect_ray(ray)
			if not result.is_empty() and result.collider==candidate:
				found=candidate
				nearest=d
		if is_instance_valid(found):
			if target!=found:
				reaction=randf_range(rules.reaction.x,rules.reaction.y)
			target=found
		elif target.finished: return
	cooldown -= delta
	reaction -= delta
	decision -= delta
	muzzle_time -= delta
	muzzle.visible = muzzle_time > 0
	alerted = maxf(0,alerted-delta)
	var distance := global_position.distance_to(target.global_position)
	var see := false
	var in_view: bool=alerted>0 or distance<6 or (-visual.global_basis.z).dot((target.global_position-global_position).normalized())>0.35
	if distance < float(rules.sight) and (not game.session.running or in_view):
		var query := PhysicsRayQueryParameters3D.create(global_position+Vector3.UP*1.55,target.global_position+Vector3.UP*1.2,1|2|4,[get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		see = not hit.is_empty() and hit.collider == target
		if see:
			if not had_sight: reaction=randf_range(rules.reaction.x,rules.reaction.y)
			alerted = 6.0
			last_known=target.global_position
	had_sight=see
	if decision <= 0:
		decision = randf_range(rules.decision.x,rules.decision.y)
		if alerted > 0:
			goal = last_known
		elif global_position.distance_to(goal) < 3 or path.is_empty():
			goal = home+Vector3(randf_range(-7,7),0,randf_range(-7,7))
		path = world.path_between(global_position,goal)
		path_step = 1 if path.size()>1 else 0
	var movement := Vector3.ZERO
	if not (see and distance < 19) and path_step < path.size():
		var point := Vector3(path[path_step].x,global_position.y,path[path_step].y)
		if global_position.distance_to(point) < 1.2:
			path_step += 1
		else:
			movement = (point-global_position).normalized()
	var speed: float = rules.pursuit_speed if alerted > 0 else 1.6
	velocity.x = movement.x * speed
	velocity.z = movement.z * speed
	velocity.y -= 20 * delta
	move_and_slide()
	var facing: Vector3 = last_known-global_position if alerted>0 else movement
	if facing.length()>0.1:
		visual.rotation.y = lerp_angle(visual.rotation.y,atan2(-facing.x,-facing.z),delta*7)
	walk_cycle += delta * speed * 2.5
	for i in range(limbs.size()): limbs[i].rotation.x = sin(walk_cycle+i*PI)*0.43*movement.length()
	if see and cooldown <= 0 and reaction<=0 and distance < float(rules.combat_range):
		cooldown = randf_range(rules.interval.x,rules.interval.y)
		muzzle_time = 0.07
		target.game.enemy_shot(global_position+Vector3.UP*1.4,target.global_position+Vector3.UP*1.3)
		if randf() < clampf(0.67-distance*0.009+float(rules.accuracy_bonus),0.16,float(rules.accuracy_cap)):
			target.take_damage(randf_range(rules.damage.x,rules.damage.y),randf()<0.12)

func hear_noise(origin: Vector3) -> void:
	alerted=7
	last_known=origin+Vector3(randf_range(-3,3),0,randf_range(-3,3))

func take_hit(damage: float, point: Vector3) -> bool:
	if dead: return false
	alerted = 10
	var headshot := point.y-global_position.y > 1.48
	health -= damage*(2.2 if headshot else 1.0)
	if health <= 0:
		dead = true
		collision_layer = 0
		collision_mask = 0
		muzzle.visible = false
		var tween := create_tween()
		tween.tween_property(visual,"rotation:x",-PI/2,0.35)
		tween.parallel().tween_property(visual,"position:y",0.28,0.35)
	return dead
