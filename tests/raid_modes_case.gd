extends SceneTree

const ItemsData = preload("res://scripts/items.gd")
const BotBrain = preload("res://scripts/raid_bot.gd")
const EquipmentData = preload("res://scripts/equipment.gd")
const WeaponModsData = preload("res://scripts/weapon_mods.gd")
var game
var capture := false

func _initialize() -> void:
	capture="--capture-modes" in OS.get_cmdline_user_args()
	call_deferred("run")

func loot_checks() -> void:
	var stats: Dictionary={}
	for mode in ["普通","机密"]:
		var rng:=RandomNumberGenerator.new()
		rng.seed=763382
		var total:=0
		var high:=0
		var value:=0
		var coffees:=0
		var eligible:=0
		for kind in ItemsData.CONTAINERS:
			for tier in range(3):
				for n in range(1200):
					var items:=ItemsData.roll_container(kind,tier,rng,mode)
					assert(items.size()>=(3 if mode=="机密" else 2) and items.size()<=int(ItemsData.CONTAINERS[kind].count))
					assert(ItemsData.pack(items,6,4).size()==items.size(),"Rolled items must fit the container")
					var special:=0
					var chance:=ItemsData.rare_exchange_chance(kind,tier)
					if chance>0: eligible+=1
					for item in items:
						if item.id==ItemsData.RARE_EXCHANGE_ID:
							special+=1
							assert(chance==0.003,"Coffee remains exclusive to its original 0.3% roll")
							continue
						assert(item.id in ItemsData.CONTAINERS[kind].pool,"Mode must preserve themed pools")
						total+=1
						value+=int(item.value)
						if int(item.rarity)>=4: high+=1
					assert(special<=1,"Only one special roll per container")
					coffees+=special
		assert(coffees>eligible*0.001 and coffees<eligible*0.005,"Special item probability must stay independent of mode")
		stats[mode]={"count":total,"high_rate":float(high)/total,"value":value}
		print("MODE LOOT %s: high=%.2f%% mean_container_value=%.0f mean_count=%.2f coffee=%d/%d" % [mode,100.0*high/total,float(value)/28800,float(total)/28800,coffees,eligible])
	assert(stats["机密"].count>stats["普通"].count*1.1)
	assert(stats["机密"].high_rate>stats["普通"].high_rate*1.5,"Classified must increase actual high-quality frequency")
	assert(stats["机密"].value>stats["普通"].value*1.25,"Classified must improve expected ordinary loot value")

func check_world(mode: String) -> void:
	assert(game.world.raid_mode==mode,"World must use the selected mode, including first deployment")
	var elites:=0
	for enemy in game.world.enemies:
		enemy.set_physics_process(false)
		if enemy.elite: elites+=1
		assert(enemy.health==((175.0 if enemy.elite else 125.0) if mode=="机密" else (140.0 if enemy.elite else 100.0)))
	assert(elites==(6 if mode=="机密" else 3))
	for chest in game.world.loot:
		assert(chest.get_meta("items").size()>=(3 if mode=="机密" else 2))

func run() -> void:
	if capture:
		await capture_ui()
		return
	loot_checks()
	game=load("res://scenes/main.tscn").instantiate()
	game.smoke_mode=true
	game.profile_path="user://mode_test_%d.json" % OS.get_process_id()
	root.add_child(game)
	current_scene=game
	assert(game.world.raid_mode=="普通" and game.raids==0)
	# Meet the real classified readiness rule without modifying a player save.
	game.loadout.armor="armor_5_durable"
	game.loadout.helmet="helmet_5_hearing"
	game.loadout.ammo_packs=3
	game.loadout.medkits=3
	game.select_raid_mode("机密")
	game.start_raid()
	game.overlay="pause"
	game.set_capture()
	check_world("机密")
	game.player.set_physics_process(false)
	game.session.actors[1]=game.player
	for i in range(6):
		var profile:=BotBrain.profile(i,"机密")
		var normal:=BotBrain.profile(i,"普通")
		assert(EquipmentData.gear_item(normal.loadout.armor).tier<=2)
		assert(profile.loadout.ammo_packs>=3 and profile.loadout.medkits>=3)
		game.session.spawn_actor(-i-1,profile,Vector3(-100-i,0.2,90))
		var actor: RaidPlayer=game.session.actors[-i-1]
		actor.set_physics_process(false)
		assert(actor.health==100 and actor.armor_tier in [4,5] and actor.helmet_tier in [4,5])
		assert(actor.weapon.damage==Arsenal.get_weapon(actor.weapon_index).damage,"Bots use the same weapon damage as players")
		assert(actor.weapon.mod_count>=5 and actor.weapon.spread<Arsenal.get_weapon(actor.weapon_index).spread)
		assert(profile.builds[str(actor.weapon_index)]==WeaponModsData.sanitize(actor.weapon_index,profile.builds[str(actor.weapon_index)]))
	var actor: RaidPlayer=game.session.actors[-1]
	var brain:=BotBrain.new()
	brain.actor=actor
	brain.session=game.session
	brain.personality="谨慎"
	actor.add_child(brain)
	assert(brain.rules.reaction.y<0.5 and brain.rules.aim_base<0.018 and brain.rules.pause.y<0.85)
	game.player.position=Vector3(-100,0.2,78)
	actor.rotation.y=0
	# Other bots are excluded from this controlled visibility check.
	for id in game.session.actors:
		if id< -1: game.session.actors[id].finished=true
	await physics_frame
	await physics_frame
	brain.perceive()
	assert(brain.visible_target==game.player and brain.reaction_left<0.6,"Classified bot must visually acquire a real target")
	var wall:=StaticBody3D.new()
	var collision:=CollisionShape3D.new()
	var shape:=BoxShape3D.new()
	shape.size=Vector3(6,4,1)
	collision.shape=shape
	wall.add_child(collision)
	wall.position=Vector3(-100,2,84)
	game.add_child(wall)
	await physics_frame
	await physics_frame
	brain.perceive()
	assert(not is_instance_valid(brain.visible_target),"Stronger bots must still lose sight behind solid cover")
	brain.hear_noise(game.player.position,42)
	assert(brain.heard_left>0 and not is_instance_valid(brain.visible_target),"Hearing must not reveal a target through a wall")
	wall.queue_free()
	game.handle_ui("return")
	# Retry the same mode, then return to normal. Rules may not leak between raids.
	for mode in ["机密","普通"]:
		game.select_raid_mode(mode)
		game.start_raid()
		game.overlay="pause"
		game.set_capture()
		check_world(mode)
		game.handle_ui("return")
	assert(not FileAccess.file_exists(game.profile_path),"Mode verification must not create or modify a player save")
	print("RAID MODES PASS: seeded loot, first classified deployment, retries, normal reset, elite reinforcements, equipped bots, real damage, reaction, cover and hearing")
	current_scene=null
	game.queue_free()
	await process_frame
	await process_frame
	quit()

func capture_ui() -> void:
	game=load("res://scenes/main.tscn").instantiate()
	game.smoke_mode=true
	game.profile_path="user://mode_preview_%d.json" % OS.get_process_id()
	root.add_child(game)
	current_scene=game
	game.loadout.armor="armor_5_durable"
	game.loadout.helmet="helmet_5_hearing"
	game.loadout.ammo_packs=3
	game.loadout.medkits=3
	for mode in ["普通","机密"]:
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var clicked:=false
		for action in game.ui.actions:
			if action.id=="raidmode:"+mode:
				game.ui.mouse=action.rect.get_center()
				var event:=InputEventMouseButton.new()
				event.button_index=MOUSE_BUTTON_LEFT
				event.pressed=true
				game.ui._gui_input(event)
				clicked=true
				break
		assert(clicked and game.raid_mode==mode,"Mode buttons must respond to clicks")
		game.message_left=0
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var suffix: String="classified" if mode=="机密" else "normal"
		assert(root.get_texture().get_image().save_png("res://docs/screenshots/15-mode-"+suffix+".png")==OK)
	assert(not FileAccess.file_exists(game.profile_path))
	print("RAID MODES PASS: rendered normal and classified mode descriptions, readiness and working mode buttons")
	quit()
