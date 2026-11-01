extends SceneTree
const BotBrain = preload("res://scripts/raid_bot.gd")

var game
var role := "host"
var started := 0
var stage := 0
var saw_other := false
var bot_starts: Dictionary={}
var epoch := 0
var raid_epoch := 0
var role_port := 24680
var raid_mode := "普通"
var remote_prepared := false
var pickup_requested := false
var client_looted := false
var human_start := Vector3.ZERO
var heard_guard_motion := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="): role=arg.trim_prefix("--case=")
		if arg.begins_with("--port="): role_port=int(arg.trim_prefix("--port="))
		if arg.begins_with("--mode="): raid_mode=arg.trim_prefix("--mode=")
	call_deferred("setup")

func setup() -> void:
	game=load("res://scenes/main.tscn").instantiate()
	game.smoke_mode=true
	game.profile_path="user://net_test_%s_%d.json" % [role,OS.get_process_id()]
	game.bank=25000
	game.stash=[]
	game.raids=0
	root.add_child(game)
	current_scene=game
	game.loadout.ammo_packs=2
	game.loadout.medkits=2
	game.raid_mode=raid_mode
	if raid_mode=="机密":
		game.loadout.armor="armor_5_durable"
		game.loadout.helmet="helmet_5_hearing"
	if role=="client":
		game.safe_boxes.progress={"extracts":10,"value":150000,"kills":20}
		assert(game.safe_boxes.claim("safe_3x3"))
	elif role=="fallback":
		assert(game.apply_verified_safe_purchase(game.SafeBoxes.PRODUCT_ID,"net-test-%d" % OS.get_process_id()))
	game.session.port=role_port
	game.session.nickname="test_"+role
	game.session.wait_seconds=1.5 if role=="fallback" else 4.0
	if role=="client": game.session.server_address="127.0.0.1"
	if role=="client": game.session.begin_matchmaking()
	else: game.session._host() # Isolate test rooms from other LAN discovery runs.
	print("NET READY "+role)
	epoch=Time.get_ticks_msec()

func _process(_delta: float) -> bool:
	if not is_instance_valid(game): return false
	var session=game.session
	var elapsed:=Time.get_ticks_msec()-epoch
	if elapsed>28000:
		print("NET FAIL %s: timeout phase=%s stage=%d" % [role,session.phase,stage])
		quit(1)
		return false
	if not session.running: return false
	if role=="client" and session.last_snapshot>0:
		for enemy in game.world.enemies:
			if Vector2(enemy.velocity.x,enemy.velocity.z).length()>0.8: heard_guard_motion=true
	if started==0:
		started=1
		raid_epoch=Time.get_ticks_msec()
		assert(session.actors.size()==6,"Six participant slots")
		var humans:=0
		var bots:=0
		for id in session.members:
			if id>0: humans+=1
			else:
				bots+=1
				bot_starts[id]=session.actors[id].position
		assert(humans==(1 if role=="fallback" else 2),"Real peers must share one room")
		assert(bots==(5 if role=="fallback" else 4),"Only empty slots become bots")
		assert(game.world.loot.size()==48)
		assert(game.world.raid_mode==raid_mode,"Both peers must generate the selected mode on their first deployment")
		var elites:=0
		for enemy in game.world.enemies:
			if enemy.elite: elites+=1
		assert(elites==(6 if raid_mode=="机密" else 3))
		for chest in game.world.loot:
			assert(chest.get_meta("items").size()>=(3 if raid_mode=="机密" else 2))
		for id in session.actors:
			if id>=0: continue
			var bot: RaidPlayer=session.actors[id]
			assert(bot.armor_tier in ([4,5] if raid_mode=="机密" else [1,2]))
			assert(bot.weapon.mod_count>0 if raid_mode=="机密" else bot.weapon.mod_count==0)
		assert(game.world.loot[0].get_meta("items")[0].has("net_uid"))
		assert(game.player.safe_box_id==("safe_3x3" if role=="client" else ("safe_2x4" if role=="fallback" else "safe_1x2")))
		for id in session.actors:
			var box_actor: RaidPlayer=session.actors[id]
			var box: Dictionary=game.SafeBoxes.definition(box_actor.safe_box_id)
			assert(box_actor.safe_columns==int(box.columns) and box_actor.safe_rows==int(box.rows),"Every peer must use the authoritative box dimensions")
			if id>1: assert(box_actor.safe_box_id=="safe_3x3","Task entitlement must reach the authority and remote peers")
		game.overlay="inventory"
		game.set_capture()
		if role=="host": human_start=session.actors.values()[1].position
		print("NET START %s mode=%s humans=%d bots=%d" % [role,raid_mode,humans,bots])
	var raid_elapsed:=Time.get_ticks_msec()-raid_epoch
	if stage==0 and raid_elapsed>900:
		assert(game.raid_left<game.RAID_LENGTH-0.6,"Inventory must not freeze online clock")
		if role=="client":
			var before: Vector3=game.player.position
			game.player.set_meta("test_start",before)
			game.player.set_physics_process(false)
			stage=1
		else:
			var actor: RaidPlayer=game.player
			var chest: Node3D=game.world.loot[0]
			actor.position=chest.position+Vector3(0,-0.5,2)
			game.overlay=""
			game.set_capture()
			stage=1
	if role=="client" and stage==1:
		if raid_elapsed<2000:
			session.send_input({"move":Vector2(-1,0),"yaw":0.0,"pitch":0.0})
		elif raid_elapsed<2200:
			session.send_input({"move":Vector2.ZERO,"yaw":0.0,"pitch":0.0})
		if raid_elapsed>2600 and game.player.position.distance_to(game.world.loot[1].position)<3:
			assert(session.last_snapshot>0,"Client receives authoritative snapshots")
			if game.overlay!="search": game.open_container(game.world.loot[1])
			if game.overlay=="search" and int(game.world.loot[1].get_meta("revealed"))>0 and not pickup_requested:
				game.take_loot(0)
				pickup_requested=true
		if not game.player.inventory.is_empty(): client_looted=true
	if role=="host" and not remote_prepared and raid_elapsed>2200:
		var remote: RaidPlayer=session.actors.values()[1]
		assert(remote.position.distance_to(human_start)>2,"Client input must move its server-owned actor")
		remote.set_physics_process(false)
		remote.position=game.world.loot[1].position+Vector3(0,-0.5,2)
		remote_prepared=true
	if stage==1 and role!="client" and raid_elapsed>1300:
		game.open_container(game.world.loot[0])
		assert(game.overlay=="search")
		stage=2
	if stage==2 and role!="client" and raid_elapsed>5500:
		var chest: Node3D=game.world.loot[0]
		assert(int(chest.get_meta("revealed"))>0,"Authority must advance shared search")
		var uid: String=chest.get_meta("items")[0].net_uid
		assert(game.take_loot(0),"Authority pickup uses the real grid and weight rules")
		assert(game.player.inventory.size()==1)
		assert(not session.perform_item(1,"take","loot",0,uid),"Duplicate UID pickup rejected")
		if role=="fallback":
			var moved:=false
			for id in bot_starts:
				if session.actors[id].position.distance_to(bot_starts[id])>2: moved=true
			assert(moved,"AI must move through the real map")
		# Patrol/AI motion has been checked. Keep the scripted PvP and ten-second
		# extraction independent of random classified-mode encounters.
		for enemy in game.world.enemies: enemy.set_physics_process(false)
		for id in session.actors:
			if id>=0: continue
			var bot: RaidPlayer=session.actors[id]
			bot.set_physics_process(false)
			for child in bot.get_children():
				if child is BotBrain: child.set_physics_process(false)
		# Test the server hit ray against a remote body with the actual weapon.
		var victim: RaidPlayer=session.actors.values()[1]
		if role=="host": assert(not victim.inventory.is_empty(),"Client pickup must reach the shared authority")
		victim.set_physics_process(false)
		victim.position=Vector3(-75,0.2,83)
		game.player.position=Vector3(-75,0.2,89)
		game.player.rotation.y=0
		game.player.pitch=0
		game.player.camera.rotation.x=0
		game.player.weapon=game.player.weapon.duplicate(true)
		game.player.weapon.spread=0.0
		game.player.weapon.damage=1000
		game.overlay=""
		stage=3
	if stage==3 and role!="client" and raid_elapsed>5700:
		game.player.fire()
		var victim: RaidPlayer=session.actors.values()[1]
		assert(victim.health<=0 and victim.finished,"Host must resolve real player hit and death")
		game.player.position=RaidWorld.EXITS[0]
		stage=4
	if role=="client" and stage==1 and game.state=="result":
		assert(heard_guard_motion,"Guard movement must reach the client so footsteps can be heard")
		assert(client_looted,"Client inventory must receive reliable pickup updates")
		assert(not game.result_success)
		assert(game.player.health==0)
		print("NET PASS client: joined, movement, snapshots, search/pickup, inventory sync, online menu, authoritative death/result")
		cleanup()
	if stage==4 and role!="client" and game.state=="result":
		assert(game.result_success)
		assert(game.stash.size()==1,"Only authoritative loot settles once")
		print("NET PASS %s: matchmaking, bot fill, shared loot, duplicate rejection, PvP, extraction, settlement" % role)
		cleanup()
	return false

func cleanup() -> void:
	game.session.leave()
	if FileAccess.file_exists(game.profile_path): DirAccess.remove_absolute(game.profile_path)
	quit()
