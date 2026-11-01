class_name RaidPlayer
extends CharacterBody3D

const WeaponModsData = preload("res://scripts/weapon_mods.gd")
const ItemsData = preload("res://scripts/items.gd")
const EquipmentData = preload("res://scripts/equipment.gd")

var game
var camera: Camera3D
var weapon_root: Node3D
var gun: Node3D
var muzzle: MeshInstance3D
var weapon: Dictionary
var weapon_index := 0
var health := 100.0
var armor := 0.0
var armor_cap := 0.0
var helmet := 0.0
var helmet_cap := 0.0
var armor_tier := 0
var helmet_tier := 0
var body_reduction := 0.0
var head_reduction := 0.0
var speed_penalty := 0.0
var stamina_penalty := 0.0
var aim_penalty := 0.0
var hearing := 1.0
var sound_cue := ""
var sound_left := 0.0
var hearing_scan := 0.0
var stamina := 100.0
var ammo := 30
var reserve := 150
var meds := 2
var reload_left := 0.0
var heal_left := 0.0
var fire_cooldown := 0.0
var pitch := 0.0
var recoil := 0.0
var hit_flash := 0.0
var shot_flash := 0.0
var damage_flash := 0.0
var aimed := false
var sprinting := false
var step_time := 0.0
var queued_shot := false
var capture_grace := 0.0
var inventory: Array = []
var safe_inventory: Array = []
var safe_box_id := "safe_1x2"
var safe_columns := 1
var safe_rows := 2
var raid_season := ""
var bag_columns := 6
var bag_rows := 4
var capacity := 20.0
var gear_weight := 0.0
var network_id := 1
var is_local := true
var finished := false
var remote_input: Dictionary = {}
var trigger_sequence := 0
var consumed_trigger := 0
var raid_kills := 0
var raid_shots := 0
var body_model
var snapshot_position := Vector3.ZERO
var snapshot_yaw := 0.0
var has_snapshot := false

func configure_protection(loadout: Dictionary) -> void:
	var body:=EquipmentData.gear_item(str(loadout.get("armor","")))
	var head:=EquipmentData.gear_item(str(loadout.get("helmet","")))
	armor_cap=float(body.get("armor",0))
	helmet_cap=float(head.get("armor",0))
	armor=armor_cap
	helmet=helmet_cap
	armor_tier=int(body.get("tier",0))
	helmet_tier=int(head.get("tier",0))
	body_reduction=float(body.get("reduction",0))
	head_reduction=float(head.get("reduction",0))
	speed_penalty=float(body.get("speed_penalty",0))+float(head.get("speed_penalty",0))
	stamina_penalty=float(body.get("stamina_penalty",0))+float(head.get("stamina_penalty",0))
	aim_penalty=float(body.get("aim_penalty",0))+float(head.get("aim_penalty",0))
	hearing=float(head.get("hearing",1))
	gear_weight=float(body.get("weight",0))+float(head.get("weight",0))
	capacity=20.0
	bag_columns=6
	bag_rows=4

func movement_multiplier() -> float:
	# Equipment penalties already include its bulk; gun and cargo add load cost.
	return clampf((1.0-speed_penalty)*(1.0-(float(weapon.weight)-2.5)*0.035-weight()*0.009),0.40,1.0)

func sound_gain(origin: Vector3, base_radius: float, obstructed: bool=false) -> float:
	var radius:=base_radius*hearing*(0.55 if obstructed else 1.0)
	if radius<=0: return 0.0
	return clampf(1.0-global_position.distance_to(origin)/radius,0.0,1.0)

func hear_sound(origin: Vector3, kind: String, radius: float) -> void:
	if not is_local or finished or sound_gain(origin,radius)<=0: return
	var ray:=PhysicsRayQueryParameters3D.create(camera.global_position,origin+Vector3.UP*0.8,1)
	var obstructed:=not get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
	var gain:=sound_gain(origin,radius,obstructed)
	if gain<=0: return
	game.audio.play_sound(kind,lerpf(-42,-19,gain))
	var direction: Vector3=global_basis.inverse()*(origin-global_position)
	var bearing: String=("右侧" if direction.x>0 else "左侧") if absf(direction.x)>absf(direction.z) else ("后方" if direction.z>0 else "前方")
	sound_cue=bearing+" · "+("脚步" if kind=="footstep" else "枪声")
	sound_left=0.65 if kind=="footstep" else 1.1

func scan_footsteps(delta: float) -> void:
	sound_left=maxf(0,sound_left-delta)
	hearing_scan-=delta
	if hearing_scan>0 or not is_local: return
	hearing_scan=0.45
	var sources: Array=game.world.enemies.duplicate()
	if game.session.running: sources.append_array(game.session.actors.values())
	var loudest
	var loudest_radius:=0.0
	var loudest_gain:=0.0
	for source in sources:
		if source==self or (source is RaidEnemy and source.dead) or (source is RaidPlayer and source.finished): continue
		var speed:=Vector2(source.velocity.x,source.velocity.z).length()
		if speed<0.8: continue
		var radius:=20.0 if speed>5 else 12.0
		if sound_gain(source.global_position,radius)<=loudest_gain: continue
		var ray:=PhysicsRayQueryParameters3D.create(camera.global_position,source.global_position+Vector3.UP*0.8,1)
		var obstructed:=not get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
		var gain:=sound_gain(source.global_position,radius,obstructed)
		if gain>loudest_gain:
			loudest=source
			loudest_radius=radius
			loudest_gain=gain
	if is_instance_valid(loudest): hear_sound(loudest.global_position,"footstep",loudest_radius)

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1|2|4
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.36
	capsule.height = 1.75
	collision.shape = capsule
	collision.position.y = 0.88
	add_child(collision)
	camera = Camera3D.new()
	camera.position.y = 1.62
	camera.near = 0.025
	camera.fov = 78
	add_child(camera)
	weapon_root = Node3D.new()
	weapon_root.scale=Vector3.ONE*0.78
	camera.add_child(weapon_root)
	var light := OmniLight3D.new()
	light.position = Vector3(0.4,0.4,0.2)
	light.light_energy = 0.32
	light.omni_range = 2.5
	camera.add_child(light)
	equip(weapon_index)
	if not is_local:
		camera.current = false
		weapon_root.visible = false
		body_model = RaidEnemy.new()
		body_model.replica = true
		body_model.world = game.world
		add_child(body_model)
		body_model.collision_layer = 0
		body_model.collision_mask = 0
		body_model.rifle.visible = weapon_index>=0

func equip(index: int) -> void:
	weapon_index = index
	var build: Dictionary = WeaponModsData.sanitize(index,get_meta("builds",{}).get(str(index),{})) if not is_local else game.build_for(index)
	weapon = WeaponModsData.weapon(index,build)
	ammo = weapon.magazine
	reserve = weapon.reserve
	if is_instance_valid(gun): gun.queue_free()
	gun = Arsenal.build_model(index,build)
	weapon_root.add_child(gun)
	if index<0:
		muzzle=MeshInstance3D.new()
		gun.add_child(muzzle)
		return
	var mat := Arsenal.material(Color("ffe6aa"))
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	muzzle = Arsenal.box(gun,Vector3(0.085,0.09,0.15),Vector3(0,0.014,-[0.82,0.88,0.58,0.55,0.99,1.02,1.04,1.16][index]*0.77),mat)
	muzzle.visible = false
	# Gloves make the weapon read as a held object, rather than a floating asset.
	var gloves := Arsenal.material(Color("404b42"))
	Arsenal.box(gun,Vector3(0.08,0.09,0.1),Vector3(0.035,-0.105,0.06),gloves)
	Arsenal.box(gun,Vector3(0.09,0.08,0.12),Vector3(-0.035,-0.06,-0.25),gloves)

func _unhandled_input(event: InputEvent) -> void:
	if not is_local or not game.accepts_player_input(): return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if capture_grace>0 or event.relative.length()>250: return
		var sensitivity := 0.0013 if aimed else 0.0021
		rotation.y -= event.relative.x * sensitivity
		pitch = clampf(pitch-event.relative.y*sensitivity,-1.4,1.4)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		queued_shot = true
		trigger_sequence += 1
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_R: reload_weapon()
		if event.physical_keycode == KEY_H: heal()

func _physics_process(delta: float) -> void:
	if finished: return
	if not is_local and game.session.running and not game.session.is_authority():
		shot_flash=maxf(0,shot_flash-delta)
		if has_snapshot:
			position = position.lerp(snapshot_position,1.0-exp(-delta*18.0))
			rotation.y = lerp_angle(rotation.y,snapshot_yaw,1.0-exp(-delta*18.0))
			animate_body(delta)
		return
	if not game.active_simulation():
		queued_shot = false
		return
	if is_local: scan_footsteps(delta)
	fire_cooldown = maxf(0,fire_cooldown-delta)
	capture_grace=maxf(0,capture_grace-delta)
	hit_flash = maxf(0,hit_flash-delta)
	damage_flash = maxf(0,damage_flash-delta)
	shot_flash = maxf(0,shot_flash-delta)
	muzzle.visible = shot_flash > 0
	recoil = lerpf(recoil,0,delta*7)
	if reload_left > 0:
		reload_left -= delta
		if reload_left <= 0:
			var needed := mini(int(weapon.magazine)-ammo,reserve)
			ammo += needed
			reserve -= needed
	if heal_left > 0:
		heal_left -= delta
		if heal_left <= 0:
			health = minf(100,health+60)
			meds -= 1
			if is_local: game.notify("治疗完成 · 生命 +60")
	var controls: Dictionary = sample_input() if is_local else remote_input
	if is_local and game.session.running: game.session.send_input(controls)
	if not is_local:
		rotation.y = float(controls.get("yaw",rotation.y))
		pitch = float(controls.get("pitch",pitch))
	aimed = weapon_index>=0 and bool(controls.get("aim",false)) and reload_left <= 0
	var input_vector: Vector2 = controls.get("move",Vector2.ZERO)
	sprinting = bool(controls.get("sprint",false)) and input_vector.y < 0 and stamina>2 and not aimed and heal_left<=0
	var speed := 4.6
	if sprinting:
		speed = 7.6
		stamina = maxf(0,stamina-delta*18*(1.0+stamina_penalty))
	else:
		stamina = minf(100,stamina+delta*13)
	if aimed: speed = 2.5
	if heal_left>0: speed = 1.8
	speed *= movement_multiplier()
	var direction := global_basis * Vector3(input_vector.x,0,input_vector.y)
	velocity.x = move_toward(velocity.x,direction.x*speed,delta*30)
	velocity.z = move_toward(velocity.z,direction.z*speed,delta*30)
	if is_on_floor():
		velocity.y = 0
		if bool(controls.get("jump",false)): velocity.y = 6.2
	else: velocity.y -= 20*delta
	move_and_slide()
	step_time += delta*Vector2(velocity.x,velocity.z).length()*1.8
	var bob := sin(step_time)*minf(input_vector.length()*0.012,0.012)
	camera.rotation.x = pitch-recoil
	var target_fov := 78.0
	if aimed: target_fov = float(weapon.aim_fov)
	camera.fov = lerpf(camera.fov,target_fov,minf(1,delta*11/(1.0+aim_penalty)))
	var aim_pos := Vector3(0,-0.10,-0.50) if aimed else Vector3(0.22,-0.23,-0.65)
	weapon_root.position = weapon_root.position.lerp(aim_pos+Vector3(bob,bob*0.7,recoil*1.5),minf(1,delta*13/(1.0+aim_penalty)))
	weapon_root.rotation.x = lerpf(weapon_root.rotation.x,-0.4 if reload_left>0 else (-0.55 if sprinting else 0.0),delta*7)
	weapon_root.rotation.z = lerpf(weapon_root.rotation.z,0.32 if reload_left>0 else 0.0,delta*7)
	if heal_left>0: weapon_root.position.y -= 0.2
	var click := int(controls.get("click",0))
	var trigger := bool(controls.get("fire",false)) if weapon.automatic else click>consumed_trigger
	consumed_trigger = click
	if trigger and fire_cooldown<=0 and reload_left<=0 and heal_left<=0 and not sprinting:
		fire()
	queued_shot = false
	animate_body(delta)

func sample_input() -> Dictionary:
	var enabled: bool = game.accepts_player_input()
	return {"move":Vector2(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W))).normalized() if enabled else Vector2.ZERO,"yaw":rotation.y,"pitch":pitch,"aim":enabled and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT),"sprint":enabled and Input.is_physical_key_pressed(KEY_SHIFT),"jump":enabled and Input.is_physical_key_pressed(KEY_SPACE),"fire":enabled and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT),"click":trigger_sequence}

func animate_body(delta: float) -> void:
	if not is_instance_valid(body_model): return
	body_model.walk_cycle += delta*Vector2(velocity.x,velocity.z).length()*2.5
	for i in range(body_model.limbs.size()): body_model.limbs[i].rotation.x=sin(body_model.walk_cycle+i*PI)*0.43*minf(1,velocity.length()/3)
	body_model.muzzle.visible=shot_flash>0

func fire() -> void:
	if weapon_index<0: return
	if ammo<=0:
		reload_weapon()
		return
	ammo -= 1
	fire_cooldown = 60.0/float(weapon.rpm)
	shot_flash = 0.045
	recoil += float(weapon.recoil)*(0.65 if aimed else 1.0)
	if game.session.running:
		raid_shots += 1
		if is_local:
			game.shots=raid_shots
			game.audio.play_sound("sniper" if weapon_index==7 else "shot")
		if game.session.is_authority(): game.session.resolve_shot(self)
		return
	rotation.y += randf_range(-0.003,0.003)
	game.audio.play_sound("sniper" if weapon_index==7 else ("heavy" if weapon_index==4 else "shot"))
	game.shots += 1
	# Noise alerts nearby patrols, including those outside direct line of sight.
	for enemy in game.world.enemies:
		if not enemy.dead and global_position.distance_to(enemy.global_position)<float(weapon.noise_radius): enemy.alerted = 7
	for i in range(int(weapon.pellets)):
		var spread := float(weapon.spread)*(0.26 if aimed else 1.0)
		if Vector2(velocity.x,velocity.z).length()>2: spread *= 1.6
		var direction := -camera.global_basis.z+camera.global_basis.x*randf_range(-spread,spread)+camera.global_basis.y*randf_range(-spread,spread)
		direction = direction.normalized()
		var origin := camera.global_position
		var endpoint := origin+direction*float(weapon.range)
		var ray := PhysicsRayQueryParameters3D.create(origin,endpoint,1|2)
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty():
			endpoint = hit.position
			if hit.collider is RaidEnemy:
				var falloff := clampf(1.0-origin.distance_to(endpoint)/float(weapon.range)*0.45,0.55,1)
				var killed: bool = hit.collider.take_hit(float(weapon.damage)*falloff,endpoint)
				hit_flash = 0.18
				game.audio.play_sound("hit",-20)
				if killed:
					game.kills += 1
					game.notify("威胁已清除",1.6)
			else:
				game.impact(endpoint,hit.normal)
		if i==0: game.tracer(camera.global_position+camera.global_basis*Vector3(0.2,-0.16,-0.7),endpoint,Color("ffe2a3"))

func reload_weapon() -> void:
	if weapon_index<0: return
	if game.session.running and not game.session.is_authority():
		game.session.player_command("reload")
		return
	if reload_left>0 or ammo>=int(weapon.magazine) or reserve<=0 or heal_left>0: return
	reload_left = float(weapon.reload)
	if is_local: game.audio.play_sound("reload",-17)

func heal() -> void:
	if game.session.running and not game.session.is_authority():
		game.session.player_command("heal")
		return
	if heal_left>0 or reload_left>0: return
	if meds<=0:
		if is_local: game.notify("医疗用品已耗尽")
	elif health>=100:
		if is_local: game.notify("当前生命值已满")
	else:
		heal_left = 2.8
		if is_local: game.notify("使用急救包 · 受伤会打断治疗")

func take_damage(amount: float, headshot: bool=false) -> void:
	if game.session.running and not game.session.is_authority(): return
	if health<=0 or not game.active_simulation() or amount<=0: return
	var damage:=amount*(2.2 if headshot else 1.0)
	var absorbed:=minf(helmet if headshot else armor,damage*(head_reduction if headshot else body_reduction))
	if headshot: helmet=maxf(0,helmet-absorbed)
	else: armor=maxf(0,armor-absorbed)
	health = maxf(0,health-(damage-absorbed))
	heal_left = 0
	damage_flash = 0.5
	if is_local: game.audio.play_sound("hurt",-19)
	if health<=0:
		if game.session.running: game.session.finish_actor(network_id,false,"干员失联")
		else: game.finish_raid(false,"干员失联")

func weight() -> float:
	var total := 0.0
	for item in inventory: total += float(item.weight)
	for item in safe_inventory: total += float(item.weight)
	return total

func loot_value() -> int:
	var total := 0
	for item in inventory: total += int(item.value)
	for item in safe_inventory: total += int(item.value)
	return total

func can_store(item: Dictionary) -> bool:
	if weight()+float(item.weight)>capacity: return false
	var proposed:=inventory.duplicate()
	proposed.append(item)
	return ItemsData.pack(proposed,bag_columns,bag_rows).size()==proposed.size()

func safe_value() -> int:
	var total:=0
	for item in safe_inventory: total+=int(item.value)
	return total
