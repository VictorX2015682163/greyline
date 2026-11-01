extends SceneTree

const BotBrain = preload("res://scripts/raid_bot.gd")
var game
var actor: RaidPlayer
var brain
var epoch := 0
var stage := 0
var stage_time := 0
var initial_position := Vector3.ZERO

func _initialize() -> void:
	call_deferred("setup")

func setup() -> void:
	game=load("res://scenes/main.tscn").instantiate()
	game.smoke_mode=true
	game.profile_path="user://bot_test_%d.json" % OS.get_process_id()
	root.add_child(game)
	current_scene=game
	game.loadout.ammo_packs=2
	game.loadout.medkits=2
	game.session.port=24688
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="): game.session.port=int(arg.trim_prefix("--port="))
	game.session.wait_seconds=0.5
	game.session._host()
	epoch=Time.get_ticks_msec()

func _process(_delta: float) -> bool:
	if not is_instance_valid(game): return false
	if Time.get_ticks_msec()-epoch>30000:
		print("NET FAIL autonomy: stage=%d state=%s position=%s goal=%s chest=%d path=%d/%d" % [stage,brain.state,actor.position,brain.goal,brain.chest_index,brain.path_step,brain.path.size()])
		quit(1)
		return false
	if not game.session.running: return false
	if stage==0:
		# Isolate navigation and resource decisions from unrelated combat.
		for enemy in game.world.enemies:
			enemy.dead=true
			enemy.collision_layer=0
		actor=game.session.actors[-1]
		for other in game.session.actors.values():
			if other==actor: continue
			other.finished=true
			other.collision_layer=0
			other.set_physics_process(false)
		for child in actor.get_children():
			if child is BotBrain: brain=child
		brain.rng.seed=20261022
		for chest in game.world.loot: chest.set_meta("searched",true)
		var chest: Node3D=game.world.loot[0]
		var item: Dictionary=game.ItemsData.get_item("bandage")
		item.net_uid="bot-autonomy:1"
		chest.set_meta("items",[item])
		chest.set_meta("searched",false)
		chest.set_meta("revealed",0)
		actor.position=Vector3(-74,0.2,84)
		initial_position=actor.position
		stage_time=Time.get_ticks_msec()
		stage=1
	elif stage==1 and not actor.inventory.is_empty():
		assert(actor.position.distance_to(initial_position)>3,"AI must navigate to its own search position")
		assert(actor.inventory[0].net_uid=="bot-autonomy:1")
		assert(game.world.loot[0].get_meta("items").is_empty(),"AI pickup must remove shared loot")
		assert(game.world.loot[0].get_meta("searched"),"AI must complete the ordinary container search")
		print("NET BOT looted autonomously after %.1f seconds" % ((Time.get_ticks_msec()-stage_time)/1000.0))
		# A late-raid scenario: the agent must select and walk into an exit.
		actor.position=RaidWorld.EXITS[0]+Vector3(-11,0.2,0)
		actor.velocity=Vector3.ZERO
		game.raid_left=80
		stage_time=Time.get_ticks_msec()
		stage=2
	elif stage==2 and actor.finished:
		assert(game.session.outcomes[-1].success,"AI must survive the same ten-second extraction as a human")
		assert(actor.position.distance_to(RaidWorld.EXITS[0])<6)
		assert(actor.inventory.size()==1,"Extracted bot keeps its collected cargo")
		assert(game.stash.is_empty(),"AI cargo must never settle into the host's stash")
		print("NET PASS autonomy: real navigation, timed search, shared pickup, late-raid exit decision, ten-second extraction")
		game.session.leave()
		if FileAccess.file_exists(game.profile_path): DirAccess.remove_absolute(game.profile_path)
		quit()
	return false
