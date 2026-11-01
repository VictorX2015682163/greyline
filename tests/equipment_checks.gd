extends RefCounted
## Exercise economy, seeded loot and real actor damage without touching user saves.
const EquipmentData = preload("res://scripts/equipment.gd")
const ItemsData = preload("res://scripts/items.gd")
const BotBrain = preload("res://scripts/raid_bot.gd")

static func base_checks(game) -> void:
	assert(EquipmentData.all_gear().size()==20)
	assert(EquipmentData.gear_for_slot("backpack").is_empty() and EquipmentData.gear_for_slot("rig").is_empty())
	for tier in range(1,7):
		for slot in ["armor","helmet"]:
			var options: Array=[]
			for item in EquipmentData.gear_for_slot(slot):
				if int(item.tier)==tier: options.append(item)
			assert(options.size()==(1 if tier<3 else 2))
			if tier>=3:
				var heavy: Dictionary=options[0]
				var light: Dictionary=options[1]
				assert(heavy.reduction>light.reduction and heavy.armor>light.armor)
				for key in ["weight","speed_penalty","stamina_penalty","aim_penalty"]: assert(heavy[key]>light[key])
				if slot=="helmet": assert(heavy.hearing<1 and light.hearing>1)
	for id in EquipmentData.LEGACY_REFUNDS: assert(EquipmentData.gear_item(id).is_empty())
	var original_bank: int=game.bank
	var original_owned: Dictionary=game.owned_gear.duplicate(true)
	var original_loadout: Dictionary=game.loadout.duplicate(true)
	var original_stash: Array=game.stash.duplicate(true)
	game.bank=1000000
	game.stash=[]
	game.owned_gear={}
	for item in EquipmentData.all_gear():
		if int(item.tier)==6:
			game.buy_gear(item.id)
			assert(not game.owned_gear.has(item.id) and game.bank==1000000,"Money must never unlock tier six")
	assert(not game.redeem_gear("armor_6_durable"),"No token means no redemption")
	game.buy_gear("armor_3_durable")
	var purchased_bank: int=game.bank
	game.buy_gear("armor_3_durable")
	assert(game.bank==purchased_bank and game.loadout.armor=="armor_3_durable")
	game.buy_gear("ammo_pack",-1)
	game.buy_gear("armor_light")
	assert(game.bank==purchased_bank,"Invalid purchases cannot create currency")
	var settled:=ItemsData.get_item("polar_coffee")
	settled.settled=true
	game.stash=[settled]
	assert(not game.redeem_gear("armor_6_durable"),"Legacy paid archives cannot redeem")
	game.stash=[ItemsData.get_item("polar_coffee")]
	assert(game.redeem_gear("armor_6_durable"))
	assert(game.stash.is_empty() and game.loadout.armor=="armor_6_durable" and game.bank==purchased_bank)
	assert(not game.redeem_gear("helmet_6_hearing"),"One token unlocks exactly one selection")
	game.stash.append(ItemsData.get_item("polar_coffee"))
	assert(not game.redeem_gear("armor_6_durable") and game.stash.size()==1,"Owned gear cannot consume another token")
	game.save_profile()
	game.owned_gear={}
	game.stash=[]
	game.load_profile()
	assert(game.owned_gear.has("armor_6_durable") and game.loadout.armor=="armor_6_durable" and game.stash.size()==1)
	game.buy_gear("armor_6_durable")
	assert(game.bank==purchased_bank,"Already redeemed gear equips freely")
	# Load an actual version-two profile and verify full, one-time refunds.
	var legacy: Dictionary={}
	var refund:=0
	for id in EquipmentData.LEGACY_REFUNDS:
		legacy[id]=true
		refund+=int(EquipmentData.LEGACY_REFUNDS[id])
	var file:=FileAccess.open(game.profile_path,FileAccess.WRITE)
	file.store_string(JSON.stringify({"profile_version":2,"bank":5000,"owned_gear":legacy,"loadout":{"weapon":0,"armor":"armor_heavy","helmet":"helmet_fast","backpack":"backpack_tactical","rig":"rig_assault"}}))
	file.close()
	game.load_profile()
	assert(game.bank==5000+refund and game.owned_gear.is_empty())
	assert(game.loadout.armor=="armor_1" and game.loadout.helmet=="helmet_1")
	assert(not game.loadout.has("backpack") and not game.loadout.has("rig"))
	game.save_profile()
	game.load_profile()
	assert(game.bank==5000+refund,"Refund migration must be idempotent across loads")
	game.bank=original_bank
	game.loadout=original_loadout
	game.owned_gear=original_owned
	game.stash=original_stash
	game.save_profile()
	# Sample the production loot roller, including every eligible and forbidden pool.
	var rng:=RandomNumberGenerator.new()
	rng.seed=20261022
	var drops:=0
	for kind in ["safe","suitcase","ration","military"]:
		var tier:=2 if kind=="military" else 1
		assert(is_equal_approx(ItemsData.rare_exchange_chance(kind,tier),0.003))
		assert("polar_coffee" not in ItemsData.CONTAINERS[kind].pool)
		for i in range(10000):
			var contents:=ItemsData.roll_container(kind,tier,rng)
			var count:=0
			for item in contents:
				if item.id=="polar_coffee": count+=1
			assert(count<=1 and contents.size()>=2 and contents.size()<=4)
			if count>0: assert(ItemsData.pack(contents,6,4).size()==contents.size())
			drops+=count
	assert(drops>=80 and drops<=170,"40,000 containers must exhibit a rare rate near 0.3%, not a normal-pool drop")
	for kind in ItemsData.CONTAINERS:
		for tier in range(3):
			if ItemsData.rare_exchange_chance(kind,tier)>0: continue
			for i in range(100):
				for item in ItemsData.roll_container(kind,tier,rng): assert(item.id!="polar_coffee")
	print("EQUIPMENT LOOT: %d / 40000 eligible containers; forbidden pools clean" % drops)

static func field_checks(game) -> void:
	var p: RaidPlayer=game.player
	var original_position:=p.position
	p.configure_protection({"armor":"armor_3_durable","helmet":"helmet_3_heavy"})
	var heavy_speed:=p.movement_multiplier()
	var heavy_stamina:=p.stamina_penalty
	var heavy_aim:=p.aim_penalty
	var origin:=p.global_position+Vector3.RIGHT*14
	assert(p.sound_gain(origin,12)==0)
	var head_before:=p.helmet
	p.take_damage(20)
	assert(is_equal_approx(p.health,92.4) and is_equal_approx(p.armor,87.6) and p.helmet==head_before)
	p.health=100
	var body_before:=p.armor
	p.take_damage(20,true)
	assert(is_equal_approx(p.health,82.4) and is_equal_approx(p.helmet,48.6) and p.armor==body_before,"Head hits must use only helmet durability")
	p.configure_protection({"armor":"armor_3_light","helmet":"helmet_3_hearing"})
	assert(p.movement_multiplier()>heavy_speed and p.stamina_penalty<heavy_stamina and p.aim_penalty<heavy_aim)
	assert(p.sound_gain(origin,12)>0 and p.sound_gain(origin,12,true)==0,"Hearing range and wall attenuation affect real sounds")
	p.health=100
	p.take_damage(20)
	assert(p.health<92.4,"Light armor trades protection for mobility")
	p.armor=1
	p.health=100
	p.take_damage(20)
	assert(p.armor==0 and p.health==81,"Nearly broken armor only absorbs remaining durability")
	p.health=100
	p.take_damage(20)
	assert(p.health==80,"Broken armor provides no protection")
	p.helmet=0
	p.health=100
	p.take_damage(20,true)
	assert(is_equal_approx(p.health,56),"Broken helmet receives the full headshot multiplier")
	# The network configurator and snapshot both carry the separate head durability.
	game.session.configure_actor(p,{"armor":"armor_5_light","helmet":"helmet_4_hearing","medkits":2,"ammo_packs":1})
	assert(p.armor_tier==5 and p.helmet_tier==4 and p.bag_rows==4 and p.capacity==20)
	var snapshot: Dictionary=game.session.actor_state(p)
	p.armor=1
	p.helmet=2
	game.session.apply_actor(p,snapshot)
	assert(p.armor==p.armor_cap and p.helmet==p.helmet_cap)
	var brain:=BotBrain.new()
	brain.actor=p
	brain.hear_noise(origin,12)
	assert(brain.heard_left>0,"AI hearing helmets must extend gunfire perception")
	brain.heard_left=0
	p.configure_protection({"armor":"armor_4_durable","helmet":"helmet_4_heavy"})
	brain.hear_noise(origin,12)
	assert(brain.heard_left==0)
	brain.free()
	for mode in ["普通","机密"]:
		for i in range(6):
			var profile:=BotBrain.profile(i,mode)
			assert(EquipmentData.gear_item(profile.loadout.armor).tier<6 and EquipmentData.gear_item(profile.loadout.helmet).tier<6)
	# A nearer quiet walker must not hide an audible, farther runner.
	var original_enemies: Array=game.world.enemies
	var original_rotation:=p.rotation
	var walker:=CharacterBody3D.new()
	var runner:=CharacterBody3D.new()
	game.world.add_child(walker)
	game.world.add_child(runner)
	p.position=Vector3(0,100,0)
	p.rotation=Vector3.ZERO
	p.hearing=1.0
	walker.global_position=p.global_position+Vector3.RIGHT*13
	walker.velocity=Vector3.RIGHT*2
	runner.global_position=p.global_position+Vector3.LEFT*16
	runner.velocity=Vector3.LEFT*6
	game.world.enemies=[walker,runner]
	p.sound_cue=""
	p.hearing_scan=0
	p.scan_footsteps(0)
	assert(p.sound_cue=="左侧 · 脚步","An inaudible nearby source cannot mask a farther audible runner")
	walker.global_position=p.global_position+Vector3.RIGHT*8
	p.hearing_scan=0
	p.scan_footsteps(0)
	assert(p.sound_cue=="右侧 · 脚步","Footstep selection must follow perceived volume")
	game.world.enemies=[runner]
	p.configure_protection({"armor":"armor_3_durable","helmet":"helmet_3_heavy"})
	p.sound_cue=""
	p.hearing_scan=0
	p.scan_footsteps(0)
	assert(p.sound_cue.is_empty(),"Heavy headgear must suppress distant footstep cues")
	p.configure_protection({"armor":"armor_3_light","helmet":"helmet_3_hearing"})
	p.hearing_scan=0
	p.scan_footsteps(0)
	assert(p.sound_cue=="左侧 · 脚步","Hearing headgear must reveal the same distant footsteps")
	game.world.enemies=original_enemies
	walker.free()
	runner.free()
	p.rotation=original_rotation
	p.sound_cue=""
	p.sound_left=0
	p.configure_protection(game.loadout)
	p.position=original_position
	p.health=100
	game.apply_loadout_to_player()
