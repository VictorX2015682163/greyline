extends Node
## A simulated participant uses the same character, ammunition, damage and loot
## rules as people. Perception remembers observations, never an unseen position.

const RaidRules = preload("res://scripts/raid_rules.gd")
const WeaponModsData = preload("res://scripts/weapon_mods.gd")

const NAMES := ["今晚早点撤","Kite_07","路过的阿北","半糖乌龙","NorthWind","港口搬运工","余温","Echo_19","山海之间","空弹匣"]
const STYLES := ["谨慎","突击","搜刮","游走","谨慎","搜刮"]
var session
var actor: RaidPlayer
var personality := "谨慎"
var rng:=RandomNumberGenerator.new()
var think_left := 0.0
var scan_left := 0.0
var reaction_left := 0.0
var visible_target
var last_seen := Vector3.ZERO
var memory_left := 0.0
var heard_at := Vector3.ZERO
var heard_left := 0.0
var goal := Vector3.ZERO
var path := PackedVector2Array()
var path_step := 0
var chest_index := -1
var searched: Dictionary = {}
var state := "route"
var state_left := 0.0
var burst_left := 0.0
var burst_pause := 0.0
var aim_error := Vector2.ZERO
var aim_left := 0.0
var last_health := 100.0
var stuck_left := 0.0
var previous_position := Vector3.ZERO
var extraction_goal := -1
var click_serial := 0
var prefer_left := false
var hearing_left := 0.0
var rules: Dictionary = {}

static func profile(index: int, mode: String) -> Dictionary:
	var classified:=mode=="机密"
	var weapon_choices: Array=[5,6,7,0,1,6] if classified else [0,1,2,3,5,6]
	var tier:=4+index%2 if classified else 1+index%2
	var armor_id: String="armor_%d" % tier if tier<3 else "armor_%d_%s" % [tier,"light" if index%2 else "durable"]
	var helmet_id: String="helmet_%d" % tier if tier<3 else "helmet_%d_%s" % [tier,"hearing" if index%2 else "heavy"]
	var weapon: int=weapon_choices[index%weapon_choices.size()]
	var builds: Dictionary={}
	if classified:
		builds[str(weapon)]=WeaponModsData.sanitize(weapon,{
			"optic":"scope_8x" if weapon==7 else "scope_4x",
			"muzzle":"suppressor" if weapon==7 else "compensator",
			"grip":"grip_vertical", "stock":"stock_stable",
			"magazine":"mag_quick", "barrel":"barrel_long",
		})
	return {"name":NAMES[index%NAMES.size()],"bot":true,"personality":STYLES[index%STYLES.size()],"builds":builds,"loadout":{"weapon":weapon,"armor":armor_id,"helmet":helmet_id,"ammo_packs":randi_range(3,4) if classified else randi_range(1,3),"medkits":randi_range(3,4) if classified else randi_range(1,3)}}

func _ready() -> void:
	rules=RaidRules.bot(session.game.raid_mode)
	rng.randomize()
	think_left=rng.randf_range(0.1,0.9)
	prefer_left=rng.randf()>0.5
	previous_position=actor.position
	goal=actor.position
	last_health=actor.health

func _physics_process(delta: float) -> void:
	if not session.running or actor.finished: return
	think_left-=delta
	scan_left-=delta
	reaction_left-=delta
	memory_left=maxf(0,memory_left-delta)
	heard_left=maxf(0,heard_left-delta)
	state_left-=delta
	burst_left-=delta
	burst_pause-=delta
	aim_left-=delta
	hearing_left-=delta
	if hearing_left<=0:
		hearing_left=rng.randf_range(0.35,0.65)
		listen_for_steps()
	if scan_left<=0:
		scan_left=rng.randf_range(rules.scan.x,rules.scan.y)
		perceive()
	if actor.health<last_health:
		if state!="cover":
			choose_cover(last_seen if memory_left>0 else heard_at)
			state="cover"
			state_left=rng.randf_range(2.0,4.5)
		actor.heal_left=0
	last_health=actor.health
	if think_left<=0:
		think_left=rng.randf_range(rules.decision.x,rules.decision.y)
		decide()
	var direction:=follow_path(delta)
	var yaw:=actor.rotation.y
	var pitch:=actor.pitch
	var fire:=false
	var aiming:=is_instance_valid(visible_target) and memory_left>0
	if aiming:
		# Aim toward the last visual observation with finite turn speed and drift.
		if aim_left<=0:
			aim_left=rng.randf_range(0.16,0.38)
			var distance:=actor.position.distance_to(last_seen)
			var error: float=rules.aim_base+distance*rules.aim_distance+(0.025 if actor.health<45 else 0.0)
			aim_error=Vector2(rng.randfn(0,error),rng.randfn(0,error*0.65))
		var toward:=last_seen+Vector3.UP*1.24-actor.camera.global_position
		var wanted_yaw:=atan2(-toward.x,-toward.z)+aim_error.x
		var wanted_pitch:=atan2(toward.y,Vector2(toward.x,toward.z).length())+aim_error.y
		yaw=rotate_toward(yaw,wanted_yaw,delta*rng.randf_range(rules.turn.x,rules.turn.y))
		pitch=move_toward(pitch,wanted_pitch,delta*float(rules.pitch_speed))
		if reaction_left<=0 and absf(angle_difference(yaw,wanted_yaw))<0.09 and actor.reload_left<=0 and actor.heal_left<=0:
			if burst_pause<=0:
				if burst_left<=0: burst_left=rng.randf_range(rules.burst.x,rules.burst.y)
				fire=has_line_of_sight(visible_target)
				if burst_left<delta*2:
					burst_pause=rng.randf_range(rules.pause.x,rules.pause.y)
					burst_left=0
		if personality=="谨慎" and actor.position.distance_to(last_seen)<13 and actor.health<65:
			direction=(actor.position-last_seen).normalized()
	else:
		var facing:=direction
		if heard_left>0 and direction.length()<0.1: facing=heard_at-actor.position
		if facing.length()>0.1: yaw=rotate_toward(yaw,atan2(-facing.x,-facing.z),delta*1.9)
		pitch=move_toward(pitch,0,delta*0.8)
	if state in ["loot","observe"] or actor.heal_left>0: direction=Vector3.ZERO
	var local: Vector3=Basis(Vector3.UP,yaw).inverse()*direction
	if fire: click_serial+=1
	actor.remote_input={"move":Vector2(local.x,local.z).limit_length(),"yaw":yaw,"pitch":pitch,"aim":aiming,"fire":fire,"click":click_serial,"sprint":not aiming and state not in ["loot","observe"] and actor.stamina>25 and direction.length()>0.1,"jump":false}

func perceive() -> void:
	var best
	var best_distance: float=rules.sight
	var candidates: Array=session.combatants()+session.game.world.enemies
	for candidate in candidates:
		if candidate==actor: continue
		if candidate is RaidEnemy and candidate.dead: continue
		var toward: Vector3=candidate.position-actor.position
		var distance:=toward.length()
		if distance>best_distance: continue
		var forward: Vector3=-actor.global_basis.z
		# Peripheral vision is limited; close movement is easier to notice.
		if distance>7 and forward.dot(toward.normalized())<0.42: continue
		if not has_line_of_sight(candidate): continue
		best=candidate
		best_distance=distance
	if is_instance_valid(best):
		if visible_target!=best:
			reaction_left=rng.randf_range(rules.reaction.x,rules.reaction.y)+(0.15 if personality=="搜刮" else 0.0)
		visible_target=best
		last_seen=best.position
		memory_left=rng.randf_range(3.0,5.5)
	else: visible_target=null

func has_line_of_sight(candidate) -> bool:
	if not is_instance_valid(candidate): return false
	var ray:=PhysicsRayQueryParameters3D.create(actor.position+Vector3.UP*1.55,candidate.position+Vector3.UP*1.25,1|2|4,[actor.get_rid()])
	var hit:=actor.get_world_3d().direct_space_state.intersect_ray(ray)
	return not hit.is_empty() and hit.collider==candidate

func hear_noise(origin: Vector3, radius: float) -> void:
	if actor.finished or actor.position.distance_to(origin)>radius*actor.hearing or actor.position.distance_to(origin)<1: return
	var ray:=PhysicsRayQueryParameters3D.create(actor.camera.global_position,origin+Vector3.UP,1)
	if not actor.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): radius*=0.55
	if actor.position.distance_to(origin)>radius*actor.hearing: return
	# Hearing gives an uncertain area; it cannot grant line of sight or a target.
	heard_at=origin+Vector3(rng.randf_range(-5,5),0,rng.randf_range(-5,5))
	heard_left=rng.randf_range(3,6)

func listen_for_steps() -> void:
	for other in session.combatants()+session.game.world.enemies:
		if other==actor or (other is RaidEnemy and other.dead): continue
		var speed:=Vector2(other.velocity.x,other.velocity.z).length()
		if speed<0.8: continue
		var radius:=20.0 if speed>5 else 12.0
		if actor.position.distance_to(other.position)<radius*actor.hearing:
			hear_noise(other.position,radius)
			if heard_left>0: return

func decide() -> void:
	if actor.ammo==0 or (not is_instance_valid(visible_target) and actor.ammo<int(actor.weapon.magazine)*0.45): actor.reload_weapon()
	if actor.health<65 and actor.meds>0 and not is_instance_valid(visible_target) and state=="cover": actor.heal()
	var should_extract: bool=actor.health<32 or actor.reserve<5 or actor.weight()>actor.capacity*0.7 or actor.loot_value()>(9000 if personality=="搜刮" else 14000) or session.game.raid_left<rng.randf_range(100,190)
	if should_extract:
		state="extract"
		if extraction_goal<0:
			extraction_goal=0
			if session.game.RAID_LENGTH-session.game.raid_left>=60 and actor.position.distance_to(RaidWorld.EXITS[1])<actor.position.distance_to(RaidWorld.EXITS[0]): extraction_goal=1
		set_goal(RaidWorld.EXITS[extraction_goal])
		return
	if state=="cover" and state_left>0: return
	if is_instance_valid(visible_target):
		state="fight"
		session.searches.erase(actor.network_id)
		var distance:=actor.position.distance_to(last_seen)
		if distance<30:
			# Short lateral changes and peeking; no perfectly fixed strafe rhythm.
			var side: Vector3=(last_seen-actor.position).cross(Vector3.UP).normalized()*(1 if prefer_left else -1)
			set_goal(actor.position+side*rng.randf_range(2,5))
			if rng.randf()<0.3: prefer_left=not prefer_left
		else: set_goal(last_seen+Vector3(rng.randf_range(-4,4),0,rng.randf_range(-4,4)))
		return
	if memory_left>0:
		state="investigate"
		set_goal(last_seen+Vector3(rng.randf_range(-4,4),0,rng.randf_range(-4,4)))
		return
	if heard_left>0 and personality in ["突击","游走"]:
		state="investigate"
		set_goal(heard_at)
		return
	if state=="loot" and chest_index>=0:
		var chest: Node3D=session.game.world.loot[chest_index]
		if actor.position.distance_to(chest.position)>3:
			state="route"
			set_loot_goal(chest)
			return
		var contents: Array=chest.get_meta("items")
		if contents.is_empty() or actor.weight()>actor.capacity*0.8:
			searched[chest_index]=true
			session.searches.erase(actor.network_id)
			chest_index=-1
			state="observe"
			state_left=rng.randf_range(0.7,2.0)
			return
		if state_left<=0 and int(chest.get_meta("revealed"))>0:
			var selected:=-1
			var best_value:=-INF
			for i in range(mini(int(chest.get_meta("revealed")),contents.size())):
				var item: Dictionary=contents[i]
				if not actor.can_store(item): continue
				var value:=float(item.value)/maxf(0.25,float(item.weight))
				if value>best_value:
					best_value=value
					selected=i
			if selected>=0:
				var item: Dictionary=contents[selected]
				session.perform_item(actor.network_id,"take","loot",selected,str(item.get("net_uid","")))
			elif int(chest.get_meta("revealed"))>=contents.size():
				# Leave what cannot fit for other participants instead of stalling.
				searched[chest_index]=true
				session.searches.erase(actor.network_id)
				chest_index=-1
				state="observe"
			state_left=rng.randf_range(0.35,1.1)
		return
	if state=="observe" and state_left>0: return
	if chest_index>=0 and actor.position.distance_to(session.game.world.loot[chest_index].position)<2.8:
		session._open_search(actor.network_id,chest_index)
		if session.searches.has(actor.network_id):
			state="loot"
			state_left=rng.randf_range(0.6,1.6)
		else:
			searched[chest_index]=true
			chest_index=-1
		return
	if chest_index<0 or path_step>=path.size(): choose_loot_route()

func choose_loot_route() -> void:
	var score:=INF
	chest_index=-1
	for i in range(session.game.world.loot.size()):
		var chest: Node3D=session.game.world.loot[i]
		if searched.has(i) or chest.get_meta("searched"): continue
		var cost:=actor.position.distance_to(chest.position)*rng.randf_range(0.75,1.3)
		if personality=="搜刮": cost/=maxf(1,float(chest.get_meta("tier")))
		if cost<score:
			score=cost
			chest_index=i
	if chest_index>=0:
		state="route"
		var chest: Node3D=session.game.world.loot[chest_index]
		set_loot_goal(chest)
	else:
		state="extract"
		extraction_goal=0
		set_goal(RaidWorld.EXITS[0])

func choose_cover(threat: Vector3) -> void:
	var best:=actor.position
	var score:=INF
	for i in range(16):
		var angle:=rng.randf_range(-PI,PI)
		var candidate:=actor.position+Vector3(cos(angle),0,sin(angle))*rng.randf_range(4,11)
		var cell: Vector2i=session.game.world.free_cell(candidate)
		candidate=Vector3(cell.x*2,actor.position.y,cell.y*2)
		var ray:=PhysicsRayQueryParameters3D.create(threat+Vector3.UP*1.4,candidate+Vector3.UP*1.3,1)
		var hit:=actor.get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty(): continue
		var cost:=actor.position.distance_to(candidate)
		if cost<score:
			score=cost
			best=candidate
	set_goal(best)

func set_goal(point: Vector3) -> void:
	goal=point
	path=session.game.world.path_between(actor.position,point)
	path_step=1 if path.size()>1 else 0

func set_loot_goal(chest: Node3D) -> void:
	# The coarse grid leaves a safety border around crates. Finish the route
	# with a capsule-checked approach so agents can actually reach search range.
	var best:=INF
	var approach:=chest.position
	var best_path:=PackedVector2Array()
	var shape:=CapsuleShape3D.new()
	shape.radius=0.38
	shape.height=1.7
	var space:=actor.get_world_3d().direct_space_state
	for x in range(-4,5):
		for z in range(-4,5):
			var cell:=Vector2i(roundi(chest.position.x/2)+x,roundi(chest.position.z/2)+z)
			var grid=session.game.world.navigation
			if not grid.is_in_boundsv(cell) or grid.is_point_solid(cell): continue
			var point:=Vector3(cell.x*2,actor.position.y,cell.y*2)
			if point.distance_to(chest.position)>8: continue
			var away:=Vector3(point.x-chest.position.x,0,point.z-chest.position.z).normalized()
			var destination:=Vector3(chest.position.x,actor.position.y,chest.position.z)+away*2.1
			var sweep:=PhysicsShapeQueryParameters3D.new()
			sweep.shape=shape
			sweep.collision_mask=1
			sweep.transform=Transform3D(Basis.IDENTITY,point+Vector3.UP*0.9)
			sweep.motion=destination-point
			if space.cast_motion(sweep)[0]<0.99: continue
			var ray:=PhysicsRayQueryParameters3D.create(destination+Vector3.UP*1.55,chest.position,1)
			var hit:=space.intersect_ray(ray)
			if not hit.is_empty() and not chest.is_ancestor_of(hit.collider): continue
			var route: PackedVector2Array=session.game.world.path_between(actor.position,point)
			if route.is_empty(): continue
			var cost:=point.distance_to(destination)
			for i in range(1,route.size()): cost+=route[i-1].distance_to(route[i])
			if cost<best:
				best=cost
				approach=destination
				best_path=route
	if best_path.is_empty():
		searched[chest_index]=true
		chest_index=-1
		return
	goal=approach
	path=best_path
	path.append(Vector2(approach.x,approach.z))
	path_step=1 if path.size()>1 else 0

func follow_path(delta: float) -> Vector3:
	stuck_left+=delta
	if stuck_left>2.0:
		if actor.position.distance_to(previous_position)<0.6 and state not in ["loot","observe"]:
			if chest_index>=0:
				searched[chest_index]=true
				chest_index=-1
			set_goal(goal+Vector3(rng.randf_range(-3,3),0,rng.randf_range(-3,3)))
		previous_position=actor.position
		stuck_left=0
	if path_step>=path.size(): return Vector3.ZERO
	var point:=Vector3(path[path_step].x,actor.position.y,path[path_step].y)
	if actor.position.distance_to(point)<0.85:
		path_step+=1
		return Vector3.ZERO
	return (point-actor.position).normalized()
