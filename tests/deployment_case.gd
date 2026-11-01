extends SceneTree
## Verify admission using real inventory ownership and real ENet peers.
var game
var role := ""
var mode := "普通"
var epoch := 0
var raid_epoch := 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="): role=arg.trim_prefix("--case=")
		if arg.begins_with("--mode="): mode=arg.trim_prefix("--mode=")
	call_deferred("run")

func exact_readiness() -> void:
	# Exactly 60,000, with no helmet, reserve ammunition or medicine.
	game.loadout={"weapon":1,"armor":"armor_5_light","helmet":"","ammo_packs":0,"medkits":0}
	game.owned_gear={"weapon:1":true,"armor_5_light":true,"mod:grip_angled":true}
	game.weapon_builds={"1":{"grip":"grip_angled"}}
	assert(game.loadout_readiness()==60000)

func run() -> void:
	game=load("res://scenes/main.tscn").instantiate()
	game.profile_path="user://deployment_test_%d.json" % OS.get_process_id()
	root.add_child(game)
	current_scene=game
	assert(not game.smoke_mode or role=="dedicated")
	if not role.is_empty():
		setup_network()
		return
	# Every combination of missing gun, armor, helmet, ammo and medicine is legal.
	for mask in range(32):
		game.owned_gear={}
		game.loadout={"weapon":0,"armor":"armor_1","helmet":"helmet_1","ammo_packs":1 if mask&8 else 0,"medkits":1 if mask&16 else 0}
		if mask&1: game.owned_gear["weapon:0"]=true
		if mask&2: game.owned_gear["armor_1"]=true
		if mask&4: game.owned_gear["helmet_1"]=true
		assert(game.can_deploy())
		var clean: Dictionary=game.session.sanitize_profile(game.session.local_profile())
		assert(not clean.is_empty() and clean.loadout==game.deployment_loadout())
	game.loadout.ammo_packs=25
	game.loadout.medkits=15
	assert(game.session.sanitize_profile(game.session.local_profile()).loadout==game.deployment_loadout(),"The authority must preserve carried quantities and their readiness value")
	game.owned_gear={}
	game.loadout={"weapon":7,"armor":"armor_6_durable","helmet":"helmet_6_heavy","ammo_packs":0,"medkits":0}
	assert(game.loadout_readiness()==0,"Unowned previews must not count toward readiness")
	game.start_raid()
	assert(game.state=="raid" and game.player.weapon_index==-1)
	assert(game.player.armor==0 and game.player.helmet==0 and game.player.meds==0 and game.player.reserve==0)
	for enemy in game.world.enemies: enemy.set_physics_process(false)
	await physics_frame
	await physics_frame
	game.player.fire()
	game.player.reload_weapon()
	assert(game.player.ammo==0 and game.shots==0 and game.player.reload_left==0)
	var chest: Node3D=game.world.loot[0]
	game.player.position=chest.position+Vector3(0,0,1)
	game.open_container(chest)
	game.advance_search(60)
	assert(game.overlay=="search" and game.take_loot(0),"Unarmed players must still search and collect loot")
	game.overlay=""
	game.player.position=RaidWorld.EXITS[0]
	game._process(10.1)
	assert(game.state=="result" and game.result_success,"Unarmed players must still extract")
	game.handle_ui("return")
	game.loadout={"weapon":-1,"armor":"","helmet":"","ammo_packs":0,"medkits":0}
	game.owned_gear={"weapon:0":true,"armor_1":true,"helmet_1":true}
	game.save_profile()
	game.load_profile()
	assert(game.loadout_readiness()==0 and game.loadout.armor.is_empty() and game.loadout.helmet.is_empty(),"Empty equipment slots must survive save/load even when other equipment is owned")
	game.raid_mode="机密"
	exact_readiness()
	game.weapon_builds={}
	assert(not game.can_deploy())
	assert(game.session.sanitize_profile(game.session.local_profile()).is_empty())
	game.session.begin_matchmaking()
	game.start_raid()
	assert(game.state=="menu" and game.session.phase=="idle","Below-threshold classified loadouts must fail both entry paths")
	exact_readiness()
	assert(game.can_deploy() and not game.session.sanitize_profile(game.session.local_profile()).is_empty())
	game.session.begin_matchmaking()
	assert(game.state=="matching")
	game.session.cancel()
	game.start_raid()
	assert(game.state=="raid" and game.player.weapon_index==1 and game.player.helmet==0 and game.player.meds==0 and game.player.reserve==0)
	game.handle_ui("return")
	DirAccess.remove_absolute(game.profile_path)
	print("DEPLOYMENT PASS: all 32 partial loadouts, unowned previews, unarmed search/extraction, classified rejection and exact-threshold admission")
	game.queue_free()
	await process_frame
	quit()

func setup_network() -> void:
	game.raid_mode=mode
	game.owned_gear={}
	if role=="dedicated":
		game.smoke_mode=false
		game.loadout={"weapon":-1,"armor":"","helmet":"","ammo_packs":0,"medkits":0}
		game.session.wait_seconds=1.0
		epoch=Time.get_ticks_msec()
		return # configure_args() already scheduled the dedicated host.
	if mode=="机密":
		exact_readiness()
		if role in ["client","dedicated_client"]:
			game.loadout={"weapon":-1,"armor":"armor_6_light","helmet":"","ammo_packs":0,"medkits":0}
			game.owned_gear={"armor_6_light":true}
	elif role in ["client","dedicated_client"]:
		game.owned_gear={"weapon:0":true}
	game.session.wait_seconds=3.0 if role=="host" else 1.0
	if role in ["client","dedicated_client"]: game.session.server_address="127.0.0.1"
	game.session.begin_matchmaking()
	assert(game.state=="matching")
	epoch=Time.get_ticks_msec()

func _process(_delta: float) -> bool:
	if role.is_empty() or not is_instance_valid(game): return false
	if Time.get_ticks_msec()-epoch>18000:
		push_error("Deployment network timeout: %s / %s" % [role,game.session.phase])
		quit(1)
	if game.session.phase=="waiting" and not game.has_meta("ready"):
		game.set_meta("ready",true)
		print("NET READY "+role)
	if not game.session.running: return false
	if raid_epoch==0:
		raid_epoch=Time.get_ticks_msec()
		for enemy in game.world.enemies: enemy.set_physics_process(false)
	if Time.get_ticks_msec()-raid_epoch<(2200 if role in ["host","dedicated"] else 1500): return false
	assert(game.state=="raid" and game.session.actors.size()==6)
	var humans:=0
	for id in game.session.members:
		if id<0: continue
		humans+=1
		var actor: RaidPlayer=game.session.actors[id]
		assert(actor.meds==0 and actor.reserve==0)
		if mode=="机密":
			assert(actor.helmet_tier==0)
			assert(actor.weapon_index==1 if id==1 else actor.weapon_index==-1)
		else:
			assert(actor.armor_tier==0 and actor.helmet_tier==0)
			assert(actor.weapon_index==-1 if id==1 else actor.weapon_index==0)
		if is_instance_valid(actor.body_model): assert(actor.body_model.rifle.visible==(actor.weapon_index>=0))
	assert(humans==(1 if role in ["fallback","dedicated","dedicated_client"] else 2))
	if role in ["client","dedicated_client"]: assert(game.session.last_snapshot>0)
	assert(not FileAccess.file_exists(game.profile_path))
	print("NET PASS %s: %s, empty/partial equipment admitted and replicated" % [role,mode])
	quit()
	return false
